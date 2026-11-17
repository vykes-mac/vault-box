import Foundation

// MARK: - Trigger

/// A moment where VaultBox just did its job well. The rating pre-prompt is only ever
/// considered right after one of these, never on launch or at a random point.
enum RatingPromptTrigger: String, Sendable, Identifiable {
    /// A photo/video import finished with nothing blocked by the free limit.
    case importCompleted = "import"
    /// The last open step of the first-run activation checklist was just finished.
    case activationCompleted = "activation_complete"
    /// "Backup Now" finished and everything is in iCloud.
    case backupCompleted = "backup"

    var id: String { rawValue }
}

// MARK: - Answer

enum RatingPromptAnswer: String, Codable, Sendable {
    /// "Yes, I love it": Apple's rating sheet was requested.
    case yes
    /// "Not really": offered the feedback email instead of the App Store.
    case notReally = "not_really"
    /// Closed or "Not now", including a prompt that was shown and never answered.
    case dismissed
}

// MARK: - History

/// Everything the policy remembers between launches. Persisted as one JSON blob by
/// ``RatingPromptStore``; kept as a plain value so tests can build any state directly.
struct RatingPromptHistory: Codable, Equatable, Sendable {
    /// Pre-prompts shown, whatever the answer.
    var promptCount = 0
    /// Pre-prompts that did not end in "Yes". Capped by ``RatingPromptPolicy/maxPromptsWithoutYes``.
    var promptsWithoutYesCount = 0
    var lastPromptAt: Date?
    var lastAnswer: RatingPromptAnswer?
    /// The app version (CFBundleShortVersionString) in which the user last said "Yes".
    var lastYesVersion: String?
    /// Distinct calendar days the real vault was opened unlocked.
    var activeDayCount = 0
    var lastActiveDay: Date?
    /// The last time any paywall was shown or closed.
    var lastPaywallAt: Date?

    /// Counts today as an active day if it hasn't been counted yet.
    /// - Returns: whether the count changed.
    @discardableResult
    mutating func recordActiveDay(now: Date, calendar: Calendar = .current) -> Bool {
        if let lastActiveDay, calendar.isDate(lastActiveDay, inSameDayAs: now) {
            return false
        }
        activeDayCount += 1
        lastActiveDay = now
        return true
    }

    /// Called the moment the pre-prompt appears. Until the user answers, an unanswered
    /// prompt (app killed, vault locked) is treated as dismissed.
    mutating func recordShown(now: Date) {
        promptCount += 1
        promptsWithoutYesCount += 1
        lastPromptAt = now
        lastAnswer = .dismissed
    }

    mutating func recordAnswer(_ answer: RatingPromptAnswer, appVersion: String) {
        if answer == .yes, lastAnswer != .yes {
            promptsWithoutYesCount = max(0, promptsWithoutYesCount - 1)
            lastYesVersion = appVersion
        }
        lastAnswer = answer
    }
}

// MARK: - Policy

/// Decides whether the rating pre-prompt may appear. Pure: every input is a parameter,
/// so the rules are tested without UI, UserDefaults or the clock.
///
/// The pre-prompt only asks a yes/no question. Apple's own sheet (which has its own cap
/// of three per 365 days and may not show at all) is requested only after a "Yes".
enum RatingPromptPolicy {

    /// Distinct days the vault has been opened. Rules out the first day and first session.
    static let minimumActiveDays = 3
    /// Live items in the vault. Someone with nothing stored hasn't seen the app work yet.
    static let minimumItemCount = 5
    /// Cumulative imported items before an import counts as a positive moment.
    static let minimumImportCount = Constants.ratePromptImportThreshold

    static let cooldownAfterYesDays = 120
    static let cooldownAfterNotReallyDays = 90
    static let cooldownAfterDismissDays = 60
    /// After this many prompts that didn't get a "Yes", never ask again.
    static let maxPromptsWithoutYes = 3
    /// A paywall seen this recently means the user was just asked for money; skip.
    static let quietPeriodAfterPaywall: TimeInterval = 60 * 60

    struct Context: Sendable {
        var trigger: RatingPromptTrigger
        var now: Date
        var appVersion: String
        var isDecoyMode: Bool
        var isUnlocked: Bool
        /// A sheet, alert, paywall, cover or the privacy shield is on screen.
        var isOtherUIPresented: Bool
        var vaultItemCount: Int
        var importCount: Int
    }

    enum SkipReason: Equatable, Sendable {
        case decoyMode
        case locked
        case otherUIPresented
        case recentPaywall
        case notEnoughActiveDays
        case notEnoughItems
        case notEnoughImports
        case alreadySaidYesThisVersion
        case coolingDown
        case maxPromptsReached
    }

    enum Decision: Equatable, Sendable {
        case show
        case skip(SkipReason)
    }

    static func evaluate(_ context: Context, history: RatingPromptHistory) -> Decision {
        // The decoy vault must look like an ordinary, unremarkable app. Asking whoever
        // opened it to rate VaultBox would give the game away.
        if context.isDecoyMode { return .skip(.decoyMode) }
        if !context.isUnlocked { return .skip(.locked) }
        if context.isOtherUIPresented { return .skip(.otherUIPresented) }

        if history.promptsWithoutYesCount >= maxPromptsWithoutYes {
            return .skip(.maxPromptsReached)
        }

        if let lastPaywallAt = history.lastPaywallAt,
           context.now.timeIntervalSince(lastPaywallAt) < quietPeriodAfterPaywall {
            return .skip(.recentPaywall)
        }

        if history.activeDayCount < minimumActiveDays { return .skip(.notEnoughActiveDays) }
        if context.vaultItemCount < minimumItemCount { return .skip(.notEnoughItems) }
        if context.trigger == .importCompleted, context.importCount < minimumImportCount {
            return .skip(.notEnoughImports)
        }

        if history.lastAnswer == .yes, history.lastYesVersion == context.appVersion {
            return .skip(.alreadySaidYesThisVersion)
        }

        if let lastPromptAt = history.lastPromptAt {
            let days = cooldownDays(after: history.lastAnswer ?? .dismissed)
            let elapsed = context.now.timeIntervalSince(lastPromptAt)
            if elapsed < TimeInterval(days) * 86_400 {
                return .skip(.coolingDown)
            }
        }

        return .show
    }

    static func cooldownDays(after answer: RatingPromptAnswer) -> Int {
        switch answer {
        case .yes: cooldownAfterYesDays
        case .notReally: cooldownAfterNotReallyDays
        case .dismissed: cooldownAfterDismissDays
        }
    }
}
