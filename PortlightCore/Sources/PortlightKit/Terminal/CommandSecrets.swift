import Foundation

/// Spots passwords, keys and tokens written into a command, so saved
/// commands stay generic (`git status`, `terraform apply`) and never become
/// a place secrets sit in plain text. Values that refer to a variable or a
/// file (`$TOKEN`, `$(gh auth token)`, `< file`) are fine: that's the way to
/// write such commands.
public enum CommandSecrets {
    /// Plain descriptions of what was found, without repeating the secret.
    public static func problems(in command: String) -> [String] {
        var found: [String] = []
        let range = NSRange(command.startIndex..., in: command)
        for rule in rules where rule.regex.firstMatch(in: command, range: range) != nil {
            if !found.contains(rule.problem) { found.append(rule.problem) }
        }
        return found
    }

    private struct Rule {
        let regex: NSRegularExpression
        let problem: String

        init(_ pattern: String, _ problem: String) {
            // The patterns are fixed, so a bad one is a programming error.
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.problem = problem
        }
    }

    // Quantifiers before a fixed point are bounded so every rule stays
    // linear: this runs on the main thread while the editor redraws.
    private static let rules: [Rule] = [
        Rule(#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, "a private key"),
        Rule(#"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#, "an AWS access key"),
        Rule(#"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[abprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{16,})"#,
             "an access token"),
        Rule(#"\beyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\."#, "a web token (JWT)"),
        Rule(#"[a-z][a-z0-9+.-]{0,15}://[^/\s:@]{1,256}:[^/\s@]{1,256}@"#, "a password inside a URL"),
        Rule(#"authorization:\s{0,8}(bearer|basic|token)\s{1,8}(?![$<])[^\s'"]+"#, "an authorization header with its credentials"),
        Rule(#"(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[\w.-]{0,64}['"]?\s{0,8}[=:]\s{0,8}['"]?(?![$<{\s'"])[^\s'"]+"#,
             "a password, key or token value"),
        Rule(#"(^|\s)--?(password|passwd|pass|token|secret|api-?key|access-key|secret-key|auth-token)(=|\s{1,8})['"]?(?![$<\s-])[^\s'"]+"#,
             "a password or token given as an option"),
        Rule(#"\bsshpass\s{1,8}-p\s{0,8}['"]?(?![$<])\S+"#, "a password given to sshpass"),
        Rule(#"\b(mysql|mysqldump|mariadb)\b[^|;&]{0,512}\s-p(?![\s$<]|$)\S+"#, "a database password after -p"),
        Rule(#"\s(-u|--user)\s{1,8}['"]?[^\s:'"]{1,256}:(?![$<\s])[^\s'"]+"#, "a username and password"),
    ]
}
