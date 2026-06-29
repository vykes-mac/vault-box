import Foundation
import UserNotifications

@MainActor
protocol DocumentReminderNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

@MainActor
struct SystemDocumentReminderNotificationClient: DocumentReminderNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        (try? await center.requestAuthorization(options: options)) ?? false
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Schedules and cancels local notifications for document expiry reminders.
///
/// Privacy: notification copy is intentionally generic — it never names the
/// document type, number, or any OCR content. The specifics are only visible
/// after the user unlocks the app.
@MainActor
final class DocumentReminderService {

    private let notificationClient: DocumentReminderNotificationClient
    private let calendar: Calendar
    private let now: () -> Date
    /// Hour of day (local) at which reminders fire.
    private let fireHour = 9

    init(
        notificationClient: DocumentReminderNotificationClient = SystemDocumentReminderNotificationClient(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationClient = notificationClient
        self.calendar = calendar
        self.now = now
    }

    static let notificationIDPrefix = "docexpiry"

    // MARK: - Permission

    /// Requests notification permission if it has not been determined yet.
    /// Returns whether notifications are authorized afterwards.
    @discardableResult
    func ensureNotificationPermission() async -> Bool {
        switch await notificationClient.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return await notificationClient.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Scheduling

    /// Cancels any existing notifications for the reminder and schedules fresh
    /// ones for each future lead day. Returns the scheduled identifiers (which the
    /// caller should persist back onto the reminder).
    @discardableResult
    func reschedule(for reminder: DocumentReminder) async -> [String] {
        // Always clear prior notifications first.
        cancel(notificationIDs: reminder.notificationIDs)

        guard reminder.reminderEnabled, !reminder.isDismissed else {
            return []
        }

        guard await ensureNotificationPermission() else {
            return []
        }

        let expiryDay = calendar.startOfDay(for: reminder.expiryDate)
        var scheduledIDs: [String] = []

        // Deduplicate and sort lead days descending so the earliest reminder fires first.
        let leads = Set(reminder.leadDays).sorted(by: >)

        for lead in leads {
            guard let fireDay = calendar.date(byAdding: .day, value: -lead, to: expiryDay) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: fireDay)
            comps.hour = fireHour
            guard let fireDate = calendar.date(from: comps), fireDate > now() else {
                continue // Lead day already passed.
            }

            let id = "\(Self.notificationIDPrefix)-\(reminder.id.uuidString)-\(lead)"
            let content = UNMutableNotificationContent()
            content.title = "Document expiring soon"
            content.body = bodyText(forLeadDays: lead)
            content.sound = .default
            content.userInfo = ["reminderID": reminder.id.uuidString]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour], from: fireDate),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await notificationClient.add(request)
                scheduledIDs.append(id)
            } catch {
                #if DEBUG
                print("[DocumentReminderService] Failed to schedule \(id): \(error)")
                #endif
            }
        }

        return scheduledIDs
    }

    /// Cancels notifications by identifier.
    func cancel(notificationIDs: [String]) {
        guard !notificationIDs.isEmpty else { return }
        notificationClient.removePendingNotificationRequests(withIdentifiers: notificationIDs)
    }

    // MARK: - Copy

    private func bodyText(forLeadDays lead: Int) -> String {
        switch lead {
        case 0: "A document in your vault expires today. Tap to review."
        case 1: "A document in your vault expires tomorrow. Tap to review."
        default: "A document in your vault expires in \(lead) days. Tap to review."
        }
    }
}
