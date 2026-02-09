import Foundation
import CloudKit

// MARK: - Upload Payload

struct CloudUploadPayload: Sendable {
    let itemID: UUID
    let encryptedFileRelativePath: String
    let itemType: String
    let originalFilename: String
    let fileSize: Int64
    let createdAt: Date
    let encryptedThumbnailData: Data?
}

// MARK: - CloudService

actor CloudService {
    private let container: CKContainer
    private let database: CKDatabase
    private let encryptionService: EncryptionService

    private(set) var uploadProgress: (completed: Int, total: Int) = (0, 0)

    init(encryptionService: EncryptionService) {
        self.container = CKContainer(identifier: "iCloud.com.vaultbox.app")
        self.database = container.privateCloudDatabase
        self.encryptionService = encryptionService
    }

    // MARK: - Upload

    func uploadItem(_ payload: CloudUploadPayload) async throws -> String {
        let fileURL = try await encryptionService.vaultFilesDirectory()
            .appendingPathComponent(payload.encryptedFileRelativePath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CloudError.fileNotFound
        }

        let record = CKRecord(recordType: Constants.cloudRecordType)
        record["itemID"] = payload.itemID.uuidString as CKRecordValue
        record["encryptedFile"] = CKAsset(fileURL: fileURL)
        record["itemType"] = payload.itemType as CKRecordValue
        record["originalFilename"] = payload.originalFilename as CKRecordValue
        record["fileSize"] = payload.fileSize as CKRecordValue
        record["createdAt"] = payload.createdAt as CKRecordValue

        if let thumbnailData = payload.encryptedThumbnailData {
            record["encryptedThumbnail"] = thumbnailData as CKRecordValue
        }

        let savedRecord = try await database.save(record)
        return savedRecord.recordID.recordName
    }

    // MARK: - Download

    func downloadItem(recordID: String) async throws -> Data {
        let ckRecordID = CKRecord.ID(recordName: recordID)
        let record = try await database.record(for: ckRecordID)

        guard let asset = record["encryptedFile"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudError.downloadFailed
        }

        return try Data(contentsOf: fileURL)
    }

    // MARK: - Delete

    func deleteItem(recordID: String) async throws {
        let ckRecordID = CKRecord.ID(recordName: recordID)
        try await database.deleteRecord(withID: ckRecordID)
    }

    // MARK: - Fetch All

    func fetchAllCloudRecords() async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: Constants.cloudRecordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        var allRecords: [CKRecord] = []
        let (results, _) = try await database.records(matching: query)

        for result in results {
            if case .success(let record) = result.1 {
                allRecords.append(record)
            }
        }

        return allRecords
    }

    // MARK: - Status

    func getICloudAccountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }

    func getUploadProgress() -> (completed: Int, total: Int) {
        uploadProgress
    }
}

// MARK: - Errors

enum CloudError: LocalizedError {
    case fileNotFound
    case downloadFailed
    case iCloudUnavailable
    case storageFull

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "The encrypted file could not be found on disk."
        case .downloadFailed:
            "Failed to download from iCloud. Please try again."
        case .iCloudUnavailable:
            "iCloud is not available. Check your Apple ID in Settings."
        case .storageFull:
            "Your iCloud storage is full. Backup paused."
        }
    }
}
