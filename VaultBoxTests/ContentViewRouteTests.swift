import Foundation
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

@Suite("Hard paywall gate")
struct PaywallGateTests {
    private func accessState(
        marked: Bool = true,
        premium: Bool = false,
        customerInfoResolved: Bool = true,
        hardPaywallEnabled: Bool = true,
        configurationResolved: Bool = true,
        waived: Bool = false
    ) -> HardPaywallAccessState {
        resolveHardPaywallAccess(
            isGateMarkedRequired: marked,
            isPremium: premium,
            hasResolvedCustomerInfo: customerInfoResolved,
            isHardPaywallEnabled: hardPaywallEnabled,
            hasResolvedPaywallConfiguration: configurationResolved,
            hasWaivedThisSession: waived
        )
    }

    @Test("Only installs that finished the new funnel are persistently marked")
    func gateRequiresExplicitMarking() throws {
        let suiteName = "PaywallGateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        #expect(!PaywallGate.isMarkedRequired(defaults: defaults))

        PaywallGate.markRequired(defaults: defaults)
        let reloadedDefaults = try #require(UserDefaults(suiteName: suiteName))
        #expect(PaywallGate.isMarkedRequired(defaults: reloadedDefaults))
        #expect(!PaywallGate.isRequired(isHardPaywallEnabled: false, defaults: reloadedDefaults))

        PaywallGate.markSatisfied(defaults: reloadedDefaults)
        #expect(!PaywallGate.isMarkedRequired(defaults: defaults))
        #expect(accessState(
            marked: PaywallGate.isMarkedRequired(defaults: defaults),
            premium: false
        ) == .allowed)
    }

    @Test("Cold launch blocks the vault until RevenueCat and configuration resolve")
    func coldLaunchFailsClosed() {
        let waitingForCustomer = accessState(customerInfoResolved: false)
        let waitingForConfiguration = accessState(configurationResolved: false)

        #expect(waitingForCustomer == .resolving)
        #expect(waitingForCustomer.blocksMainContent)
        #expect(waitingForConfiguration == .resolving)
        #expect(waitingForConfiguration.blocksMainContent)
    }

    @Test("Resolved gated user sees the paywall only on the main route")
    func paywallPresentationRoute() {
        let state = accessState()
        #expect(state == .requiresPaywall)
        #expect(shouldPresentHardPaywall(route: .main, accessState: state))
        #expect(!shouldPresentHardPaywall(route: .lock, accessState: state))
        #expect(!shouldPresentHardPaywall(route: .onboarding, accessState: state))
    }

    @Test("Only legitimate access conditions unblock the vault")
    func allowedConditions() {
        #expect(accessState(marked: false) == .allowed)
        #expect(accessState(premium: true) == .allowed)
        #expect(accessState(hardPaywallEnabled: false) == .allowed)
        #expect(accessState(
            customerInfoResolved: false,
            hardPaywallEnabled: false
        ) == .resolving)
        #expect(accessState(waived: true) == .allowed)
    }

    @Test("Every user waits for entitlement resolution before the vault mounts")
    func unmarkedInstallStillWaitsForCustomerInfo() {
        #expect(accessState(marked: false, customerInfoResolved: false) == .resolving)
        #expect(accessState(marked: false, customerInfoResolved: true) == .allowed)
    }

    @Test("Force quit drops the temporary store-failure waiver")
    func forceQuitReevaluatesPersistedGate() {
        #expect(accessState(waived: true) == .allowed)
        #expect(accessState(waived: false) == .requiresPaywall)
    }
}

@Suite("RevenueCat entitlement enforcement")
struct RevenueCatEntitlementEnforcementTests {
    @Test("RevenueCat identity survives reconstruction with the same Keychain storage")
    func stableAppUserID() throws {
        let keyStorage = InMemoryKeyStorage()
        let firstStore = RevenueCatAppUserIDStore(keyStorage: keyStorage)
        let secondStore = RevenueCatAppUserIDStore(keyStorage: keyStorage)

        let firstID = try firstStore.getOrCreate()
        let secondID = try secondStore.getOrCreate()

        #expect(firstID == secondID)
        #expect(UUID(uuidString: firstID) != nil)
    }

    @Test("Free trial access ends at RevenueCat's known expiration time")
    func trialExpirationIsEnforcedLocally() {
        let expiration = Date(timeIntervalSince1970: 2_000)

        #expect(PurchaseService.grantsPremiumAccess(
            entitlementIsActive: true,
            isTrial: true,
            expirationDate: expiration,
            now: Date(timeIntervalSince1970: 1_999)
        ))
        #expect(!PurchaseService.grantsPremiumAccess(
            entitlementIsActive: true,
            isTrial: true,
            expirationDate: expiration,
            now: expiration
        ))
    }

    @Test("Paid billing grace follows RevenueCat's active entitlement")
    func paidAccessUsesRevenueCatAuthority() {
        #expect(PurchaseService.grantsPremiumAccess(
            entitlementIsActive: true,
            isTrial: false,
            expirationDate: Date(timeIntervalSince1970: 1),
            now: Date(timeIntervalSince1970: 2)
        ))
        #expect(!PurchaseService.grantsPremiumAccess(
            entitlementIsActive: false,
            isTrial: false,
            expirationDate: nil,
            now: Date()
        ))
    }
}
