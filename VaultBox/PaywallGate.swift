import Foundation

/// Decides who has to get past the hard paywall.
///
/// Only accounts created through the current onboarding funnel are gated. Anyone who was
/// already inside the app before the hard paywall shipped keeps the access they had —
/// retroactively locking existing users out of their own encrypted files would be a
/// betrayal, and they didn't come from the ad spend this gate exists to pay for.
enum PaywallGate {
    private static let requiresKey = "com.vaultbox.requiresHardPaywall"

    /// Marks this install as gated. Called once, when a brand-new user finishes the
    /// onboarding questions and moves on to creating their PIN.
    static func markRequired(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: requiresKey)
    }

    /// Called when RevenueCat grants trial or paid premium access. Once admitted, the
    /// user is not hard-gated again after expiry; they continue on the limited free tier.
    static func markSatisfied(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: requiresKey)
    }

    static func isMarkedRequired(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: requiresKey)
    }

    static func isRequired(
        isHardPaywallEnabled: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        isHardPaywallEnabled && isMarkedRequired(defaults: defaults)
    }
}

enum HardPaywallAccessState: Equatable {
    case allowed
    case resolving
    case requiresPaywall

    var blocksMainContent: Bool {
        self != .allowed
    }
}

/// Resolves access before the main vault UI is mounted.
///
/// A marked install fails closed while RevenueCat and offering metadata load. The only
/// non-premium escape is an explicit, in-memory waiver after the store has failed; a
/// process restart intentionally loses that waiver and evaluates the persisted gate again.
func resolveHardPaywallAccess(
    isGateMarkedRequired: Bool,
    isPremium: Bool,
    hasResolvedCustomerInfo: Bool,
    isHardPaywallEnabled: Bool,
    hasResolvedPaywallConfiguration: Bool,
    hasWaivedThisSession: Bool
) -> HardPaywallAccessState {
    guard hasResolvedCustomerInfo else { return .resolving }
    guard isGateMarkedRequired else { return .allowed }
    guard !isPremium else { return .allowed }
    guard !hasWaivedThisSession else { return .allowed }
    guard hasResolvedPaywallConfiguration else { return .resolving }
    guard isHardPaywallEnabled else { return .allowed }
    return .requiresPaywall
}

func shouldPresentHardPaywall(
    route: AppRootRoute?,
    accessState: HardPaywallAccessState
) -> Bool {
    route == .main && accessState == .requiresPaywall
}
