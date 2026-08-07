import Foundation
import UserNotifications

/// The RevenueCat entitlement facts needed to manage a trial reminder.
struct TrialReminderState: Equatable, Sendable {
    let isActive: Bool
    let isTrial: Bool
    let willRenew: Bool
    let expirationDate: Date?
    /// When the trial started. Combined with `expirationDate` this gives the trial
    /// length, which scales how early the reminder fires.
    let purchaseDate: Date?
    /// Set by RevenueCat while Apple retries a failed charge. Mutually exclusive with
    /// the trial reminder: once billing has failed there is nothing left to warn about.
    let billingIssueDetectedAt: Date?

    init(
        isActive: Bool,
        isTrial: Bool,
        willRenew: Bool,
        expirationDate: Date?,
        purchaseDate: Date? = nil,
        billingIssueDetectedAt: Date? = nil
    ) {
        self.isActive = isActive
        self.isTrial = isTrial
        self.willRenew = willRenew
        self.expirationDate = expirationDate
        self.purchaseDate = purchaseDate
        self.billingIssueDetectedAt = billingIssueDetectedAt
    }
}

@MainActor
protocol TrialReminderNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
struct SystemTrialReminderNotificationClient: TrialReminderNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Keeps the local trial-ending notification aligned with RevenueCat's latest
/// entitlement state.
@MainActor
final class TrialReminderService {

    nonisolated static let notificationID = "com.vaultbox.trialEndingReminder"
    nonisolated static let billingIssueNotificationID = "com.vaultbox.billingIssueReminder"
    /// Used only when the trial length is unknown (no purchase date from RevenueCat).
    nonisolated static let defaultLeadDays = 2

    /// How long after RevenueCat reports the failed charge the recovery nudge fires.
    /// Apple sometimes succeeds on an immediate retry, so this leaves a short gap
    /// rather than alarming a customer whose payment is about to go through anyway.
    nonisolated static let billingIssueLeadMinutes = 60
    nonisolated static let billingIssueMinimumDelayMinutes = 5

    private let notificationClient: TrialReminderNotificationClient
    private let calendar: Calendar
    private let now: () -> Date
    private var pendingState: TrialReminderState?
    private var isReconciling = false

    init(
        notificationClient: TrialReminderNotificationClient? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationClient = notificationClient ?? SystemTrialReminderNotificationClient()
        self.calendar = calendar
        self.now = now
    }

    /// How many days before expiry to warn, scaled to the trial's length. A flat
    /// two-day lead lands on day one of a three-day trial — before the customer has
    /// really used the app, and too early to read as "your trial is ending".
    ///
    /// ``PaywallTrialTimeline`` renders the promised reminder day from this same
    /// function, so the paywall's promise and the scheduled notification cannot drift.
    nonisolated static func leadDays(forTrialDays trialDays: Int) -> Int {
        switch trialDays {
        case ...3: return 1
        case 4...14: return 2
        default: return 3
        }
    }

    /// Whole days between trial start and expiry, as reported by RevenueCat.
    nonisolated static func trialDays(
        from purchaseDate: Date,
        to expirationDate: Date,
        calendar: Calendar = .current
    ) -> Int? {
        guard expirationDate > purchaseDate else { return nil }
        return calendar.dateComponents(
            [.day],
            from: purchaseDate,
            to: expirationDate
        ).day
    }

    /// Returns the reminder time derived from RevenueCat's actual trial expiry.
    /// A reminder is skipped when the two-day warning point has already passed.
    nonisolated static func reminderDate(
        expirationDate: Date,
        now: Date,
        leadDays: Int = defaultLeadDays,
        calendar: Calendar = .current
    ) -> Date? {
        guard let fireDate = calendar.date(
            byAdding: .day,
            value: -leadDays,
            to: expirationDate
        ), fireDate > now else {
            return nil
        }
        return fireDate
    }

    /// Returns when the billing-recovery nudge should fire, or nil when the grace
    /// period ends before the nudge would be useful.
    nonisolated static func billingIssueReminderDate(
        detectedAt: Date,
        expirationDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let preferred = calendar.date(
            byAdding: .minute,
            value: billingIssueLeadMinutes,
            to: detectedAt
        ) ?? detectedAt
        let earliest = calendar.date(
            byAdding: .minute,
            value: billingIssueMinimumDelayMinutes,
            to: now
        ) ?? now

        let fireDate = max(preferred, earliest)

        // Nothing to recover once the grace period has closed.
        if let expirationDate, fireDate >= expirationDate { return nil }
        return fireDate
    }

    /// Replaces the pending reminder with one that matches the latest RevenueCat
    /// entitlement, or removes it when the customer is not in a renewing trial.
    func reconcile(with state: TrialReminderState) async {
        pendingState = state
        guard !isReconciling else { return }

        isReconciling = true
        defer { isReconciling = false }

        while let nextState = pendingState {
            pendingState = nil
            await apply(nextState)
        }
    }

    /// Reconciliation is serialized so a slower, older RevenueCat update cannot
    /// overwrite a newer cancellation after an async notification-center call.
    private func apply(_ state: TrialReminderState) async {
        cancelReminder()

        guard state.isActive else { return }

        // A failed charge supersedes the trial warning: the charge the reminder warns
        // about has already been attempted, and recovery is now the urgent message.
        if let detectedAt = state.billingIssueDetectedAt {
            guard let fireDate = Self.billingIssueReminderDate(
                detectedAt: detectedAt,
                expirationDate: state.expirationDate,
                now: now(),
                calendar: calendar
            ) else {
                return
            }

            await schedule(
                identifier: Self.billingIssueNotificationID,
                title: String(localized: "There's a problem with your payment"),
                body: String(
                    localized: "We couldn't renew your VaultBox subscription. Update your payment method to keep premium features."
                ),
                at: fireDate
            )
            return
        }

        guard state.isTrial,
              state.willRenew,
              let expirationDate = state.expirationDate else {
            return
        }

        let leadDays = Self.resolvedLeadDays(
            purchaseDate: state.purchaseDate,
            expirationDate: expirationDate,
            calendar: calendar
        )

        guard let fireDate = Self.reminderDate(
            expirationDate: expirationDate,
            now: now(),
            leadDays: leadDays,
            calendar: calendar
        ) else {
            return
        }

        await schedule(
            identifier: Self.notificationID,
            title: Self.trialReminderTitle(leadDays: leadDays),
            body: String(
                localized: "You'll be charged when it ends. Cancel any time in Settings if VaultBox isn't for you."
            ),
            at: fireDate
        )
    }

    /// Falls back to ``defaultLeadDays`` when RevenueCat hasn't given us a purchase
    /// date, which preserves the previous behaviour rather than guessing.
    nonisolated static func resolvedLeadDays(
        purchaseDate: Date?,
        expirationDate: Date,
        calendar: Calendar = .current
    ) -> Int {
        guard let purchaseDate,
              let trialDays = trialDays(
                  from: purchaseDate,
                  to: expirationDate,
                  calendar: calendar
              ) else {
            return defaultLeadDays
        }
        return leadDays(forTrialDays: trialDays)
    }

    /// A one-day lead can't reuse the "in %lld days" copy without reading as
    /// "in 1 days", so short trials get their own phrasing.
    nonisolated static func trialReminderTitle(leadDays: Int) -> String {
        guard leadDays > 1 else {
            return String(localized: "Your VaultBox trial ends tomorrow")
        }
        return String(
            format: String(localized: "Your VaultBox trial ends in %lld days"),
            locale: Locale.current,
            Int64(leadDays)
        )
    }

    private func schedule(
        identifier: String,
        title: String,
        body: String,
        at fireDate: Date
    ) async {
        let status = await notificationClient.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        )

        do {
            try await notificationClient.add(request)
        } catch {
            #if DEBUG
            print("[TrialReminderService] Failed to schedule \(identifier): \(error)")
            #endif
        }
    }

    func cancelReminder() {
        notificationClient.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationID, Self.billingIssueNotificationID]
        )
    }
}
