import PortlightSSH
import SwiftUI
import UniformTypeIdentifiers

struct KeyImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var name = ""
    @State private var passphrase = ""
    @State private var pickingFile = false
    @State private var problem: String?
    @State private var importing = false
    /// The clipboard's change count when its text was pasted in, so it can
    /// be cleared after import if it still holds the private key.
    @State private var pastedChangeCount: Int?

    private var inspection: KeyImporter.Inspection? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : KeyImporter.inspect(text)
    }

    private var needsPassphrase: Bool { inspection == .openSSH(encrypted: true) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.caption.monospaced())
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        pickingFile = true
                    } label: {
                        Label("Choose a file…", systemImage: "folder")
                    }
                    if UIPasteboard.general.hasStrings {
                        Button {
                            text = UIPasteboard.general.string ?? ""
                            pastedChangeCount = UIPasteboard.general.changeCount
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                    }
                } header: {
                    Text("Private key")
                } footer: {
                    Text("OpenSSH (-----BEGIN OPENSSH PRIVATE KEY-----) or PEM, Ed25519 or ECDSA. RSA keys aren't supported yet.")
                }

                if let inspection {
                    Section {
                        switch inspection {
                        case .openSSH(let encrypted):
                            Label(encrypted ? "OpenSSH key, passphrase protected" : "OpenSSH key", systemImage: "checkmark.seal")
                                .foregroundStyle(.green)
                        case .pem:
                            Label("PEM key", systemImage: "checkmark.seal")
                                .foregroundStyle(.green)
                        case .unsupported(let error):
                            Label(error.localizedDescription, systemImage: "xmark.octagon")
                                .foregroundStyle(.red)
                        }
                    }
                }

                if needsPassphrase {
                    Section("Passphrase") {
                        SecureField("Passphrase", text: $passphrase)
                    }
                }

                Section("Name") {
                    TextField("Name (optional)", text: $name)
                }

                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if importing {
                        ProgressView()
                    } else {
                        Button("Import", action: importKey)
                            .disabled(!canImport)
                    }
                }
            }
            .disabled(importing)
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.data, .plainText, .item]) { result in
                switch result {
                case .success(let url):
                    do { text = try FileReading.text(at: url) } catch { problem = error.localizedDescription }
                case .failure(let error):
                    problem = error.localizedDescription
                }
            }
            .onDisappear {
                // Don't leave key material in memory longer than needed.
                text = ""
                passphrase = ""
            }
        }
    }

    private var canImport: Bool {
        switch inspection {
        case .openSSH(let encrypted)?: !encrypted || !passphrase.isEmpty
        case .pem?: true
        default: false
        }
    }

    /// Decrypting runs off the main thread: bcrypt can take seconds.
    private func importKey() {
        let (text, passphrase) = (self.text, self.passphrase.isEmpty ? nil : self.passphrase)
        importing = true
        problem = nil
        Task {
            let decoded = await Task.detached(priority: .userInitiated) {
                Result { try KeyImporter.importKey(text, passphrase: passphrase) }
            }.value
            importing = false
            do {
                try model.library.add(decoded.get(), name: name.isEmpty ? nil : name)
                clearPastedKey()
                dismiss()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    /// The private key was pasted in and nothing has been copied since:
    /// don't leave it on the clipboard (or Universal Clipboard).
    private func clearPastedKey() {
        guard let pastedChangeCount, UIPasteboard.general.changeCount == pastedChangeCount else { return }
        UIPasteboard.general.items = []
    }
}
