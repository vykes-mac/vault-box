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

    /// Called when the user becomes premium. Once they've paid, they are never gated
    /// again — including after a lapse, where a soft upsell is the right tool.
    static func markSatisfied(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: requiresKey)
    }

    static func isRequired(
        isHardPaywallEnabled: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        isHardPaywallEnabled && defaults.bool(forKey: requiresKey)
    }
}

/// Whether the hard paywall should be on screen right now.
///
/// `hasWaivedThisSession` is the escape valve: if the paywall let the user through
/// (App Store unreachable), we must not immediately shove it back in their face.
func shouldPresentHardPaywall(
    route: AppRootRoute?,
    isGateRequired: Bool,
    isPremium: Bool,
    hasResolvedCustomerInfo: Bool,
    hasResolvedPaywallConfiguration: Bool,
    hasWaivedThisSession: Bool
) -> Bool {
    guard route == .main else { return false }
    guard isGateRequired else { return false }
    guard hasResolvedCustomerInfo else { return false }
    guard hasResolvedPaywallConfiguration else { return false }
    guard !isPremium else { return false }
    return !hasWaivedThisSession
}
