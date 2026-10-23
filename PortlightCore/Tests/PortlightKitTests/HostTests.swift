import Foundation
import Testing
@testable import PortlightKit

@Suite struct HostTests {
    @Test func displayNameAndAddress() {
        var host = SSHHost(hostname: "1.2.3.4", username: "ubuntu")
        #expect(host.displayName == "ubuntu@1.2.3.4")
        host.port = 2222
        host.label = "  web  "
        #expect(host.displayName == "web")
        #expect(host.address == "ubuntu@1.2.3.4:2222")
        #expect(SSHHost(hostname: "2001:db8::1", username: "me").address == "me@[2001:db8::1]")
    }

    @Test func validation() {
        #expect(SSHHost(hostname: "box", username: "me").validate().isEmpty)
        #expect(SSHHost(hostname: " ", username: "me").validate() == [.missingHostname])
        #expect(SSHHost(hostname: "a b", username: "me").validate() == [.invalidHostname])
        #expect(SSHHost(hostname: "box", port: 0, username: "").validate() == [.invalidPort, .missingUsername])
        #expect(SSHHost(hostname: "box", username: "me@x").validate() == [.invalidUsername])
    }

    @Test(arguments: [
        ("ubuntu@1.2.3.4", QuickConnect.Target(username: "ubuntu", hostname: "1.2.3.4", port: 22)),
        ("root@box:2222", .init(username: "root", hostname: "box", port: 2222)),
        ("me@[2001:db8::1]:2200", .init(username: "me", hostname: "2001:db8::1", port: 2200)),
        ("2001:db8::1", .init(username: nil, hostname: "2001:db8::1", port: 22)),
        ("ssh -p 2222 -l admin host.example.com", .init(username: "admin", hostname: "host.example.com", port: 2222)),
        ("ssh -i key.pem ec2-user@ec2-1-2-3-4.compute-1.amazonaws.com", .init(username: "ec2-user", hostname: "ec2-1-2-3-4.compute-1.amazonaws.com", port: 22)),
        ("ssh://deploy@git.example.com:2022", .init(username: "deploy", hostname: "git.example.com", port: 2022)),
    ])
    func quickConnectParses(text: String, expected: QuickConnect.Target) {
        #expect(QuickConnect.parse(text) == expected)
    }

    @Test(arguments: ["", "ssh", "a@b:notaport", "a@b:70000", "one two", "me@[::1"])
    func quickConnectRejects(text: String) {
        #expect(QuickConnect.parse(text) == nil)
    }

    @Test func providerDefaultsAndGCPKeyLine() throws {
        #expect(CloudProvider.aws.suggestedUsernames.first == "ec2-user")
        #expect(CloudProvider.azure.suggestedUsernames == ["azureuser"])
        let key = SSHPrivateKey.generate(.ed25519).publicKey
        #expect(CloudProvider.gcp.authorizedKeyLine(for: key, username: "madhu", keyName: "iPhone").hasSuffix(" madhu"))
        #expect(CloudProvider.aws.authorizedKeyLine(for: key, username: "ec2-user", keyName: "iPhone").hasSuffix(" iPhone"))
    }

    @Test func providerGuessFromDNS() {
        #expect(SSHConfigParser.guessProvider("ec2-3-80-1-2.compute-1.amazonaws.com") == .aws)
        #expect(SSHConfigParser.guessProvider("2.1.80.34.bc.googleusercontent.com") == .gcp)
        #expect(SSHConfigParser.guessProvider("myvm.eastus.cloudapp.azure.com") == .azure)
        #expect(SSHConfigParser.guessProvider("10.0.0.1") == .other)
    }

    @Test func hostCodableRoundTripAndForwardCompatibility() throws {
        let host = SSHHost(label: "db", hostname: "db.internal", port: 2200, username: "admin", auth: .key(UUID()),
                        provider: .gcp, group: "Prod", jumpHostID: UUID(), startupCommand: "tmux a")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(host)
        #expect(try decoder.decode(SSHHost.self, from: data).hostname == "db.internal")
        // Unknown extra fields from a newer version are ignored.
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["futureField"] = 42
        let extended = try JSONSerialization.data(withJSONObject: object)
        #expect(try decoder.decode(SSHHost.self, from: extended).auth == host.auth)
    }
}

@Suite struct SSHConfigTests {
    static let config = """
    # Personal
    Host bastion
        HostName bastion.example.com
        User ec2-user
        IdentityFile ~/.ssh/aws.pem

    Host web-* db
      User ubuntu
      ProxyJump bastion

    Host web-1
      HostName 10.0.1.10
      Port 2222

    Host db
      HostName=10.0.2.20
      User postgres   # overridden? no: first value wins, ubuntu came first

    Host gcp-vm
      Hostname "34.1.2.3"
      user madhu

    Match host *.corp
      User corp

    Host *
      User fallback
      Port 22
      ServerAliveInterval 30

    Include ~/.ssh/config.d/*
    Host !nothing  weird?
    """

    @Test func readsEntriesWithFirstValueWins() {
        let result = SSHConfigParser.parse(Self.config)
        let byAlias = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.alias, $0) })
        #expect(result.entries.map(\.alias) == ["bastion", "db", "web-1", "gcp-vm"])
        #expect(byAlias["bastion"]?.hostname == "bastion.example.com")
        #expect(byAlias["bastion"]?.user == "ec2-user")
        #expect(byAlias["bastion"]?.identityFile == "~/.ssh/aws.pem")
        #expect(byAlias["web-1"]?.hostname == "10.0.1.10")
        #expect(byAlias["web-1"]?.user == "ubuntu")
        #expect(byAlias["web-1"]?.port == 2222)
        #expect(byAlias["web-1"]?.proxyJump == "bastion")
        #expect(byAlias["db"]?.user == "ubuntu")
        #expect(byAlias["db"]?.hostname == "10.0.2.20")
        #expect(byAlias["gcp-vm"]?.hostname == "34.1.2.3")
        #expect(byAlias["gcp-vm"]?.user == "madhu")
        #expect(byAlias["gcp-vm"]?.port == 22)
        #expect(result.warnings.contains { $0.contains("Match") })
        #expect(result.warnings.contains { $0.contains("Include") })
    }

    @Test func globAndNegation() {
        #expect(SSHConfigParser.glob("web-*", "web-12"))
        #expect(SSHConfigParser.glob("w?b", "WEB"))
        #expect(!SSHConfigParser.glob("web-?", "web-12"))
        #expect(SSHConfigParser.glob("*", ""))
        #expect(SSHConfigParser.matches("prod-db", patterns: ["prod-*", "!prod-db"]) == false)
        #expect(SSHConfigParser.matches("prod-web", patterns: ["prod-*", "!prod-db"]))
    }

    @Test func makesHostsAndLinksJumps() {
        let entries = SSHConfigParser.parse(Self.config).entries
        let hosts = SSHConfigParser.makeHosts(from: entries)
        let bastion = hosts.first { $0.label == "bastion" }!
        let web = hosts.first { $0.label == "web-1" }!
        #expect(web.jumpHostID == bastion.id)
        #expect(bastion.notes?.contains("aws.pem") == true)
        #expect(bastion.provider == .other)
        // Already saved hosts aren't imported twice, but can be jump targets.
        let again = SSHConfigParser.makeHosts(from: entries, existing: [bastion])
        #expect(!again.contains { $0.label == "bastion" })
        #expect(again.first { $0.label == "web-1" }?.jumpHostID == bastion.id)
    }

    @Test func unknownJumpIsNoted() {
        let entries = SSHConfigParser.parse("Host a\n  HostName a.example\n  ProxyJump me@gateway:2222\n").entries
        let host = SSHConfigParser.makeHosts(from: entries)[0]
        #expect(host.jumpHostID == nil)
        #expect(host.notes?.contains("gateway") == true)
    }
}

@Suite struct KnownHostsTests {
    let keyA = SSHPrivateKey.generate(.ed25519).publicKey
    let keyB = SSHPrivateKey.generate(.ed25519).publicKey
    let keyP = SSHPrivateKey.generate(.ecdsaP256).publicKey

    @Test func trustOnFirstUseFlow() {
        var known = KnownHosts()
        #expect(known.verdict(host: "box", port: 22, key: keyA) == .unknown(otherTypesKnown: false))
        known.trust(host: "Box", port: 22, key: keyA)
        #expect(known.verdict(host: "box", port: 22, key: keyA) == .trusted)
        #expect(known.verdict(host: "box", port: 22, key: keyB) == .changed(previous: keyA))
        #expect(known.verdict(host: "box", port: 22, key: keyP) == .unknown(otherTypesKnown: true))
        // Another port is another host.
        #expect(known.verdict(host: "box", port: 2222, key: keyA) == .unknown(otherTypesKnown: false))
        // Replacing deliberately.
        known.trust(host: "box", port: 22, key: keyB)
        #expect(known.verdict(host: "box", port: 22, key: keyB) == .trusted)
        #expect(known.entries.count == 1)
        known.forget(host: "box", port: 22)
        #expect(known.entries.isEmpty)
    }

    @Test func nameFormatMatchesOpenSSH() {
        #expect(KnownHosts.hostKeyName(host: "Box", port: 22) == "box")
        #expect(KnownHosts.hostKeyName(host: "10.0.0.5", port: 2222) == "[10.0.0.5]:2222")
    }

    @Test func importsOpenSSHIncludingHashedAndRevoked() throws {
        let line = keyA.openSSHString()
        let text = """
        # comment
        bastion.example.com,10.0.0.9 \(line)
        |1|AAECAwQFBgcICQoLDA0ODxAREhM=|hW7hge8XWLBv0cG0pl8cz3E+/cQ= \(keyB.openSSHString())
        @revoked * \(keyP.openSSHString())
        @cert-authority *.example.com \(line)
        garbage line
        """
        var known = KnownHosts()
        #expect(known.importOpenSSH(text) == 4)
        #expect(known.verdict(host: "10.0.0.9", port: 22, key: keyA) == .trusted)
        #expect(known.verdict(host: "bastion.example.com", port: 22, key: keyA) == .trusted)
        #expect(known.verdict(host: "10.0.0.5", port: 2222, key: keyB) == .trusted)  // hashed
        #expect(known.verdict(host: "anything", port: 22, key: keyP) == .revoked)
        #expect(known.importOpenSSH(text) == 0, "re-importing adds nothing")
        let exported = known.exportOpenSSH()
        #expect(exported.contains("@revoked * ecdsa-sha2-nistp256"))
        var again = KnownHosts()
        #expect(again.importOpenSSH(exported) == 4)
    }

    @Test func hashedEntryFromSSHKeygen() throws {
        let line = "|1|XsR5D3GnS1By5xxR7S6poX5Mi3U=|vljhXwYNRh3ahtljTHzwglRKpS4= ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJnnIVEZ0KqglYfW1V/OpN9io9SBodLAG/hEffisjAUi"
        var known = KnownHosts()
        known.importOpenSSH(line)
        let key = try SSHPublicKey(openSSH: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJnnIVEZ0KqglYfW1V/OpN9io9SBodLAG/hEffisjAUi")
        #expect(known.verdict(host: "box.example.com", port: 22, key: key) == .trusted)
        #expect(known.verdict(host: "other.example.com", port: 22, key: key) == .unknown(otherTypesKnown: false))
    }

    @Test func pythonHashedNameMatches() {
        #expect(KnownHosts.patternMatches("|1|AAECAwQFBgcICQoLDA0ODxAREhM=|D1nwL0aCEF7sboOeRlA0DDMPIMs=", name: "bastion.example.com"))
        #expect(!KnownHosts.patternMatches("|1|AAECAwQFBgcICQoLDA0ODxAREhM=|D1nwL0aCEF7sboOeRlA0DDMPIMs=", name: "bastion"))
        #expect(!KnownHosts.patternMatches("|1|bad", name: "x"))
    }
}
