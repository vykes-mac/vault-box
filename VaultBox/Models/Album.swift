import SwiftData
import Foundation

@Model
final class Album {
    @Attribute(.unique) var id: UUID
    var name: String
    var coverItem: VaultItem?
    @Relationship(deleteRule: .nullify, inverse: \VaultItem.album)
    var items: [VaultItem]?
    var sortOrder: Int
    var isLocked: Bool
    var albumPINHash: String?
    var isDecoy: Bool
    var createdAt: Date

    init(name: String, sortOrder: Int = 0, isDecoy: Bool = false) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isLocked = false
        self.isDecoy = isDecoy
        self.createdAt = Date()
    }
}
