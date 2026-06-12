import AppKit
import Foundation
import Observation

/// How the user prefers to unlock a locked session. Others remain available
/// as fallbacks on the lock screen.
enum UnlockMethod: String, CaseIterable, Identifiable {
    case touchID
    case passphrase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .touchID: "Touch ID"
        case .passphrase: "Passphrase"
        }
    }

    var icon: String {
        switch self {
        case .touchID: "touchid"
        case .passphrase: "key.horizontal"
        }
    }
}

/// Single source of truth for app-level state. Persists lightweight flags to
/// UserDefaults; the master record itself lives in MasterKeyStore.
@Observable
final class AppStore {
    private enum Keys {
        static let onboardingComplete = "onboarding_complete"
        static let touchIDEnrolled = "touchid_enrolled"
        static let autoLockMinutes = "auto_lock_minutes"
        static let preferredUnlock = "preferred_unlock"
    }

    var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: Keys.onboardingComplete) }
    }

    /// Milestone-1: records the user's choice and a successful biometric check.
    /// The Touch ID keyslot binding arrives with the crypto core.
    var touchIDEnrolled: Bool {
        didSet { UserDefaults.standard.set(touchIDEnrolled, forKey: Keys.touchIDEnrolled) }
    }

    // MARK: - Auto lock

    /// Idle minutes before the session locks. 0 = never.
    var autoLockMinutes: Int {
        didSet { UserDefaults.standard.set(autoLockMinutes, forKey: Keys.autoLockMinutes) }
    }

    var preferredUnlock: UnlockMethod {
        didSet { UserDefaults.standard.set(preferredUnlock.rawValue, forKey: Keys.preferredUnlock) }
    }

    /// While locked, RootView swaps the entire UI for the lock screen —
    /// no app content is rendered underneath.
    var isLocked: Bool

    private var lastActivity = Date()
    private var idleTimer: Timer?
    private var eventMonitor: Any?

    init() {
        let defaults = UserDefaults.standard
        let onboarded = defaults.bool(forKey: Keys.onboardingComplete)
        onboardingComplete = onboarded
        touchIDEnrolled = defaults.bool(forKey: Keys.touchIDEnrolled)
        autoLockMinutes = defaults.object(forKey: Keys.autoLockMinutes) as? Int ?? 5
        preferredUnlock = UnlockMethod(rawValue: defaults.string(forKey: Keys.preferredUnlock) ?? "") ?? .touchID
        // A secrets app starts locked: every launch requires authentication.
        isLocked = onboarded && MasterKeyStore.masterExists
    }

    /// Installs the idle watcher: any local event resets the clock, a periodic
    /// check locks the session once the configured idle interval elapses.
    func startAutoLock() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.any]) { [weak self] event in
            self?.lastActivity = Date()
            return event
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
    }

    private func checkIdle() {
        guard !isLocked, onboardingComplete, autoLockMinutes > 0 else { return }
        if Date().timeIntervalSince(lastActivity) >= Double(autoLockMinutes) * 60 {
            isLocked = true
            let minutes = autoLockMinutes
            Task { @MainActor in
                AuditLog.shared.record(.session, "Locked", detail: "Auto — idle \(minutes) min")
            }
        }
    }

    func lockNow() {
        guard onboardingComplete else { return }
        isLocked = true
        Task { @MainActor in
            AuditLog.shared.record(.session, "Locked", detail: "Manual")
        }
    }

    func unlock() {
        lastActivity = Date()
        isLocked = false
    }
}
