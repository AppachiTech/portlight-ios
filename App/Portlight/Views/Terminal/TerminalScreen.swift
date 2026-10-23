import PortlightSSH
import SwiftUI

/// Full-screen terminal: a tab strip of open sessions over the active one.
struct TerminalScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        let theme = TerminalTheme.named(model.library.settings.themeName)
        VStack(spacing: 0) {
            SessionTabBar(compact: verticalSizeClass == .compact) { dismiss() }
            if let session = model.sessions.active {
                TerminalPane(session: session)
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
        .background(SwiftUI.Color(theme.background).ignoresSafeArea())
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .statusBarHidden(verticalSizeClass == .compact)
        .persistentSystemOverlays(verticalSizeClass == .compact ? .hidden : .automatic)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = model.library.settings.keepScreenAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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
    @Environment(AppModel.self) private var model
    @State private var showingSnippets = false
    @State private var pendingPaste: PendingPaste?

    var body: some View {
        ZStack(alignment: .bottom) {
            TerminalViewRepresentable(
                controller: model.terminal(for: session),
                settings: model.library.settings,
                onSnippets: { showingSnippets = true },
                onFontSizeChange: { model.library.settings.fontSize = $0 },
                onConfirmPaste: { text, answer in pendingPaste = PendingPaste(text: text, answer: answer) })
            SessionStatusBanner(session: session) {
                model.close(session)
            }
            .padding(12)
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
                session.send(snippet.payload)
            }
            .presentationDetents([.medium, .large])
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
