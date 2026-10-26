import PortlightKit
import UIKit

/// Turns the screen for the terminal. Asking the scene for an orientation
/// works even with the phone's rotation lock on, which is the point: the
/// lock usually holds the phone in portrait.
@MainActor
enum OrientationLock {
    static var deviceDefault: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// Applies a terminal orientation, or with nil goes back to following
    /// the phone.
    static func apply(_ orientation: TerminalOrientation?) {
        let mask: UIInterfaceOrientationMask = switch orientation {
        case .landscape: .landscape
        case .portrait: .portrait
        case .automatic, nil: deviceDefault
        }
        guard mask != AppDelegate.orientationMask else { return }
        AppDelegate.orientationMask = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
