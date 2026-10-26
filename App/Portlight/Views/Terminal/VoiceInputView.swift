import PortlightSSH
import SwiftUI

/// Speak-to-type strip under the terminal: one row in landscape, two in
/// portrait. Speech goes into a draft you can edit, clear or add to by
/// speaking again; Insert types it into the terminal without pressing
/// Return, and ⏎ is a separate tap.
struct VoiceInputView: View {
    let controller: TerminalController
    @Binding var draft: String
    var onSavedCommands: () -> Void

    @State private var dictation = SpeechDictation()
    /// The draft as it was when speaking started; speech is added after it.
    @State private var spokenAfter = ""
    @FocusState private var editing: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 6) {
                    keys
                        .fixedSize()
                    draftField
                    actions
                }
            } else {
                VStack(spacing: 6) {
                    draftField
                    HStack(spacing: 6) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            keys
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                        actions
                    }
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .onChange(of: dictation.transcript) { _, heard in
            guard !heard.isEmpty else { return }
            // Lower case: instructions and commands read better without
            // the recogniser's sentence capitals.
            let words = heard.lowercased()
            draft = spokenAfter.isEmpty ? words : spokenAfter + " " + words
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dictation.stop() }
        }
        .onDisappear { dictation.stop() }
        .alert("Voice input", isPresented: Binding(get: { failure != nil }, set: { if !$0 { dictation.dismissFailure() } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Parts

    private var draftField: some View {
        HStack(spacing: 4) {
            TextField(dictation.isListening ? "Listening…" : "Tap Speak and say what to type", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($editing)
                .font(.callout)
                .textInputAutocapitalization(.never)
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(dictation.isListening ? Color.red : Color.clear, lineWidth: 1.5))
    }

    private var keys: some View {
        HStack(spacing: 4) {
            Button {
                editing = false
                controller.handle(.keyboard)
            } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Show the keyboard")
            Button(action: onSavedCommands) {
                Image(systemName: "list.bullet.rectangle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Saved commands")
            keyButton("esc", accessibility: "Escape") { controller.handle(.key(.escape)) }
            keyButton("^C", accessibility: "Control C") { controller.session.send([0x03]) }
            keyButton("tab", accessibility: "Tab") { controller.handle(.key(.tab)) }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            speakButton
            insertButton
            enterButton
        }
        .fixedSize()
    }

    private var speakButton: some View {
        Button {
            if dictation.isListening {
                dictation.stop()
            } else {
                editing = false
                spokenAfter = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                dictation.start()
            }
        } label: {
            Label(dictation.isListening ? "Stop" : "Speak",
                  systemImage: dictation.isListening ? "stop.fill" : "mic.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private var insertButton: some View {
        Button {
            // Drop any revision still on its way, so it can't refill the draft.
            dictation.cancel()
            let bytes = DictatedText.bytes(for: draft)
            guard !bytes.isEmpty else { return }
            controller.session.send(bytes)
            draft = ""
            spokenAfter = ""
            editing = false
        } label: {
            Label("Insert", systemImage: "text.insert")
        }
        .buttonStyle(.borderedProminent)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityHint("Types the text into the terminal without pressing Return")
    }

    private var enterButton: some View {
        Button {
            controller.handle(.key(.enter))
        } label: {
            Image(systemName: "return")
                .frame(minWidth: 20)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Return")
    }

    private func keyButton(_ title: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.monospaced().weight(.medium))
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibility)
    }

    private func clear() {
        dictation.cancel()
        draft = ""
        spokenAfter = ""
    }

    private var failure: String? {
        if case .failed(let message) = dictation.state { return message }
        return nil
    }
}
