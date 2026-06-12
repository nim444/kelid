import Foundation

/// Pure, deterministic policy pipeline — Svault's gate order, with the rate
/// limit moved to the secret level. No I/O, no state: callers pass the seal,
/// the recent activity window, and get a verdict gate back.
///
/// Pipeline (first hit wins):
///   sealed → reason valid → required callers → per-secret rate limit →
///   per-caller burst → per-secret burst (any caller) → tier gate.
nonisolated enum PolicyEngine {
    // Svault-verified constants (policy.rs).
    static let sealDenyThreshold = 5
    static let sealWindowSecs: TimeInterval = 300
    static let burstWindowSecs: TimeInterval = 10
    static let burstMax = 5          // allowed reads per caller per secret / 10s
    static let secretBurstMax = 10   // allowed reads per secret, any caller / 10s
    static let minReasonLength = 10

    /// One past request, used for rate/burst/seal counting.
    struct ActivityRecord: Codable, Hashable {
        var secret: String
        var caller: String
        var allowed: Bool
        var at: Date
    }

    enum Gate: Equatable {
        case deny(String)
        case allow(note: String?)
        case needsJudge
    }

    static func gate(
        secret: String,
        caller: String,
        reason: String,
        rule: SecretRule,
        seal: Seal?,
        recent: [ActivityRecord],
        now: Date = .now
    ) -> Gate {
        // 1. Sealed? Denied before anything else — even a perfect reason.
        if let seal {
            return .deny("sealed: \(seal.trigger) — a human must clear it")
        }

        // 2. Reason must be substantive.
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedReason.count < minReasonLength {
            return .deny("reason too short (min \(minReasonLength) characters)")
        }

        // 3. Per-secret caller restriction.
        if !rule.requiredCallers.isEmpty, !rule.requiredCallers.contains(caller) {
            return .deny("caller not authorized for this secret")
        }

        // 4. Per-secret rate limit (caller-agnostic — rotating callers doesn't help).
        if let (count, window) = rateLimitParse(rule.rateLimit) {
            let allowedInWindow = recent.count {
                $0.secret == secret && $0.allowed && now.timeIntervalSince($0.at) < window
            }
            if allowedInWindow >= count {
                return .deny("rate limit exceeded (\(rule.rateLimit))")
            }
        }

        // 5. Per-caller burst.
        let callerBurst = recent.count {
            $0.secret == secret && $0.caller == caller && $0.allowed
                && now.timeIntervalSince($0.at) < burstWindowSecs
        }
        if callerBurst >= burstMax {
            return .deny("burst limit: \(burstMax) reads in \(Int(burstWindowSecs))s for one caller")
        }

        // 6. Per-secret burst across all callers.
        let secretBurst = recent.count {
            $0.secret == secret && $0.allowed && now.timeIntervalSince($0.at) < burstWindowSecs
        }
        if secretBurst >= secretBurstMax {
            return .deny("burst limit: \(secretBurstMax) reads in \(Int(burstWindowSecs))s for this secret")
        }

        // 7. Tier gate.
        if rule.tier == .low && !rule.requireReason {
            return .allow(note: nil)
        }
        return .needsJudge
    }

    /// Should this denial seal the secret? Low tier never seals; medium/high
    /// seal after 5 denials within 300s, counted across any caller.
    static func shouldSeal(
        secret: String,
        tier: Tier,
        recent: [ActivityRecord],
        now: Date = .now
    ) -> Bool {
        guard tier != .low else { return false }
        let denials = recent.count {
            $0.secret == secret && !$0.allowed && now.timeIntervalSince($0.at) < sealWindowSecs
        }
        return denials >= sealDenyThreshold
    }

    /// Parses "5/hour", "20/day", "10/min", "3/s" → (count, window seconds).
    static func rateLimitParse(_ s: String) -> (count: Int, window: TimeInterval)? {
        let parts = s.lowercased().split(separator: "/")
        guard parts.count == 2, let count = Int(parts[0]), count > 0 else { return nil }
        let window: TimeInterval? = switch parts[1] {
        case "s", "sec", "second", "seconds": 1
        case "m", "min", "minute", "minutes": 60
        case "h", "hr", "hour", "hours": 3600
        case "d", "day", "days": 86400
        default: nil
        }
        guard let window else { return nil }
        return (count, window)
    }
}
