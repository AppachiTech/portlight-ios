import Foundation

/// Where a host lives. Only used for labels, icons and sensible defaults;
/// every provider is reached the same way, over plain SSH.
public enum CloudProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case aws
    case gcp
    case azure
    case digitalOcean
    case oracle
    case hetzner
    case linode
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aws: "AWS"
        case .gcp: "Google Cloud"
        case .azure: "Azure"
        case .digitalOcean: "DigitalOcean"
        case .oracle: "Oracle Cloud"
        case .hetzner: "Hetzner"
        case .linode: "Linode / Akamai"
        case .other: "Other"
        }
    }

    /// Login names the provider's stock images use, most common first.
    public var suggestedUsernames: [String] {
        switch self {
        case .aws: ["ec2-user", "ubuntu", "admin", "rocky", "fedora", "bitnami"]
        case .gcp: []  // your own username: OS Login or the name on the metadata key
        case .azure: ["azureuser"]
        case .digitalOcean: ["root"]
        case .oracle: ["opc", "ubuntu"]
        case .hetzner: ["root"]
        case .linode: ["root"]
        case .other: []
        }
    }

    /// How to get a phone key onto a server of this kind, in one sentence.
    public var keyInstallHint: String {
        switch self {
        case .aws:
            "Append the public key to ~/.ssh/authorized_keys on the instance, or import it as an ED25519 key pair in the EC2 console before launching."
        case .gcp:
            "Add the key line in Compute Engine → Metadata → SSH keys (Portlight ends the line with your username, as Google expects), or use OS Login."
        case .azure:
            "Paste the public key into the VM's Reset password → SSH public key blade, or append it to ~/.ssh/authorized_keys."
        default:
            "Append the public key to ~/.ssh/authorized_keys for your user on the server."
        }
    }

    /// The public key line to paste for this provider. Google Compute Engine
    /// reads the trailing comment as the account to create, so it must be
    /// the username.
    public func authorizedKeyLine(for key: SSHPublicKey, username: String, keyName: String) -> String {
        switch self {
        case .gcp where !username.isEmpty: key.openSSHString(comment: username)
        default: key.openSSHString(comment: keyName)
        }
    }

    /// SF Symbols name for lists.
    public var symbolName: String {
        switch self {
        case .aws: "shippingbox"
        case .gcp: "cloud"
        case .azure: "square.grid.2x2"
        case .digitalOcean: "drop"
        case .oracle: "circle.hexagongrid"
        case .hetzner: "server.rack"
        case .linode: "leaf"
        case .other: "terminal"
        }
    }
}
