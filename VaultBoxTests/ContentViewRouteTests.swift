import Testing
@testable import VaultBox

@Suite("ContentView Route Tests")
struct ContentViewRouteTests {
    @Test("Security setup is shown and paywall is deferred on onboarding to main")
    func onboardingToMainShowsSecuritySetupFirst() {
        let decision = determinePostSetupOverlayDecision(oldRoute: .onboarding, newRoute: .main)

        #expect(decision.showSecuritySetup)
        #expect(decision.deferPaywallUntilSecuritySetupCompletes)
    }

    @Test("Security setup is shown and paywall is deferred on setup PIN to main")
    func setupPINToMainShowsSecuritySetupFirst() {
        let decision = determinePostSetupOverlayDecision(oldRoute: .setupPIN, newRoute: .main)

        #expect(decision.showSecuritySetup)
        #expect(decision.deferPaywallUntilSecuritySetupCompletes)
    }

    @Test("No security setup is shown for lock to main")
    func lockToMainDoesNotShowSecuritySetup() {
        let decision = determinePostSetupOverlayDecision(oldRoute: .lock, newRoute: .main)

        #expect(!decision.showSecuritySetup)
        #expect(!decision.deferPaywallUntilSecuritySetupCompletes)
    }

    @Test("Deferred paywall is shown after security setup completes")
    func deferredPaywallResolvesAfterSecuritySetupDismiss() {
        let resolution = resolveDeferredPostSetupPaywall(shouldDefer: true)

        #expect(resolution.showPaywall)
        #expect(!resolution.shouldDefer)
    }
}

