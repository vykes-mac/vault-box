import Foundation
import Testing
import UserNotifications

@testable import VaultBox

@Suite("Onboarding answers")
struct OnboardingAnswersTests {

    @Test("Target summary keeps acronym casing and reads as a list")
    func targetSummaryFormatting() {
        var answers = OnboardingAnswers()
        #expect(answers.targetSummary == "everything private")

        answers.targets = [ProtectionTarget.documents.rawValue]
        #expect(answers.targetSummary == "IDs and documents")

        answers.targets = [
            ProtectionTarget.photos.rawValue,
            ProtectionTarget.documents.rawValue
        ]
        #expect(answers.targetSummary == "private photos and IDs and documents")

        answers.targets = [
            ProtectionTarget.photos.rawValue,
            ProtectionTarget.documents.rawValue,
            ProtectionTarget.work.rawValue
        ]
        #expect(answers.targetSummary == "private photos, IDs and documents, and work files")
    }

    @Test("Plan headline mirrors the snooping answer back to the user")
    func planHeadlineVariesByHistory() {
        var answers = OnboardingAnswers()
        let neutral = answers.planHeadline

        answers.snoopingHistory = SnoopingHistory.yes.rawValue
        let happened = answers.planHeadline

        answers.snoopingHistory = SnoopingHistory.suspected.rawValue
        let suspected = answers.planHeadline

        #expect(happened != neutral)
        #expect(suspected != neutral)
        #expect(happened != suspected)
    }

    @Test("Answers round-trip through the store")
    func answersPersist() throws {
        let defaults = try #require(UserDefaults(suiteName: "OnboardingAnswersTests-\(UUID().uuidString)"))

        var answers = OnboardingAnswers()
        answers.targets = [ProtectionTarget.videos.rawValue]
        answers.risks = [ExposureRisk.partner.rawValue]
        answers.snoopingHistory = SnoopingHistory.notYet.rawValue

        OnboardingAnswersStore.save(answers, to: defaults)
        #expect(OnboardingAnswersStore.load(from: defaults) == answers)
    }

    @Test("Loading with nothing saved yields empty answers")
    func loadDefaultsToEmpty() throws {
        let defaults = try #require(UserDefaults(suiteName: "OnboardingAnswersTests-\(UUID().uuidString)"))
        #expect(OnboardingAnswersStore.load(from: defaults) == OnboardingAnswers())
    }
}

@Suite("Onboarding step order")
struct OnboardingStepTests {

    @Test("Funnel runs hook to plan and never lets progress hit the end")
    func stepOrdering() {
        #expect(OnboardingStep.hook.previous == nil)
        #expect(OnboardingStep.plan.next == nil)
        #expect(OnboardingStep.targets.next == .risks)
        #expect(OnboardingStep.risks.previous == .targets)

        for step in OnboardingStep.allCases {
            #expect(step.progress > 0)
            #expect(step.progress < 1)
        }
    }

    @Test("Back is blocked on the opener and during the build animation")
    func backAvailability() {
        #expect(OnboardingStep.hook.allowsBack == false)
        #expect(OnboardingStep.building.allowsBack == false)
        #expect(OnboardingStep.targets.allowsBack)
        #expect(OnboardingStep.plan.allowsBack)
    }
}

@Suite("Hard paywall gate")
struct PaywallGateTests {

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "PaywallGateTests-\(UUID().uuidString)"))
    }

    @Test("Only installs that finished the new funnel are gated")
    func gateRequiresExplicitMarking() throws {
        let defaults = try makeDefaults()
        #expect(PaywallGate.isRequired(isHardPaywallEnabled: true, defaults: defaults) == false)

        PaywallGate.markRequired(defaults: defaults)
        #expect(PaywallGate.isRequired(isHardPaywallEnabled: true, defaults: defaults))
        #expect(PaywallGate.isRequired(isHardPaywallEnabled: false, defaults: defaults) == false)

        PaywallGate.markSatisfied(defaults: defaults)
        #expect(PaywallGate.isRequired(isHardPaywallEnabled: true, defaults: defaults) == false)
    }

    @Test("Paywall presents only for a gated, unsubscribed user sitting on main")
    func presentationConditions() {
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: true,
            isPremium: false,
            hasResolvedCustomerInfo: true,
            hasResolvedPaywallConfiguration: true,
            hasWaivedThisSession: false
        ))

        // Never over the lock screen or onboarding.
        for route in [AppRootRoute.lock, .onboarding, .setupPIN] {
            #expect(shouldPresentHardPaywall(
                route: route,
                isGateRequired: true,
                isPremium: false,
                hasResolvedCustomerInfo: true,
                hasResolvedPaywallConfiguration: true,
                hasWaivedThisSession: false
            ) == false)
        }

        // Existing (ungated) users are left alone.
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: false,
            isPremium: false,
            hasResolvedCustomerInfo: true,
            hasResolvedPaywallConfiguration: true,
            hasWaivedThisSession: false
        ) == false)

        // Subscribers are never shown it.
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: true,
            isPremium: true,
            hasResolvedCustomerInfo: true,
            hasResolvedPaywallConfiguration: true,
            hasWaivedThisSession: false
        ) == false)

        // Don't flash it before RevenueCat has answered.
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: true,
            isPremium: false,
            hasResolvedCustomerInfo: false,
            hasResolvedPaywallConfiguration: true,
            hasWaivedThisSession: false
        ) == false)

        // Don't enforce the local fallback before RevenueCat offering metadata arrives.
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: true,
            isPremium: false,
            hasResolvedCustomerInfo: true,
            hasResolvedPaywallConfiguration: false,
            hasWaivedThisSession: false
        ) == false)

        // A store failure that let them through must not re-trap them.
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: true,
            isPremium: false,
            hasResolvedCustomerInfo: true,
            hasResolvedPaywallConfiguration: true,
            hasWaivedThisSession: true
        ) == false)
    }

    @Test("Lock cycle preserves the gate and re-presents after unlock")
    func lockCycleDoesNotWaiveHardPaywall() {
        let commonConditions = (
            isGateRequired: true,
            isPremium: false,
            hasResolvedCustomerInfo: true,
            hasResolvedPaywallConfiguration: true
        )

        #expect(!shouldPresentHardPaywall(
            route: .lock,
            isGateRequired: commonConditions.isGateRequired,
            isPremium: commonConditions.isPremium,
            hasResolvedCustomerInfo: commonConditions.hasResolvedCustomerInfo,
            hasResolvedPaywallConfiguration: commonConditions.hasResolvedPaywallConfiguration,
            hasWaivedThisSession: false
        ))
        #expect(shouldPresentHardPaywall(
            route: .main,
            isGateRequired: commonConditions.isGateRequired,
            isPremium: commonConditions.isPremium,
            hasResolvedCustomerInfo: commonConditions.hasResolvedCustomerInfo,
            hasResolvedPaywallConfiguration: commonConditions.hasResolvedPaywallConfiguration,
            hasWaivedThisSession: false
        ))
    }
}

@Suite("Paywall remote configuration")
struct PaywallConfigurationTests {

    @Test("Hard paywall defaults on when offering metadata is absent or malformed")
    func fallback() {
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: [:]))
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": "sometimes"]))
    }

    @Test("RevenueCat offering metadata accepts dashboard boolean and string values")
    func remoteValues() {
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": true]))
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": false]) == false)
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": "true"]))
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": "false"]) == false)
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": 1]))
        #expect(PaywallConfiguration.isHardPaywallEnabled(in: ["isHard": 0]) == false)
    }
}

@Suite("Paywall pricing maths")
struct PaywallPricingTests {

    @Test("Savings compare the annual price against a year of weekly billing")
    func savingsPercent() {
        // $3.99/wk = $207.48/yr versus $79.99 → 61% saved.
        #expect(PaywallViewModel.savingsPercent(annualPrice: 79.99, weeklyPrice: 3.99) == 61)
        #expect(PaywallViewModel.savingsPercent(annualPrice: 79.99, weeklyPrice: nil) == nil)
        // Never advertise a "saving" that isn't one.
        #expect(PaywallViewModel.savingsPercent(annualPrice: 300, weeklyPrice: 3.99) == nil)
        #expect(PaywallViewModel.savingsPercent(annualPrice: 79.99, weeklyPrice: 0) == nil)
    }
}

@Suite("Paywall purchase outcomes")
struct PaywallPurchaseOutcomeTests {

    @Test("RevenueCat cancellation is not reported as a failed purchase")
    func cancellation() {
        #expect(PurchaseService.classifyPurchase(
            userCancelled: true,
            hasPremium: false
        ) == .cancelled)
    }

    @Test("An active premium entitlement marks the purchase as successful")
    func premiumGranted() {
        #expect(PurchaseService.classifyPurchase(
            userCancelled: false,
            hasPremium: true
        ) == .premiumGranted)
    }

    @Test("A completed purchase without premium remains a genuine failure")
    func premiumNotGranted() {
        #expect(PurchaseService.classifyPurchase(
            userCancelled: false,
            hasPremium: false
        ) == .premiumNotGranted)
    }
}

@Suite("TelemetryDeck analytics identity")
struct TelemetryDeckAnalyticsIdentityTests {

    @Test("SDK automatic and VaultBox events share the install identity")
    @MainActor
    func configurationUsesVaultBoxInstallIDAsDefaultUser() {
        let installID = UUID().uuidString
        let configuration = TelemetryDeckAnalyticsSink.makeConfiguration(
            appID: UUID().uuidString,
            defaultUserID: installID
        )

        #expect(configuration.defaultUser == installID)
    }
}

@MainActor
private final class MockTrialReminderNotificationClient: TrialReminderNotificationClient {
    var status: UNAuthorizationStatus
    private(set) var pendingRequests: [String: UNNotificationRequest] = [:]
    private(set) var removedIdentifiers: [[String]] = []

    init(status: UNAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func add(_ request: UNNotificationRequest) async throws {
        pendingRequests[request.identifier] = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
        for identifier in identifiers {
            pendingRequests.removeValue(forKey: identifier)
        }
    }
}

@Suite("Trial reminder scheduling")
struct TrialReminderServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        ) ?? Date()
    }

    @Test("Reminder uses RevenueCat's exact expiration date")
    func reminderDateUsesConfirmedExpiration() throws {
        let now = date(year: 2026, month: 1, day: 1, hour: 9)
        let expiration = date(year: 2026, month: 1, day: 8, hour: 14, minute: 37)
        let fireDate = try #require(
            TrialReminderService.reminderDate(
                expirationDate: expiration,
                now: now,
                calendar: calendar
            )
        )

        #expect(fireDate == date(year: 2026, month: 1, day: 6, hour: 14, minute: 37))
    }

    @Test("Renewing trial schedules one notification at the exact warning time")
    @MainActor
    func renewingTrialSchedulesReminder() async throws {
        let client = MockTrialReminderNotificationClient()
        let now = date(year: 2026, month: 1, day: 1, hour: 9)
        let expiration = date(
            year: 2026,
            month: 1,
            day: 8,
            hour: 14,
            minute: 37,
            second: 12
        )
        let service = TrialReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { now }
        )

        await service.reconcile(
            with: TrialReminderState(
                isActive: true,
                isTrial: true,
                willRenew: true,
                expirationDate: expiration
            )
        )

        let request = try #require(
            client.pendingRequests[TrialReminderService.notificationID]
        )
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.day == 6)
        #expect(trigger.dateComponents.hour == 14)
        #expect(trigger.dateComponents.minute == 37)
        #expect(trigger.dateComponents.second == 12)
        #expect(client.removedIdentifiers == [[TrialReminderService.notificationID]])
    }

    @Test("Cancellation or non-trial state removes the reminder")
    @MainActor
    func ineligibleStateCancelsReminder() async {
        let client = MockTrialReminderNotificationClient()
        let now = date(year: 2026, month: 1, day: 1)
        let expiration = date(year: 2026, month: 1, day: 8)
        let service = TrialReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { now }
        )

        await service.reconcile(
            with: TrialReminderState(
                isActive: true,
                isTrial: true,
                willRenew: true,
                expirationDate: expiration
            )
        )
        #expect(client.pendingRequests.count == 1)

        await service.reconcile(
            with: TrialReminderState(
                isActive: true,
                isTrial: true,
                willRenew: false,
                expirationDate: expiration
            )
        )
        #expect(client.pendingRequests.isEmpty)

        await service.reconcile(
            with: TrialReminderState(
                isActive: true,
                isTrial: false,
                willRenew: true,
                expirationDate: expiration
            )
        )
        #expect(client.pendingRequests.isEmpty)
    }

    @Test("Past warning time and denied notifications schedule nothing")
    @MainActor
    func unavailableReminderDoesNotSchedule() async {
        let now = date(year: 2026, month: 1, day: 7)
        let expiration = date(year: 2026, month: 1, day: 8)
        #expect(
            TrialReminderService.reminderDate(
                expirationDate: expiration,
                now: now,
                calendar: calendar
            ) == nil
        )

        let client = MockTrialReminderNotificationClient(status: .denied)
        let service = TrialReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { date(year: 2026, month: 1, day: 1) }
        )
        await service.reconcile(
            with: TrialReminderState(
                isActive: true,
                isTrial: true,
                willRenew: true,
                expirationDate: expiration
            )
        )
        #expect(client.pendingRequests.isEmpty)
    }
}
