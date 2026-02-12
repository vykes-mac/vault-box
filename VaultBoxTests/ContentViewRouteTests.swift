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

    @Test("Main shell is preserved for lock and main routes")
    func mainShellIsPreservedForLockAndMain() {
        #expect(shouldRenderMainShell(for: .main))
        #expect(shouldRenderMainShell(for: .lock))
    }

    @Test("Main shell is not used for onboarding and setup routes")
    func mainShellIsNotUsedForSetupFlow() {
        #expect(!shouldRenderMainShell(for: .onboarding))
        #expect(!shouldRenderMainShell(for: .setupPIN))
    }

    @Test("Main to lock transition dismisses main-shell presentations")
    func mainToLockDismissesMainShellPresentations() {
        #expect(shouldDismissMainShellPresentations(oldRoute: .main, newRoute: .lock))
    }

    @Test("Other route transitions do not dismiss main-shell presentations")
    func nonMainToLockTransitionsDoNotDismissMainShellPresentations() {
        #expect(!shouldDismissMainShellPresentations(oldRoute: .onboarding, newRoute: .lock))
        #expect(!shouldDismissMainShellPresentations(oldRoute: .setupPIN, newRoute: .lock))
        #expect(!shouldDismissMainShellPresentations(oldRoute: .lock, newRoute: .main))
        #expect(!shouldDismissMainShellPresentations(oldRoute: .main, newRoute: .main))
    }
}
