import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import PortlightKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// An authenticated SSH connection, direct or through a jump host.
public final class SSHConnection: Sendable {
    /// The channel carrying this connection's SSH protocol: a TCP socket, or
    /// a direct-tcpip channel of the jump connection.
    let channel: Channel
    /// The jump connection this one runs through, closed along with it.
    let jump: SSHConnection?
    public let endpoint: (host: String, port: Int, username: String)
    /// The host key the server presented and the validator accepted.
    public let hostKey: SSHPublicKey

    private init(channel: Channel, jump: SSHConnection?, host: String, port: Int, username: String, hostKey: SSHPublicKey) {
        self.channel = channel
        self.jump = jump
        self.endpoint = (host, port, username)
        self.hostKey = hostKey
    }

    public static var defaultEventLoopGroup: EventLoopGroup { MultiThreadedEventLoopGroup.singleton }

    /// Connects, checks the host key with `hostKeyValidator`, and logs in.
    /// Pass `jump` to tunnel through an existing connection (ProxyJump).
    /// Cancelling the calling task abandons the attempt.
    public static func connect(
        to endpoint: SSHEndpoint,
        through jump: SSHConnection? = nil,
        options: SSHConnectionOptions = SSHConnectionOptions(),
        group: EventLoopGroup = SSHConnection.defaultEventLoopGroup,
        hostKeyValidator: @escaping HostKeyValidator
    ) async throws -> SSHConnection {
        let state = HandshakeState()
        let channelBox = ChannelBox()

        return try await withTaskCancellationHandler {
            let channel: Channel
            let ready: EventLoopFuture<Void>
            if let jump {
                (channel, ready) = try await jump.tunnel(to: endpoint, options: options, state: state, validator: hostKeyValidator)
            } else {
                (channel, ready) = try await direct(to: endpoint, options: options, group: group, state: state, validator: hostKeyValidator)
            }
            channelBox.set(channel)
            if Task.isCancelled { channel.close(promise: nil) }
            do {
                try await ready.get()
            } catch {
                channel.close(promise: nil)
                throw (error as? SSHConnectionError) ?? state.explain(error, username: endpoint.username)
            }
            guard let key = state.presentedKey else {
                channel.close(promise: nil)
                throw SSHConnectionError.connectionFailed("no host key was presented")
            }
            return SSHConnection(channel: channel, jump: jump, host: endpoint.host, port: endpoint.port,
                                 username: endpoint.username, hostKey: key)
        } onCancel: {
            channelBox.closeIfSet()
        }
    }

    private static func sshHandlers(for endpoint: SSHEndpoint, channel: Channel, options: SSHConnectionOptions,
                                    state: HandshakeState, validator: @escaping HostKeyValidator,
                                    ready: EventLoopPromise<Void>) -> [ChannelHandler] {
        let configuration = SSHClientConfiguration(
            userAuthDelegate: CredentialsDelegate(username: endpoint.username, credentials: endpoint.credentials, state: state),
            serverAuthDelegate: HostKeyDelegate(host: endpoint.host, port: endpoint.port, validator: validator,
                                                state: state, channel: channel, stageTimeout: options.handshakeTimeout))
        return [
            NIOSSHHandler(role: .client(configuration), allocator: channel.allocator, inboundChildChannelInitializer: nil),
            ConnectionReadyHandler(ready: ready, state: state, username: endpoint.username),
        ]
    }

    private static func direct(to endpoint: SSHEndpoint, options: SSHConnectionOptions, group: EventLoopGroup,
                               state: HandshakeState, validator: @escaping HostKeyValidator) async throws -> (Channel, EventLoopFuture<Void>) {
        let readyBox = PromiseBox()
        var bootstrap = ClientBootstrap(group: group)
            .connectTimeout(options.connectTimeout)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                let ready = channel.eventLoop.makePromise(of: Void.self)
                readyBox.set(ready)
                return channel.eventLoop.makeCompletedFuture {
                    let handlers = sshHandlers(for: endpoint, channel: channel, options: options, state: state,
                                               validator: validator, ready: ready)
                    try channel.pipeline.syncOperations.addHandlers(handlers)
                    state.startTimer(on: channel, after: options.handshakeTimeout)
                }
            }
        if options.keepAliveInterval > 0 {
            bootstrap = bootstrap
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_KEEPALIVE), value: 1)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), keepAliveIdleOption), value: SocketOptionValue(options.keepAliveInterval))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_KEEPINTVL), value: SocketOptionValue(max(5, options.keepAliveInterval / 3)))
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_KEEPCNT), value: 4)
        }
        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: endpoint.host, port: endpoint.port).get()
        } catch let error as ChannelError where error == .connectTimeout(options.connectTimeout) {
            throw SSHConnectionError.timedOut
        } catch {
            throw SSHConnectionError.connectionFailed(describe(error))
        }
        guard let ready = readyBox.future else { throw SSHConnectionError.connectionFailed("internal: no handshake") }
        return (channel, ready)
    }

    /// Opens a direct-tcpip channel to the target and runs a second SSH
    /// connection inside it.
    private func tunnel(to endpoint: SSHEndpoint, options: SSHConnectionOptions, state: HandshakeState,
                        validator: @escaping HostKeyValidator) async throws -> (Channel, EventLoopFuture<Void>) {
        let readyBox = PromiseBox()
        let originator = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        let type = SSHChannelType.directTCPIP(.init(targetHost: endpoint.host, targetPort: endpoint.port, originatorAddress: originator))
        let child: Channel
        do {
            child = try await createChildChannel(type: type) { child in
                let ready = child.eventLoop.makePromise(of: Void.self)
                readyBox.set(ready)
                var handlers: [ChannelHandler] = [ChannelDataUnwrapper()]
                handlers += Self.sshHandlers(for: endpoint, channel: child, options: options, state: state,
                                             validator: validator, ready: ready)
                try child.pipeline.syncOperations.addHandlers(handlers)
                state.startTimer(on: child, after: options.handshakeTimeout)
            }
        } catch {
            throw SSHConnectionError.connectionFailed("the jump host couldn't reach \(endpoint.host):\(endpoint.port)")
        }
        guard let ready = readyBox.future else { throw SSHConnectionError.connectionFailed("internal: no handshake") }
        return (child, ready)
    }

    /// Creates a child channel on this connection, running `initialize` on
    /// the event loop to set up its pipeline.
    func createChildChannel(type: SSHChannelType, initialize: @escaping @Sendable (Channel) throws -> Void) async throws -> Channel {
        let channel = self.channel
        let promise = channel.eventLoop.makePromise(of: Channel.self)
        channel.eventLoop.execute {
            do {
                let ssh = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                ssh.createChannel(promise, channelType: type) { child, _ in
                    child.eventLoop.makeCompletedFuture { try initialize(child) }
                }
            } catch {
                promise.fail(error)
            }
        }
        return try await promise.futureResult.get()
    }

    // MARK: Sessions

    /// Starts an interactive shell with a PTY.
    public func openShell(term: String = "xterm-256color", size: TerminalSize = .standard,
                          environment: [String: String] = ["LANG": "en_US.UTF-8"]) async throws -> SSHShell {
        // Unbounded here, but OutputFlow stops reading once ~1 MiB waits.
        let (stream, continuation) = AsyncStream.makeStream(of: ShellEvent.self, bufferingPolicy: .unbounded)
        let flow = OutputFlow()
        let startedBox = PromiseBox()
        let env = environment.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        let child: Channel
        do {
            child = try await createChildChannel(type: .session) { child in
                let started = child.eventLoop.makePromise(of: Void.self)
                startedBox.set(started)
                try child.pipeline.syncOperations.addHandler(
                    ShellHandler(term: term, size: size, environment: env, continuation: continuation, flow: flow,
                                 started: started))
            }
        } catch {
            continuation.finish()
            throw SSHConnectionError.channelRejected("open a session")
        }
        try await startedBox.future?.get()
        return SSHShell(channel: child, events: stream, flow: flow)
    }

    /// Runs one command without a PTY and returns its output.
    public func exec(_ command: String) async throws -> (status: Int?, stdout: String, stderr: String) {
        let doneBox = ExecPromiseBox()
        _ = try await createChildChannel(type: .session) { child in
            let done = child.eventLoop.makePromise(of: ExecHandler.Result.self)
            doneBox.set(done)
            try child.pipeline.syncOperations.addHandler(ExecHandler(command: command, done: done))
        }
        guard let future = doneBox.future else { throw SSHConnectionError.disconnected }
        let result = try await future.get()
        return (result.status, String(decoding: result.stdout, as: UTF8.self), String(decoding: result.stderr, as: UTF8.self))
    }

    // MARK: Lifecycle

    public var isActive: Bool { channel.isActive }

    /// Closes this connection and any jump connection under it.
    public func close() async {
        try? await channel.close().get()
        await jump?.close()
    }

    /// Returns when the connection has closed, for whatever reason.
    public func waitUntilClosed() async {
        try? await channel.closeFuture.get()
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? NIOConnectionError {
            if let dns = error.dnsAAAAError ?? error.dnsAError { return "couldn't resolve the hostname (\(dns))" }
            if let first = error.connectionErrors.first { return describe(first.error) }
            return "no address to connect to"
        }
        if let error = error as? IOError {
            switch error.errnoCode {
            case ECONNREFUSED: return "connection refused (is SSH running on that port?)"
            case ENETUNREACH, EHOSTUNREACH: return "the host is unreachable"
            case ETIMEDOUT: return "timed out"
            default: return error.description
            }
        }
        return String(describing: error)
    }
}

#if canImport(Darwin)
private let keepAliveIdleOption = TCP_KEEPALIVE
#else
private let keepAliveIdleOption = TCP_KEEPIDLE
#endif

/// A running remote shell.
public final class SSHShell: Sendable {
    let channel: Channel
    /// Terminal output, then one `.exited` event when the shell ends. Call
    /// `outputHandled` as output is used, or reading pauses at ~1 MiB.
    public let events: AsyncStream<ShellEvent>
    let flow: OutputFlow

    init(channel: Channel, events: AsyncStream<ShellEvent>, flow: OutputFlow) {
        self.channel = channel
        self.events = events
        self.flow = flow
    }

    /// Output from `events` has been used; lets a paused channel read again.
    public func outputHandled(_ count: Int) {
        guard flow.handled(count) else { return }
        let channel = channel
        channel.eventLoop.execute {
            channel.setOption(ChannelOptions.autoRead, value: true).whenSuccess { channel.read() }
        }
    }

    /// Sends keystrokes or pasted text.
    public func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        channel.writeAndFlush(buffer, promise: nil)
    }

    public func write(_ text: String) { write(Array(text.utf8)) }

    /// Tells the server the terminal changed size (rotation, font size).
    public func resize(_ size: TerminalSize) {
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: size.columns, terminalRowHeight: size.rows,
            terminalPixelWidth: size.pixelWidth, terminalPixelHeight: size.pixelHeight)
        channel.triggerUserOutboundEvent(request, promise: nil)
    }

    public func close() {
        channel.close(promise: nil)
    }

    public var isActive: Bool { channel.isActive }
}

// MARK: Small thread-safe boxes for values created on the event loop.

import NIOConcurrencyHelpers

final class PromiseBox: Sendable {
    private let box = NIOLockedValueBox<EventLoopPromise<Void>?>(nil)
    func set(_ promise: EventLoopPromise<Void>) { box.withLockedValue { $0 = promise } }
    var future: EventLoopFuture<Void>? { box.withLockedValue { $0?.futureResult } }
}

final class ExecPromiseBox: Sendable {
    private let box = NIOLockedValueBox<EventLoopPromise<ExecHandler.Result>?>(nil)
    func set(_ promise: EventLoopPromise<ExecHandler.Result>) { box.withLockedValue { $0 = promise } }
    var future: EventLoopFuture<ExecHandler.Result>? { box.withLockedValue { $0?.futureResult } }
}

final class ChannelBox: Sendable {
    private let box = NIOLockedValueBox<(channel: Channel?, cancelled: Bool)>((nil, false))
    func set(_ channel: Channel) {
        let cancelled = box.withLockedValue { value -> Bool in
            value.channel = channel
            return value.cancelled
        }
        if cancelled { channel.close(promise: nil) }
    }
    func closeIfSet() {
        let channel = box.withLockedValue { value -> Channel? in
            value.cancelled = true
            return value.channel
        }
        channel?.close(promise: nil)
    }
}
