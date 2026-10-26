import Foundation
import NIOCore
import Testing
@testable import PortlightSSH

/// End-to-end tests against a real OpenSSH server on 127.0.0.1.
@Suite(.serialized, .enabled(if: TestSSHServer.isAvailable, "needs OpenSSH's sshd and ssh-keygen"))
struct SSHIntegrationTests {
    static let keys: [KeyAlgorithm: SSHPrivateKey] = Dictionary(
        uniqueKeysWithValues: KeyAlgorithm.allCases.map { ($0, SSHPrivateKey.generate($0)) })

    func server(extra: String = "") throws -> TestSSHServer {
        try TestSSHServer(authorizedKeys: Self.keys.values.map(\.publicKey), extraConfig: extra)
    }

    func endpoint(_ server: TestSSHServer, _ credentials: [SSHCredential]) -> SSHEndpoint {
        SSHEndpoint(host: "127.0.0.1", port: server.port, username: server.username, credentials: credentials)
    }

    @Test(arguments: KeyAlgorithm.allCases)
    func authenticatesWithEveryKeyTypeAndRunsACommand(algorithm: KeyAlgorithm) async throws {
        let server = try server()
        defer { server.stop() }
        let seen = SeenKeys()
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[algorithm]!)])) { challenge in
            await seen.add(challenge.key)
            return true
        }
        defer { Task { await connection.close() } }
        #expect(connection.hostKey == server.hostKey)
        #expect(connection.hostKey.sha256Fingerprint == server.hostKeyFingerprint)
        #expect(await seen.keys == [server.hostKey])
        let result = try await connection.exec("echo hello; echo oops >&2; exit 3")
        #expect(result.stdout == "hello\n")
        #expect(result.stderr == "oops\n")
        #expect(result.status == 3)
    }

    @Test func rejectedHostKeyDisconnects() async throws {
        let server = try server()
        defer { server.stop() }
        await #expect(throws: SSHConnectionError.hostKeyRejected(server.hostKey)) {
            _ = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)])) { _ in false }
        }
    }

    @Test func wrongCredentialsAreReported() async throws {
        let server = try server()
        defer { server.stop() }
        let stranger = SSHPrivateKey.generate(.ed25519)
        await #expect(throws: SSHConnectionError.authenticationFailed(username: server.username)) {
            _ = try await SSHConnection.connect(to: endpoint(server, [.key(stranger), .password("nope")])) { _ in true }
        }
        // A good key after a bad one still works.
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(stranger), .key(Self.keys[.ecdsaP256]!)])) { _ in true }
        await connection.close()
    }

    @Test func refusedPortIsExplained() async throws {
        let server = try server()
        let port = server.port
        server.stop()
        let error = await #expect(throws: SSHConnectionError.self) {
            _ = try await SSHConnection.connect(
                to: SSHEndpoint(host: "127.0.0.1", port: port, username: "x", credentials: [])) { _ in true }
        }
        guard case .connectionFailed(let reason) = error else {
            Issue.record("expected connectionFailed, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("refused"))
    }

    @Test func interactiveShellHasTheRightTerminalAndResizes() async throws {
        let server = try server()
        defer { server.stop() }
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)])) { _ in true }
        let shell = try await connection.openShell(size: TerminalSize(columns: 100, rows: 30))
        let reader = OutputReader(shell)

        shell.write("stty size; echo TERM=$TERM\n")
        #expect(try await reader.waitFor("30 100"))
        #expect(try await reader.waitFor("TERM=xterm-256color"))

        shell.resize(TerminalSize(columns: 132, rows: 43))
        try await Task.sleep(for: .milliseconds(200))
        shell.write("stty size\n")
        #expect(try await reader.waitFor("43 132"))

        shell.write("exit 7\n")
        let exit = try await reader.waitForExit()
        #expect(exit.status == 7)
        await connection.close()
    }

    @Test func ctrlCInterruptsAForegroundCommand() async throws {
        let server = try server()
        defer { server.stop() }
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)])) { _ in true }
        let shell = try await connection.openShell()
        let reader = OutputReader(shell)
        shell.write("sleep 30; echo FINISHED-$((1+1))\n")
        try await Task.sleep(for: .milliseconds(300))
        shell.write(KeyEncoder.bytes(for: .text("c"), modifiers: .ctrl))
        shell.write("echo AFTER-$((6*7))\n")
        #expect(try await reader.waitFor("AFTER-42", timeout: .seconds(5)))
        #expect(!(await reader.text.contains("FINISHED-2")))
        shell.close()
        await connection.close()
    }

    @Test func readingPausesUntilOutputIsHandled() async throws {
        let server = try server()
        defer { server.stop() }
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)])) { _ in true }
        let shell = try await connection.openShell()
        // ~12 MB of output, then a marker.
        shell.write("head -c 12000000 /dev/zero | tr '\\0' a; echo; echo DONE-$((2*21))\n")
        let counter = ByteCounter()
        let unhandled = Task {
            for await event in shell.events {
                guard case .output(let bytes) = event else { continue }
                if await counter.add(bytes) { return }
            }
        }
        try await Task.sleep(for: .seconds(2))
        // Nothing handled: the backlog stops near the 1 MiB pause point
        // plus one SSH window, far short of the 12 MB sent.
        let stalled = await counter.total
        #expect(stalled > 0 && stalled < 8_000_000, "\(stalled) bytes")
        // Handling it lets the rest through.
        await counter.setHandler { shell.outputHandled($0) }
        shell.outputHandled(stalled)
        let deadline = ContinuousClock.now + .seconds(30)
        while !(await counter.sawMarker), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await counter.sawMarker)
        unhandled.cancel()
        shell.close()
        await connection.close()
    }

    @Test func serverRekeyDoesNotEndTheSession() async throws {
        // Rekey every second; with the old stage timer, each re-key
        // restarted it after login and closed the connection.
        let server = try server(extra: "RekeyLimit default 1")
        defer { server.stop() }
        var options = SSHConnectionOptions()
        options.handshakeTimeout = .milliseconds(800)
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)]),
                                                         options: options) { _ in true }
        let shell = try await connection.openShell()
        let reader = OutputReader(shell)
        try await Task.sleep(for: .seconds(4))
        #expect(connection.isActive)
        shell.write("echo ALIVE-$((40+2))\n")
        #expect(try await reader.waitFor("ALIVE-42", timeout: .seconds(5)))
        shell.close()
        await connection.close()
    }

    @Test func jumpHostTunnelsToTheTarget() async throws {
        let bastion = try server()
        let target = try server()
        defer {
            bastion.stop()
            target.stop()
        }
        let seen = SeenKeys()
        let validator: HostKeyValidator = { challenge in
            await seen.add(challenge.key)
            return true
        }
        let jump = try await SSHConnection.connect(to: endpoint(bastion, [.key(Self.keys[.ed25519]!)]), hostKeyValidator: validator)
        let inner = try await SSHConnection.connect(to: endpoint(target, [.key(Self.keys[.ecdsaP384]!)]), through: jump,
                                                    hostKeyValidator: validator)
        #expect(await seen.keys == [bastion.hostKey, target.hostKey])
        #expect(inner.hostKey == target.hostKey)
        let result = try await inner.exec("echo through-the-bastion")
        #expect(result.stdout == "through-the-bastion\n")
        let shell = try await inner.openShell()
        let reader = OutputReader(shell)
        shell.write("echo SHELL-OK\n")
        #expect(try await reader.waitFor("SHELL-OK"))
        await inner.close()
        #expect(!jump.isActive, "closing the inner connection closes its jump connection too")
    }

    @Test func jumpHostThatCantReachTargetIsExplained() async throws {
        let bastion = try server(extra: "PermitOpen none")
        defer { bastion.stop() }
        let jump = try await SSHConnection.connect(to: endpoint(bastion, [.key(Self.keys[.ed25519]!)])) { _ in true }
        defer { Task { await jump.close() } }
        let error = await #expect(throws: SSHConnectionError.self) {
            _ = try await SSHConnection.connect(
                to: SSHEndpoint(host: "127.0.0.1", port: 9, username: "x", credentials: []), through: jump) { _ in true }
        }
        if case .connectionFailed(let reason) = error {
            #expect(reason.contains("jump host"))
        } else {
            Issue.record("expected connectionFailed, got \(String(describing: error))")
        }
    }

    @Test func slowHostKeyDecisionDoesNotTimeOut() async throws {
        let server = try server()
        defer { server.stop() }
        var options = SSHConnectionOptions()
        options.handshakeTimeout = .milliseconds(800)
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)]), options: options) { _ in
            try? await Task.sleep(for: .seconds(2))  // the user reading the fingerprint
            return true
        }
        #expect(try await connection.exec("echo ok").stdout == "ok\n")
        await connection.close()
    }

    @Test func cancellingAConnectStopsIt() async throws {
        let server = try server()
        defer { server.stop() }
        let started = Date()
        let task = Task {
            try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)])) { _ in
                try? await Task.sleep(for: .seconds(1))
                return true
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func serverSideCloseEndsTheShell() async throws {
        let server = try server()
        defer { server.stop() }
        let connection = try await SSHConnection.connect(to: endpoint(server, [.key(Self.keys[.ed25519]!)])) { _ in true }
        let shell = try await connection.openShell()
        let reader = OutputReader(shell)
        shell.write("kill -HUP $$\n")
        let exit = try await reader.waitForExit()
        #expect(exit.status != 0 || exit.signal != nil)
        await connection.close()
    }
}

actor SeenKeys {
    var keys: [SSHPublicKey] = []
    func add(_ key: SSHPublicKey) { keys.append(key) }
}

/// Collects a shell's output so tests can wait for text to appear.
actor ByteCounter {
    private(set) var total = 0
    private(set) var sawMarker = false
    private var tail: [UInt8] = []
    private var handler: ((Int) -> Void)?

    func setHandler(_ handler: @escaping @Sendable (Int) -> Void) { self.handler = handler }

    /// Returns true once the marker has been seen.
    func add(_ bytes: [UInt8]) -> Bool {
        total += bytes.count
        handler?(bytes.count)
        tail = Array((tail + bytes).suffix(64))
        if String(decoding: tail, as: UTF8.self).contains("DONE-42") { sawMarker = true }
        return sawMarker
    }
}

actor OutputReader {
    private(set) var text = ""
    private var exit: (status: Int?, signal: String?)?
    private var task: Task<Void, Never>?

    init(_ shell: SSHShell) {
        Task { await self.start(shell) }
    }

    private func start(_ shell: SSHShell) {
        task = Task {
            for await event in shell.events {
                switch event {
                case .output(let bytes):
                    self.append(bytes)
                    shell.outputHandled(bytes.count)
                case .exited(let status, let signal): self.finish(status, signal)
                }
            }
        }
    }

    private func append(_ bytes: [UInt8]) { text += String(decoding: bytes, as: UTF8.self) }
    private func finish(_ status: Int?, _ signal: String?) { exit = (status, signal) }

    func waitFor(_ needle: String, timeout: Duration = .seconds(5)) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if text.contains(needle) { return true }
            try await Task.sleep(for: .milliseconds(25))
        }
        print("waited for \(needle.debugDescription), got:\n\(text)")
        return false
    }

    func waitForExit(timeout: Duration = .seconds(5)) async throws -> (status: Int?, signal: String?) {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let exit { return exit }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw SSHConnectionError.timedOut
    }
}
