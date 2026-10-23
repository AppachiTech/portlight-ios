import Foundation
import LocalAuthentication
import Observation
import PortlightSSH

/// Holds the authenticated LAContext so the Keychain (on any thread) can
/// read secrets without asking again while the app is unlocked.
final class AuthContextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: LAContext?

    var context: LAContext? { lock.withLock { current } }

    func replace(with context: LAContext?) {
        let old = lock.withLock { () -> LAContext? in
            let previous = current
            current = context
            return previous
        }
        old?.invalidate()
    }
}

/// The mandatory lock: nothing is shown until the device owner
/// authenticates (Face ID, Touch ID or the passcode), and the app locks
/// again when it leaves the foreground.
@MainActor
@Observable
final class AppLock {
    enum Status: Equatable {
        case locked
        case unlocking
        case unlocked
        /// The device has no passcode, so Portlight refuses to open.
        case unavailable(String)
    }

    private(set) var status: Status = .locked
    private(set) var message: String?
    @ObservationIgnored private var policy: AppLockPolicy
    @ObservationIgnored let contextBox = AuthContextBox()

    init(gracePeriod: Int) {
        policy = AppLockPolicy(gracePeriod: gracePeriod)
    }

    var isUnlocked: Bool { status == .unlocked }

    func setGracePeriod(_ seconds: Int) {
        policy.gracePeriod = TimeInterval(AppLockPolicy.allowedGracePeriods.contains(seconds) ? seconds : 0)
    }

    /// What the device offers, for the unlock button.
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func unlock() async {
        guard status != .unlocking, status != .unlocked else { return }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        // deviceOwnerAuthentication: biometrics with passcode fallback. It
        // fails only when the device has no passcode at all.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            status = .unavailable(
                "Portlight only opens on a device protected by a passcode. Set one in Settings → Face ID & Passcode, then come back.")
            return
        }
        status = .unlocking
        message = nil
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "Unlock Portlight to reach your servers")
            if ok {
                contextBox.replace(with: context)
                policy.unlocked()
                status = .unlocked
            } else {
                status = .locked
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            status = .locked
        } catch {
            status = .locked
            message = error.localizedDescription
        }
    }

    func didEnterBackground() {
        policy.didEnterBackground()
        if policy.isLocked { lockNow() }
    }

    func willEnterForeground() {
        if policy.willEnterForeground() { lockNow() }
    }

    func lockNow() {
        policy.lock()
        contextBox.replace(with: nil)
        if case .unavailable = status { return }
        status = .locked
    }
}
