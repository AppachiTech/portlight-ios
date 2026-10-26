import Testing
@testable import PortlightKit

@Suite struct CommandSecretsTests {
    @Test(arguments: [
        "git status",
        "git pull --rebase",
        "terraform apply",
        "terraform plan -var-file=prod.tfvars",
        "kubectl get pods -n kube-system",
        "aws s3 ls --profile prod",
        "docker login -u me --password-stdin < ~/.docker-pass",
        "mysql -u root -p",
        "export GITHUB_TOKEN=$(gh auth token)",
        "curl -H \"Authorization: Bearer $TOKEN\" https://api.example.com",
        "psql postgres://app@db.internal/app",
        "echo password reset done",
        "git log --format='%h %s' -n 20",
        "sha256sum release.tar.gz",
    ])
    func genericCommandsAreFine(_ command: String) {
        #expect(CommandSecrets.problems(in: command).isEmpty, "\(command)")
    }

    /// Commands holding a secret. Token-shaped values are split so secret
    /// scanners don't flag this file; they're made-up examples.
    static let withSecrets: [String] = [
        "mysql -u root -phunter2",
        "sshpass -p hunter2 ssh me@host",
        "export DB_PASSWORD=hunter2",
        "AWS_SECRET_ACCESS_KEY=" + "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY aws s3 ls",
        "aws configure set aws_access_key_id " + "AKIA" + "IOSFODNN7EXAMPLE",
        "git clone https://" + "ghp_" + "aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789@github.com/me/repo",
        "curl -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc' https://x",
        "psql postgres://app:hunter2@db.internal/app",
        "vault login token=s.abcdefgh12345678",
        "app --api-key=sk-live-1234567890abcdef",
        "app --password hunter2",
        "echo '-----BEGIN OPENSSH PRIVATE KEY-----'",
        "curl -u admin:hunter2 https://example.com",
        "SLACK=" + "xoxb-" + "123456789012-abcdefghij",
    ]

    @Test(arguments: withSecrets)
    func secretsAreCaught(_ command: String) {
        #expect(!CommandSecrets.problems(in: command).isEmpty, "\(command)")
    }

    @Test func problemsDescribeWhatWasFound() {
        let problems = CommandSecrets.problems(in: "export DB_PASSWORD=hunter2 && git push https://me:pw@example.com/r")
        #expect(problems.count == 2)
        #expect(problems.allSatisfy { !$0.isEmpty })
        // The secret itself is never repeated back.
        #expect(problems.allSatisfy { !$0.contains("hunter2") && !$0.contains(":pw@") })
    }

    @Test(arguments: [
        String(repeating: "token", count: 2000),
        String(repeating: "password_", count: 1200),
        "a://" + String(repeating: "x:", count: 5000),
        "--password" + String(repeating: " ", count: 10000),
        "-u " + String(repeating: "a", count: 10000),
        "authorization: bearer" + String(repeating: " ", count: 10000),
        "mysql " + String(repeating: "a ", count: 5000),
        String(repeating: "eyJabcde.", count: 1200),
    ])
    func longInputStaysFast(_ input: String) {
        // The check runs on the main thread as the editor redraws, so it
        // must stay linear: a 2,000-character string once took 12 seconds.
        let started = ContinuousClock.now
        _ = CommandSecrets.problems(in: input)
        #expect(ContinuousClock.now - started < .milliseconds(500), "\(input.prefix(20))…")
    }

    @Test func startersPassTheirOwnCheck() {
        for snippet in Snippet.starters {
            #expect(CommandSecrets.problems(in: snippet.command).isEmpty, "\(snippet.command)")
        }
        #expect(Snippet.starters.contains { $0.command == "git status" })
        // Changes infrastructure: typed, not run, until Return is pressed.
        #expect(Snippet.starters.first { $0.command == "terraform apply" }?.runImmediately == false)
    }
}
