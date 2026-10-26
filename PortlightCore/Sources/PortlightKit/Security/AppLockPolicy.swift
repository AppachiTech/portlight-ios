import Foundation

/// When the app must ask for Face ID, Touch ID or the passcode. The lock
/// can't be turned off; only a short grace period after leaving the app is
/// configurable. Time away is measured on ContinuousClock, which keeps
/// counting while the phone sleeps and ignores changes to the date and
/// time in Settings, so setting the clock back can't stretch the grace
/// period.
public struct AppLockPolicy: Equatable, Sendable {
    /// Grace periods offered in Settings, in seconds.
    public static let allowedGracePeriods = [0, 30, 60, 300]

    public private(set) var isLocked = true
    private var backgroundedAt: ContinuousClock.Instant?
    public var gracePeriod: TimeInterval

    public init(gracePeriod: Int = 0) {
        self.gracePeriod = TimeInterval(Self.allowedGracePeriods.contains(gracePeriod) ? gracePeriod : 0)
    }

    /// Successful device-owner authentication.
    public mutating func unlocked() {
        isLocked = false
        backgroundedAt = nil
    }

    /// The app left the foreground (or the screen locked).
    public mutating func didEnterBackground(at now: ContinuousClock.Instant = .now) {
        if gracePeriod == 0 {
            isLocked = true
        } else if backgroundedAt == nil {
            backgroundedAt = now
        }
    }

    /// The app is coming back. Returns true when it must authenticate.
    public mutating func willEnterForeground(at now: ContinuousClock.Instant = .now) -> Bool {
        if let since = backgroundedAt {
            backgroundedAt = nil
            let away = since.duration(to: now)
            if away < .zero || away >= .seconds(gracePeriod) { isLocked = true }
        }
        return isLocked
    }

    /// Lock now, e.g. from a "Lock" button or after a failed check.
    public mutating func lock() {
        isLocked = true
        backgroundedAt = nil
    }

    public static func describe(_ seconds: Int) -> String {
        switch seconds {
        case 0: "Immediately"
        case 60: "After 1 minute"
        case 300: "After 5 minutes"
        default: "After \(seconds) seconds"
        }
    }
}
