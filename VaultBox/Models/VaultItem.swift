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
