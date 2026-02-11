import SwiftUI
import PhotosUI

@MainActor
@Observable
class ImportViewModel {
    let vaultService: VaultService

    var selectedItems: [PhotosPickerItem] = []
    var isImporting = false
    var importProgress: Int = 0
    var importTotal: Int = 0
    var showDeletePrompt = false
    var pendingAssetIdentifiers: [String] = []
    var showDeleteError = false
    var deleteErrorMessage = "VaultBox couldn't delete one or more originals. Your imported items are still safe in the vault."

    init(vaultService: VaultService) {
        self.vaultService = vaultService
    }

    func startImport(album: Album?, onComplete: @escaping () -> Void) {
        isImporting = true
        importTotal = selectedItems.count
        importProgress = 0

        Task { @MainActor in
            var identifiers: [String] = []

            for (index, pickerItem) in selectedItems.enumerated() {
                var didImport = false

                do {
                    // Prefer image bytes first so Live Photos import as photos (eligible for vision tags).
                    if let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                        _ = try await vaultService.importPhotoData(imageData, filename: nil, album: album)
                        didImport = true
                    } else if let movie = try await pickerItem.loadTransferable(type: VideoTransferable.self) {
                        let item = try await vaultService.importDocument(at: movie.url, album: album)
                        item.type = .video
                        didImport = true
                    }
                } catch {
                    // Skip failed items
                }

                if didImport, let itemIdentifier = pickerItem.itemIdentifier {
                    identifiers.append(itemIdentifier)
                }

                importProgress = index + 1
            }

            isImporting = false

            if !identifiers.isEmpty {
                pendingAssetIdentifiers = identifiers
                showDeletePrompt = true
            } else {
                onComplete()
            }
        }
    }

    func deleteCameraRollOriginals(onComplete: @escaping () -> Void) {
        guard !pendingAssetIdentifiers.isEmpty else {
            onComplete()
            return
        }

        Task { @MainActor in
            do {
                try await vaultService.deleteFromCameraRoll(localIdentifiers: pendingAssetIdentifiers)
                onComplete()
            } catch {
                deleteErrorMessage = (error as? LocalizedError)?.errorDescription ??
                    "VaultBox couldn't delete one or more originals. You can remove them manually in Photos."
                showDeleteError = true
            }
        }
    }
}
