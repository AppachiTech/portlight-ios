import PortlightSSH
import SwiftUI

struct KeyListView: View {
    @Environment(AppModel.self) private var model
    @State private var generating: KeyAlgorithm?
    @State private var generatingEnclave = false
    @State private var importing = false
    @State private var newKeyName = "iPhone"
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                if model.library.keys.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No keys yet").font(.headline)
                            Text("Create an Ed25519 key, then add its public key to each server's ~/.ssh/authorized_keys. Keys are stronger than passwords and can't be phished.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                ForEach(model.library.keys) { key in
                    NavigationLink(value: key.id) {
                        KeyRow(key: key)
                    }
                }
            }
            .navigationTitle("Keys")
            .navigationDestination(for: UUID.self) { id in
                if let key = model.library.key(id) {
                    KeyDetailView(key: key)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newKeyName = defaultName("iPhone")
                            generating = .ed25519
                        } label: {
                            Label("New Ed25519 key (recommended)", systemImage: "key")
                        }
                        if SecureEnclaveKeys.isAvailable {
                            Button {
                                newKeyName = defaultName("iPhone Secure Enclave")
                                generatingEnclave = true
                            } label: {
                                Label("New Secure Enclave key", systemImage: "cpu")
                            }
                        }
                        Menu("Other key types") {
                            ForEach([KeyAlgorithm.ecdsaP256, .ecdsaP384, .ecdsaP521], id: \.self) { algorithm in
                                Button(algorithm.displayName) {
                                    newKeyName = defaultName("iPhone")
                                    generating = algorithm
                                }
                            }
                        }
                        Divider()
                        Button {
                            importing = true
                        } label: {
                            Label("Import a private key", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Add key", systemImage: "plus")
                    }
                }
            }
            .alert("Name the new key", isPresented: Binding(get: { generating != nil }, set: { if !$0 { generating = nil } })) {
                TextField("Name", text: $newKeyName)
                Button("Create") {
                    if let algorithm = generating { create(algorithm) }
                    generating = nil
                }
                Button("Cancel", role: .cancel) { generating = nil }
            } message: {
                Text("The private key stays in this iPhone's Keychain.")
            }
            .alert("Name the Secure Enclave key", isPresented: $generatingEnclave) {
                TextField("Name", text: $newKeyName)
                Button("Create") { createEnclave() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A P-256 key made inside the Secure Enclave. It can never leave this iPhone, can't be exported or backed up, and each use needs Face ID or your passcode. If you lose the phone, you'll need another way into your servers.")
            }
            .sheet(isPresented: $importing) {
                KeyImportView()
            }
            .alert("Couldn't create the key", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
        }
    }

    private func defaultName(_ base: String) -> String {
        let names = Set(model.library.keys.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func create(_ algorithm: KeyAlgorithm) {
        let name = newKeyName.trimmingCharacters(in: .whitespaces)
        do {
            try model.library.generateKey(named: name.isEmpty ? defaultName("iPhone") : name, algorithm: algorithm)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func createEnclave() {
        let name = newKeyName.trimmingCharacters(in: .whitespaces)
        do {
            try model.generateSecureEnclaveKey(named: name.isEmpty ? defaultName("iPhone Secure Enclave") : name)
        } catch {
            problem = error.localizedDescription
        }
    }
}

struct KeyRow: View {
    let key: KeyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(key.name).font(.body.weight(.medium))
                if key.storage == .secureEnclave {
                    Text("Secure Enclave")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SwiftUI.Color.portlightBrass.opacity(0.2), in: Capsule())
                }
            }
            Text(key.algorithm.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(key.fingerprint)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
