import SwiftData
import Foundation

@Model
final class Album {
    var id: UUID = UUID()
    var name: String = ""
    @Relationship(deleteRule: .nullify, inverse: \VaultItem.coverForAlbum)
    var coverItem: VaultItem?
    @Relationship(deleteRule: .nullify, inverse: \VaultItem.album)
    var items: [VaultItem]?
    var sortOrder: Int = 0
    var isLocked: Bool = false
    var albumPINHash: String?
    var isDecoy: Bool = false
    var createdAt: Date = Date()
    /// Encrypted thumbnail-sized JPEG for a custom album cover (premium feature).
    /// When set, takes priority over coverItem and first-item fallback.
    var customCoverImageData: Data?

    init(name: String, sortOrder: Int = 0, isDecoy: Bool = false) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isLocked = false
        self.isDecoy = isDecoy
        self.createdAt = Date()
    }
}
