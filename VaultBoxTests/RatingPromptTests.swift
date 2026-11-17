import Foundation
import Testing

@testable import VaultBox

@Suite("Rating prompt policy")
struct RatingPromptTests {

    private static let day: TimeInterval = 86_400
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A context where everything allows the prompt.
    private static func context(
        trigger: RatingPromptTrigger = .backupCompleted,
        now: Date = now,
        appVersion: String = "1.3.0",
        isDecoyMode: Bool = false,
        isUnlocked: Bool = true,
        isOtherUIPresented: Bool = false,
        vaultItemCount: Int = 40,
        importCount: Int = 40
    ) -> RatingPromptPolicy.Context {
        RatingPromptPolicy.Context(
            trigger: trigger,
            now: now,
            appVersion: appVersion,
            isDecoyMode: isDecoyMode,
            isUnlocked: isUnlocked,
            isOtherUIPresented: isOtherUIPresented,
            vaultItemCount: vaultItemCount,
            importCount: importCount
        )
    }

    /// An engaged user who has never been asked.
    private static var engaged: RatingPromptHistory {
        var history = RatingPromptHistory()
        history.activeDayCount = RatingPromptPolicy.minimumActiveDays
        return history
    }

    private static func history(lastAnswer: RatingPromptAnswer, daysAgo: Double, version: String = "1.3.0") -> RatingPromptHistory {
        var history = engaged
        history.recordShown(now: now.addingTimeInterval(-daysAgo * day))
        history.recordAnswer(lastAnswer, appVersion: version)
        return history
    }

    // MARK: - Baseline

    @Test("An engaged user after a positive moment is asked")
    func engagedUserIsAsked() {
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: Self.engaged) == .show)
    }

    // MARK: - Engagement

    @Test("Never on the first day or the first sessions")
    func firstSessionBlocked() {
        var history = RatingPromptHistory()
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .skip(.notEnoughActiveDays))

        history.activeDayCount = RatingPromptPolicy.minimumActiveDays - 1
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .skip(.notEnoughActiveDays))
    }

    @Test("Several opens on one day count as a single active day")
    func activeDaysAreDistinctDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        var history = RatingPromptHistory()

        let countedFirstOpen = history.recordActiveDay(now: morning, calendar: calendar)
        let countedSecondOpen = history.recordActiveDay(now: morning.addingTimeInterval(3_600), calendar: calendar)
        #expect(countedFirstOpen)
        #expect(!countedSecondOpen)
        #expect(history.activeDayCount == 1)

        let countedNextDay = history.recordActiveDay(now: morning.addingTimeInterval(Self.day), calendar: calendar)
        let countedLater = history.recordActiveDay(now: morning.addingTimeInterval(5 * Self.day), calendar: calendar)
        #expect(countedNextDay)
        #expect(countedLater)
        #expect(history.activeDayCount == 3)
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .show)
    }

    @Test("A nearly empty vault is not asked")
    func needsItems() {
        let decision = RatingPromptPolicy.evaluate(
            Self.context(vaultItemCount: RatingPromptPolicy.minimumItemCount - 1),
            history: Self.engaged
        )
        #expect(decision == .skip(.notEnoughItems))
    }

    @Test("Imports only count once the import threshold is reached")
    func importThreshold() {
        let below = RatingPromptPolicy.minimumImportCount - 1
        #expect(
            RatingPromptPolicy.evaluate(
                Self.context(trigger: .importCompleted, importCount: below),
                history: Self.engaged
            ) == .skip(.notEnoughImports)
        )
        #expect(
            RatingPromptPolicy.evaluate(
                Self.context(trigger: .importCompleted, importCount: RatingPromptPolicy.minimumImportCount),
                history: Self.engaged
            ) == .show
        )
        // Other wins don't depend on how much was imported.
        #expect(
            RatingPromptPolicy.evaluate(
                Self.context(trigger: .activationCompleted, importCount: 0),
                history: Self.engaged
            ) == .show
        )
    }

    // MARK: - Hard Blocks

    @Test("Never in the decoy vault")
    func decoyBlocked() {
        let decision = RatingPromptPolicy.evaluate(Self.context(isDecoyMode: true), history: Self.engaged)
        #expect(decision == .skip(.decoyMode))
    }

    @Test("Never while locked or while something else is on screen")
    func lockedOrBusyBlocked() {
        #expect(
            RatingPromptPolicy.evaluate(Self.context(isUnlocked: false), history: Self.engaged)
                == .skip(.locked)
        )
        #expect(
            RatingPromptPolicy.evaluate(Self.context(isOtherUIPresented: true), history: Self.engaged)
                == .skip(.otherUIPresented)
        )
    }

    @Test("Never right after a paywall")
    func recentPaywallBlocked() {
        var history = Self.engaged
        history.lastPaywallAt = Self.now.addingTimeInterval(-60)
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .skip(.recentPaywall))

        history.lastPaywallAt = Self.now.addingTimeInterval(-RatingPromptPolicy.quietPeriodAfterPaywall - 1)
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .show)
    }

    // MARK: - Cooldowns

    @Test("A dismissed prompt waits out its cooldown")
    func dismissCooldown() {
        let days = Double(RatingPromptPolicy.cooldownAfterDismissDays)
        #expect(
            RatingPromptPolicy.evaluate(Self.context(), history: Self.history(lastAnswer: .dismissed, daysAgo: days - 1))
                == .skip(.coolingDown)
        )
        #expect(
            RatingPromptPolicy.evaluate(Self.context(), history: Self.history(lastAnswer: .dismissed, daysAgo: days + 1))
                == .show
        )
    }

    @Test("An unanswered prompt counts as dismissed")
    func unansweredCountsAsDismissed() {
        var history = Self.engaged
        history.recordShown(now: Self.now.addingTimeInterval(-Self.day))
        #expect(history.lastAnswer == .dismissed)
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .skip(.coolingDown))
    }

    @Test("\"Not really\" backs off longer than a dismissal")
    func notReallyCooldown() {
        let days = Double(RatingPromptPolicy.cooldownAfterNotReallyDays)
        #expect(RatingPromptPolicy.cooldownAfterNotReallyDays > RatingPromptPolicy.cooldownAfterDismissDays)
        #expect(
            RatingPromptPolicy.evaluate(Self.context(), history: Self.history(lastAnswer: .notReally, daysAgo: days - 1))
                == .skip(.coolingDown)
        )
        #expect(
            RatingPromptPolicy.evaluate(Self.context(), history: Self.history(lastAnswer: .notReally, daysAgo: days + 1))
                == .show
        )
    }

    // MARK: - Yes

    @Test("After a yes, never again in the same version")
    func yesSuppressesSameVersion() {
        let history = Self.history(lastAnswer: .yes, daysAgo: 400, version: "1.3.0")
        #expect(
            RatingPromptPolicy.evaluate(Self.context(appVersion: "1.3.0"), history: history)
                == .skip(.alreadySaidYesThisVersion)
        )
    }

    @Test("After a yes, a new version still waits the long cooldown")
    func yesCooldownAcrossVersions() {
        let days = Double(RatingPromptPolicy.cooldownAfterYesDays)
        #expect(
            RatingPromptPolicy.evaluate(
                Self.context(appVersion: "1.4.0"),
                history: Self.history(lastAnswer: .yes, daysAgo: days - 1, version: "1.3.0")
            ) == .skip(.coolingDown)
        )
        #expect(
            RatingPromptPolicy.evaluate(
                Self.context(appVersion: "1.4.0"),
                history: Self.history(lastAnswer: .yes, daysAgo: days + 1, version: "1.3.0")
            ) == .show
        )
    }

    @Test("A yes doesn't count toward the limit for unhappy answers")
    func yesDoesNotUseUpTheLimit() {
        var history = Self.engaged
        history.recordShown(now: Self.now)
        history.recordAnswer(.yes, appVersion: "1.3.0")
        #expect(history.promptCount == 1)
        #expect(history.promptsWithoutYesCount == 0)
        #expect(history.lastYesVersion == "1.3.0")
    }

    // MARK: - Limit

    @Test("Stops for good after three prompts without a yes")
    func maxPrompts() {
        var history = Self.engaged
        let start = Self.now.addingTimeInterval(-1_000 * Self.day)
        for index in 0..<RatingPromptPolicy.maxPromptsWithoutYes {
            history.recordShown(now: start.addingTimeInterval(Double(index) * 100 * Self.day))
            history.recordAnswer(index.isMultiple(of: 2) ? .dismissed : .notReally, appVersion: "1.3.0")
        }
        #expect(history.promptsWithoutYesCount == RatingPromptPolicy.maxPromptsWithoutYes)
        #expect(RatingPromptPolicy.evaluate(Self.context(), history: history) == .skip(.maxPromptsReached))
    }

    // MARK: - Persistence

    @Test("History survives a relaunch")
    func storeRoundTrip() throws {
        let suiteName = "RatingPromptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = RatingPromptStore(defaults: defaults)

        #expect(store.load() == RatingPromptHistory())

        var history = Self.history(lastAnswer: .notReally, daysAgo: 3)
        history.lastPaywallAt = Self.now
        store.save(history)
        #expect(RatingPromptStore(defaults: defaults).load() == history)
    }

    // MARK: - Analytics

    @Test("Events carry only the trigger and a count")
    func analyticsParameters() {
        let shown = AnalyticsEvent.ratingPromptShown(trigger: .importCompleted, promptNumber: 2)
        #expect(shown.name == "rating_prompt_shown")
        #expect(shown.parameters == ["trigger": "import", "prompt_number": "2"])

        #expect(AnalyticsEvent.ratingPromptAnsweredYes(trigger: .backupCompleted).name == "rating_prompt_answered_yes")
        #expect(AnalyticsEvent.ratingPromptAnsweredNotReally(trigger: .backupCompleted).name == "rating_prompt_answered_not_really")
        #expect(AnalyticsEvent.ratingPromptDismissed(trigger: .activationCompleted).parameters == ["trigger": "activation_complete"])
        #expect(AnalyticsEvent.ratingPromptFeedbackOpened(trigger: .importCompleted).name == "rating_prompt_feedback_opened")
    }
}
