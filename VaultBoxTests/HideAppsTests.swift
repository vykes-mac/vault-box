import Foundation
import Testing

@testable import VaultBox

@Suite("Hide Apps")
struct HideAppsTests {

    // MARK: - Availability

    @Test("The build flag turns the feature on only for an explicit yes")
    func availabilityReadsBuildFlag() {
        #expect(HideAppsAvailability.isEnabled(infoDictionary: ["HideAppsEnabled": "YES"]))
        #expect(HideAppsAvailability.isEnabled(infoDictionary: ["HideAppsEnabled": "yes"]))
        #expect(!HideAppsAvailability.isEnabled(infoDictionary: ["HideAppsEnabled": "NO"]))
        // An unexpanded build setting means the flag was never set: stay off.
        #expect(!HideAppsAvailability.isEnabled(infoDictionary: ["HideAppsEnabled": "$(HIDE_APPS_ENABLED)"]))
        #expect(!HideAppsAvailability.isEnabled(infoDictionary: [:]))
        #expect(!HideAppsAvailability.isEnabled(infoDictionary: nil))
    }

    @Test("An unavailable service never reports hidden apps")
    @MainActor
    func unavailableServiceIsInert() {
        let service = HideAppsService(isAvailable: false)

        #expect(!service.isHiding)
        #expect(!service.isAuthorized)
        #expect(service.hiddenAppCount == 0)
        #expect(service.selectionIssue == nil)
    }

    // MARK: - Showing for a while

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Hiding off shows everything, whatever else is set")
    func disabledHidesNothing() {
        let hidden = HideAppsRules.appsToHide(
            selected: [1, 2, 3], isEnabled: false, revealed: nil, revealUntil: nil, now: now
        )
        #expect(hidden.isEmpty)
    }

    @Test("With no reveal running, every picked app is hidden")
    func noRevealHidesAll() {
        let hidden = HideAppsRules.appsToHide(
            selected: [1, 2, 3], isEnabled: true, revealed: nil, revealUntil: nil, now: now
        )
        #expect(hidden == [1, 2, 3])
    }

    @Test("Showing all apps for a while hides nothing until the time is up")
    func showAllRevealsEverything() {
        let until = now.addingTimeInterval(900)
        let during = HideAppsRules.appsToHide(
            selected: [1, 2, 3], isEnabled: true, revealed: nil, revealUntil: until, now: now
        )
        #expect(during.isEmpty)

        let after = HideAppsRules.appsToHide(
            selected: [1, 2, 3], isEnabled: true, revealed: nil, revealUntil: until,
            now: until.addingTimeInterval(1)
        )
        #expect(after == [1, 2, 3])
    }

    @Test("Showing one app keeps the rest hidden")
    func showOneKeepsOthersHidden() {
        let hidden = HideAppsRules.appsToHide(
            selected: [1, 2, 3], isEnabled: true, revealed: [2],
            revealUntil: now.addingTimeInterval(900), now: now
        )
        #expect(hidden == [1, 3])
    }

    @Test("A new reveal on top of a running one keeps both apps showing until the later end")
    func revealsMerge() {
        let first = now.addingTimeInterval(3600)
        let merged = HideAppsRules.merge(
            existing: (tokens: Set([1]), until: first),
            adding: Set([2]),
            until: now.addingTimeInterval(900),
            now: now
        )
        #expect(merged.tokens == [1, 2])
        #expect(merged.until == first)
    }

    @Test("Showing all on top of showing one shows all")
    func showAllWinsOverOne() {
        let merged = HideAppsRules.merge(
            existing: (tokens: Set([1]), until: now.addingTimeInterval(900)),
            adding: nil,
            until: now.addingTimeInterval(3600),
            now: now
        )
        #expect(merged.tokens == nil)
        #expect(merged.until == now.addingTimeInterval(3600))
    }

    @Test("An expired reveal doesn't carry into a new one")
    func expiredRevealIsIgnored() {
        let merged = HideAppsRules.merge(
            existing: (tokens: Set([1]), until: now.addingTimeInterval(-1)),
            adding: Set([2]),
            until: now.addingTimeInterval(900),
            now: now
        )
        #expect(merged.tokens == [2])
    }

    // MARK: - Releasing apps one at a time

    @Test("Several apps come back one per step, ending at the target")
    func releasesOneAtATime() {
        let steps = HideAppsRules.releaseSteps(from: [1, 2, 3, 4], to: [4])

        #expect(steps.count == 3)
        #expect(steps.last == [4])
        var previous: Set<Int> = [1, 2, 3, 4]
        for step in steps {
            #expect(previous.subtracting(step).count == 1)
            #expect(step.isSubset(of: previous))
            previous = step
        }
    }

    @Test("Showing everything releases each app separately")
    func showAllReleasesSeparately() {
        let steps = HideAppsRules.releaseSteps(from: [1, 2, 3], to: [])
        #expect(steps.map(\.count) == [2, 1, 0])
    }

    @Test("A single app, or only hiding, is written in one go")
    func singleChangesAreImmediate() {
        #expect(HideAppsRules.releaseSteps(from: [1, 2], to: [2]) == [[2]])
        #expect(HideAppsRules.releaseSteps(from: [1], to: [1, 2, 3]) == [[1, 2, 3]])
        #expect(HideAppsRules.releaseSteps(from: Set<Int>(), to: Set<Int>()) == [[]])
    }

    @Test("New apps are hidden first, before any app is released")
    func hidesBeforeReleasing() {
        let steps = HideAppsRules.releaseSteps(from: [1, 2], to: [3])

        #expect(steps.first == [1, 2, 3])
        #expect(steps.last == [3])
        #expect(steps.count == 3)
    }

    @Test("Timers are never shorter than Screen Time allows")
    func durationsRespectScreenTimeMinimum() {
        #expect(HideAppsRevealDuration.allCases.allSatisfy { $0.seconds >= 15 * 60 })
    }

    @Test("Saved state survives a round trip through the app group")
    func stateRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "HideAppsTests.\(UUID().uuidString)"))
        let state = HideAppsState(
            isEnabled: true,
            reveal: HideAppsReveal(tokens: nil, until: now)
        )
        HideAppsStore.save(state, to: defaults)
        #expect(HideAppsStore.load(from: defaults) == state)
    }

    @Test("The locked-phone copy of the state survives a round trip through its file")
    func stateFileRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HideAppsTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let state = HideAppsState(
            isEnabled: true,
            reveal: HideAppsReveal(tokens: nil, until: now)
        )
        #expect(HideAppsStore.load(fromFile: url) == nil)
        HideAppsStore.save(state, toFile: url)
        #expect(HideAppsStore.load(fromFile: url) == state)
    }

    // MARK: - Premium ending

    @Test("Apps only reappear after a lapse RevenueCat confirmed, in the real vault")
    func lapseNeedsConfirmationAndRealVault() {
        func ask(
            main: Bool = true, decoy: Bool = false, premium: Bool = false,
            confirmed: Bool = true, hiding: Bool = true
        ) -> Bool {
            HideAppsLapsePolicy.shouldAskAfterLapse(
                isMainRoute: main, isDecoyMode: decoy, isPremium: premium,
                hasConfirmedCustomerInfo: confirmed, isHidingApps: hiding
            )
        }

        #expect(ask())
        // An offline launch never looks like a lapse.
        #expect(!ask(confirmed: false))
        #expect(!ask(premium: true))
        // Never in decoy mode, and never from behind the lock screen.
        #expect(!ask(decoy: true))
        #expect(!ask(main: false))
        #expect(!ask(hiding: false))
    }

    @Test("The vault warns in the final week of a cancelled subscription")
    func warnsBeforeCancelledPremiumEnds() {
        func warn(
            premium: Bool = true, lifetime: Bool = false, willRenew: Bool = false,
            billingIssue: Bool = false, endsIn days: Double? = 3, hiding: Bool = true,
            dismissedFor: Date? = nil
        ) -> Bool {
            HideAppsLapsePolicy.shouldWarnBeforeLapse(
                isPremium: premium, isLifetime: lifetime, willRenew: willRenew,
                hasBillingIssue: billingIssue,
                expirationDate: days.map { now.addingTimeInterval($0 * 86_400) },
                isHidingApps: hiding, dismissedForExpiration: dismissedFor, now: now
            )
        }

        #expect(warn())
        #expect(!warn(willRenew: true))
        #expect(!warn(lifetime: true))
        // Billing problems have their own recovery banner.
        #expect(!warn(billingIssue: true))
        #expect(!warn(endsIn: 10))
        #expect(!warn(endsIn: nil))
        #expect(!warn(hiding: false))
        #expect(!warn(premium: false))
    }

    @Test("Dismissing the warning covers that end date only")
    func dismissalIsPerEndDate() {
        let end = now.addingTimeInterval(3 * 86_400)
        func warn(dismissedFor: Date?) -> Bool {
            HideAppsLapsePolicy.shouldWarnBeforeLapse(
                isPremium: true, isLifetime: false, willRenew: false, hasBillingIssue: false,
                expirationDate: end, isHidingApps: true,
                dismissedForExpiration: dismissedFor, now: now
            )
        }

        #expect(!warn(dismissedFor: end))
        #expect(warn(dismissedFor: end.addingTimeInterval(-30 * 86_400)))
    }

    @Test("State saved before lapse support still loads")
    func olderStateStillDecodes() throws {
        let defaults = try #require(UserDefaults(suiteName: "HideAppsTests.\(UUID().uuidString)"))
        var legacy = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(HideAppsState(isEnabled: true)))
                as? [String: Any]
        )
        legacy.removeValue(forKey: "lapsePausedAt")
        defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: HideAppsShared.stateKey)

        let loaded = try #require(HideAppsStore.load(from: defaults))
        #expect(loaded.isEnabled)
        #expect(loaded.lapsePausedAt == nil)
    }

    // MARK: - Selection rules

    @Test("Individual apps alone are a clean pick")
    func appsOnlyIsClean() {
        #expect(HideAppsSelectionIssue.issue(appCount: 3, otherCount: 0) == nil)
        #expect(HideAppsSelectionIssue.issue(appCount: 0, otherCount: 0) == nil)
    }

    @Test("Categories without apps are flagged, because categories can't be hidden")
    func categoriesOnlyIsFlagged() {
        let issue = HideAppsSelectionIssue.issue(appCount: 0, otherCount: 2)
        #expect(issue == .noAppsPicked)
        #expect(issue?.blocksSaving == false)
    }

    @Test("Categories next to apps are noted but don't block the apps")
    func mixedPickNotesCategories() {
        let issue = HideAppsSelectionIssue.issue(appCount: 2, otherCount: 1)
        #expect(issue == .ignoresCategories)
        #expect(issue?.blocksSaving == false)
    }

    @Test("More apps than Screen Time accepts blocks saving")
    func tooManyAppsBlocks() {
        let limit = HideAppsSelectionIssue.appLimit
        #expect(HideAppsSelectionIssue.issue(appCount: limit, otherCount: 0) == nil)

        let issue = HideAppsSelectionIssue.issue(appCount: limit + 1, otherCount: 0)
        #expect(issue == .tooManyApps(limit: limit))
        #expect(issue?.blocksSaving == true)
    }

    // MARK: - Checklist

    @Test("Builds without Hide Apps keep the original four steps")
    func checklistWithoutHideApps() {
        let checklist = ActivationChecklist(isDisguised: false, hasItems: false)

        #expect(!checklist.steps.contains(.hideApps))
        #expect(checklist.totalCount == 4)
    }

    @Test("Hide Apps sits between the first import and sharing")
    func checklistOrderWithHideApps() {
        let checklist = ActivationChecklist(
            isDisguised: false,
            hasItems: false,
            includesHideApps: true
        )

        #expect(checklist.steps == [.secured, .disguise, .firstImport, .hideApps, .secureShare])
        #expect(checklist.totalCount == 5)
    }

    @Test("The step follows whether apps are hidden right now")
    func checklistDerivesFromLiveHiding() {
        var checklist = ActivationChecklist(
            isDisguised: true,
            hasItems: true,
            includesHideApps: true
        )
        #expect(checklist.nextStep == .hideApps)

        checklist.isHidingApps = true
        #expect(checklist.isComplete(.hideApps))
        #expect(checklist.nextStep == .secureShare)

        // Showing the apps again, or iOS clearing them after access is revoked, reopens it.
        checklist.isHidingApps = false
        #expect(checklist.nextStep == .hideApps)
    }

    @Test("Hidden apps don't count on a build that can't show the step")
    func hiddenAppsIgnoredWhenStepAbsent() {
        let checklist = ActivationChecklist(
            isDisguised: true,
            hasItems: true,
            hasShared: true,
            includesHideApps: false,
            isHidingApps: true
        )

        #expect(checklist.completedCount == 4)
        #expect(checklist.isFullyComplete)
    }

    // MARK: - Onboarding

    @Test("Private apps is only offered when the build can hide apps")
    func onboardingTargetFollowsAvailability() {
        #expect(ProtectionTarget.available(hideAppsEnabled: true).contains(.apps))
        #expect(!ProtectionTarget.available(hideAppsEnabled: false).contains(.apps))
    }

    @Test("A saved Private apps answer is dropped when the feature is off")
    func savedAnswerRespectsAvailability() {
        var answers = OnboardingAnswers()
        answers.targets = [ProtectionTarget.photos.rawValue, ProtectionTarget.apps.rawValue]

        #expect(answers.protectionTargets(hideAppsEnabled: true) == [.photos, .apps])
        #expect(answers.protectionTargets(hideAppsEnabled: false) == [.photos])
    }

    // MARK: - Analytics

    @Test("Events carry counts and entry points, never app identities")
    func analyticsPayloads() {
        let applied = AnalyticsEvent.hideAppsApplied(entryPoint: .checklist, appCount: 3)
        #expect(applied.name == "hide_apps_applied")
        #expect(applied.parameters == ["entry_point": "checklist", "app_count": "3"])

        let authorized = AnalyticsEvent.hideAppsAuthorized(entryPoint: .securitySetup, granted: true)
        #expect(authorized.name == "hide_apps_authorized")
        #expect(authorized.parameters == ["entry_point": "security_setup", "granted": "true"])

        #expect(AnalyticsEvent.hideAppsViewed(entryPoint: .settings).parameters == ["entry_point": "settings"])
        #expect(AnalyticsEvent.hideAppsRevealed(entryPoint: .settings).name == "hide_apps_revealed")
        #expect(ActivationStep.hideApps.analyticsName == "hide_apps")

        let shown = AnalyticsEvent.hideAppsShownTemporarily(entryPoint: .vault, minutes: 15, scope: .one)
        #expect(shown.name == "hide_apps_shown_temporarily")
        #expect(shown.parameters == ["entry_point": "vault", "minutes": "15", "scope": "one"])
        #expect(AnalyticsEvent.hideAppsLapseResolved(outcome: .shown).parameters == ["outcome": "shown"])
        #expect(AnalyticsEvent.hideAppsLapseViewed(appCount: 4).name == "hide_apps_lapse_viewed")
    }
}
