import SwiftData
import Foundation

@Model
final class VaultItem {
    @Attribute(.unique) var id: UUID
    var type: ItemType
    var originalFilename: String
    var encryptedFileRelativePath: String
    var encryptedThumbnailData: Data?
    var album: Album?
    var fileSize: Int64
    var durationSeconds: Double?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var createdAt: Date
    var importedAt: Date
    var isFavorite: Bool
    var isUploaded: Bool
    var cloudRecordID: String?

    enum ItemType: String, Codable {
        case photo
        case video
        case document
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
