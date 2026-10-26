import PortlightSSH
import SwiftUI

struct SnippetsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Snippet?

    var body: some View {
        List {
            ForEach(model.library.snippets) { snippet in
                Button {
                    editing = snippet
                } label: {
                    SavedCommandRow(snippet: snippet)
                }
            }
            .onDelete { offsets in
                offsets.map { model.library.snippets[$0] }.forEach { model.library.delete($0) }
            }
            .onMove { source, destination in
                model.library.moveSnippets(from: source, to: destination)
            }
        }
        .navigationTitle("Saved commands")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = Snippet(title: "", command: "")
                } label: {
                    Label("Add saved command", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet)
        }
    }
}

/// A saved command's title and command, flagged if it holds a secret
/// (possible for ones saved before the check existed).
struct SavedCommandRow: View {
    let snippet: Snippet

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.title).foregroundStyle(.primary)
                Text(snippet.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
            }
            if !CommandSecrets.problems(in: snippet.command).isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Contains a secret")
            }
        }
    }
}

struct SnippetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var snippet: Snippet

    var body: some View {
        let problems = CommandSecrets.problems(in: snippet.command)
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $snippet.title)
                    TextField("Command", text: $snippet.command, axis: .vertical)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...6)
                } footer: {
                    if problems.isEmpty {
                        Text("Keep saved commands generic, like git status or terraform apply. They're stored as plain text, so passwords, keys and tokens can't be saved here.")
                    } else {
                        Label("This looks like it contains \(problems.formatted(.list(type: .and))). Saved commands are stored as plain text, so secrets can't be saved. Refer to them instead, for example $TOKEN, or read them from a file.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Toggle("Press Return after typing", isOn: $snippet.runImmediately)
                        .disabled(!model.library.settings.runSavedCommands)
                } footer: {
                    if model.library.settings.runSavedCommands {
                        Text("Leave this off for commands that change things, like terraform apply, so you can check before running.")
                    } else {
                        Text("Saved commands are only typed, never run, while Settings → Saved commands → Run straight away is off.")
                    }
                }
            }
            .navigationTitle(snippet.title.isEmpty ? "New saved command" : snippet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if snippet.title.trimmingCharacters(in: .whitespaces).isEmpty {
                            snippet.title = String(snippet.command.prefix(30))
                        }
                        model.library.save(snippet)
                        dismiss()
                    }
                    .disabled(snippet.command.trimmingCharacters(in: .whitespaces).isEmpty || !problems.isEmpty)
                }
            }
        }
    }
}
