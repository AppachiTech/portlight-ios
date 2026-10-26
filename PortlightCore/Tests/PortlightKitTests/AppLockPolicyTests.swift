import Foundation
import Testing
@testable import PortlightKit

@Suite struct AppLockPolicyTests {
    let t0 = ContinuousClock.now

    @Test func startsLockedAndLocksImmediatelyByDefault() {
        var policy = AppLockPolicy()
        #expect(policy.isLocked)
        policy.unlocked()
        #expect(!policy.isLocked)
        policy.didEnterBackground(at: t0)
        #expect(policy.isLocked)
        let locks1 = policy.willEnterForeground(at: t0.advanced(by: .seconds(1)))
        #expect(locks1)
    }

    @Test func gracePeriodAllowsAQuickReturnOnly() {
        var policy = AppLockPolicy(gracePeriod: 60)
        policy.unlocked()
        policy.didEnterBackground(at: t0)
        let locks2 = policy.willEnterForeground(at: t0.advanced(by: .seconds(59)))
        #expect(!locks2)
        policy.didEnterBackground(at: t0)
        let locks3 = policy.willEnterForeground(at: t0.advanced(by: .seconds(60)))
        #expect(locks3)
    }

    @Test func anEarlierInstantLocks() {
        // Can't happen on a monotonic clock, but if it did, lock.
        var policy = AppLockPolicy(gracePeriod: 300)
        policy.unlocked()
        policy.didEnterBackground(at: t0)
        let locks4 = policy.willEnterForeground(at: t0.advanced(by: .seconds(-10)))
        #expect(locks4)
    }

    @Test func gracePeriodIsCapped() {
        #expect(AppLockPolicy(gracePeriod: 86_400).gracePeriod == 0)
        let settings = try? JSONDecoder().decode(AppSettings.self, from: Data(#"{"lockGracePeriod": 3600}"#.utf8))
        #expect(settings?.lockGracePeriod == 0)
        #expect(AppLockPolicy.describe(0) == "Immediately")
    }

    @Test func manualLock() {
        var policy = AppLockPolicy(gracePeriod: 300)
        policy.unlocked()
        policy.lock()
        #expect(policy.isLocked)
    }
}
