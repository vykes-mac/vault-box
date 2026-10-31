import SwiftData
import Foundation

@Model
final class VaultItem {
    var id: UUID = UUID()
    var type: ItemType = VaultItem.ItemType.photo
    var originalFilename: String = ""
    var encryptedFileRelativePath: String = ""
    var encryptedThumbnailData: Data?
    var album: Album?
    var coverForAlbum: Album?
    var fileSize: Int64 = 0
    var durationSeconds: Double?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var createdAt: Date = Date()
    var importedAt: Date = Date()
    var isFavorite: Bool = false
    var isUploaded: Bool = false
    var cloudRecordID: String?
    var smartTags: [String] = []
    var extractedText: String?
    var isIndexed: Bool = false
    var indexingFailed: Bool = false
    var extractedTextPreview: String?
    var totalPages: Int?
    var chunkCount: Int = 0
    /// When the item was moved to Recently Deleted; `nil` while it is live in the vault.
    var deletedAt: Date?
    /// Whether the item belonged to the decoy vault when it was trashed. Kept separately
    /// because the album link can be lost (e.g. "Delete Album and Contents") while the
    /// item waits in the bin, and the decoy bin must never show real-vault items.
    var deletedFromDecoy: Bool = false

    enum ItemType: String, Codable {
        case photo
        case video
        case document

        var displayName: String {
            switch self {
            case .photo: String(localized: "Photo")
            case .video: String(localized: "Video")
            case .document: String(localized: "Document")
            }
        }
    }

    init(type: ItemType, originalFilename: String, encryptedFileRelativePath: String, fileSize: Int64) {
        self.id = UUID()
        self.type = type
        self.originalFilename = originalFilename
        self.encryptedFileRelativePath = encryptedFileRelativePath
        self.fileSize = fileSize
        self.createdAt = Date()
        self.importedAt = Date()
        self.isFavorite = false
        self.isUploaded = false
    }
}

// MARK: - Targeted Fetches

/// For screens that need facts about the whole vault. Items store their thumbnails
/// inline, so these avoid loading full records. Screens opened with
/// `navigationDestination(isPresented:)` must use these rather than a filtered `@Query`,
/// which makes SwiftUI rebuild the screen and its parent endlessly.
extension VaultItem {
    static func liveItemCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))
    }

    static func uploadedLiveItemCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isUploaded == true }
        ))
    }

    /// The next live items waiting to upload, newest first. Fetched in small batches
    /// so a large backup doesn't hold every thumbnail in memory.
    static func pendingUploads(limit: Int, in context: ModelContext) throws -> [VaultItem] {
        var descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.deletedAt == nil && $0.isUploaded == false },
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    static func trashedItemIDs(in context: ModelContext) throws -> Set<UUID> {
        var descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.deletedAt != nil }
        )
        descriptor.propertiesToFetch = [\.id]
        return Set(try context.fetch(descriptor).map(\.id))
    }
}

// MARK: - Recently Deleted

extension VaultItem {
    var isTrashed: Bool { deletedAt != nil }

    /// Which vault the item belongs to. Trashed items keep the side they were deleted from.
    var isInDecoyVault: Bool {
        isTrashed ? deletedFromDecoy : album?.isDecoy == true
    }

    /// Live (not trashed) and part of the vault that is currently unlocked.
    func isVisible(inDecoyMode isDecoyMode: Bool) -> Bool {
        !isTrashed && isInDecoyVault == isDecoyMode
    }

    /// In the Recently Deleted bin of the vault that is currently unlocked.
    func isInRecentlyDeleted(inDecoyMode isDecoyMode: Bool) -> Bool {
        isTrashed && isInDecoyVault == isDecoyMode
    }

    /// The moment an item trashed at `deletedAt` becomes eligible for permanent deletion.
    static func purgeDate(forDeletedAt deletedAt: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: Constants.recentlyDeletedRetentionDays, to: deletedAt)
            ?? deletedAt.addingTimeInterval(TimeInterval(Constants.recentlyDeletedRetentionDays) * 86_400)
    }

    /// Whole days left before purge, as shown on each Recently Deleted thumbnail.
    static func daysUntilPurge(deletedAt: Date, now: Date, calendar: Calendar = .current) -> Int {
        let purge = purgeDate(forDeletedAt: deletedAt, calendar: calendar)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: purge)
        ).day ?? 0
        return max(0, days)
    }
}

extension Album {
    /// Album contents excluding items waiting in Recently Deleted.
    var liveItems: [VaultItem] {
        (items ?? []).filter { !$0.isTrashed }
    }
}
