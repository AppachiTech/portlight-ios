import PortlightSSH
import SwiftUI

struct ImportConfigView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var pickingFile = false
    @State private var added: [SSHHost] = []
    @State private var warnings: [String] = []
    @State private var done = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.caption.monospaced())
                    .frame(minHeight: 220)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    pickingFile = true
                } label: {
                    Label("Choose a file…", systemImage: "folder")
                }
            } header: {
                Text("~/.ssh/config")
            } footer: {
                Text("Host, HostName, User, Port and ProxyJump are imported. Hosts with wildcards are used as defaults, not imported. Hosts you already have (same name) are skipped. Keys aren't in this file: import them under Keys and pick one for each host.")
            }

            Section {
                Button("Import hosts") {
                    let result = model.library.importSSHConfig(text)
                    added = result.added
                    warnings = result.warnings
                    done = true
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if done {
                Section("Imported") {
                    if added.isEmpty {
                        Text("No new hosts.")
                    }
                    ForEach(added) { host in
                        VStack(alignment: .leading) {
                            Text(host.displayName)
                            Text(host.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !warnings.isEmpty {
                    Section("Skipped") {
                        ForEach(warnings, id: \.self) { warning in
                            Text(warning).font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Import ssh config")
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.plainText, .data, .item]) { result in
            if case .success(let url) = result, let contents = try? FileReading.text(at: url) {
                text = contents
            }
        }
    }
}
