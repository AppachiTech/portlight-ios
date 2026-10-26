import PortlightSSH
import SwiftUI

/// Speak-to-type controls beside a landscape terminal. Speech goes into a
/// draft you can edit, clear or add to by speaking again; Insert types it
/// into the terminal without pressing Return, and ⏎ is a separate tap.
struct VoiceInputView: View {
    let layout: VoiceInputLayout
    let controller: TerminalController
    @Binding var draft: String

    @State private var dictation = SpeechDictation()
    /// The draft as it was when speaking started; speech is added after it.
    @State private var spokenAfter = ""
    @FocusState private var editing: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch layout {
            case .sidePanel: sidePanel
            case .bottomStrip: bottomStrip
            }
        }
        .background(.bar)
        .onChange(of: dictation.transcript) { _, heard in
            guard !heard.isEmpty else { return }
            draft = spokenAfter.isEmpty ? heard : spokenAfter + " " + heard
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

    // MARK: Layouts

    private var sidePanel: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .focused($editing)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                if draft.isEmpty {
                    Text(dictation.isListening ? "Listening…" : "Tap Speak and say what to type")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(dictation.isListening ? Color.red : Color.clear, lineWidth: 1.5))
            HStack(spacing: 6) {
                speakButton.frame(maxWidth: .infinity)
                clearButton.frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                insertButton.frame(maxWidth: .infinity)
                enterButton.frame(maxWidth: .infinity)
            }
            // Scrolls sideways if larger text sizes make the keys too wide.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    keyButton("esc", accessibility: "Escape") { controller.handle(.key(.escape)) }
                    keyButton("^C", accessibility: "Control C") { controller.session.send([0x03]) }
                    keyButton("tab", accessibility: "Tab") { controller.handle(.key(.tab)) }
                    keyButton("↑", accessibility: "Up arrow") { controller.handle(.key(.up)) }
                    keyButton("↓", accessibility: "Down arrow") { controller.handle(.key(.down)) }
                    keyboardButton
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .controlSize(.small)
        .padding(8)
        .frame(width: 250)
    }

    private var bottomStrip: some View {
        HStack(spacing: 6) {
            keyboardButton
            keyButton("esc", accessibility: "Escape") { controller.handle(.key(.escape)) }
            keyButton("^C", accessibility: "Control C") { controller.session.send([0x03]) }
            TextField(dictation.isListening ? "Listening…" : "Tap Speak and say what to type", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .focused($editing)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(dictation.isListening ? Color.red : Color.clear, lineWidth: 1.5))
            if !draft.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear")
            }
            speakButton
            insertButton
            enterButton
        }
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Controls

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

    private var clearButton: some View {
        Button("Clear", action: clear)
            .buttonStyle(.bordered)
            .disabled(draft.isEmpty && !dictation.isListening)
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
            Label("Return", systemImage: "return")
                .labelStyle(.iconOnly)
                .frame(minWidth: 24)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Return")
    }

    private var keyboardButton: some View {
        Button {
            editing = false
            controller.handle(.keyboard)
        } label: {
            Image(systemName: "keyboard")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Show or hide the keyboard")
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
