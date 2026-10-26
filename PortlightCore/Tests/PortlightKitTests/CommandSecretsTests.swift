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

    @Test(arguments: [
        "mysql -u root -phunter2",
        "sshpass -p hunter2 ssh me@host",
        "export DB_PASSWORD=hunter2",
        "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY aws s3 ls",
        "aws configure set aws_access_key_id AKIAIOSFODNN7EXAMPLE",
        "git clone https://ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789@github.com/me/repo",
        "curl -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc' https://x",
        "psql postgres://app:hunter2@db.internal/app",
        "vault login token=s.abcdefgh12345678",
        "app --api-key=sk-live-1234567890abcdef",
        "app --password hunter2",
        "echo '-----BEGIN OPENSSH PRIVATE KEY-----'",
        "curl -u admin:hunter2 https://example.com",
        "SLACK=xoxb-123456789012-abcdefghij",
    ])
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

    @Test func startersPassTheirOwnCheck() {
        for snippet in Snippet.starters {
            #expect(CommandSecrets.problems(in: snippet.command).isEmpty, "\(snippet.command)")
        }
        #expect(Snippet.starters.contains { $0.command == "git status" })
        // Changes infrastructure: typed, not run, until Return is pressed.
        #expect(Snippet.starters.first { $0.command == "terraform apply" }?.runImmediately == false)
    }
}
