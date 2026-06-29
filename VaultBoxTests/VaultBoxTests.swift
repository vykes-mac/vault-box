import Testing
import SwiftData
import UIKit
import UserNotifications
@testable import VaultBox

@Suite("VaultBox Tests")
struct VaultBoxTests {
    @Test("App launches")
    func appLaunches() {
        #expect(true)
    }
}

@MainActor
private final class MockDocumentReminderNotificationClient: DocumentReminderNotificationClient {
    var status: UNAuthorizationStatus
    var requestResult: Bool
    private(set) var requestCallCount = 0
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [[String]] = []

    init(status: UNAuthorizationStatus = .authorized, requestResult: Bool = true) {
        self.status = status
        self.requestResult = requestResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        requestCallCount += 1
        status = requestResult ? .authorized : .denied
        return requestResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(identifiers)
    }
}

@Suite("DocumentReminderService Tests")
struct DocumentReminderServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    @Test("reschedule cancels old notifications and schedules unique future lead days")
    @MainActor
    func rescheduleSchedulesUniqueFutureLeadDays() async {
        let client = MockDocumentReminderNotificationClient()
        let service = DocumentReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { date(year: 2026, month: 1, day: 1) }
        )
        let reminder = DocumentReminder(
            itemID: UUID(),
            documentType: "Passport",
            expiryDate: date(year: 2026, month: 4, day: 1)
        )
        reminder.leadDays = [30, 7, 7, 1]
        reminder.notificationIDs = ["old-request"]

        let ids = await service.reschedule(for: reminder)

        #expect(client.removedIdentifiers == [["old-request"]])
        #expect(ids == [
            "docexpiry-\(reminder.id.uuidString)-30",
            "docexpiry-\(reminder.id.uuidString)-7",
            "docexpiry-\(reminder.id.uuidString)-1"
        ])
        #expect(client.addedRequests.count == 3)
        let trigger = client.addedRequests.first?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 9)
    }

    @Test("reschedule skips lead days whose fire date already passed")
    @MainActor
    func rescheduleSkipsPastLeadDays() async {
        let client = MockDocumentReminderNotificationClient()
        let service = DocumentReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { date(year: 2026, month: 1, day: 1) }
        )
        let reminder = DocumentReminder(
            itemID: UUID(),
            documentType: "Passport",
            expiryDate: date(year: 2026, month: 1, day: 20)
        )
        reminder.leadDays = [30, 7, 1]

        let ids = await service.reschedule(for: reminder)

        #expect(ids == [
            "docexpiry-\(reminder.id.uuidString)-7",
            "docexpiry-\(reminder.id.uuidString)-1"
        ])
        #expect(client.addedRequests.count == 2)
    }

    @Test("reschedule does not request permission again when notifications are denied")
    @MainActor
    func rescheduleDoesNotRequestWhenDenied() async {
        let client = MockDocumentReminderNotificationClient(status: .denied)
        let service = DocumentReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { date(year: 2026, month: 1, day: 1) }
        )
        let reminder = DocumentReminder(
            itemID: UUID(),
            documentType: "Passport",
            expiryDate: date(year: 2026, month: 4, day: 1)
        )
        reminder.notificationIDs = ["old-request"]

        let ids = await service.reschedule(for: reminder)

        #expect(ids.isEmpty)
        #expect(client.addedRequests.isEmpty)
        #expect(client.requestCallCount == 0)
        #expect(client.removedIdentifiers == [["old-request"]])
    }
}

@Suite("VaultService Tests")
struct VaultServiceTests {

    enum TestError: Error {
        case failedToCreateImageData
    }

    @MainActor
    private func makeService(
        reminderService: DocumentReminderService = DocumentReminderService()
    ) async throws -> (VaultService, ModelContext, ModelContainer) {
        let schema = Schema([AppSettings.self, VaultItem.self, Album.self, BreakInAttempt.self, DocumentReminder.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let encryption = EncryptionService(keyStorage: InMemoryKeyStorage())
        let masterKey = await encryption.generateMasterKey()
        try await encryption.storeMasterKey(masterKey)

        let service = VaultService(
            encryptionService: encryption,
            modelContext: context,
            hasPremiumAccess: { true },
            reminderService: reminderService
        )

        return (service, context, container)
    }

    private func makeImageData(width: CGFloat, height: CGFloat) throws -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw TestError.failedToCreateImageData
        }
        return data
    }

    @Test("importPhotoData keeps original byte size and dimensions")
    @MainActor
    func importPhotoDataKeepsOriginalSize() async throws {
        let (service, context, _) = try await makeService()
        let imageData = try makeImageData(width: 32, height: 24)

        let item = try await service.importPhotoData(imageData, filename: "selfie.png", album: nil)

        #expect(item.type.rawValue == "photo")
        #expect(item.originalFilename == "selfie.png")
        #expect(item.fileSize == Int64(imageData.count))
        #expect(item.pixelWidth == 32)
        #expect(item.pixelHeight == 24)

        let storedItems = try context.fetch(FetchDescriptor<VaultItem>())
        #expect(storedItems.count == 1)
    }

    @Test("importPhotoData uses default filename when input is empty")
    @MainActor
    func importPhotoDataUsesDefaultFilename() async throws {
        let (service, _, _) = try await makeService()
        let imageData = try makeImageData(width: 12, height: 12)

        let item = try await service.importPhotoData(imageData, filename: "   ", album: nil)

        #expect(item.originalFilename == "Photo")
    }

    @Test("smartTags persist after save")
    @MainActor
    func smartTagsPersistAfterSave() async throws {
        let (service, context, container) = try await makeService()
        let imageData = try makeImageData(width: 20, height: 20)
        let item = try await service.importPhotoData(imageData, filename: "tag-test.png", album: nil)

        item.smartTags = ["people", "document"]
        try context.save()
        let itemID = item.id

        let descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        let fetched = try context.fetch(descriptor).first
        #expect(fetched != nil)
        #expect(fetched?.smartTags.contains("people") == true)
        #expect(fetched?.smartTags.contains("document") == true)

        let freshContext = ModelContext(container)
        let reloaded = try freshContext.fetch(descriptor).first
        #expect(reloaded != nil)
        #expect(reloaded?.smartTags.contains("people") == true)
        #expect(reloaded?.smartTags.contains("document") == true)
    }

    @Test("repairConfirmedDocumentReminders persists rebuilt notification IDs")
    @MainActor
    func repairConfirmedDocumentRemindersPersistsIDs() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)) ?? Date()
        let expiry = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)) ?? Date()
        let client = MockDocumentReminderNotificationClient()
        let reminderScheduler = DocumentReminderService(
            notificationClient: client,
            calendar: calendar,
            now: { now }
        )
        let (service, context, _) = try await makeService(reminderService: reminderScheduler)

        let reminder = DocumentReminder(
            itemID: UUID(),
            documentType: "Passport",
            expiryDate: expiry
        )
        reminder.isConfirmed = true
        reminder.leadDays = [30, 7, 1]
        context.insert(reminder)
        try context.save()

        await service.repairConfirmedDocumentReminders()

        #expect(reminder.notificationIDs.count == 3)
        #expect(client.addedRequests.count == 3)
    }
}
