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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.title).foregroundStyle(.primary)
                        Text(snippet.command).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .onDelete { offsets in
                offsets.map { model.library.snippets[$0] }.forEach { model.library.delete($0) }
            }
            .onMove { source, destination in
                model.library.moveSnippets(from: source, to: destination)
            }
        }
        .navigationTitle("Snippets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = Snippet(title: "", command: "")
                } label: {
                    Label("Add snippet", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { snippet in
            SnippetEditor(snippet: snippet)
        }
    }
}

struct SnippetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var snippet: Snippet

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $snippet.title)
                TextField("Command", text: $snippet.command, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1...6)
                Toggle("Press Return after typing", isOn: $snippet.runImmediately)
            }
            .navigationTitle(snippet.title.isEmpty ? "New snippet" : snippet.title)
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
                    .disabled(snippet.command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
