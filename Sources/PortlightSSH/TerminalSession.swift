import Foundation
import NIOSSH
import Observation
import PortlightKit

/// Asks the user whether to trust a host key. The UI shows it and calls
/// `trust()` or `reject()`; until then the connection waits.
@MainActor
public final class HostKeyPrompt: Identifiable {
    public enum Kind: Equatable {
        /// First time seeing this host (or this key type for it).
        case new(otherTypesKnown: Bool)
        /// A different key than the one on file: possibly an attack.
        case changed(previousFingerprint: String)
    }

    public let id = UUID()
    public let hostLabel: String
    public let host: String
    public let port: Int
    public let key: SSHPublicKey
    public let kind: Kind
    private var continuation: CheckedContinuation<Bool, Never>?

    init(hostLabel: String, challenge: HostKeyChallenge, kind: Kind, continuation: CheckedContinuation<Bool, Never>) {
        self.hostLabel = hostLabel
        self.host = challenge.host
        self.port = challenge.port
        self.key = challenge.key
        self.kind = kind
        self.continuation = continuation
    }

    public var fingerprint: String { key.sha256Fingerprint }
    public var algorithm: String { key.algorithmName }

    public func trust() { resolve(true) }
    public func reject() { resolve(false) }

    fileprivate func resolve(_ answer: Bool) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

/// Asks for a password when none is saved (or the saved one was refused).
@MainActor
public final class PasswordPrompt: Identifiable {
    public let id = UUID()
    public let hostLabel: String
    public let username: String
    /// Set when a previous attempt was refused.
    public let message: String?
    private var continuation: CheckedContinuation<(password: String, save: Bool)?, Never>?

    init(hostLabel: String, username: String, message: String?,
         continuation: CheckedContinuation<(password: String, save: Bool)?, Never>) {
        self.hostLabel = hostLabel
        self.username = username
        self.message = message
        self.continuation = continuation
    }

    public func submit(_ password: String, save: Bool) { resolve((password, save)) }
    public func cancel() { resolve(nil) }

    fileprivate func resolve(_ answer: (password: String, save: Bool)?) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

/// The user dismissed a password prompt.
struct PromptCancelled: Error {}

/// Supplies private keys the Library can't read on its own (Secure Enclave
/// keys on iOS).
public typealias ExternalKeyProvider = @MainActor (KeyRecord) throws -> NIOSSHPrivateKey

/// One terminal tab: connects to a saved host (through its jump hosts),
/// runs a shell and feeds the terminal view.
@Observable
@MainActor
public final class TerminalSession: Identifiable {
    public enum State: Equatable {
        case idle
        case connecting(String)
        case connected
        /// The shell or connection ended; `reason` says why.
        case disconnected(String)
        case failed(String)

        public var isLive: Bool {
            switch self {
            case .connecting, .connected: true
            default: false
            }
        }
    }

    public let id = UUID()
    public private(set) var host: SSHHost
    public private(set) var state: State = .idle
    /// A host key decision the UI should show, if any.
    public private(set) var hostKeyPrompt: HostKeyPrompt?
    /// A password the UI should ask for, if any.
    public private(set) var passwordPrompt: PasswordPrompt?
    /// The window title set by the remote program (OSC 0/2), if any.
    public var remoteTitle: String?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let externalKeys: ExternalKeyProvider?
    @ObservationIgnored private let options: SSHConnectionOptions
    @ObservationIgnored private var connections: [SSHConnection] = []
    @ObservationIgnored private var shell: SSHShell?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var size = TerminalSize.standard
    @ObservationIgnored private var outputSink: (([UInt8]) -> Void)?
    @ObservationIgnored private var pendingOutput: [UInt8] = []
    /// Output kept while no terminal view is attached.
    public static let maxPendingOutput = 1 << 20

    public init(host: SSHHost, library: Library, externalKeys: ExternalKeyProvider? = nil,
                options: SSHConnectionOptions? = nil) {
        self.host = host
        self.library = library
        self.externalKeys = externalKeys
        var resolved = options ?? SSHConnectionOptions()
        if options == nil { resolved.keepAliveInterval = library.settings.keepAliveInterval }
        self.options = resolved
    }

    public var title: String { remoteTitle ?? host.displayName }

    // MARK: Terminal view hookup

    /// Connects the terminal view. Output that arrived before it attached is
    /// delivered first.
    public func attach(output: @escaping ([UInt8]) -> Void) {
        outputSink = output
        if !pendingOutput.isEmpty {
            let backlog = pendingOutput
            pendingOutput.removeAll()
            output(backlog)
        }
    }

    public func detach() { outputSink = nil }

    private func deliver(_ bytes: [UInt8]) {
        if let outputSink {
            outputSink(bytes)
        } else {
            pendingOutput += bytes
            if pendingOutput.count > Self.maxPendingOutput {
                pendingOutput.removeFirst(pendingOutput.count - Self.maxPendingOutput)
            }
        }
    }

    /// Writes a local status line into the terminal (dimmed, on its own line).
    private func notice(_ text: String) {
        deliver(Array("\r\n\u{1B}[2m[\(text)]\u{1B}[0m\r\n".utf8))
    }

    /// Keystrokes and pastes from the user.
    public func send(_ bytes: [UInt8]) {
        guard state == .connected, let shell else { return }
        shell.write(bytes)
    }

    public func resize(_ newSize: TerminalSize) {
        guard newSize != size else { return }
        size = newSize
        shell?.resize(newSize)
    }

    // MARK: Lifecycle

    /// Starts connecting. Safe to call again after a disconnect (reconnect).
    public func connect() {
        guard !state.isLive else { return }
        if let fresh = library.host(host.id) { host = fresh }
        connectTask?.cancel()
        connectTask = Task { [weak self] in await self?.run() }
    }

    /// Waits for the current connection attempt to finish (for tests).
    public func waitForConnectAttempt() async {
        await connectTask?.value
    }

    public func disconnect() {
        connectTask?.cancel()
        hostKeyPrompt?.resolve(false)
        passwordPrompt?.resolve(nil)
        teardown()
        if state.isLive { state = .disconnected("Disconnected") }
    }

    private func teardown() {
        readTask?.cancel()
        readTask = nil
        shell?.close()
        shell = nil
        let open = connections
        connections = []
        Task { for connection in open.reversed() { await connection.close() } }
    }

    private func run() async {
        teardown()
        do {
            let chain = try library.jumpChain(for: host.id)
            var through: SSHConnection?
            for (index, hop) in chain.enumerated() {
                let isTarget = index == chain.count - 1
                state = .connecting(isTarget ? "Connecting to \(hop.displayName)…" : "Connecting to jump host \(hop.displayName)…")
                let connection = try await connectHop(hop, through: through)
                try Task.checkCancellation()
                connections.append(connection)
                through = connection
            }
            guard let target = through else { throw SSHConnectionError.disconnected }
            state = .connecting("Starting shell…")
            let shell = try await target.openShell(size: size)
            try Task.checkCancellation()
            self.shell = shell
            library.markConnected(host.id)
            state = .connected
            startReading(shell)
            if let command = host.startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
                shell.write(Array(command.utf8) + [0x0D])
            }
        } catch is CancellationError {
            teardown()
        } catch is PromptCancelled {
            teardown()
            state = .disconnected("Cancelled")
        } catch {
            teardown()
            guard !Task.isCancelled else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            state = .failed(message)
            notice(message)
        }
    }

    private func startReading(_ shell: SSHShell) {
        let events = shell.events
        readTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .output(let bytes):
                    self.deliver(bytes)
                case .exited(let status, let signal):
                    self.shellEnded(status: status, signal: signal)
                }
            }
        }
    }

    private func shellEnded(status: Int?, signal: String?) {
        guard state == .connected else { return }
        let reason: String
        if let signal {
            reason = "Session ended (signal \(signal))"
        } else if let status {
            reason = status == 0 ? "Session ended" : "Session ended (exit \(status))"
        } else {
            reason = "Connection lost"
        }
        shell = nil
        teardown()
        state = .disconnected(reason)
        notice(reason + ". Tap Reconnect to start again.")
    }

    // MARK: One hop

    private func connectHop(_ hop: SSHHost, through: SSHConnection?) async throws -> SSHConnection {
        var message: String?
        // A refused saved password is asked for again, up to three times.
        for attempt in 0..<3 {
            let (credentials, typedPassword) = try await credentials(for: hop, refusedMessage: message, forcePrompt: attempt > 0)
            let endpoint = SSHEndpoint(host: hop.hostname, port: hop.port, username: hop.username, credentials: credentials)
            do {
                let connection = try await SSHConnection.connect(
                    to: endpoint, through: through, options: options,
                    hostKeyValidator: { [weak self] challenge in
                        guard let self else { return false }
                        return await self.validate(challenge, label: hop.displayName)
                    })
                if let typed = typedPassword, typed.save {
                    try? library.setPassword(typed.password, for: hop.id)
                }
                return connection
            } catch SSHConnectionError.authenticationFailed(let user) where hop.auth == .password {
                message = "The server didn't accept that password for \(user)."
                continue
            }
        }
        throw SSHConnectionError.authenticationFailed(username: hop.username)
    }

    private func credentials(for hop: SSHHost, refusedMessage: String?, forcePrompt: Bool)
        async throws -> ([SSHCredential], (password: String, save: Bool)?) {
        switch hop.auth {
        case .key(let id):
            guard let record = library.key(id) else {
                throw SSHConnectionError.connectionFailed("the key for \(hop.displayName) was deleted; pick another in the host's settings")
            }
            switch record.storage {
            case .keychain:
                return ([.key(try library.privateKey(for: record))], nil)
            case .secureEnclave:
                guard let externalKeys else { throw LibraryError.missingSecret }
                return ([.privateKey(try externalKeys(record))], nil)
            }
        case .password:
            if !forcePrompt, let saved = library.password(for: hop.id) {
                return ([.password(saved)], nil)
            }
            guard let typed = await askPassword(label: hop.displayName, username: hop.username, message: refusedMessage) else {
                throw PromptCancelled()
            }
            return ([.password(typed.password)], typed)
        }
    }

    private func askPassword(label: String, username: String, message: String?) async -> (password: String, save: Bool)? {
        let answer = await withCheckedContinuation { continuation in
            passwordPrompt = PasswordPrompt(hostLabel: label, username: username, message: message, continuation: continuation)
        }
        passwordPrompt = nil
        return answer
    }

    /// Known keys pass silently; new or changed ones go to the user.
    private func validate(_ challenge: HostKeyChallenge, label: String) async -> Bool {
        let kind: HostKeyPrompt.Kind
        switch library.hostKeyVerdict(host: challenge.host, port: challenge.port, key: challenge.key) {
        case .trusted:
            return true
        case .revoked:
            notice("The host key for \(label) is marked revoked. Refusing to connect.")
            return false
        case .unknown(let otherTypesKnown):
            kind = .new(otherTypesKnown: otherTypesKnown)
        case .changed(let previous):
            kind = .changed(previousFingerprint: previous.sha256Fingerprint)
        }
        let trusted = await withCheckedContinuation { continuation in
            hostKeyPrompt = HostKeyPrompt(hostLabel: label, challenge: challenge, kind: kind, continuation: continuation)
        }
        hostKeyPrompt = nil
        if trusted {
            library.trustHostKey(host: challenge.host, port: challenge.port, key: challenge.key)
        }
        return trusted
    }
}

/// The open terminal tabs.
@Observable
@MainActor
public final class SessionManager {
    public private(set) var sessions: [TerminalSession] = []
    public var activeID: UUID?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let externalKeys: ExternalKeyProvider?

    public init(library: Library, externalKeys: ExternalKeyProvider? = nil) {
        self.library = library
        self.externalKeys = externalKeys
    }

    public var active: TerminalSession? { sessions.first { $0.id == activeID } }

    /// Opens a new tab for the host and starts connecting.
    @discardableResult
    public func open(_ host: SSHHost) -> TerminalSession {
        let session = TerminalSession(host: host, library: library, externalKeys: externalKeys)
        sessions.append(session)
        activeID = session.id
        session.connect()
        return session
    }

    public func close(_ session: TerminalSession) {
        session.disconnect()
        let index = sessions.firstIndex { $0.id == session.id }
        sessions.removeAll { $0.id == session.id }
        if activeID == session.id {
            activeID = index.flatMap { sessions.indices.contains($0) ? sessions[$0].id : sessions.last?.id }
        }
    }

    public func closeAll() {
        sessions.forEach { $0.disconnect() }
        sessions.removeAll()
        activeID = nil
    }
}
