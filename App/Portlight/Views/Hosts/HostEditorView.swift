import PortlightSSH
import SwiftUI

struct HostEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var host: SSHHost
    @State private var portText: String
    @State private var password = ""
    @State private var savePassword = true
    @State private var problems: [String] = []
    @State private var copied = false
    @State private var hasSavedPassword = false
    private let isNew: Bool

    init(draft: HostDraft) {
        _host = State(initialValue: draft.host)
        _portText = State(initialValue: String(draft.host.port))
        isNew = draft.isNew
    }

    private var library: Library { model.library }
    private var otherHosts: [SSHHost] { library.hosts.filter { $0.id != host.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name (optional)", text: $host.label)
                    TextField("Hostname or IP address", text: $host.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $portText)
                        .keyboardType(.numberPad)
                    Picker("Provider", selection: $host.provider) {
                        ForEach(CloudProvider.allCases) { provider in
                            Label(provider.displayName, systemImage: provider.symbolName).tag(provider)
                        }
                    }
                }

                Section {
                    TextField("Username", text: $host.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !host.provider.suggestedUsernames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(host.provider.suggestedUsernames, id: \.self) { name in
                                    Button(name) { host.username = name }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    Picker("Log in with", selection: authSelection) {
                        Text("Password").tag(UUID?.none)
                        ForEach(library.keys) { key in
                            Text(key.name).tag(UUID?.some(key.id))
                        }
                    }
                    if host.auth == .password {
                        SecureField(hasSavedPassword ? "Saved (type to replace)" : "Password (optional)", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Toggle("Save password in Keychain", isOn: $savePassword)
                    }
                } header: {
                    Text("Login")
                } footer: {
                    if host.auth == .password {
                        Text("Leave the password empty to be asked each time. Keys are safer: they can't be phished or guessed.")
                    }
                }

                if let keyID = host.auth.keyID, let key = library.key(keyID) {
                    Section {
                        Button {
                            Pasteboard.copyPublic(host.provider.authorizedKeyLine(for: key.publicKey, username: host.username, keyName: key.name))
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy public key for this server", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                    } footer: {
                        Text(host.provider.keyInstallHint)
                    }
                }

                Section {
                    Picker("Jump host", selection: $host.jumpHostID) {
                        Text("None").tag(UUID?.none)
                        ForEach(otherHosts) { other in
                            Text(other.displayName).tag(UUID?.some(other.id))
                        }
                    }
                    TextField("Group (optional)", text: groupBinding)
                    TextField("Run on connect, e.g. tmux new -A -s main", text: startupBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Options")
                } footer: {
                    if let warning = secretWarning(in: host.startupCommand, field: "Run on connect") {
                        Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Text("A jump host (bastion) is connected first, and this server is reached through it, like ProxyJump.")
                    }
                }

                Section {
                    TextField("Notes", text: notesBinding, axis: .vertical)
                        .lineLimit(2...6)
                        .autocorrectionDisabled()
                } header: {
                    Text("Notes")
                } footer: {
                    if let warning = secretWarning(in: host.notes, field: "Notes") {
                        Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Text("Stored as plain text: don't put passwords or keys here.")
                    }
                }

                if !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New host" : "Edit host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                hasSavedPassword = !isNew && library.password(for: host.id) != nil
            }
            .onChange(of: host.provider) { _, provider in
                if host.username.isEmpty, let first = provider.suggestedUsernames.first {
                    host.username = first
                }
            }
        }
    }

    private var authSelection: Binding<UUID?> {
        Binding(get: { host.auth.keyID }, set: { host.auth = $0.map { .key($0) } ?? .password })
    }

    private var groupBinding: Binding<String> {
        Binding(get: { host.group ?? "" }, set: { host.group = $0.isEmpty ? nil : $0 })
    }

    private var startupBinding: Binding<String> {
        Binding(get: { host.startupCommand ?? "" }, set: { host.startupCommand = $0.isEmpty ? nil : $0 })
    }

    private var notesBinding: Binding<String> {
        Binding(get: { host.notes ?? "" }, set: { host.notes = $0.isEmpty ? nil : $0 })
    }

    /// Host settings are stored as plain text, like saved commands.
    private func secretWarning(in text: String?, field: String) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let found = CommandSecrets.problems(in: text)
        guard !found.isEmpty else { return nil }
        return "\(field) looks like it contains \(found.formatted(.list(type: .and))). It's stored as plain text; refer to the secret instead, e.g. $TOKEN."
    }

    private func save() {
        // Run on connect is a saved command in all but name: same rule.
        if let warning = secretWarning(in: host.startupCommand, field: "Run on connect") {
            problems = [warning]
            return
        }
        host.hostname = host.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        host.username = host.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(portText.trimmingCharacters(in: .whitespaces)) else {
            problems = [HostValidationError.invalidPort.localizedDescription]
            return
        }
        host.port = port
        let found = host.validate()
        guard found.isEmpty else {
            problems = found.map(\.localizedDescription)
            return
        }
        do {
            try library.save(host)
            if host.auth == .password, !password.isEmpty {
                try library.setPassword(savePassword ? password : nil, for: host.id)
            } else if host.auth != .password {
                try library.setPassword(nil, for: host.id)
            }
            dismiss()
        } catch {
            problems = [error.localizedDescription]
        }
    }
}
