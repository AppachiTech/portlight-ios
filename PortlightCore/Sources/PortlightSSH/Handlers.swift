import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOSSH
import PortlightKit

/// Shared, thread-safe notes about one handshake: which key the server
/// showed, whether we rejected it, and the stage timer.
final class HandshakeState: Sendable {
    private struct Values {
        var presentedKey: SSHPublicKey?
        var hostKeyRejected = false
        var credentialsExhausted = false
        var timedOut = false
        var authenticated = false
        var timer: Scheduled<Void>?
    }

    private let values = NIOLockedValueBox(Values())

    var presentedKey: SSHPublicKey? { values.withLockedValue { $0.presentedKey } }
    var hostKeyRejected: Bool { values.withLockedValue { $0.hostKeyRejected } }
    var credentialsExhausted: Bool { values.withLockedValue { $0.credentialsExhausted } }
    var timedOut: Bool { values.withLockedValue { $0.timedOut } }

    func recordKey(_ key: SSHPublicKey) { values.withLockedValue { $0.presentedKey = key } }
    func recordRejection() { values.withLockedValue { $0.hostKeyRejected = true } }
    func recordExhausted() { values.withLockedValue { $0.credentialsExhausted = true } }

    /// (Re)starts the stage timer; when it fires the channel is closed.
    /// Does nothing once logged in: a server re-key asks for the host key
    /// again, and must not start a timer that closes a working session.
    func startTimer(on channel: Channel, after delay: TimeAmount) {
        let scheduled = channel.eventLoop.scheduleTask(in: delay) { [weak self] in
            self?.values.withLockedValue { $0.timedOut = true }
            channel.close(promise: nil)
        }
        let (previous, started) = values.withLockedValue { values -> (Scheduled<Void>?, Bool) in
            guard !values.authenticated else { return (nil, false) }
            let old = values.timer
            values.timer = scheduled
            return (old, true)
        }
        previous?.cancel()
        if !started { scheduled.cancel() }
    }

    /// Login succeeded: the handshake stages are over.
    func markAuthenticated() {
        values.withLockedValue { values in
            values.authenticated = true
            values.timer?.cancel()
            values.timer = nil
        }
    }

    func stopTimer() {
        values.withLockedValue { values in
            values.timer?.cancel()
            values.timer = nil
        }
    }

    /// The most meaningful error for how the handshake ended.
    func explain(_ error: Error?, username: String) -> SSHConnectionError {
        if hostKeyRejected, let key = presentedKey { return .hostKeyRejected(key) }
        if credentialsExhausted { return .authenticationFailed(username: username) }
        if timedOut { return .timedOut }
        if let error = error as? SSHConnectionError { return error }
        if let error = error as? NIOSSHError, error.type == .keyExchangeNegotiationFailure {
            return .connectionFailed("no common algorithms with the server (it may only offer RSA host keys or old ciphers)")
        }
        if let error { return .connectionFailed(String(describing: error)) }
        return .disconnected
    }
}

/// Offers the endpoint's credentials in order, skipping any kind the
/// server doesn't accept.
final class CredentialsDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private var remaining: [SSHCredential]
    private let state: HandshakeState

    init(username: String, credentials: [SSHCredential], state: HandshakeState) {
        self.username = username
        self.remaining = credentials
        self.state = state
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        while !remaining.isEmpty {
            let next = remaining.removeFirst()
            switch next {
            case .password(let password) where availableMethods.contains(.password):
                nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .password(.init(password: password))))
                return
            case .privateKey(let key) where availableMethods.contains(.publicKey):
                nextChallengePromise.succeed(.init(username: username, serviceName: "", offer: .privateKey(.init(privateKey: key))))
                return
            default:
                continue
            }
        }
        state.recordExhausted()
        nextChallengePromise.fail(SSHConnectionError.authenticationFailed(username: username))
    }
}

/// Hands the server's key to the app's validator, pausing the handshake
/// timer while the user decides.
final class HostKeyDelegate: NIOSSHClientServerAuthenticationDelegate {
    private let host: String
    private let port: Int
    private let validator: HostKeyValidator
    private let state: HandshakeState
    private let channel: Channel
    private let stageTimeout: TimeAmount

    init(host: String, port: Int, validator: @escaping HostKeyValidator, state: HandshakeState, channel: Channel, stageTimeout: TimeAmount) {
        self.host = host
        self.port = port
        self.validator = validator
        self.state = state
        self.channel = channel
        self.stageTimeout = stageTimeout
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let line = String(openSSHPublicKey: hostKey)
        guard let key = try? SSHPublicKey(openSSH: line) else {
            validationCompletePromise.fail(SSHConnectionError.unsupportedHostKey(String(line.prefix(while: { $0 != " " }))))
            return
        }
        state.recordKey(key)
        state.stopTimer()
        let challenge = HostKeyChallenge(host: host, port: port, key: key)
        let (validator, state, channel, timeout) = (self.validator, self.state, self.channel, self.stageTimeout)
        Task {
            if await validator(challenge) {
                state.startTimer(on: channel, after: timeout)
                validationCompletePromise.succeed(())
            } else {
                state.recordRejection()
                validationCompletePromise.fail(SSHConnectionError.hostKeyRejected(key))
            }
        }
    }
}

/// Sits after NIOSSHHandler and resolves `ready` when authentication
/// succeeds, or fails it with the reason the connection ended.
final class ConnectionReadyHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private var ready: EventLoopPromise<Void>?
    private let state: HandshakeState
    private let username: String
    private var firstError: Error?

    init(ready: EventLoopPromise<Void>, state: HandshakeState, username: String) {
        self.ready = ready
        self.state = state
        self.username = username
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent, let ready {
            self.ready = nil
            state.markAuthenticated()
            ready.succeed(())
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if firstError == nil { firstError = error }
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        state.stopTimer()
        if let ready {
            self.ready = nil
            ready.fail(state.explain(firstError, username: username))
        }
        context.fireChannelInactive()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        if let ready {
            self.ready = nil
            ready.fail(state.explain(firstError, username: username))
        }
    }
}

/// Unwraps SSH channel data to plain bytes and back, so an SSH connection
/// can run inside another connection's direct-tcpip channel (jump hosts).
final class ChannelDataUnwrapper: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .channel = message.type, case .byteBuffer(let buffer) = message.data else { return }
        context.fireChannelRead(wrapInboundOut(buffer))
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}

/// Keeps a server from outrunning the terminal. Output goes into an
/// AsyncStream that the terminal drains on the main thread; once
/// `pauseAbove` bytes are waiting, the channel stops reading, so the SSH
/// window fills and the server pauses instead of the backlog growing until
/// the app runs out of memory. Reading resumes below `resumeBelow`.
final class OutputFlow: @unchecked Sendable {
    static let pauseAbove = 1 << 20
    static let resumeBelow = 256 << 10

    private let lock = NIOLock()
    private var waiting = 0
    private var paused = false

    /// Output was queued (on the event loop). True means stop reading.
    func queued(_ count: Int) -> Bool {
        lock.withLock {
            waiting += count
            guard !paused, waiting > Self.pauseAbove else { return false }
            paused = true
            return true
        }
    }

    /// Output was drawn. True means start reading again.
    func handled(_ count: Int) -> Bool {
        lock.withLock {
            waiting = max(0, waiting - count)
            guard paused, waiting < Self.resumeBelow else { return false }
            paused = false
            return true
        }
    }
}

/// Drives an interactive session channel: requests a PTY and a shell,
/// forwards output to an AsyncStream and reports how the shell ended.
final class ShellHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let term: String
    private let size: TerminalSize
    private let environment: [(String, String)]
    private let continuation: AsyncStream<ShellEvent>.Continuation
    private let flow: OutputFlow
    private var started: EventLoopPromise<Void>?
    private var pendingReplies = 2  // pty-req and shell
    private var exitStatus: Int?
    private var exitSignal: String?

    init(term: String, size: TerminalSize, environment: [(String, String)],
         continuation: AsyncStream<ShellEvent>.Continuation, flow: OutputFlow, started: EventLoopPromise<Void>) {
        self.term = term
        self.size = size
        self.environment = environment
        self.continuation = continuation
        self.flow = flow
        self.started = started
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func channelActive(context: ChannelHandlerContext) {
        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true, term: term,
            terminalCharacterWidth: size.columns, terminalRowHeight: size.rows,
            terminalPixelWidth: size.pixelWidth, terminalPixelHeight: size.pixelHeight,
            terminalModes: SSHTerminalModes([.ECHO: 1]))
        context.triggerUserOutboundEvent(pty, promise: nil)
        for (name, value) in environment {
            // Servers only accept variables listed in AcceptEnv; no reply wanted.
            context.triggerUserOutboundEvent(SSHChannelRequestEvent.EnvironmentRequest(wantReply: false, name: name, value: value), promise: nil)
        }
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true), promise: nil)
        context.fireChannelActive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            pendingReplies -= 1
            if pendingReplies == 0, let started {
                self.started = nil
                started.succeed(())
            }
        case is ChannelFailureEvent:
            if let started {
                self.started = nil
                started.fail(SSHConnectionError.channelRejected(pendingReplies == 2 ? "open a terminal (pty)" : "start a shell"))
                context.close(promise: nil)
            }
        case let status as SSHChannelRequestEvent.ExitStatus:
            exitStatus = status.exitStatus
        case let signal as SSHChannelRequestEvent.ExitSignal:
            exitSignal = signal.signalName
        case let event as ChannelEvent where event == .inputClosed:
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = message.data else { return }
        if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes), !bytes.isEmpty {
            continuation.yield(.output(bytes))
            if flow.queued(bytes.count) {
                context.channel.setOption(ChannelOptions.autoRead, value: false).whenFailure { _ in }
            }
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        finish()
        context.fireChannelInactive()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        finish()
    }

    private func finish() {
        if let started {
            self.started = nil
            started.fail(SSHConnectionError.channelRejected("start a shell"))
        }
        continuation.yield(.exited(status: exitStatus, signal: exitSignal))
        continuation.finish()
    }
}

/// Runs one command and collects its output and exit status.
final class ExecHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    struct Result: Sendable {
        var status: Int?
        var stdout: [UInt8] = []
        var stderr: [UInt8] = []
    }

    private let command: String
    private var result = Result()
    private var done: EventLoopPromise<Result>?

    init(command: String, done: EventLoopPromise<Result>) {
        self.command = command
        self.done = done
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { _ in }
    }

    func channelActive(context: ChannelHandlerContext) {
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true), promise: nil)
        context.fireChannelActive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let status as SSHChannelRequestEvent.ExitStatus:
            result.status = status.exitStatus
        case is ChannelFailureEvent:
            done?.fail(SSHConnectionError.channelRejected("run the command"))
            done = nil
            context.close(promise: nil)
        case let event as ChannelEvent where event == .inputClosed:
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = message.data,
              let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) else { return }
        if message.type == .stdErr { result.stderr += bytes } else { result.stdout += bytes }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        done?.succeed(result)
        done = nil
        context.fireChannelInactive()
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        done?.fail(SSHConnectionError.disconnected)
        done = nil
    }
}
