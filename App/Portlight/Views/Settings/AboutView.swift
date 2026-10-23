import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    PortlightMark(size: 64)
                    VStack(alignment: .leading) {
                        Text("Portlight").font(.title2.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("How your data is protected") {
                AboutPoint(icon: "faceid", text: "The app always opens with Face ID, Touch ID or your passcode, and locks when you leave it.")
                AboutPoint(icon: "key.horizontal", text: "Passwords and private keys live in the Keychain on this device only. iOS releases them only after that same check, and never syncs or backs them up.")
                AboutPoint(icon: "cpu", text: "Secure Enclave keys never leave the chip at all.")
                AboutPoint(icon: "checkmark.shield", text: "Every server's host key is checked. A changed key stops the connection.")
                AboutPoint(icon: "keyboard", text: "Third-party keyboards are blocked, so nothing you type passes through them.")
                AboutPoint(icon: "doc.on.clipboard", text: "Text copied from a terminal stays on this device and expires after two minutes. Servers can't read your clipboard.")
                AboutPoint(icon: "antenna.radiowaves.left.and.right.slash", text: "No accounts, analytics or tracking. Portlight connects only to the servers you add.")
            }
            Section("Open source") {
                Text("Portlight is MIT licensed. It is built on SwiftNIO SSH and swift-crypto (Apache 2.0, Apple) and SwiftTerm (MIT, Miguel de Icaza).")
                    .font(.callout)
            }
        }
        .navigationTitle("About")
    }
}

struct AboutPoint: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: icon).foregroundStyle(SwiftUI.Color.portlightBrass)
        }
    }
}
