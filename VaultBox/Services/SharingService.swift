import Foundation
import CloudKit
import CryptoKit
import os

// MARK: - ShareDuration

enum ShareDuration: CaseIterable, Identifiable {
    case oneMinute
    case fiveMinutes
    case thirtyMinutes
    case oneHour
    case twentyFourHours
    case sevenDays

    var id: String { label }

    var label: String {
        switch self {
        case .oneMinute: "1 Minute"
        case .fiveMinutes: "5 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .oneHour: "1 Hour"
        case .twentyFourHours: "24 Hours"
        case .sevenDays: "7 Days"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        case .twentyFourHours: 86400
        case .sevenDays: 604800
        }
    }
}

// MARK: - SharedFileResult

/// The result of receiving a shared file, including the decrypted data,
/// MIME type, original filename, and the sender's permission preferences.
struct SharedFileResult {
    let fileData: Data
    let mimeType: String
    let originalFilename: String
    let allowSave: Bool
}

// MARK: - SharingService

actor SharingService {
    private let container: CKContainer
    private let database: CKDatabase
    private let logger = Logger(subsystem: "com.vaultbox.app", category: "SharingService")

    init(containerIdentifier: String = "iCloud.com.vaultbox.app") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.publicCloudDatabase
    }

    // MARK: - Share a File

    /// Encrypts the file with a one-time key, uploads to CloudKit public DB,
    /// and returns the share URL containing the decryption key in the fragment.
    func shareFile(
        fileData: Data,
        duration: ShareDuration,
        allowSave: Bool = false,
        mimeType: String = "image/jpeg",
        originalFilename: String
    ) async throws -> (shareURL: String, cloudRecordName: String, expiresAt: Date) {
        // 1. Generate a one-time symmetric key
        let oneTimeKey = SymmetricKey(size: .bits256)

        // 2. Encrypt the file with the one-time key
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(fileData, using: oneTimeKey, nonce: nonce)
        guard let encryptedData = sealedBox.combined else {
            throw SharingError.encryptionFailed
        }

        // 3. Calculate expiry date
        let expiresAt = Date().addingTimeInterval(duration.seconds)

        // 4. Write encrypted data to a temporary file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).enc")
        try encryptedData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 5. Create CloudKit record
        let shareID = UUID().uuidString
        let recordID = CKRecord.ID(recordName: "share_\(shareID)")
        let record = CKRecord(recordType: Constants.sharedFileRecordType, recordID: recordID)
        record["shareID"] = shareID as CKRecordValue
        record["encryptedData"] = CKAsset(fileURL: tempURL)
        record["expiresAt"] = expiresAt as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["mimeType"] = mimeType as CKRecordValue
        record["originalFilename"] = originalFilename as CKRecordValue
        record["allowSave"] = (allowSave ? 1 : 0) as CKRecordValue

        // 6. Upload to CloudKit public database
        let savedRecord = try await database.save(record)
        let cloudRecordName = savedRecord.recordID.recordName

        // 7. Build the share URL with the key in the fragment
        let keyData = oneTimeKey.withUnsafeBytes { Data($0) }
        let keyBase64 = keyData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let shareURL = "\(Constants.shareURLScheme)://\(Constants.shareURLHost)/\(shareID)#\(keyBase64)"

        logger.info("Shared file with ID \(shareID), expires at \(expiresAt)")

        return (shareURL: shareURL, cloudRecordName: cloudRecordName, expiresAt: expiresAt)
    }

    // MARK: - Receive a Shared File

    /// Fetches and decrypts a shared file from a share URL.
    /// Returns the decrypted data, MIME type, filename, and sender permissions, or throws if expired/invalid.
    func receiveSharedFile(shareID: String, keyBase64URL: String) async throws -> SharedFileResult {
        // 1. Decode the key from base64url
        var keyBase64 = keyBase64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad with '=' to make valid base64
        let remainder = keyBase64.count % 4
        if remainder > 0 {
            keyBase64.append(contentsOf: String(repeating: "=", count: 4 - remainder))
        }
        guard let keyData = Data(base64Encoded: keyBase64) else {
            throw SharingError.invalidShareURL
        }
        let key = SymmetricKey(data: keyData)

        // 2. Fetch the record from CloudKit
        let recordID = CKRecord.ID(recordName: "share_\(shareID)")
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            throw SharingError.shareNotFound
        }

        // 3. Check expiry
        guard let expiresAt = record["expiresAt"] as? Date else {
            throw SharingError.shareNotFound
        }
        if Date() > expiresAt {
            // Clean up the expired record
            _ = try? await database.deleteRecord(withID: recordID)
            throw SharingError.shareExpired
        }

        // 4. Download the encrypted data
        guard let asset = record["encryptedData"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw SharingError.downloadFailed
        }
        let encryptedData = try Data(contentsOf: fileURL)

        // 5. Decrypt with the one-time key
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        // 6. Read sender permissions and metadata
        let allowSave = (record["allowSave"] as? Int ?? 0) == 1
        let mimeType = record["mimeType"] as? String ?? "application/octet-stream"
        let originalFilename = record["originalFilename"] as? String ?? "Shared File"

        logger.info("Received shared file \(shareID)")
        return SharedFileResult(
            fileData: decryptedData,
            mimeType: mimeType,
            originalFilename: originalFilename,
            allowSave: allowSave
        )
    }

    // MARK: - Revoke a Share

    /// Immediately deletes a shared file from CloudKit, making the link dead.
    func revokeShare(cloudRecordName: String) async throws {
        let recordID = CKRecord.ID(recordName: cloudRecordName)
        try await database.deleteRecord(withID: recordID)
        logger.info("Revoked share \(cloudRecordName)")
    }

    // MARK: - Cleanup Expired Shares

    /// Queries for expired SharedFile records and deletes them.
    /// Call on app launch and during background refresh.
    func cleanupExpiredShares() async {
        do {
            let predicate = NSPredicate(format: "expiresAt < %@", Date() as NSDate)
            let query = CKQuery(recordType: Constants.sharedFileRecordType, predicate: predicate)

            let (results, _) = try await database.records(matching: query)
            var deletedCount = 0

            for (recordID, result) in results {
                if case .success = result {
                    if let _ = try? await database.deleteRecord(withID: recordID) {
                        deletedCount += 1
                    }
                }
            }

            if deletedCount > 0 {
                logger.info("Cleaned up \(deletedCount) expired shared files")
            }
        } catch {
            logger.error("Expired share cleanup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Parse Share URL

    /// Parses a vaultbox://shared/{shareID}#{keyBase64URL} URL into components.
    static func parseShareURL(_ url: URL) -> (shareID: String, keyBase64URL: String)? {
        guard url.scheme == Constants.shareURLScheme,
              url.host == Constants.shareURLHost else {
            return nil
        }

        // Path is /{shareID}
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let shareID = pathComponents.first, !shareID.isEmpty else {
            return nil
        }

        // Fragment is the base64url-encoded key
        guard let fragment = url.fragment, !fragment.isEmpty else {
            return nil
        }

        return (shareID: shareID, keyBase64URL: fragment)
    }

    // MARK: - iCloud Account Check

    func isICloudAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}

// MARK: - SharingError

enum SharingError: LocalizedError {
    case encryptionFailed
    case invalidShareURL
    case shareNotFound
    case shareExpired
    case downloadFailed
    case iCloudUnavailable

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            "Failed to encrypt the file for sharing."
        case .invalidShareURL:
            "This share link is invalid or corrupted."
        case .shareNotFound:
            "This shared file could not be found. It may have been revoked."
        case .shareExpired:
            "This share has expired and is no longer available."
        case .downloadFailed:
            "Failed to download the shared file. Please check your connection."
        case .iCloudUnavailable:
            "iCloud is not available. Sign in to iCloud to share files."
        }
    }
}
