import Foundation
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import SwiftData
import UIKit
import Photos

// MARK: - Errors

enum VaultError: LocalizedError {
    case importFailed
    case itemNotFound
    case thumbnailNotFound
    case freeLimitReached
    case fileNotFound
    case photosPermissionDenied

    var errorDescription: String? {
        switch self {
        case .importFailed:
            "Failed to import the selected item. Please try again."
        case .itemNotFound:
            "The requested item could not be found."
        case .thumbnailNotFound:
            "No thumbnail available for this item."
        case .freeLimitReached:
            "You've reached the free item limit. Upgrade to Premium for unlimited storage."
        case .fileNotFound:
            "The encrypted file could not be found on disk."
        case .photosPermissionDenied:
            "VaultBox needs Photos access to delete originals. Allow Photos access in Settings."
        }
    }
}

// MARK: - VaultService

@MainActor
@Observable
class VaultService {
    private let encryptionService: EncryptionService
    private let modelContext: ModelContext

    init(encryptionService: EncryptionService, modelContext: ModelContext) {
        self.encryptionService = encryptionService
        self.modelContext = modelContext
    }

    // MARK: - Import Result

    struct ImportResult {
        let items: [VaultItem]
        let assetIdentifiers: [String]
    }

    // MARK: - Import from PHPicker

    func importPhotos(from results: [PHPickerResult], album: Album?, progress: ((Int, Int) -> Void)? = nil) async throws -> ImportResult {
        var importedItems: [VaultItem] = []
        var assetIdentifiers: [String] = []

        for (index, result) in results.enumerated() {
            let provider = result.itemProvider

            var didImport = false
            do {
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    let item = try await importVideo(from: provider, album: album)
                    importedItems.append(item)
                    didImport = true
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let item = try await importImage(from: provider, album: album)
                    importedItems.append(item)
                    didImport = true
                }
            } catch {
                // Skip failed items and continue importing the remainder.
            }

            if didImport, let assetID = result.assetIdentifier {
                assetIdentifiers.append(assetID)
            }

            progress?(index + 1, results.count)
        }

        return ImportResult(items: importedItems, assetIdentifiers: assetIdentifiers)
    }

    private func importImage(from provider: NSItemProvider, album: Album?) async throws -> VaultItem {
        let imageData = try await loadImageData(from: provider)
        let filename = provider.suggestedName ?? "Untitled"

        let image = UIImage(data: imageData)
        let pixelWidth = image.map { Int($0.size.width * $0.scale) }
        let pixelHeight = image.map { Int($0.size.height * $0.scale) }

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileID = UUID()
        let relativePath = "\(fileID).\(Constants.encryptedFileExtension)"
        let fileURL = vaultDir.appendingPathComponent(relativePath)

        let encryptedData = try await encryptionService.encryptData(imageData)
        try encryptedData.write(to: fileURL)

        let encryptedThumbnail = try await encryptionService.generateEncryptedThumbnail(
            from: imageData,
            maxSize: Constants.thumbnailMaxSize
        )

        let item = VaultItem(
            type: .photo,
            originalFilename: filename,
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(imageData.count)
        )
        item.encryptedThumbnailData = encryptedThumbnail
        item.pixelWidth = pixelWidth
        item.pixelHeight = pixelHeight
        item.album = album

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    private func importVideo(from provider: NSItemProvider, album: Album?) async throws -> VaultItem {
        let (videoData, tempURL) = try await loadVideoData(from: provider)
        let filename = provider.suggestedName ?? "Untitled"

        // Get duration
        let asset = AVURLAsset(url: tempURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Generate thumbnail from first frame
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let (cgImage, _) = try await imageGenerator.image(at: .zero)
        let thumbnailImage = UIImage(cgImage: cgImage)
        let thumbnailJPEG = thumbnailImage.jpegData(compressionQuality: Constants.thumbnailJPEGQuality)

        // Get dimensions from thumbnail
        let pixelWidth = Int(thumbnailImage.size.width * thumbnailImage.scale)
        let pixelHeight = Int(thumbnailImage.size.height * thumbnailImage.scale)

        // Encrypt and write file
        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileID = UUID()
        let relativePath = "\(fileID).\(Constants.encryptedFileExtension)"
        let fileURL = vaultDir.appendingPathComponent(relativePath)

        let encryptedData = try await encryptionService.encryptData(videoData)
        try encryptedData.write(to: fileURL)

        // Encrypt thumbnail
        var encryptedThumbnail: Data?
        if let jpegData = thumbnailJPEG {
            encryptedThumbnail = try await encryptionService.generateEncryptedThumbnail(
                from: jpegData,
                maxSize: Constants.thumbnailMaxSize
            )
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        let item = VaultItem(
            type: .video,
            originalFilename: filename,
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(videoData.count)
        )
        item.encryptedThumbnailData = encryptedThumbnail
        item.pixelWidth = pixelWidth
        item.pixelHeight = pixelHeight
        item.durationSeconds = durationSeconds
        item.album = album

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    // MARK: - Import from Camera

    func importFromCamera(_ image: UIImage, album: Album?) async throws -> VaultItem {
        guard let jpegData = image.jpegData(compressionQuality: 1.0) else {
            throw VaultError.importFailed
        }

        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileID = UUID()
        let relativePath = "\(fileID).\(Constants.encryptedFileExtension)"
        let fileURL = vaultDir.appendingPathComponent(relativePath)

        let encryptedData = try await encryptionService.encryptData(jpegData)
        try encryptedData.write(to: fileURL)

        let encryptedThumbnail = try await encryptionService.generateEncryptedThumbnail(
            from: jpegData,
            maxSize: Constants.thumbnailMaxSize
        )

        let item = VaultItem(
            type: .photo,
            originalFilename: "Camera Photo",
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(jpegData.count)
        )
        item.encryptedThumbnailData = encryptedThumbnail
        item.pixelWidth = pixelWidth
        item.pixelHeight = pixelHeight
        item.album = album

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    // MARK: - Import Document

    func importDocument(at url: URL, album: Album?) async throws -> VaultItem {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let filename = url.lastPathComponent

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileID = UUID()
        let relativePath = "\(fileID).\(Constants.encryptedFileExtension)"
        let fileURL = vaultDir.appendingPathComponent(relativePath)

        let encryptedData = try await encryptionService.encryptData(data)
        try encryptedData.write(to: fileURL)

        let item = VaultItem(
            type: .document,
            originalFilename: filename,
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(data.count)
        )
        item.album = album

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    // MARK: - Decrypt Methods

    func decryptThumbnail(for item: VaultItem) async throws -> UIImage {
        guard let encryptedThumbnail = item.encryptedThumbnailData else {
            throw VaultError.thumbnailNotFound
        }

        let decryptedData = try await encryptionService.decryptData(encryptedThumbnail)

        guard let image = UIImage(data: decryptedData) else {
            throw VaultError.thumbnailNotFound
        }

        return image
    }

    func decryptFullImage(for item: VaultItem) async throws -> UIImage {
        let fileURL = try await buildFileURL(for: item)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound
        }

        let decryptedData = try await encryptionService.decryptFile(at: fileURL)

        guard let image = UIImage(data: decryptedData) else {
            throw VaultError.itemNotFound
        }

        return image
    }

    func decryptVideoURL(for item: VaultItem) async throws -> URL {
        let fileURL = try await buildFileURL(for: item)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound
        }

        let decryptedData = try await encryptionService.decryptFile(at: fileURL)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).mov")
        try decryptedData.write(to: tempURL)

        return tempURL
    }

    // MARK: - Organize Methods

    func moveItems(_ items: [VaultItem], to album: Album) async throws {
        for item in items {
            item.album = album
        }
        try modelContext.save()
    }

    func removeFromAlbum(_ items: [VaultItem]) async throws {
        for item in items {
            item.album = nil
        }
        try modelContext.save()
    }

    func toggleFavorite(_ item: VaultItem) async {
        item.isFavorite.toggle()
        try? modelContext.save()
    }

    // MARK: - Delete Methods

    func deleteItems(_ items: [VaultItem]) async throws {
        for item in items {
            let fileURL = try await buildFileURL(for: item)
            try? FileManager.default.removeItem(at: fileURL)
            modelContext.delete(item)
        }
        try modelContext.save()
    }

    func deleteFromCameraRoll(localIdentifiers: [String]) async throws {
        guard !localIdentifiers.isEmpty else { return }
        try await ensurePhotoLibraryReadWriteAccess()
        try await PhotoLibraryDeleteHelper.deleteAssets(withLocalIdentifiers: localIdentifiers)
    }

    // MARK: - Stats Methods

    func getTotalItemCount() -> Int {
        let descriptor = FetchDescriptor<VaultItem>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    func getTotalStorageUsed() -> Int64 {
        let descriptor = FetchDescriptor<VaultItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return 0 }
        return items.reduce(0) { $0 + $1.fileSize }
    }

    func isAtFreeLimit() -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        let limit = (try? modelContext.fetch(descriptor).first)?.freeItemLimit ?? Constants.freeItemLimit
        return getTotalItemCount() >= limit
    }

    // MARK: - Private Helpers

    private func buildFileURL(for item: VaultItem) async throws -> URL {
        let vaultDir = try await encryptionService.vaultFilesDirectory()
        return vaultDir.appendingPathComponent(item.encryptedFileRelativePath)
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: VaultError.importFailed)
                }
            }
        }
    }

    private func loadVideoData(from provider: NSItemProvider) async throws -> (Data, URL) {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url else {
                    continuation.resume(throwing: VaultError.importFailed)
                    return
                }

                // Copy to temp location since the provided URL is temporary
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    let data = try Data(contentsOf: tempURL)
                    continuation.resume(returning: (data, tempURL))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func ensurePhotoLibraryReadWriteAccess() async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch currentStatus {
        case .authorized, .limited:
            return

        case .notDetermined:
            let status = await requestPhotoLibraryReadWriteAuthorization()
            guard status == .authorized || status == .limited else {
                throw VaultError.photosPermissionDenied
            }

        case .denied, .restricted:
            throw VaultError.photosPermissionDenied

        @unknown default:
            throw VaultError.photosPermissionDenied
        }
    }

    private func requestPhotoLibraryReadWriteAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

private enum PhotoLibraryDeleteHelper {
    static func deleteAssets(withLocalIdentifiers identifiers: [String]) async throws {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetsToDelete: [PHAsset] = []
        assetsToDelete.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assetsToDelete.append(asset)
        }

        guard !assetsToDelete.isEmpty else { throw VaultError.itemNotFound }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }
    }
}
