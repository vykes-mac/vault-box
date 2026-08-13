import Foundation

/// Stable RevenueCat placement identifiers for every context that can present a paywall.
///
/// Keep these values aligned with the RevenueCat dashboard. The identifiers are also
/// sent with VaultBox funnel events so onboarding and in-product paywalls never get
/// blended into one conversion rate.
enum PaywallPlacement: String, CaseIterable, Sendable {
    case onboardingEnd = "onboarding_end"
    case featureGate = "feature_gate"
    case settings = "settings"
    case subscriptionLapsed = "subscription_lapsed"
}
