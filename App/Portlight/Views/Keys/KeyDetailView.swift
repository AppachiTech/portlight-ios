import PortlightSSH
import SwiftUI

struct KeyDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let key: KeyRecord
    @State private var name: String
    @State private var copied = false
    @State private var confirmingDelete = false
    @State private var exporting = false
    @State private var exportDocument: TextFileDocument?
    @State private var problem: String?

    init(key: KeyRecord) {
        self.key = key
        _name = State(initialValue: key.name)
    }

    private var publicLine: String { key.publicKey.openSSHString(comment: key.name) }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
                    .onSubmit { model.library.rename(key, to: name) }
            }

            Section {
                Text(publicLine)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                Button {
                    Pasteboard.copyPublic(publicLine)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy public key", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                ShareLink(item: publicLine) {
                    Label("Share public key", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Public key")
            } footer: {
                Text("Safe to share. Add this line to ~/.ssh/authorized_keys on each server, e.g.\necho '<line>' >> ~/.ssh/authorized_keys")
            }

            Section("Details") {
                LabeledContent("Type", value: key.algorithm.displayName)
                LabeledContent("Stored in", value: key.storage == .secureEnclave ? "Secure Enclave" : "Keychain (this device only)")
                LabeledContent("Created", value: key.createdAt.formatted(date: .abbreviated, time: .shortened))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fingerprint").font(.caption).foregroundStyle(.secondary)
                    Text(key.fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                }
            }

            let users = model.library.hostsUsing(key)
            if !users.isEmpty {
                Section("Used by") {
                    ForEach(users) { host in
                        Text(host.displayName)
                    }
                }
            }

            if key.storage == .keychain {
                Section {
                    Button {
                        exporting = true
                    } label: {
                        Label("Export private key…", systemImage: "square.and.arrow.up.on.square")
                    }
                } footer: {
                    Text("The exported file is encrypted with a passphrase you choose. Keep it somewhere safe.")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete key", systemImage: "trash")
                }
            }
        }
        .navigationTitle(key.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.library.rename(key, to: name) }
        .confirmationDialog("Delete \(key.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.library.delete(key)
                dismiss()
            }
        } message: {
            let count = model.library.hostsUsing(key).count
            Text(count == 0
                 ? "This can't be undone."
                 : "\(count) host(s) use this key and will switch to password login. This can't be undone.")
        }
        .sheet(isPresented: $exporting) {
            ExportPassphraseView { passphrase in
                do {
                    exportDocument = TextFileDocument(text: try model.library.exportPrivateKey(key, passphrase: passphrase))
                } catch {
                    problem = error.localizedDescription
                }
            }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument, contentType: .plainText,
                      defaultFilename: key.name.replacingOccurrences(of: " ", with: "_") + "_id_" + key.algorithm.rawValue.lowercased()) { _ in
            exportDocument = nil
        }
        .alert("Couldn't export", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(problem ?? "")
        }
    }
}

struct ExportPassphraseView: View {
    @Environment(\.dismiss) private var dismiss
    var onExport: (String) -> Void
    @State private var passphrase = ""
    @State private var confirm = ""

    private var valid: Bool {
        passphrase.count >= Library.minimumExportPassphraseLength && passphrase == confirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                    SecureField("Repeat passphrase", text: $confirm)
                } footer: {
                    Text("At least \(Library.minimumExportPassphraseLength) characters. You'll need it to use the file elsewhere (ssh-keygen and OpenSSH read it directly).")
                }
            }
            .navigationTitle("Encrypt export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        let chosen = passphrase
                        dismiss()
                        onExport(chosen)
                    }
                    .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
