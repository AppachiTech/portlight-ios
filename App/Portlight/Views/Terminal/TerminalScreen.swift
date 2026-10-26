import PortlightSSH
import SwiftUI

/// Full-screen terminal: a tab strip of open sessions over the active one.
struct TerminalScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var keyboard = KeyboardInset()

    var body: some View {
        let theme = TerminalTheme.named(model.library.settings.themeName)
        VStack(spacing: 0) {
            SessionTabBar(compact: verticalSizeClass == .compact) { dismiss() }
            if let session = model.sessions.active {
                TerminalPane(session: session, keyboardHeight: keyboard.height)
                    .id(session.id)
            } else {
                Spacer()
                ContentUnavailableView {
                    Label("No open terminals", systemImage: "terminal")
                } description: {
                    Text("Pick a host to connect.")
                } actions: {
                    Button("Back to hosts") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
        // Make room for the keyboard ourselves, so the terminal shrinks to
        // the space above it rather than running underneath.
        .padding(.bottom, keyboard.height)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(SwiftUI.Color(theme.background).ignoresSafeArea())
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .statusBarHidden(verticalSizeClass == .compact)
        .persistentSystemOverlays(verticalSizeClass == .compact ? .hidden : .automatic)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = model.library.settings.keepScreenAwake
            OrientationLock.apply(model.library.settings.terminalOrientation)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationLock.apply(nil)
        }
        .onChange(of: model.library.settings.terminalOrientation) { _, orientation in
            OrientationLock.apply(orientation)
        }
    }
}

struct SessionTabBar: View {
    @Environment(AppModel.self) private var model
    var compact: Bool
    var onMinimize: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onMinimize) {
                Image(systemName: "chevron.down")
                    .frame(width: 34, height: 30)
            }
            .accessibilityLabel("Back to hosts")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.sessions.sessions) { session in
                        SessionChip(session: session, isActive: session.id == model.sessions.activeID) {
                            model.sessions.activeID = session.id
                        } onClose: {
                            model.close(session)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            TerminalViewControls(compact: compact)
            Button(action: onMinimize) {
                Image(systemName: "plus")
                    .frame(width: 34, height: 30)
            }
            .accessibilityLabel("New session")
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 2 : 6)
        .background(.bar)
    }
}

/// Font size, rotation and the terminal's view options, in the tab bar.
struct TerminalViewControls: View {
    @Environment(AppModel.self) private var model
    var compact: Bool

    var body: some View {
        @Bindable var library = model.library
        let size = library.settings.fontSize
        HStack(spacing: 2) {
            Button {
                library.settings.fontSize = AppSettings.fontSize(size, steppedBy: -1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 30, height: 30)
            }
            .disabled(size <= AppSettings.fontSizeRange.lowerBound)
            .accessibilityLabel("Smaller text")
            .accessibilityValue("\(Int(size)) points")
            Button {
                library.settings.fontSize = AppSettings.fontSize(size, steppedBy: 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 30, height: 30)
            }
            .disabled(size >= AppSettings.fontSizeRange.upperBound)
            .accessibilityLabel("Larger text")
            .accessibilityValue("\(Int(size)) points")
            Button {
                // Flip whichever way the screen faces now.
                library.settings.terminalOrientation = compact ? .portrait : .landscape
            } label: {
                Image(systemName: compact ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel(compact ? "Turn to portrait" : "Turn to landscape")
            Menu {
                Section("Text size: \(Int(size)) pt") {
                    Button {
                        if let session = model.sessions.active,
                           let fitted = model.terminal(for: session).fontSize(fittingColumns: 80) {
                            library.settings.fontSize = fitted
                        }
                    } label: {
                        Label("Fit 80 columns", systemImage: "arrow.left.and.right.text.vertical")
                    }
                    .disabled(model.sessions.active == nil)
                }
                Picker(selection: $library.settings.terminalOrientation) {
                    Label("Follow the phone", systemImage: "iphone").tag(TerminalOrientation.automatic)
                    Label("Landscape", systemImage: "rectangle").tag(TerminalOrientation.landscape)
                    Label("Portrait", systemImage: "rectangle.portrait").tag(TerminalOrientation.portrait)
                } label: {
                    Label("Orientation", systemImage: "rectangle.landscape.rotate")
                }
                .pickerStyle(.menu)
                Toggle(isOn: $library.settings.voiceInput) {
                    Label("Speak to type", systemImage: "mic")
                }
                Picker(selection: $library.settings.themeName) {
                    ForEach(TerminalTheme.all) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                } label: {
                    Label("Theme", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel("Terminal options")
        }
    }
}

struct SessionChip: View {
    let session: TerminalSession
    let isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(session.title)
                .lineLimit(1)
                .frame(maxWidth: 160)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .padding(4)
            }
            .accessibilityLabel("Close \(session.title)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(isActive ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var dotColor: SwiftUI.Color {
        switch session.state {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .idle, .disconnected: .gray
        }
    }
}

/// One session's terminal plus its status banner and prompts.
struct TerminalPane: View {
    let session: TerminalSession
    /// How much the keyboard covers; the terminal re-scrolls when it changes.
    var keyboardHeight: CGFloat = 0
    @Environment(AppModel.self) private var model
    @State private var showingSnippets = false
    @State private var pendingPaste: PendingPaste?
    @State private var pendingLink: URL?
    /// The voice input draft; kept here so it survives turning the phone.
    @State private var voiceDraft = ""
    /// Whether the terminal has the keyboard. Voice input steps aside while
    /// you type, and comes back when the keyboard goes down.
    @State private var terminalFocused = false

    var body: some View {
        let settings = model.library.settings
        let controller = model.terminal(for: session)
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                TerminalViewRepresentable(
                    controller: controller,
                    settings: settings,
                    autoFocus: !settings.voiceInput,
                    onSnippets: { showingSnippets = true },
                    onFontSizeChange: { model.library.settings.fontSize = $0 },
                    onConfirmPaste: { text, answer in pendingPaste = PendingPaste(text: text, answer: answer) },
                    onFocusChange: { terminalFocused = $0 },
                    onOpenLink: { pendingLink = $0 })
                SessionStatusBanner(session: session) {
                    model.close(session)
                }
                .padding(12)
            }
            if settings.voiceInput && !terminalFocused {
                VoiceInputView(controller: controller, draft: $voiceDraft) {
                    showingSnippets = true
                }
            }
        }
        .onAppear { terminalFocused = controller.view.isFirstResponder }
        .onChange(of: keyboardHeight) {
            // Once the resize has settled, show the latest lines again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                controller.scrollToBottom()
            }
        }
        .sheet(item: Binding(get: { session.hostKeyPrompt }, set: { _ in })) { prompt in
            HostKeyPromptView(prompt: prompt)
                .interactiveDismissDisabled()
        }
        .sheet(item: Binding(get: { session.passwordPrompt }, set: { _ in })) { prompt in
            PasswordPromptView(prompt: prompt)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSnippets) {
            SnippetPicker { snippet in
                let input = snippet.input(allowRun: model.library.settings.runSavedCommands)
                let controller = model.terminal(for: session)
                if input.pressReturn {
                    controller.session.send(PastedText.bytes(for: input.text, bracketed: false) + [0x0D])
                } else {
                    controller.type(input.text)
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Open this link?", isPresented: Binding(
            get: { pendingLink != nil }, set: { if !$0 { pendingLink = nil } }),
            titleVisibility: .visible, presenting: pendingLink) { url in
            Button("Open in Safari") { UIApplication.shared.open(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text(url.absoluteString)
        }
        .confirmationDialog("Paste several lines?", isPresented: Binding(
            get: { pendingPaste != nil }, set: { if !$0 { pendingPaste = nil } }),
            titleVisibility: .visible, presenting: pendingPaste) { paste in
            Button("Paste \(paste.lineCount) lines") { paste.answer(true) }
            Button("Cancel", role: .cancel) { paste.answer(false) }
        } message: { paste in
            Text("Each line is sent as if you pressed Return, so the commands run straight away. Check the text came from somewhere you trust:\n\n\(paste.preview)")
        }
    }
}

struct PendingPaste {
    let text: String
    let answer: (Bool) -> Void

    var lineCount: Int { text.split(whereSeparator: \.isNewline).count }
    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).prefix(6).map { String($0.prefix(80)) }
        return lines.joined(separator: "\n") + (lineCount > 6 ? "\n…" : "")
    }
}

struct SessionStatusBanner: View {
    let session: TerminalSession
    var onClose: () -> Void

    var body: some View {
        switch session.state {
        case .connecting(let message):
            HStack(spacing: 10) {
                ProgressView()
                Text(message).lineLimit(2)
                Spacer(minLength: 0)
                Button("Cancel") { session.disconnect() }
            }
            .font(.callout)
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .disconnected(let reason), .failed(let reason):
            VStack(alignment: .leading, spacing: 10) {
                Label(reason, systemImage: session.state == .failed(reason) ? "exclamationmark.triangle.fill" : "powerplug")
                    .font(.callout)
                    .foregroundStyle(session.state == .failed(reason) ? SwiftUI.Color.red : SwiftUI.Color.primary)
                HStack {
                    Button {
                        session.connect()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Close", role: .destructive, action: onClose)
                        .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .idle, .connected:
            EmptyView()
        }
    }
}
