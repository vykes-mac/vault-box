import SwiftUI
import SwiftData

@MainActor
@Observable
class VaultViewModel {
    let vaultService: VaultService

    var isSelectionMode = false
    var selectedItems: Set<UUID> = []

    init(vaultService: VaultService) {
        self.vaultService = vaultService
    }

    func toggleSelection(_ itemID: UUID) {
        if selectedItems.contains(itemID) {
            selectedItems.remove(itemID)
        } else {
            selectedItems.insert(itemID)
        }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedItems.removeAll()
    }

    func deleteSelected(from items: [VaultItem]) async {
        let toDelete = items.filter { selectedItems.contains($0.id) }
        try? await vaultService.deleteItems(toDelete)
        exitSelectionMode()
    }

    func favoriteSelected(from items: [VaultItem]) async {
        let toFavorite = items.filter { selectedItems.contains($0.id) }
        for item in toFavorite {
            await vaultService.toggleFavorite(item)
        }
        exitSelectionMode()
    }

    func moveSelectedToAlbum(_ album: Album, from items: [VaultItem]) async {
        let toMove = items.filter { selectedItems.contains($0.id) }
        try? await vaultService.moveItems(toMove, to: album)
        exitSelectionMode()
    }
}
