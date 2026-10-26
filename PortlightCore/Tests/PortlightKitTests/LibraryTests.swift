import Foundation
import Testing
@testable import PortlightKit

@MainActor
@Suite struct LibraryTests {
    let storage = MemoryStorage()
    let secrets = InMemorySecretStore()

    func makeLibrary() -> Library { Library(storage: storage, secrets: secrets) }

    @Test func hostsPersistAcrossLaunches() throws {
        let library = makeLibrary()
        // Whole seconds: the JSON files store ISO 8601 dates, which drop fractions.
        let host = SSHHost(label: "web", hostname: "web.example.com", username: "ubuntu", provider: .aws, group: "Prod",
                        createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        try library.save(host)
        try library.setPassword("hunter2", for: host.id)
        let reopened = makeLibrary()
        #expect(reopened.hosts == [host])
        #expect(reopened.password(for: host.id) == "hunter2")
        // The password is not in the JSON on disk.
        let json = String(decoding: try storage.read("hosts.json")!, as: UTF8.self)
        #expect(!json.contains("hunter2"))
    }

    @Test func invalidHostsAreRefused() {
        let library = makeLibrary()
        #expect(throws: HostValidationError.missingHostname) { try library.save(SSHHost(hostname: "", username: "me")) }
        #expect(library.hosts.isEmpty)
    }

    @Test func updateDeleteAndDuplicate() throws {
        let library = makeLibrary()
        var host = SSHHost(hostname: "a", username: "me")
        try library.save(host)
        host.port = 2222
        try library.save(host)
        #expect(library.hosts.count == 1 && library.hosts[0].port == 2222)
        let copy = try library.duplicate(host)
        #expect(library.hosts.count == 2 && copy.id != host.id && copy.lastConnectedAt == nil)
        try library.setPassword("pw", for: host.id)
        library.delete(host)
        #expect(library.hosts.map(\.id) == [copy.id])
        #expect(library.password(for: host.id) == nil)
    }

    @Test func jumpHostsAreCheckedForLoops() throws {
        let library = makeLibrary()
        let bastion = SSHHost(label: "bastion", hostname: "b", username: "me")
        try library.save(bastion)
        var inner = SSHHost(label: "inner", hostname: "i", username: "me", jumpHostID: bastion.id)
        try library.save(inner)
        #expect(try library.jumpChain(for: inner.id).map(\.label) == ["bastion", "inner"])

        var looped = bastion
        looped.jumpHostID = inner.id
        #expect(throws: LibraryError.jumpLoop) { try library.save(looped) }
        inner.jumpHostID = inner.id
        #expect(throws: LibraryError.jumpLoop) { try library.save(inner) }

        // Deleting the bastion clears the reference.
        library.delete(bastion)
        #expect(library.hosts[0].jumpHostID == nil)
    }

    @Test func sectionsGroupSortAndSearch() throws {
        let library = makeLibrary()
        let now = Date()
        for (i, name) in ["zeta", "alpha", "mid", "beta", "gamma"].enumerated() {
            var host = SSHHost(label: name, hostname: "\(name).example.com", username: "me", provider: i == 0 ? .gcp : .aws)
            host.group = i < 2 ? "Prod" : nil
            host.lastConnectedAt = i == 3 ? now : (i == 4 ? now.addingTimeInterval(-60) : nil)
            try library.save(host)
        }
        let sections = library.sections()
        #expect(sections.map(\.title) == ["Recent", "Hosts", "Prod"])
        #expect(sections[0].hosts.map(\.label) == ["beta", "gamma"])
        #expect(sections[1].hosts.map(\.label) == ["beta", "gamma", "mid"])
        #expect(sections[2].hosts.map(\.label) == ["alpha", "zeta"])
        #expect(library.sections(matching: "google").flatMap(\.hosts).map(\.label) == ["zeta"])
        #expect(library.sections(matching: "ALPHA.example").flatMap(\.hosts).map(\.label) == ["alpha"])
        #expect(library.groups == ["Prod"])
    }

    @Test func keysGenerateImportExportDelete() throws {
        let library = makeLibrary()
        let generated = try library.generateKey(named: "iPhone")
        #expect(generated.algorithm == .ed25519 && generated.storage == .keychain)
        #expect(try library.privateKey(for: generated).publicKey == generated.publicKey)

        let imported = try library.importKey(KeyFixtures.p384Enc, passphrase: KeyFixtures.passphrase)
        #expect(imported.name == "portlight-test-p384_enc")
        #expect(imported.fingerprint == KeyFixtures.p384EncFingerprint)
        #expect(throws: LibraryError.duplicateKey("portlight-test-p384_enc")) {
            try library.importKey(KeyFixtures.p384Enc, passphrase: KeyFixtures.passphrase)
        }

        #expect(throws: LibraryError.weakExportPassphrase) { try library.exportPrivateKey(generated, passphrase: "short") }
        let exported = try library.exportPrivateKey(generated, passphrase: "long enough")
        #expect(try OpenSSHKeyFile.isEncrypted(pem: exported))
        #expect(try KeyImporter.importKey(exported, passphrase: "long enough").key.publicKey == generated.publicKey)

        let host = SSHHost(hostname: "box", username: "me", auth: .key(generated.id))
        try library.save(host)
        #expect(library.hostsUsing(generated).map(\.id) == [host.id])
        library.delete(generated)
        #expect(library.hosts[0].auth == .password)
        #expect(throws: LibraryError.self) { try library.privateKey(for: generated) }
        #expect(!secrets.accounts.contains(SecretAccount.privateKey(generated.id)))

        let reopened = makeLibrary()
        #expect(reopened.keys.map(\.id) == [imported.id])
        library.rename(imported, to: "  laptop  ")
        #expect(makeLibrary().keys[0].name == "laptop")
    }

    @Test func secureEnclaveRecordsAreNotExportable() throws {
        let library = makeLibrary()
        let record = try KeyRecord(name: "SE", publicKey: SSHPrivateKey.generate(.ecdsaP256).publicKey, storage: .secureEnclave)
        library.addExternalKey(record)
        #expect(throws: LibraryError.keyNotExportable) { try library.exportPrivateKey(record, passphrase: "long enough") }
    }

    @Test func knownHostsPersist() throws {
        let library = makeLibrary()
        let key = SSHPrivateKey.generate(.ed25519).publicKey
        library.trustHostKey(host: "box", port: 22, key: key)
        #expect(makeLibrary().hostKeyVerdict(host: "box", port: 22, key: key) == .trusted)
        library.forgetHostKeys(host: "box", port: 22)
        #expect(makeLibrary().hostKeyVerdict(host: "box", port: 22, key: key) == .unknown)
        #expect(library.importKnownHosts("box \(key.openSSHString())") == 1)
    }

    @Test func importSSHConfig() {
        let library = makeLibrary()
        let (added, warnings) = library.importSSHConfig(SSHConfigTests.config)
        #expect(added.count == 4)
        #expect(!warnings.isEmpty)
        #expect(library.importSSHConfig(SSHConfigTests.config).added.isEmpty, "a second import adds nothing")
        #expect(makeLibrary().hosts.count == 4)
    }

    @Test func settingsAndSnippetsPersist() {
        let library = makeLibrary()
        #expect(library.snippets == Snippet.starters)
        library.settings.themeName = "Nord"
        let snippet = Snippet(title: "Logs", command: "tail -f /var/log/app.log")
        library.save(snippet)
        library.moveSnippets(from: [library.snippets.count - 1], to: 0)
        let reopened = makeLibrary()
        #expect(reopened.settings.themeName == "Nord")
        #expect(reopened.snippets.first == snippet)
        reopened.delete(snippet)
        #expect(makeLibrary().snippets == Snippet.starters)
    }

    @Test func corruptFileIsReportedNotFatal() throws {
        try storage.write(Data("{not json".utf8), name: "hosts.json")
        let library = makeLibrary()
        #expect(library.hosts.isEmpty)
        #expect(library.lastError?.contains("hosts.json") == true)
    }

    @Test func directoryStorageWritesFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("portlight-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let disk = try DirectoryStorage(directory: dir)
        try disk.write(Data("x".utf8), name: "a.json")
        #expect(try disk.read("a.json") == Data("x".utf8))
        #expect(try disk.read("missing.json") == nil)
    }
}

@MainActor
@Suite struct FreshInstallTests {
    @Test func leftoverSecretsAreClearedOnAFreshInstall() throws {
        // Keychain items outlive the app; its files don't.
        let storage = MemoryStorage()
        let secrets = InMemorySecretStore()
        try secrets.set(Data("old".utf8), for: SecretAccount.password(UUID()))
        Library.clearSecretsLeftFromAnEarlierInstall(storage: storage, secrets: secrets)
        #expect(secrets.accounts.isEmpty)
        // Only once: later launches keep what's stored.
        try secrets.set(Data("new".utf8), for: SecretAccount.password(UUID()))
        Library.clearSecretsLeftFromAnEarlierInstall(storage: storage, secrets: secrets)
        #expect(secrets.accounts.count == 1)
    }

    @Test func anExistingLibraryIsNeverCleared() throws {
        // Upgrading from a build without the marker must keep secrets.
        let storage = MemoryStorage()
        let secrets = InMemorySecretStore()
        let library = Library(storage: storage, secrets: secrets)
        let host = SSHHost(hostname: "box", username: "me")
        try library.save(host)
        try library.setPassword("pw", for: host.id)
        Library.clearSecretsLeftFromAnEarlierInstall(storage: storage, secrets: secrets)
        #expect(Library(storage: storage, secrets: secrets).password(for: host.id) == "pw")
    }
}
