import Foundation
import UserNotifications

/// The RevenueCat entitlement facts needed to manage a trial reminder.
struct TrialReminderState: Equatable, Sendable {
    let isActive: Bool
    let isTrial: Bool
    let willRenew: Bool
    let expirationDate: Date?
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
    nonisolated static let leadDays = 2

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

    /// Returns the reminder time derived from RevenueCat's actual trial expiry.
    /// A reminder is skipped when the two-day warning point has already passed.
    nonisolated static func reminderDate(
        expirationDate: Date,
        now: Date,
        leadDays: Int = leadDays,
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

        guard state.isActive,
              state.isTrial,
              state.willRenew,
              let expirationDate = state.expirationDate,
              let fireDate = Self.reminderDate(
                  expirationDate: expirationDate,
                  now: now(),
                  calendar: calendar
              ) else {
            return
        }

        let status = await notificationClient.authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = String(
            format: String(localized: "Your VaultBox trial ends in %lld days"),
            locale: Locale.current,
            Int64(Self.leadDays)
        )
        content.body = String(
            localized: "You'll be charged when it ends. Cancel any time in Settings if VaultBox isn't for you."
        )
        content.sound = .default

        var dateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone

        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        )

        do {
            try await notificationClient.add(request)
        } catch {
            #if DEBUG
            print("[TrialReminderService] Failed to schedule reminder: \(error)")
            #endif
        }
    }

    func cancelReminder() {
        notificationClient.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationID]
        )
    }
}
