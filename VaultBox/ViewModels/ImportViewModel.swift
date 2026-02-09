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

    init(vaultService: VaultService) {
        self.vaultService = vaultService
    }

    func startImport(album: Album?, onComplete: @escaping () -> Void) {
        isImporting = true
        importTotal = selectedItems.count
        importProgress = 0

        Task {
            var identifiers: [String] = []

            for (index, pickerItem) in selectedItems.enumerated() {
                do {
                    if let movie = try await pickerItem.loadTransferable(type: VideoTransferable.self) {
                        let item = try await vaultService.importDocument(at: movie.url, album: album)
                        item.type = .video
                    } else if let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                        let image = UIImage(data: imageData)
                        let pixelWidth = image.map { Int($0.size.width * $0.scale) }
                        let pixelHeight = image.map { Int($0.size.height * $0.scale) }

                        if let uiImage = image {
                            let item = try await vaultService.importFromCamera(uiImage, album: album)
                            item.pixelWidth = pixelWidth
                            item.pixelHeight = pixelHeight
                        }
                    }
                } catch {
                    // Skip failed items
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
        Task {
            try? await vaultService.deleteFromCameraRoll(localIdentifiers: pendingAssetIdentifiers)
            onComplete()
        }
    }
}
