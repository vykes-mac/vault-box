import SwiftData
import Foundation

/// Tracks an active time-limited share created by this user.
/// Stored locally to display in the "Shared Items" list and manage cleanup.
@Model
final class SharedItem {
    var id: UUID = UUID()
    /// The CloudKit record name for the SharedFile record in the public database.
    var cloudRecordName: String = ""
    /// The UUID of the VaultItem that was shared.
    var vaultItemID: UUID = UUID()
    /// The full share URL including the decryption key fragment.
    var shareURL: String = ""
    /// When this share expires.
    var expiresAt: Date = Date()
    /// When the share was created.
    var createdAt: Date = Date()
    /// Original filename for display.
    var originalFilename: String = ""
    /// Whether this share has been revoked early (manually by the user).
    var isRevoked: Bool = false

    init(
        cloudRecordName: String,
        vaultItemID: UUID,
        shareURL: String,
        expiresAt: Date,
        originalFilename: String
    ) {
        self.id = UUID()
        self.cloudRecordName = cloudRecordName
        self.vaultItemID = vaultItemID
        self.shareURL = shareURL
        self.expiresAt = expiresAt
        self.createdAt = Date()
        self.originalFilename = originalFilename
        self.isRevoked = false
    }

    var isExpired: Bool {
        Date() > expiresAt || isRevoked
    }

    var remainingTime: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
}
