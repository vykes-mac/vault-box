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
    private(set) var downloadProgress: (completed: Int, total: Int) = (0, 0)

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

    /// Fetches all backed-up vault item records from CloudKit with cursor-based pagination.
    func fetchAllCloudRecords() async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: Constants.cloudRecordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        var allRecords: [CKRecord] = []

        // First page
        let (firstResults, firstCursor) = try await database.records(matching: query, resultsLimit: 200)
        for result in firstResults {
            if case .success(let record) = result.1 {
                allRecords.append(record)
            }
        }

        // Continue fetching with cursor if there are more pages
        var cursor = firstCursor
        while let currentCursor = cursor {
            let (nextResults, nextCursor) = try await database.records(
                continuingMatchFrom: currentCursor,
                resultsLimit: 200
            )
            for result in nextResults {
                if case .success(let record) = result.1 {
                    allRecords.append(record)
                }
            }
            cursor = nextCursor
        }

        return allRecords
    }

    /// Returns just the count of backed-up records without downloading them.
    func countCloudRecords() async throws -> Int {
        let records = try await fetchAllCloudRecords()
        return records.count
    }

    // MARK: - Key Backup

    /// Well-known record ID for the single key backup record per user.
    private static let keyBackupRecordID = CKRecord.ID(recordName: "MasterKeyBackup")

    /// Uploads a PIN-wrapped master key to CloudKit for restore on new devices.
    /// Uses a fixed record ID so repeated calls overwrite the previous backup.
    func uploadKeyBackup(wrappedKey: Data, salt: Data) async throws {
        let record = CKRecord(
            recordType: Constants.cloudKeyBackupRecordType,
            recordID: Self.keyBackupRecordID
        )
        record["wrappedMasterKey"] = wrappedKey as CKRecordValue
        record["keySalt"] = salt as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        // Use changedKeys save policy so re-uploads overwrite the existing record.
        let (saveResults, _) = try await database.modifyRecords(
            saving: [record],
            deleting: [],
            savePolicy: .changedKeys
        )
        // Surface any per-record error
        for (_, result) in saveResults {
            let _ = try result.get()
        }
    }

    /// Fetches the PIN-wrapped master key from CloudKit.
    func fetchKeyBackup() async throws -> (wrappedKey: Data, salt: Data)? {
        guard let record = try? await database.record(for: Self.keyBackupRecordID) else {
            return nil
        }

        guard let wrappedKey = record["wrappedMasterKey"] as? Data,
              let salt = record["keySalt"] as? Data else {
            return nil
        }

        return (wrappedKey: wrappedKey, salt: salt)
    }

    /// Checks whether a key backup exists in iCloud without downloading it.
    func hasKeyBackup() async -> Bool {
        (try? await database.record(for: Self.keyBackupRecordID)) != nil
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

    func getDownloadProgress() -> (completed: Int, total: Int) {
        downloadProgress
    }

    func setDownloadProgress(completed: Int, total: Int) {
        downloadProgress = (completed, total)
    }

    func resetDownloadProgress() {
        downloadProgress = (0, 0)
    }
}

// MARK: - Errors

enum CloudError: LocalizedError {
    case fileNotFound
    case downloadFailed
    case iCloudUnavailable
    case storageFull
    case keyBackupNotFound
    case keyDecryptionFailed

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
        case .keyBackupNotFound:
            "No encryption key backup found in iCloud. Back up your vault first."
        case .keyDecryptionFailed:
            "Incorrect PIN. Could not decrypt your backup encryption key."
        }
    }
}
