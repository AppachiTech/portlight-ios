import SwiftUI
import UIKit

/// How much of the screen the keyboard (with its key bar) covers, tracked
/// from UIKit's notifications. The terminal is a UIKit view that SwiftUI's
/// own keyboard avoidance didn't shrink reliably, which left its last
/// lines under the keyboard; with this the screen gives up exactly the
/// keyboard's height instead.
@MainActor
@Observable
final class KeyboardInset {
    private(set) var height: CGFloat = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.update(note) }
            })
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func update(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        var covered: CGFloat = 0
        if note.name != UIResponder.keyboardWillHideNotification, let window = Self.keyWindow {
            let local = window.convert(frame, from: window.screen.coordinateSpace)
            // Content already stays clear of the home indicator area.
            covered = max(0, window.bounds.maxY - local.minY - window.safeAreaInsets.bottom)
        }
        guard covered != height else { return }
        withAnimation(.easeOut(duration: duration)) { height = covered }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
