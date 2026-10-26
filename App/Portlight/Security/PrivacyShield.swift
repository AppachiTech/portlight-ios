import SwiftUI
import UIKit

/// Covers the whole app whenever it isn't active, so the app switcher's
/// snapshot shows no hosts or terminal output. It's a window above
/// everything: a cover drawn in the main view would sit underneath the
/// terminal and sheets, which are presented on top of it. Shown on
/// will-resign-active, before iOS takes the snapshot.
@MainActor
final class PrivacyShield {
    private var window: UIWindow?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let show = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification]
        for name in show {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show() }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func show() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: PrivacyCover())
        window.isHidden = false
        self.window = window
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}
