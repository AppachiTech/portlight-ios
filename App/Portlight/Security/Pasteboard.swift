import UIKit
import UniformTypeIdentifiers

enum Pasteboard {
    /// How long text copied out of a terminal stays on the clipboard.
    static let terminalCopyLifetime: TimeInterval = 120

    /// Terminal output may contain secrets: keep it on this device (no
    /// Universal Clipboard) and let it expire.
    static func copySensitive(_ text: String) {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(terminalCopyLifetime)])
    }

    /// Public keys and similar non-secrets: a normal copy, so Universal
    /// Clipboard can carry them to a Mac.
    static func copyPublic(_ text: String) {
        UIPasteboard.general.string = text
    }
}
