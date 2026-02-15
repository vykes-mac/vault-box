import SwiftUI
import SwiftData

@MainActor
@Observable
class AlbumViewModel {
    let vaultService: VaultService

    var showCreateAlert = false
    var newAlbumName = ""
    var albumToRename: Album?
    var renameText = ""
    var albumToDelete: Album?
    var coverCache: [UUID: UIImage] = [:]

    init(vaultService: VaultService) {
        self.vaultService = vaultService
    }

    func createAlbum(existingCount: Int, modelContext: ModelContext) {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let album = Album(name: name, sortOrder: existingCount)
        modelContext.insert(album)
        try? modelContext.save()
    }

    func renameAlbum() {
        guard let album = albumToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        album.name = name
        albumToRename = nil
    }

    func deleteAlbum(deleteContents: Bool, modelContext: ModelContext) {
        guard let album = albumToDelete else { return }
        if deleteContents {
            if let items = album.items {
                Task {
                    try? await vaultService.deleteItems(items)
                }
            }
        } else {
            if let items = album.items {
                for item in items {
                    item.album = nil
                }
            }
        }
        modelContext.delete(album)
        try? modelContext.save()
        albumToDelete = nil
    }

    func loadCover(for albumID: UUID, albums: [Album]) async {
        guard coverCache[albumID] == nil else { return }
        guard let album = albums.first(where: { $0.id == albumID }) else { return }

        // Priority: custom cover image > explicit cover item > first item in album
        if let customData = album.customCoverImageData,
           let image = try? await vaultService.decryptAlbumCoverImage(customData) {
            coverCache[albumID] = image
            return
        }

        let coverSource = album.coverItem ?? album.items?.first
        guard let source = coverSource else { return }
        guard let image = try? await vaultService.decryptThumbnail(for: source) else { return }
        coverCache[albumID] = image
    }

    func invalidateCover(for albumID: UUID) {
        coverCache[albumID] = nil
    }
}
