import PortlightSSH
import SwiftUI

/// Shown the first time a server is seen, or when its key changed.
struct HostKeyPromptView: View {
    let prompt: HostKeyPrompt
    @State private var confirmingReplace = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch prompt.kind {
                    case .new(let otherTypesKnown):
                        Label("New server", systemImage: "questionmark.diamond")
                            .font(.title2.weight(.semibold))
                        Text("This is the first connection to **\(prompt.hostLabel)** (\(prompt.host), port \(prompt.port)). Check the fingerprint below matches the server's before trusting it.")
                        if otherTypesKnown {
                            Text("A key of a different type is already trusted for this server. That's usually harmless (the server offered another key type), but check the fingerprint.")
                                .foregroundStyle(.orange)
                        }
                    case .changed:
                        Label("The server's identity changed", systemImage: "exclamationmark.octagon.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.red)
                        Text("**\(prompt.hostLabel)** (\(prompt.host), port \(prompt.port)) presented a different key than the one you trusted. Someone may be intercepting the connection, or the server was rebuilt or reinstalled. Only continue if you know why it changed.")
                    }

                    FingerprintBox(title: "Presented key (\(prompt.algorithm))", fingerprint: prompt.fingerprint)
                    if case .changed(let previous) = prompt.kind {
                        FingerprintBox(title: "Previously trusted key", fingerprint: previous)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("How to check")
                            .font(.headline)
                        Text("On the server, run:")
                        Text("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        Text("Cloud consoles also print the host key fingerprints in the instance's boot log (EC2: Get system log; GCP: serial port output).")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)

                    VStack(spacing: 10) {
                        switch prompt.kind {
                        case .new:
                            Button {
                                prompt.trust()
                            } label: {
                                Text("Trust and connect").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                prompt.reject()
                            } label: {
                                Text("Cancel").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        case .changed:
                            Button {
                                prompt.reject()
                            } label: {
                                Text("Disconnect").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            Button(role: .destructive) {
                                confirmingReplace = true
                            } label: {
                                Text("Replace the trusted key…").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.large)
                    .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle("Host key")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Replace the trusted key for \(prompt.hostLabel)?", isPresented: $confirmingReplace, titleVisibility: .visible) {
                Button("Replace and connect", role: .destructive) { prompt.trust() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do this only if you know the server was rebuilt or its keys were rotated.")
            }
        }
    }
}

struct FingerprintBox: View {
    let title: String
    let fingerprint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(fingerprint)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PasswordPromptView: View {
    let prompt: PasswordPrompt
    @State private var password = ""
    @State private var save = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(submit)
                    Toggle("Save in Keychain", isOn: $save)
                } header: {
                    Text("\(prompt.username) on \(prompt.hostLabel)")
                } footer: {
                    if let message = prompt.message {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { prompt.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect", action: submit)
                        .disabled(password.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard !password.isEmpty else { return }
        prompt.submit(password, save: save)
    }
}

struct SnippetPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onPick: (Snippet) -> Void

    var body: some View {
        NavigationStack {
            List {
                if model.library.snippets.isEmpty {
                    Text("No snippets yet. Add them in Settings → Snippets.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.library.snippets) { snippet in
                    Button {
                        onPick(snippet)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snippet.title).foregroundStyle(.primary)
                            Text(snippet.command)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Snippets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
