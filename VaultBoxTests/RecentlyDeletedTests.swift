import Testing
import Foundation
import SwiftData
import UIKit
@testable import VaultBox

/// Records CloudKit deletions without touching the network.
private final class CloudDeleteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    private var offline = false

    var deletedRecordIDs: [String] {
        lock.withLock { ids }
    }

    var isOffline: Bool {
        get { lock.withLock { offline } }
        set { lock.withLock { offline = newValue } }
    }

    func record(_ id: String) throws {
        try lock.withLock {
            if offline { throw URLError(.notConnectedToInternet) }
            ids.append(id)
        }
    }
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(days: Double) {
        now = now.addingTimeInterval(days * 86_400)
    }
}

@Suite("Recently Deleted Tests")
@MainActor
struct RecentlyDeletedTests {

    private struct Harness {
        let service: VaultService
        let context: ModelContext
        let container: ModelContainer
        let encryption: EncryptionService
        let clock: TestClock
        let cloud: CloudDeleteRecorder
    }

    enum TestError: Error {
        case failedToCreateImageData
    }

    private func makeHarness() async throws -> Harness {
        let schema = Schema([AppSettings.self, VaultItem.self, Album.self, BreakInAttempt.self, DocumentReminder.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.insert(AppSettings())
        try context.save()

        let encryption = EncryptionService(keyStorage: InMemoryKeyStorage())
        let masterKey = await encryption.generateMasterKey()
        try await encryption.storeMasterKey(masterKey)

        let clock = TestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let cloud = CloudDeleteRecorder()
        let service = VaultService(
            encryptionService: encryption,
            modelContext: context,
            hasPremiumAccess: { true },
            deleteCloudRecord: { try cloud.record($0) },
            now: { clock.now },
            defaults: UserDefaults(suiteName: "RecentlyDeletedTests-\(UUID().uuidString)")!
        )
        return Harness(
            service: service,
            context: context,
            container: container,
            encryption: encryption,
            clock: clock,
            cloud: cloud
        )
    }

    private func makeImageData() throws -> Data {
        let size = CGSize(width: 8, height: 8)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else { throw TestError.failedToCreateImageData }
        return data
    }

    private func importPhoto(_ harness: Harness, album: Album? = nil, isDecoyMode: Bool = false) async throws -> VaultItem {
        try await harness.service.importPhotoData(
            try makeImageData(),
            filename: "photo.png",
            album: album,
            isDecoyMode: isDecoyMode
        )
    }

    private func fileURL(for item: VaultItem, in harness: Harness) async throws -> URL {
        try await harness.encryption.vaultFilesDirectory().appendingPathComponent(item.encryptedFileRelativePath)
    }

    private func allItems(in harness: Harness) throws -> [VaultItem] {
        try harness.context.fetch(FetchDescriptor<VaultItem>())
    }

    // MARK: - Soft Delete

    @Test("deleteItems moves items to Recently Deleted without removing data")
    func softDeleteKeepsDataAndHidesItem() async throws {
        let harness = try await makeHarness()
        let album = Album(name: "Trips")
        harness.context.insert(album)
        let item = try await importPhoto(harness, album: album)
        item.cloudRecordID = "record-1"
        let url = try await fileURL(for: item, in: harness)

        try harness.service.deleteItems([item])

        #expect(item.deletedAt == harness.clock.now)
        #expect(item.isTrashed)
        #expect(item.album === album)
        #expect(try allItems(in: harness).count == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(harness.service.getTotalItemCount() == 0)
        #expect(harness.service.getItemCount(isDecoyMode: false) == 0)
        #expect(album.liveItems.isEmpty)
        #expect(!item.isVisible(inDecoyMode: false))
        #expect(harness.service.trashedItems(isDecoyMode: false).map(\.id) == [item.id])
        #expect(harness.cloud.deletedRecordIDs.isEmpty, "Soft delete must keep the iCloud backup")

        try? FileManager.default.removeItem(at: url)
    }

    @Test("Deleting an already-trashed item keeps its original deletion date")
    func softDeleteIsIdempotent() async throws {
        let harness = try await makeHarness()
        let item = try await importPhoto(harness)
        try harness.service.deleteItems([item])
        let firstDeletedAt = item.deletedAt

        harness.clock.advance(days: 5)
        try harness.service.deleteItems([item])

        #expect(item.deletedAt == firstDeletedAt)
        try? FileManager.default.removeItem(at: try await fileURL(for: item, in: harness))
    }

    // MARK: - Restore

    @Test("restoreItems returns items to their album and the live vault")
    func restoreReturnsItemToVault() async throws {
        let harness = try await makeHarness()
        let album = Album(name: "Family")
        harness.context.insert(album)
        let item = try await importPhoto(harness, album: album)
        try harness.service.deleteItems([item])

        try await harness.service.restoreItems([item])

        #expect(item.deletedAt == nil)
        #expect(!item.deletedFromDecoy)
        #expect(item.album === album)
        #expect(item.isVisible(inDecoyMode: false))
        #expect(album.liveItems.map(\.id) == [item.id])
        #expect(harness.service.getTotalItemCount() == 1)
        #expect(harness.service.trashedItems().isEmpty)

        try? FileManager.default.removeItem(at: try await fileURL(for: item, in: harness))
    }

    // MARK: - Decoy Isolation

    @Test("Decoy bin only sees decoy items, even after their album is deleted")
    func decoyBinIsIsolated() async throws {
        let harness = try await makeHarness()
        let realItem = try await importPhoto(harness)
        let decoyItem = try await importPhoto(harness, isDecoyMode: true)
        let decoyAlbum = try #require(decoyItem.album)
        #expect(decoyAlbum.isDecoy)

        try harness.service.deleteItems([realItem, decoyItem])
        // "Delete Album and Contents" trashes the items, then deletes the album.
        harness.context.delete(decoyAlbum)
        try harness.context.save()

        #expect(decoyItem.album == nil)
        #expect(harness.service.trashedItems(isDecoyMode: true).map(\.id) == [decoyItem.id])
        #expect(harness.service.trashedItems(isDecoyMode: false).map(\.id) == [realItem.id])
        #expect(harness.service.getStorageUsed(isDecoyMode: true) == decoyItem.fileSize)

        try await harness.service.restoreItems([decoyItem])

        #expect(decoyItem.album?.isDecoy == true, "Restored decoy items must stay in the decoy vault")
        #expect(decoyItem.isVisible(inDecoyMode: true))
        #expect(!decoyItem.isVisible(inDecoyMode: false))

        for item in [realItem, decoyItem] {
            try? FileManager.default.removeItem(at: try await fileURL(for: item, in: harness))
        }
    }

    // MARK: - Purge

    @Test("Items are purged only after 30 days, removing file and iCloud record")
    func purgeRemovesExpiredItems() async throws {
        let harness = try await makeHarness()
        let expiring = try await importPhoto(harness)
        expiring.cloudRecordID = "record-expiring"
        let expiringURL = try await fileURL(for: expiring, in: harness)
        let expiringID = expiring.id
        try harness.service.deleteItems([expiring])

        harness.clock.advance(days: 10)
        let recent = try await importPhoto(harness)
        let recentURL = try await fileURL(for: recent, in: harness)
        try harness.service.deleteItems([recent])

        harness.clock.advance(days: 19.9)
        #expect(await harness.service.purgeExpiredItems() == 0)
        #expect(try allItems(in: harness).count == 2)

        harness.clock.advance(days: 0.2) // 30.1 days after the first delete
        #expect(await harness.service.purgeExpiredItems() == 1)

        let remaining = try allItems(in: harness)
        #expect(remaining.map(\.id) == [recent.id])
        #expect(!remaining.contains { $0.id == expiringID })
        #expect(!FileManager.default.fileExists(atPath: expiringURL.path))
        #expect(FileManager.default.fileExists(atPath: recentURL.path))
        #expect(harness.cloud.deletedRecordIDs == ["record-expiring"])

        try? FileManager.default.removeItem(at: recentURL)
    }

    @Test("Purge leaves live items alone regardless of age")
    func purgeIgnoresLiveItems() async throws {
        let harness = try await makeHarness()
        let item = try await importPhoto(harness)

        harness.clock.advance(days: 365)
        #expect(await harness.service.purgeExpiredItems() == 0)
        #expect(item.deletedAt == nil)
        #expect(harness.service.getTotalItemCount() == 1)

        try? FileManager.default.removeItem(at: try await fileURL(for: item, in: harness))
    }

    @Test("Days remaining counts down from 30")
    func daysUntilPurgeCountdown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let deletedAt = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(VaultItem.daysUntilPurge(deletedAt: deletedAt, now: deletedAt, calendar: calendar) == 30)
        #expect(VaultItem.daysUntilPurge(
            deletedAt: deletedAt,
            now: deletedAt.addingTimeInterval(29 * 86_400),
            calendar: calendar
        ) == 1)
        #expect(VaultItem.daysUntilPurge(
            deletedAt: deletedAt,
            now: deletedAt.addingTimeInterval(45 * 86_400),
            calendar: calendar
        ) == 0)
    }

    // MARK: - Permanent Delete

    @Test("Permanent delete removes the item, its file and its iCloud record")
    func permanentDeleteRemovesEverything() async throws {
        let harness = try await makeHarness()
        let item = try await importPhoto(harness)
        item.cloudRecordID = "record-permanent"
        let url = try await fileURL(for: item, in: harness)
        try harness.service.deleteItems([item])

        try await harness.service.permanentlyDeleteItems([item])

        #expect(try allItems(in: harness).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(harness.cloud.deletedRecordIDs == ["record-permanent"])
    }

    @Test("Offline permanent delete queues the iCloud delete and retries it later")
    func offlinePermanentDeleteIsRetried() async throws {
        let harness = try await makeHarness()
        let item = try await importPhoto(harness)
        item.cloudRecordID = "record-offline"
        try harness.service.deleteItems([item])

        harness.cloud.isOffline = true
        let waiting = try await harness.service.permanentlyDeleteItems([item])

        #expect(waiting == 1)
        #expect(try allItems(in: harness).isEmpty)
        #expect(harness.cloud.deletedRecordIDs.isEmpty)
        #expect(await harness.service.retryPendingCloudDeletions() == 1)

        harness.cloud.isOffline = false
        #expect(await harness.service.retryPendingCloudDeletions() == 0)
        #expect(harness.cloud.deletedRecordIDs == ["record-offline"])
        // Nothing left to retry
        #expect(await harness.service.retryPendingCloudDeletions() == 0)
        #expect(harness.cloud.deletedRecordIDs == ["record-offline"])
    }

    // MARK: - Search Exclusion

    @Test("Ask My Vault excludes trashed items from searchable results")
    func searchExcludesTrashedItems() async throws {
        let harness = try await makeHarness()
        let kept = try await importPhoto(harness)
        let trashed = try await importPhoto(harness)
        let decoy = try await importPhoto(harness, isDecoyMode: true)
        let trashedDecoy = try await importPhoto(harness, isDecoyMode: true)
        try harness.service.deleteItems([trashed, trashedDecoy])

        let all = try allItems(in: harness)
        let realSearchable = AskVaultViewModel.searchableItems(from: all, isDecoyMode: false)
        let decoySearchable = AskVaultViewModel.searchableItems(from: all, isDecoyMode: true)

        #expect(realSearchable.map(\.id) == [kept.id])
        #expect(decoySearchable.map(\.id) == [decoy.id])

        // Restoring makes the item searchable again without re-indexing.
        try await harness.service.restoreItems([trashed])
        let restoredSearchable = AskVaultViewModel.searchableItems(
            from: try allItems(in: harness),
            isDecoyMode: false
        )
        #expect(Set(restoredSearchable.map(\.id)) == [kept.id, trashed.id])

        for item in [kept, trashed, decoy, trashedDecoy] {
            try? FileManager.default.removeItem(at: try await fileURL(for: item, in: harness))
        }
    }
}
