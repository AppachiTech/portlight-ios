import Foundation
import Testing
@testable import PortlightSSH

@MainActor
@Suite(.serialized, .enabled(if: TestSSHServer.isAvailable, "needs OpenSSH's sshd and ssh-keygen"))
struct TerminalSessionTests {
    let library = Library(storage: MemoryStorage(), secrets: InMemorySecretStore())

    /// A server that accepts the library's first key, and a saved host for it.
    func setUp(startupCommand: String? = nil) throws -> (TestSSHServer, SSHHost) {
        let record = try library.generateKey(named: "test")
        let server = try TestSSHServer(authorizedKeys: [record.publicKey])
        let host = SSHHost(label: "local", hostname: "127.0.0.1", port: server.port, username: server.username,
                           auth: .key(record.id), startupCommand: startupCommand)
        try library.save(host)
        return (server, host)
    }

    func waitUntil(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func firstConnectionAsksAboutTheHostKeyThenRemembersIt() async throws {
        let (server, host) = try setUp()
        defer { server.stop() }
        let session = TerminalSession(host: host, library: library)
        let output = OutputCollector()
        session.attach { output.append($0) }
        session.connect()
        try await waitUntil { session.hostKeyPrompt != nil }
        let prompt = try #require(session.hostKeyPrompt)
        #expect(prompt.kind == .new)
        #expect(prompt.fingerprint == server.hostKeyFingerprint)
        #expect(prompt.hostLabel == "local")
        prompt.trust()
        try await waitUntil { session.state == .connected }
        #expect(library.hostKeyVerdict(host: "127.0.0.1", port: server.port, key: server.hostKey) == .trusted)
        #expect(library.host(host.id)?.lastConnectedAt != nil)

        session.send(Array("echo READY-$((20+22))\r".utf8))
        try await waitUntil { output.text.contains("READY-42") }

        // Reconnecting doesn't ask again.
        session.disconnect()
        #expect(session.state == .disconnected("Disconnected"))
        session.connect()
        try await waitUntil { session.state == .connected }
        #expect(session.hostKeyPrompt == nil)
        session.disconnect()
    }

    @Test func aPromptLeftOpenWhenTheServerGivesUpIsClosed() async throws {
        let record = try library.generateKey(named: "grace")
        let server = try TestSSHServer(authorizedKeys: [record.publicKey], extraConfig: "LoginGraceTime 2")
        defer { server.stop() }
        let host = SSHHost(label: "grace", hostname: "127.0.0.1", port: server.port, username: server.username,
                           auth: .key(record.id))
        try library.save(host)
        let session = TerminalSession(host: host, library: library)
        session.connect()
        try await waitUntil { session.hostKeyPrompt != nil }
        // Unanswered until the server hangs up: the stale sheet must go.
        try await waitUntil(.seconds(15)) {
            if case .failed = session.state { return true }
            return false
        }
        #expect(session.hostKeyPrompt == nil)
        #expect(library.hostKeyVerdict(host: "127.0.0.1", port: server.port, key: server.hostKey) == .unknown)
    }

    @Test func rejectingTheHostKeyFailsWithoutTrusting() async throws {
        let (server, host) = try setUp()
        defer { server.stop() }
        let session = TerminalSession(host: host, library: library)
        session.connect()
        try await waitUntil { session.hostKeyPrompt != nil }
        session.hostKeyPrompt?.reject()
        await session.waitForConnectAttempt()
        guard case .failed(let message) = session.state else {
            Issue.record("expected failure, got \(session.state)")
            return
        }
        #expect(message.contains("host key"))
        #expect(library.knownHosts.entries.isEmpty)
    }

    @Test func aChangedHostKeyIsFlagged() async throws {
        let (server, host) = try setUp()
        defer { server.stop() }
        let impostor = SSHPrivateKey.generate(.ed25519).publicKey
        library.trustHostKey(host: "127.0.0.1", port: server.port, key: impostor)
        let session = TerminalSession(host: host, library: library)
        session.connect()
        try await waitUntil { session.hostKeyPrompt != nil }
        #expect(session.hostKeyPrompt?.kind == .changed(previousFingerprint: impostor.sha256Fingerprint))
        session.hostKeyPrompt?.reject()
        await session.waitForConnectAttempt()
        #expect(library.hostKeyVerdict(host: "127.0.0.1", port: server.port, key: impostor) == .trusted, "old key kept")
    }

    @Test func revokedKeysAreRefusedWithoutAsking() async throws {
        let (server, host) = try setUp()
        defer { server.stop() }
        library.importKnownHosts("@revoked * \(server.hostKey.openSSHString())")
        let session = TerminalSession(host: host, library: library)
        let output = OutputCollector()
        session.attach { output.append($0) }
        session.connect()
        await session.waitForConnectAttempt()
        #expect(session.hostKeyPrompt == nil)
        guard case .failed = session.state else {
            Issue.record("expected failure, got \(session.state)")
            return
        }
        #expect(output.text.contains("revoked"))
    }

    @Test func startupCommandRunsAndExitEndsTheSession() async throws {
        let (server, host) = try setUp(startupCommand: "echo STARTUP-$((2+3))")
        defer { server.stop() }
        library.trustHostKey(host: "127.0.0.1", port: server.port, key: server.hostKey)
        let session = TerminalSession(host: host, library: library)
        session.connect()
        try await waitUntil { session.state == .connected }
        // Output arriving before a view attaches is kept and replayed.
        try await Task.sleep(for: .milliseconds(500))
        let output = OutputCollector()
        session.attach { output.append($0) }
        try await waitUntil { output.text.contains("STARTUP-5") }

        session.resize(TerminalSize(columns: 90, rows: 33))
        try await Task.sleep(for: .milliseconds(150))
        session.send(Array("stty size; exit 4\r".utf8))
        try await waitUntil { session.state == .disconnected("Session ended (exit 4)") }
        #expect(output.text.contains("33 90"))
        #expect(output.text.contains("Tap Reconnect"))
    }

    @Test func passwordIsAskedForAndRetriedWhenRefused() async throws {
        let (server, _) = try setUp()
        defer { server.stop() }
        library.trustHostKey(host: "127.0.0.1", port: server.port, key: server.hostKey)
        // This server refuses passwords, so every attempt fails.
        let host = SSHHost(label: "pw", hostname: "127.0.0.1", port: server.port, username: server.username, auth: .password)
        try library.save(host)
        try library.setPassword("saved-but-wrong", for: host.id)
        let session = TerminalSession(host: host, library: library)
        session.connect()
        try await waitUntil { session.passwordPrompt != nil }
        let prompt = try #require(session.passwordPrompt)
        #expect(prompt.message?.contains("didn't accept") == true)
        #expect(prompt.username == server.username)
        prompt.submit("typed", save: true)
        try await waitUntil { session.passwordPrompt != nil && session.passwordPrompt?.id != prompt.id }
        session.passwordPrompt?.cancel()
        await session.waitForConnectAttempt()
        #expect(session.state == .disconnected("Cancelled"))
        #expect(library.password(for: host.id) == "saved-but-wrong", "a refused password is never saved")
    }

    @Test func connectsThroughSavedJumpHosts() async throws {
        let record = try library.generateKey(named: "both")
        let bastionServer = try TestSSHServer(authorizedKeys: [record.publicKey])
        let targetServer = try TestSSHServer(authorizedKeys: [record.publicKey])
        defer {
            bastionServer.stop()
            targetServer.stop()
        }
        let bastion = SSHHost(label: "bastion", hostname: "127.0.0.1", port: bastionServer.port,
                              username: bastionServer.username, auth: .key(record.id))
        let target = SSHHost(label: "private", hostname: "127.0.0.1", port: targetServer.port,
                             username: targetServer.username, auth: .key(record.id), jumpHostID: bastion.id)
        try library.save(bastion)
        try library.save(target)
        let session = TerminalSession(host: target, library: library)
        let output = OutputCollector()
        session.attach { output.append($0) }
        session.connect()
        try await waitUntil { session.hostKeyPrompt?.hostLabel == "bastion" }
        session.hostKeyPrompt?.trust()
        try await waitUntil { session.hostKeyPrompt?.hostLabel == "private" }
        session.hostKeyPrompt?.trust()
        try await waitUntil { session.state == .connected }
        session.send(Array("echo VIA-$((1+1))\r".utf8))
        try await waitUntil { output.text.contains("VIA-2") }
        session.disconnect()
    }

    @Test func managerTracksTabs() async throws {
        let (server, host) = try setUp()
        defer { server.stop() }
        library.trustHostKey(host: "127.0.0.1", port: server.port, key: server.hostKey)
        let manager = SessionManager(library: library)
        let first = manager.open(host)
        let second = manager.open(host)
        #expect(manager.activeID == second.id)
        try await waitUntil { first.state == .connected && second.state == .connected }
        manager.close(second)
        #expect(manager.activeID == first.id)
        manager.closeAll()
        #expect(manager.sessions.isEmpty && manager.activeID == nil)
    }

    @Test func deletedKeyIsExplained() async throws {
        let (server, host) = try setUp()
        defer { server.stop() }
        var orphan = host
        orphan.auth = .key(UUID())
        try library.save(orphan)
        let session = TerminalSession(host: orphan, library: library)
        session.connect()
        await session.waitForConnectAttempt()
        guard case .failed(let message) = session.state else {
            Issue.record("expected failure, got \(session.state)")
            return
        }
        #expect(message.contains("was deleted"))
    }
}

@MainActor
final class OutputCollector {
    private(set) var text = ""
    func append(_ bytes: [UInt8]) { text += String(decoding: bytes, as: UTF8.self) }
}
