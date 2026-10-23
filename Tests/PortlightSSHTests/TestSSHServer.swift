import Foundation
import PortlightKit
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A throwaway OpenSSH server for integration tests: runs as the current
/// user on 127.0.0.1 with its own config, host key and authorized_keys in a
/// temporary directory. Nothing system-wide is touched. Tests skip when
/// sshd isn't installed.
final class TestSSHServer: @unchecked Sendable {
    let directory: URL
    let port: Int
    let username: String
    let hostKey: SSHPublicKey
    let hostKeyFingerprint: String
    private let pid: pid_t

    static let sshdPath = ["/usr/sbin/sshd", "/usr/local/sbin/sshd", "/opt/homebrew/sbin/sshd"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    static let keygenPath = ["/usr/bin/ssh-keygen", "/usr/local/bin/ssh-keygen", "/opt/homebrew/bin/ssh-keygen"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static var isAvailable: Bool { sshdPath != nil && keygenPath != nil && ProcessInfo.processInfo.environment["PORTLIGHT_SKIP_SSHD"] == nil }

    init(authorizedKeys: [SSHPublicKey], extraConfig: String = "") throws {
        guard let sshd = Self.sshdPath, let keygen = Self.keygenPath else { throw CocoaError(.featureUnsupported) }
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("portlight-sshd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        username = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()

        let hostKeyPath = directory.appendingPathComponent("host_ed25519").path
        try Self.run(keygen, ["-q", "-t", "ed25519", "-N", "", "-f", hostKeyPath])
        let pub = try String(contentsOfFile: hostKeyPath + ".pub", encoding: .utf8)
        hostKey = try SSHPublicKey(openSSH: pub.trimmingCharacters(in: .whitespacesAndNewlines))
        hostKeyFingerprint = try Self.run(keygen, ["-lf", hostKeyPath + ".pub"]).split(separator: " ")[1].description

        let authorized = authorizedKeys.map { $0.openSSHString(comment: "test") }.joined(separator: "\n") + "\n"
        try authorized.write(to: directory.appendingPathComponent("authorized_keys"), atomically: true, encoding: .utf8)

        var lastError: Error?
        for _ in 0..<8 {
            let candidate = Int.random(in: 20000...60000)
            let config = """
            Port \(candidate)
            ListenAddress 127.0.0.1
            HostKey \(hostKeyPath)
            PidFile \(directory.path)/sshd.pid
            AuthorizedKeysFile \(directory.path)/authorized_keys
            StrictModes no
            UsePAM no
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PubkeyAuthentication yes
            AllowTcpForwarding yes
            PermitTTY yes
            LogLevel ERROR
            \(extraConfig)
            """
            let configPath = directory.appendingPathComponent("sshd_config")
            try config.write(to: configPath, atomically: true, encoding: .utf8)
            let pid = try Spawn.start(sshd, ["-D", "-e", "-f", configPath.path], output: "/dev/null")
            if Self.waitForPort(candidate, pid: pid) {
                self.port = candidate
                self.pid = pid
                return
            }
            Spawn.stop(pid)
            lastError = CocoaError(.fileReadUnknown)
        }
        throw lastError ?? CocoaError(.fileReadUnknown)
    }

    private let stopped = NSLock()
    private var isStopped = false

    func stop() {
        let first = stopped.withLock { () -> Bool in
            defer { isStopped = true }
            return !isStopped
        }
        guard first else { return }
        Spawn.stop(pid)
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { stop() }

    /// Runs a tool and returns its output.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent("portlight-tool-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: outputPath) }
        let pid = try Spawn.start(tool, arguments, output: outputPath)
        let status = Spawn.wait(pid)
        let text = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
        guard status == 0 else {
            throw NSError(domain: "TestSSHServer", code: Int(status), userInfo: [NSLocalizedDescriptionKey: text])
        }
        return text
    }

    /// True once something accepts TCP connections on the port.
    static func waitForPort(_ port: Int, pid: pid_t) -> Bool {
        for _ in 0..<50 {
            guard Spawn.isRunning(pid) else { return false }
            let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(UInt16(port).bigEndian)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            close(fd)
            if result == 0 { return true }
            usleep(100_000)
        }
        return false
    }
}

/// posix_spawn with waitpid on the exact child. Foundation's Process on
/// Linux can miss a child's exit while another child (sshd) is alive.
enum Spawn {
    static func start(_ path: String, _ arguments: [String], output: String) throws -> pid_t {
        var actions = posix_spawn_file_actions_t()
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        let argv = ([path] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, path, &actions, nil, argv, environ)
        guard result == 0 else { throw NSError(domain: "Spawn", code: Int(result)) }
        return pid
    }

    static func wait(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        // WIFEXITED / WEXITSTATUS by hand (the C macros aren't imported).
        return (status & 0x7F) == 0 ? (status >> 8) & 0xFF : -1
    }

    static func isRunning(_ pid: pid_t) -> Bool {
        var status: Int32 = 0
        return waitpid(pid, &status, WNOHANG) == 0
    }

    static func stop(_ pid: pid_t) {
        guard isRunning(pid) else { return }
        kill(pid, SIGTERM)
        _ = wait(pid)
    }
}
