import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Refuses third-party keyboards everywhere in the app. Everything typed
    /// into a terminal (including passwords at sudo prompts) would otherwise
    /// pass through the keyboard extension.
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
