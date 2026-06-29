import SwiftData
import Foundation

/// A detected expiry reminder for a document stored in the vault.
///
/// Created (unconfirmed) when OCR finds an expiry date on an imported document,
/// then confirmed/edited by the user. All properties are defaulted so the model
/// stays CloudKit-compatible, matching the other `@Model` types in this app.
@Model
final class DocumentReminder {
    var id: UUID = UUID()
    /// The `VaultItem.id` this reminder belongs to.
    var itemID: UUID = UUID()
    /// User-facing document type, e.g. "Passport".
    var documentType: String = ""
    /// The expiry date (start of day, local time).
    var expiryDate: Date = Date()
    /// Whether the user has confirmed the auto-detected date.
    var isConfirmed: Bool = false
    /// Whether the user dismissed this reminder (kept to avoid re-creating it on re-scan).
    var isDismissed: Bool = false
    /// Whether local notifications should fire for this reminder.
    var reminderEnabled: Bool = true
    /// Comma-delimited days-before-expiry values. Stored as text to avoid
    /// SwiftData/CoreData transformable-array fragility.
    private var leadDaysStorage: String = "30,7,1"
    /// Newline-delimited `UNUserNotificationCenter` request identifiers.
    private var notificationIDsStorage: String = ""
    var detectedAt: Date = Date()

    /// Days-before-expiry at which to notify.
    @Transient
    var leadDays: [Int] {
        get {
            let parsed = leadDaysStorage
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return parsed.isEmpty ? [30, 7, 1] : parsed
        }
        set {
            leadDaysStorage = newValue
                .map(String.init)
                .joined(separator: ",")
        }
    }

    /// Identifiers of the scheduled `UNUserNotificationCenter` requests.
    @Transient
    var notificationIDs: [String] {
        get {
            notificationIDsStorage
                .split(separator: "\n")
                .map(String.init)
        }
        set {
            notificationIDsStorage = newValue.joined(separator: "\n")
        }
    }

    init(itemID: UUID, documentType: String, expiryDate: Date) {
        self.id = UUID()
        self.itemID = itemID
        self.documentType = documentType
        self.expiryDate = expiryDate
        self.isConfirmed = false
        self.isDismissed = false
        self.reminderEnabled = true
        self.leadDaysStorage = "30,7,1"
        self.notificationIDsStorage = ""
        self.detectedAt = Date()
    }

    /// Days until expiry from now (negative if already expired).
    var daysUntilExpiry: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: expiryDate)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }

    var isExpired: Bool { daysUntilExpiry < 0 }
}
