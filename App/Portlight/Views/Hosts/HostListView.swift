import PortlightSSH
import SwiftUI

struct HostListView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var editing: HostDraft?
    @State private var deleting: SSHHost?
    @State private var quickConnect = ""
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                quickConnectSection
                let sections = model.library.sections(matching: search)
                if sections.isEmpty, search.isEmpty {
                    emptyState
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.hosts) { host in
                            Button {
                                model.connect(host)
                            } label: {
                                HostRow(host: host, jump: model.library.host(host.jumpHostID))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { deleting = host } label: { Label("Delete", systemImage: "trash") }
                                Button { editing = HostDraft(host: host, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(.blue)
                            }
                            .contextMenu {
                                Button { model.connect(host) } label: { Label("Connect", systemImage: "terminal") }
                                Button { editing = HostDraft(host: host, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                                Button {
                                    do { _ = try model.library.duplicate(host) } catch { problem = error.localizedDescription }
                                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                Button { Pasteboard.copyPublic(host.address) } label: { Label("Copy address", systemImage: "doc.on.doc") }
                                Button(role: .destructive) { deleting = host } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search hosts")
            .navigationTitle("Hosts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !model.sessions.sessions.isEmpty {
                        Button {
                            model.showingTerminal = true
                        } label: {
                            Label("\(model.sessions.sessions.count) open", systemImage: "terminal.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = HostDraft(host: SSHHost(hostname: "", username: ""), isNew: true)
                    } label: {
                        Label("Add host", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { draft in
                HostEditorView(draft: draft)
            }
            .confirmationDialog("Delete this host?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible, presenting: deleting) { host in
                Button("Delete \(host.displayName)", role: .destructive) { model.library.delete(host) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its saved password is deleted too. Trusted host keys are kept.")
            }
            .alert("Couldn't do that", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
        }
    }

    private var quickConnectSection: some View {
        Section {
            HStack {
                Image(systemName: "bolt.horizontal")
                    .foregroundStyle(.secondary)
                TextField("user@host:port", text: $quickConnect)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(startQuickConnect)
                if QuickConnect.parse(quickConnect) != nil {
                    Button("Set up", action: startQuickConnect)
                        .buttonStyle(.borderless)
                }
            }
        } footer: {
            Text("Paste an address or an ssh command to set up a host quickly.")
        }
    }

    private func startQuickConnect() {
        guard let target = QuickConnect.parse(quickConnect) else { return }
        let host = SSHHost(hostname: target.hostname, port: target.port, username: target.username ?? "",
                           provider: SSHConfigParser.guessProvider(target.hostname))
        editing = HostDraft(host: host, isNew: true)
        quickConnect = ""
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("No hosts yet")
                    .font(.headline)
                Text("Add a server with the + button, or import your ~/.ssh/config from Settings. Create a key under Keys and add its public key to your servers for password-free, phishing-proof logins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}

/// A host being edited, wrapped so `.sheet(item:)` gets a fresh identity.
struct HostDraft: Identifiable {
    let id = UUID()
    var host: SSHHost
    var isNew: Bool
}

struct HostRow: View {
    let host: SSHHost
    let jump: SSHHost?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: host.provider.symbolName)
                .font(.title3)
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.portlightBrass)
                .background(Color.portlightBrass.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(host.address)
                    if let jump {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        Text("via \(jump.displayName)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: host.auth.keyID == nil ? "key.slash" : "key.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel(host.auth.keyID == nil ? "Password login" : "Key login")
        }
        .contentShape(Rectangle())
    }
}
