import PortlightSSH
import SwiftUI

struct KnownHostsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false

    var body: some View {
        List {
            if model.library.knownHosts.entries.isEmpty {
                Text("No trusted host keys yet. Portlight asks the first time it sees a server and remembers your answer here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.library.knownHosts.entries, id: \.self) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.hostPattern.hasPrefix("|1|") ? "Hashed host name" : entry.hostPattern)
                            .font(.body.weight(.medium))
                        if entry.revoked {
                            Text("Revoked").font(.caption2.weight(.bold)).foregroundStyle(.red)
                        }
                    }
                    if let key = entry.key {
                        Text(key.algorithmName).font(.caption).foregroundStyle(.secondary)
                        Text(key.sha256Fingerprint)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Added \(entry.addedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        model.library.removeKnownHost(entry)
                    } label: {
                        Label("Forget", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Trusted host keys")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    importing = true
                } label: {
                    Label("Import known_hosts", systemImage: "square.and.arrow.down")
                }
            }
        }
        .sheet(isPresented: $importing) {
            TextImportView(
                title: "Import known_hosts",
                placeholder: "Paste lines from ~/.ssh/known_hosts",
                footer: "Hashed entries and @revoked lines are supported. Keys are added; nothing is removed."
            ) { text in
                let added = model.library.importKnownHosts(text)
                return added == 1 ? "Added 1 key." : "Added \(added) keys."
            }
        }
    }
}

/// A paste-or-pick-a-file sheet for importing text.
struct TextImportView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    let footer: String
    /// Imports the text and returns a summary to show.
    let onImport: (String) -> String
    @State private var text = ""
    @State private var pickingFile = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 4)
                        }
                        TextEditor(text: $text)
                            .font(.caption.monospaced())
                            .frame(minHeight: 200)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Button {
                        pickingFile = true
                    } label: {
                        Label("Choose a file…", systemImage: "folder")
                    }
                } footer: {
                    Text(footer)
                }
                if let result {
                    Section {
                        Text(result)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { result = onImport(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.plainText, .data, .item]) { picked in
                switch picked {
                case .success(let url):
                    do { text = try FileReading.text(at: url) } catch { result = error.localizedDescription }
                case .failure(let error):
                    result = error.localizedDescription
                }
            }
        }
    }
}
