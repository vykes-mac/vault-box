import Testing

@testable import VaultBox

@Suite("Paywall experiments")
struct PaywallExperimentTests {

    @Test("Offering metadata selects the bundled privacy-stat treatment")
    func privacyStatTreatment() {
        let configuration = PaywallConfiguration(metadata: [
            "isHard": true,
            "paywallLayout": "privacy_stat",
            "defaultPlan": "weekly",
            "showTrialTimeline": false
        ])

        #expect(configuration.isHardPaywallEnabled)
        #expect(configuration.layout == .privacyStat)
        #expect(configuration.defaultPlan == .weekly)
        #expect(configuration.showsTrialTimeline == false)
    }

    @Test("Unknown experiment tokens fall back to the reviewed control")
    func malformedMetadataFallsBack() {
        let configuration = PaywallConfiguration(metadata: [
            "paywallLayout": "surprise_layout",
            "defaultPlan": "lifetime",
            "showTrialTimeline": "maybe"
        ])

        #expect(configuration == .fallback)
    }

    @Test("RevenueCat placement identifiers remain stable")
    func stablePlacementIdentifiers() {
        #expect(PaywallPlacement.onboardingEnd.rawValue == "onboarding_end")
        #expect(PaywallPlacement.featureGate.rawValue == "feature_gate")
        #expect(PaywallPlacement.settings.rawValue == "settings")
        #expect(PaywallPlacement.subscriptionLapsed.rawValue == "subscription_lapsed")
    }

    @Test("Every paywall event carries its experiment context")
    func analyticsContext() {
        let context = PaywallAnalyticsContext(
            placement: .onboardingEnd,
            offeringID: "privacy_stat_v1",
            layout: .privacyStat,
            isHard: true
        )
        let event = AnalyticsEvent.paywallViewed(
            context: context,
            selectedProductID: "vaultbox_premium_annual",
            trialDays: 3
        )

        #expect(event.parameters["placement"] == "onboarding_end")
        #expect(event.parameters["offering_id"] == "privacy_stat_v1")
        #expect(event.parameters["layout"] == "privacy_stat")
        #expect(event.parameters["is_hard"] == "true")
        #expect(event.parameters["selected_product_id"] == "vaultbox_premium_annual")
        #expect(event.parameters["trial_days"] == "3")
    }

    @Test("A rejected paywall has an explicit exit reason")
    func dismissalReason() {
        let context = PaywallAnalyticsContext(
            placement: .settings,
            offeringID: "default",
            layout: .classic,
            isHard: false
        )
        let event = AnalyticsEvent.paywallDismissed(
            context: context,
            secondsOnScreen: 4.25,
            reason: .closed
        )

        #expect(event.parameters["reason"] == "closed")
        #expect(event.parameters["seconds_on_screen"] == "4.2")
    }
}
