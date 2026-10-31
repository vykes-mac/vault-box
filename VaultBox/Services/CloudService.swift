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

// MARK: - Key Backup

struct KeyBackup: Sendable {
    let wrappedKey: Data
    let salt: Data
    let formatVersion: Int
    /// Absent on format 1 backups.
    let keyFingerprint: Data?
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
        let encryptedName = try await encryptedFilename(payload.originalFilename)
        record["encryptedFilename"] = encryptedName as CKRecordValue
        record["fileSize"] = payload.fileSize as CKRecordValue
        record["createdAt"] = payload.createdAt as CKRecordValue

        if let thumbnailData = payload.encryptedThumbnailData {
            record["encryptedThumbnail"] = thumbnailData as CKRecordValue
        }

        do {
            let savedRecord = try await database.save(record)
            return savedRecord.recordID.recordName
        } catch let error as CKError where error.code == .quotaExceeded {
            throw CloudError.storageFull
        }
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

    /// Uploads from older versions stored filenames in plain text. Encrypts them
    /// in place and clears the plain-text field.
    func encryptLegacyFilenames() async throws {
        let query = CKQuery(recordType: Constants.cloudRecordType, predicate: NSPredicate(value: true))
        let desiredKeys = ["originalFilename"]
        var page = try await database.records(matching: query, desiredKeys: desiredKeys, resultsLimit: 200)

        while true {
            var updated: [CKRecord] = []
            for (_, result) in page.matchResults {
                guard let record = try? result.get(),
                      let filename = record["originalFilename"] as? String else { continue }
                let encryptedName = try await encryptedFilename(filename)
                record["encryptedFilename"] = encryptedName as CKRecordValue
                record["originalFilename"] = nil
                updated.append(record)
            }

            if !updated.isEmpty {
                let (saveResults, _) = try await database.modifyRecords(
                    saving: updated,
                    deleting: [],
                    savePolicy: .changedKeys
                )
                for (_, result) in saveResults {
                    _ = try result.get()
                }
            }

            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys, resultsLimit: 200)
        }
    }

    private func encryptedFilename(_ filename: String) async throws -> Data {
        try await encryptionService.encryptData(Data(filename.utf8))
    }

    /// Returns just the count of backed-up records without downloading them.
    func countCloudRecords() async throws -> Int {
        let records = try await fetchAllCloudRecords()
        return records.count
    }

    // MARK: - Key Backup

    /// Well-known record ID for the single key backup record per user.
    private static let keyBackupRecordID = CKRecord.ID(recordName: "MasterKeyBackup")

    /// Uploads a wrapped master key (see `EncryptionService.exportWrappedMasterKey`)
    /// to CloudKit for restore on new devices.
    /// Uses a fixed record ID so repeated calls overwrite the previous backup.
    func uploadKeyBackup(wrappedKey: Data, salt: Data, keyFingerprint: Data) async throws {
        let record = CKRecord(
            recordType: Constants.cloudKeyBackupRecordType,
            recordID: Self.keyBackupRecordID
        )
        record["wrappedMasterKey"] = wrappedKey as CKRecordValue
        record["keySalt"] = salt as CKRecordValue
        record["formatVersion"] = Constants.keyBackupFormatVersion as CKRecordValue
        record["keyFingerprint"] = keyFingerprint as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        do {
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
        } catch let error as CKError where error.code == .quotaExceeded {
            throw CloudError.storageFull
        }
    }

    /// Fetches the wrapped master key from CloudKit. Returns nil only when no
    /// backup exists; network and account errors are thrown.
    func fetchKeyBackup() async throws -> KeyBackup? {
        let record: CKRecord
        do {
            record = try await database.record(for: Self.keyBackupRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }

        guard let wrappedKey = record["wrappedMasterKey"] as? Data,
              let salt = record["keySalt"] as? Data else {
            return nil
        }

        return KeyBackup(
            wrappedKey: wrappedKey,
            salt: salt,
            formatVersion: record["formatVersion"] as? Int ?? 1,
            keyFingerprint: record["keyFingerprint"] as? Data
        )
    }

    /// Brings the iCloud backup up to date for the PIN the user just unlocked
    /// with: re-wraps a format 1 (PIN-only) backup or one made before a PIN
    /// change, and encrypts any plain-text filenames left by older versions.
    /// Only touches a backup of this device's vault key, so a fresh install
    /// can never overwrite the backup it still needs to restore from.
    func upgradeBackupIfNeeded(pin: String) async throws -> KeyBackupUpgradeResult {
        guard let backup = try await fetchKeyBackup() else { return .noBackup }

        let localFingerprint = try await encryptionService.masterKeyFingerprint()
        let cloudKey = try? await encryptionService.unwrapMasterKey(
            backup.wrappedKey,
            pin: pin,
            salt: backup.salt,
            formatVersion: backup.formatVersion
        )
        // Format 1 backups carry no fingerprint: they belong to this vault if this
        // PIN opens them to this device's key, or (after a PIN change) if this
        // device's key decrypts the backed-up items.
        let isThisVault: Bool
        if let cloudFingerprint = backup.keyFingerprint ?? cloudKey.map(EncryptionService.fingerprint(of:)) {
            isThisVault = cloudFingerprint == localFingerprint
        } else {
            isThisVault = try await backedUpItemsUseLocalKey()
        }
        guard isThisVault else { return .differentVault }

        if backup.formatVersion < Constants.keyBackupFormatVersion || cloudKey == nil {
            let salt = await encryptionService.generateSalt()
            let wrappedKey = try await encryptionService.exportWrappedMasterKey(pin: pin, salt: salt)
            try await uploadKeyBackup(wrappedKey: wrappedKey, salt: salt, keyFingerprint: localFingerprint)
        }

        try await encryptLegacyFilenames()
        return .upToDate
    }

    /// True when this device's key decrypts every sampled backed-up thumbnail, or
    /// when there are no backed-up items to lose. All must open, because an account
    /// can hold items from an earlier install under a different key.
    private func backedUpItemsUseLocalKey() async throws -> Bool {
        let query = CKQuery(recordType: Constants.cloudRecordType, predicate: NSPredicate(value: true))
        let page = try await database.records(matching: query, desiredKeys: ["encryptedThumbnail"], resultsLimit: 200)
        let records = page.matchResults.compactMap { try? $0.1.get() }
        guard !records.isEmpty else { return true }

        let thumbnails = records.compactMap { $0["encryptedThumbnail"] as? Data }
        guard !thumbnails.isEmpty else { return false }
        for thumbnail in thumbnails where await !encryptionService.canDecrypt(thumbnail) {
            return false
        }
        return true
    }

    /// Whether the existing key backup can restore items this device uploads. Uploading
    /// when it can't would create backups that nothing can open.
    func keyBackupMatchesThisVault() async throws -> Bool {
        guard let backup = try await fetchKeyBackup() else { return true }
        if let cloudFingerprint = backup.keyFingerprint {
            return cloudFingerprint == (try await encryptionService.masterKeyFingerprint())
        }
        return try await backedUpItemsUseLocalKey()
    }

    /// How many backed-up items this device's key can't open, for the warning shown
    /// before the backup is replaced.
    func unreadableBackupItemCount() async throws -> Int {
        try await unreadableBackupItemIDs().count
    }

    /// Makes this vault the owner of the iCloud backup: deletes the items its key can't
    /// open, then replaces the key backup. The key goes last, so a failure part way
    /// leaves a state the same action can finish. Returns the deleted record names.
    func replaceBackup(wrappedKey: Data, salt: Data, keyFingerprint: Data) async throws -> [String] {
        let unreadableIDs = try await unreadableBackupItemIDs()
        try await deleteRecords(unreadableIDs)
        try await uploadKeyBackup(wrappedKey: wrappedKey, salt: salt, keyFingerprint: keyFingerprint)
        return unreadableIDs.map(\.recordName)
    }

    /// Deletes every backed-up item and the key backup from iCloud. The key goes last,
    /// so if this fails part way, nothing left behind has lost its key and it can run again.
    func deleteEntireBackup() async throws {
        let query = CKQuery(recordType: Constants.cloudRecordType, predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, desiredKeys: [], resultsLimit: 200)
        var recordIDs: [CKRecord.ID] = []
        while true {
            recordIDs.append(contentsOf: page.matchResults.map(\.0))
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: [], resultsLimit: 200)
        }

        try await deleteRecords(recordIDs)
        try await deleteRecords([Self.keyBackupRecordID])
    }

    private static let maxRecordsPerDelete = 400

    private func deleteRecords(_ recordIDs: [CKRecord.ID]) async throws {
        var startIndex = 0
        while startIndex < recordIDs.count {
            let endIndex = min(startIndex + Self.maxRecordsPerDelete, recordIDs.count)
            let (_, deleteResults) = try await database.modifyRecords(
                saving: [],
                deleting: Array(recordIDs[startIndex..<endIndex])
            )
            for (_, result) in deleteResults {
                do {
                    try result.get()
                } catch let error as CKError where error.code == .unknownItem {
                    continue
                }
            }
            startIndex = endIndex
        }
    }

    private func unreadableBackupItemIDs() async throws -> [CKRecord.ID] {
        let query = CKQuery(recordType: Constants.cloudRecordType, predicate: NSPredicate(value: true))
        let desiredKeys = ["encryptedThumbnail"]
        var page = try await database.records(matching: query, desiredKeys: desiredKeys, resultsLimit: 200)
        var unreadableIDs: [CKRecord.ID] = []

        while true {
            for (recordID, result) in page.matchResults {
                let record = try result.get()
                let isReadable: Bool
                if let thumbnail = record["encryptedThumbnail"] as? Data {
                    isReadable = await encryptionService.canDecrypt(thumbnail)
                } else {
                    let file = try await downloadItem(recordID: recordID.recordName)
                    isReadable = await encryptionService.canDecrypt(file)
                }
                if !isReadable {
                    unreadableIDs.append(recordID)
                }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys, resultsLimit: 200)
        }
        return unreadableIDs
    }

    /// Replacing the device's key leaves anything already encrypted with it unreadable,
    /// so a backup with a different key can't be restored over existing items.
    nonisolated static func keyImportWouldOrphanItems(
        localFingerprint: Data?,
        backupFingerprint: Data,
        localItemCount: Int
    ) -> Bool {
        guard let localFingerprint else { return false }
        return localFingerprint != backupFingerprint && localItemCount > 0
    }

    /// Value stored once `upgradeBackupIfNeeded` returns `.upToDate`, so the check
    /// runs once per PIN and backup format instead of on every unlock. The suffix
    /// ignores older markers, which could be saved without an upgrade having run.
    nonisolated static func keyBackupMarker(pinSalt: String) -> String {
        "\(pinSalt)#\(Constants.keyBackupFormatVersion)#upgraded"
    }

    /// True for failures that clear up by themselves, such as being offline.
    /// These retry on the next PIN unlock without warning the user.
    nonisolated static func isTransientUpgradeFailure(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        switch cloudError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable:
            return true
        default:
            return false
        }
    }

    /// Checks whether a key backup exists in iCloud. Network and account errors are
    /// thrown, so an outage is never mistaken for there being no backup.
    func keyBackupExists() async throws -> Bool {
        do {
            _ = try await database.record(for: Self.keyBackupRecordID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
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

enum KeyBackupUpgradeResult: Sendable {
    /// The backup belongs to this vault and is on the current format.
    case upToDate
    /// This iCloud environment has no key backup yet.
    case noBackup
    /// The backup belongs to another vault, so it was left alone.
    case differentVault

    /// Only a finished upgrade stops the check. The other results can change,
    /// for example after a restore or when a build moves to another CloudKit environment.
    var finishesCheck: Bool {
        self == .upToDate
    }
}

enum CloudError: LocalizedError {
    case fileNotFound
    case downloadFailed
    case iCloudUnavailable
    case storageFull
    case keyBackupNotFound
    case keyDecryptionFailed
    case backupFromDifferentVault
    case restoreWouldOrphanItems

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            String(localized: "The encrypted file could not be found on disk.")
        case .downloadFailed:
            String(localized: "Failed to download from iCloud. Please try again.")
        case .iCloudUnavailable:
            String(localized: "iCloud is not available. Check your Apple ID in Settings.")
        case .storageFull:
            String(localized: "Your iCloud storage is full. Backup paused.")
        case .keyBackupNotFound:
            String(localized: "No encryption key backup found in iCloud. Back up your vault first.")
        case .keyDecryptionFailed:
            String(localized: "Incorrect PIN. Could not decrypt your backup encryption key.")
        case .backupFromDifferentVault:
            String(localized: "Your iCloud backup was made with a different encryption key, usually from before the app was reinstalled. New items can't be restored with that key, so they weren't uploaded.")
        case .restoreWouldOrphanItems:
            String(localized: "This iCloud backup uses a different encryption key from the items on this device. Restoring it would make those items unreadable, so nothing was changed.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storageFull:
            String(localized: "Manage your iCloud storage in Settings.")
        default:
            nil
        }
    }
}
