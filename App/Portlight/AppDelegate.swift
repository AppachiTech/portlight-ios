import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// What the app may rotate to. The terminal narrows it to turn the
    /// screen; see OrientationLock.
    static var orientationMask: UIInterfaceOrientationMask = OrientationLock.deviceDefault

    /// Refuses third-party keyboards everywhere in the app. Everything typed
    /// into a terminal (including passwords at sudo prompts) would otherwise
    /// pass through the keyboard extension.
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }
}
