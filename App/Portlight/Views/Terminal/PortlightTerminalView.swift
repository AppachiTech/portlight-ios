import PortlightSSH
import SwiftTerm
import SwiftUI
import UIKit

/// SwiftTerm's terminal view with Portlight's clipboard rules: copies stay on
/// this device and expire, and multi-line pastes are confirmed first.
final class PortlightTerminalView: TerminalView {
    /// Asks the user before pasting text that would run several lines.
    var confirmPaste: ((String, @escaping (Bool) -> Void) -> Void)?

    override func copy(_ sender: Any?) {
        if let text = getSelection(), !text.isEmpty {
            Pasteboard.copySensitive(text)
        }
        clearSelection()
    }

    override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        let multiLine = text.contains("\n") || text.contains("\r")
        if multiLine, !getTerminal().bracketedPasteMode, let confirmPaste {
            // Without bracketed paste every newline is an Enter: make sure.
            confirmPaste(text) { [weak self] ok in
                if ok { self?.send(txt: text) }
            }
            return
        }
        super.paste(sender)
    }
}

/// One session's terminal view, kept alive for as long as the session is
/// open (owned by AppModel), so the screen survives app locking and
/// switching tabs, and output keeps arriving while it's off screen. Bridges
/// SwiftTerm's callbacks to the session; SwiftTerm calls on the main
/// thread, which `MainActor.assumeIsolated` states.
final class TerminalController: NSObject, TerminalViewDelegate {
    let session: TerminalSession
    let view: PortlightTerminalView
    let keyBar: KeyBarView
    var sticky = StickyModifiers()
    var hapticBell = true
    var onSnippets: () -> Void = {}
    var onFontSizeChange: (Double) -> Void = { _ in }
    var onConfirmPaste: (String, @escaping (Bool) -> Void) -> Void = { _, answer in answer(false) }

    private var applied: AppSettings?
    private var observers: [NSObjectProtocol] = []
    private var pinchStartSize: Double = 13

    init(session: TerminalSession, settings: AppSettings) {
        self.session = session
        view = PortlightTerminalView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480),
            font: UIFont.monospacedSystemFont(ofSize: CGFloat(settings.fontSize), weight: .regular))
        var handle: (KeyBarItem) -> Void = { _ in }
        keyBar = KeyBarView(items: settings.keyBar) { item in handle(item) }
        super.init()
        handle = { [weak self] item in self?.handle(item) }
        view.terminalDelegate = self
        view.optionAsMetaKey = true
        view.inputAccessoryView = keyBar
        attach()
        apply(settings)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func attach() {
        view.confirmPaste = { [weak self] text, answer in self?.onConfirmPaste(text, answer) }
        MainActor.assumeIsolated {
            session.attach { [weak view = self.view] bytes in
                view?.feed(byteArray: bytes[...])
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .terminalViewControlModifierReset, object: view, queue: .main) { [weak self] _ in
            self?.modifierConsumed(ctrl: true)
        })
        observers.append(center.addObserver(forName: .terminalViewMetaModifierReset, object: view, queue: .main) { [weak self] _ in
            self?.modifierConsumed(ctrl: false)
        })
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        view.addGestureRecognizer(pinch)
    }

    /// Stops feeding this view; called when the session's tab closes.
    func close() {
        MainActor.assumeIsolated { session.detach() }
        _ = view.resignFirstResponder()
    }

    func focus() {
        _ = view.becomeFirstResponder()
    }

    // MARK: Settings

    func apply(_ settings: AppSettings) {
        guard settings != applied else { return }
        let previous = applied
        applied = settings
        hapticBell = settings.hapticBell
        if previous?.themeName != settings.themeName {
            let theme = TerminalTheme.named(settings.themeName)
            view.installColors(theme.swiftTermColors)
            view.nativeForegroundColor = UIColor(theme.foreground)
            view.nativeBackgroundColor = UIColor(theme.background)
            view.caretColor = UIColor(theme.cursor)
            view.selectedTextBackgroundColor = UIColor(theme.selection)
            view.keyboardAppearance = theme.isDark ? .dark : .light
        }
        if previous?.fontSize != settings.fontSize {
            view.font = UIFont.monospacedSystemFont(ofSize: CGFloat(settings.fontSize), weight: .regular)
        }
        if previous?.cursorStyle != settings.cursorStyle || previous?.cursorBlink != settings.cursorBlink {
            view.getTerminal().setCursorStyle(settings.cursorStyle.swiftTerm(blink: settings.cursorBlink))
        }
        if previous?.scrollbackLines != settings.scrollbackLines {
            view.changeScrollback(settings.scrollbackLines)
        }
        if previous?.keyBar != settings.keyBar {
            keyBar.setItems(settings.keyBar)
        }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartSize = applied?.fontSize ?? 13
        case .changed:
            let range = AppSettings.fontSizeRange
            let size = min(max((pinchStartSize * Double(gesture.scale)).rounded(), range.lowerBound), range.upperBound)
            view.font = UIFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
            applied?.fontSize = size
        case .ended:
            if let size = applied?.fontSize { onFontSizeChange(size) }
        default:
            break
        }
    }

    // MARK: Key bar

    func handle(_ item: KeyBarItem) {
        switch item {
        case .key(let key):
            let modifiers = sticky.consume()
            syncModifiers()
            let bytes = KeyEncoder.bytes(for: key, modifiers: modifiers,
                                         applicationCursorKeys: view.getTerminal().applicationCursor)
            MainActor.assumeIsolated { session.send(bytes) }
        case .ctrl:
            sticky.tap(.ctrl)
            syncModifiers()
        case .alt:
            sticky.tap(.alt)
            syncModifiers()
        case .snippets:
            onSnippets()
        case .keyboard:
            if view.isFirstResponder {
                _ = view.resignFirstResponder()
            } else {
                _ = view.becomeFirstResponder()
            }
        }
    }

    /// SwiftTerm used a modifier for a typed character: clear one-shot ones,
    /// keep locked ones.
    private func modifierConsumed(ctrl: Bool) {
        if ctrl, sticky.ctrl == .once { sticky.ctrl = .off }
        if !ctrl, sticky.alt == .once { sticky.alt = .off }
        syncModifiers()
    }

    private func syncModifiers() {
        view.controlModifier = sticky.ctrl != .off
        view.metaModifier = sticky.alt != .off
        keyBar.update(sticky)
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let bytes = Array(data)
        MainActor.assumeIsolated { session.send(bytes) }
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        MainActor.assumeIsolated { session.resize(TerminalSize(columns: newCols, rows: newRows)) }
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        let trimmed = String(title.prefix(80))
        MainActor.assumeIsolated { session.remoteTitle = trimmed.isEmpty ? nil : trimmed }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // Only web links; never custom URL schemes a server could aim at other apps.
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return
        }
        MainActor.assumeIsolated { UIApplication.shared.open(url) }
    }

    func bell(source: TerminalView) {
        guard hapticBell else { return }
        MainActor.assumeIsolated { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    /// OSC 52 from the server: allowed to set the clipboard (vim/tmux yank),
    /// under the same local-only, expiring rules as a manual copy.
    func clipboardCopy(source: TerminalView, content: Data) {
        guard let text = String(data: content, encoding: .utf8), !text.isEmpty else { return }
        MainActor.assumeIsolated { Pasteboard.copySensitive(text) }
    }

    /// Never let a server read the clipboard.
    func clipboardRead(source: TerminalView) -> Data? { nil }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Shows a session's long-lived terminal view.
struct TerminalViewRepresentable: UIViewRepresentable {
    let controller: TerminalController
    let settings: AppSettings
    var onSnippets: () -> Void
    var onFontSizeChange: (Double) -> Void
    var onConfirmPaste: (String, @escaping (Bool) -> Void) -> Void

    func makeUIView(context: Context) -> PortlightTerminalView {
        update()
        controller.apply(settings)
        // Bring up the keyboard once the view is on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak controller] in
            controller?.focus()
        }
        return controller.view
    }

    func updateUIView(_ view: PortlightTerminalView, context: Context) {
        update()
        controller.apply(settings)
    }

    private func update() {
        controller.onSnippets = onSnippets
        controller.onFontSizeChange = onFontSizeChange
        controller.onConfirmPaste = onConfirmPaste
    }
}
