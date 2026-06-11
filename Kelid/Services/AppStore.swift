import Foundation
import Observation

/// Single source of truth for app-level state. Persists lightweight flags to
/// UserDefaults; the master record itself lives in MasterKeyStore.
@Observable
final class AppStore {
    private enum Keys {
        static let onboardingComplete = "onboarding_complete"
        static let touchIDEnrolled = "touchid_enrolled"
    }

    var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: Keys.onboardingComplete) }
    }

    /// Milestone-1: records the user's choice and a successful biometric check.
    /// The Touch ID keyslot binding arrives with the crypto core.
    var touchIDEnrolled: Bool {
        didSet { UserDefaults.standard.set(touchIDEnrolled, forKey: Keys.touchIDEnrolled) }
    }

    init() {
        let defaults = UserDefaults.standard
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        touchIDEnrolled = defaults.bool(forKey: Keys.touchIDEnrolled)
    }
}
