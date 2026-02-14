import Foundation
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers
import SwiftData
import UIKit
import Photos
import ImageIO

// MARK: - Errors

enum VaultError: LocalizedError {
    case importFailed
    case itemNotFound
    case thumbnailNotFound
    case freeLimitReached
    case premiumRequired
    case fileNotFound
    case photosPermissionDenied
    case videoTooLarge(maxMB: Int)

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
        case .premiumRequired:
            "This feature requires a Premium subscription."
        case .fileNotFound:
            "The encrypted file could not be found on disk."
        case .photosPermissionDenied:
            "VaultBox needs Photos access to delete originals. Allow Photos access in Settings."
        case .videoTooLarge(let maxMB):
            "This video is too large to import. The current limit is \(maxMB) MB."
        }
    }
}

// MARK: - VaultService

@MainActor
@Observable
class VaultService {
    private let encryptionService: EncryptionService
    private let modelContext: ModelContext
    private let hasPremiumAccess: () -> Bool
    private var visionService: VisionAnalysisService?
    private(set) var ingestionService: IngestionService?

    init(
        encryptionService: EncryptionService,
        modelContext: ModelContext,
        hasPremiumAccess: @escaping () -> Bool = { false }
    ) {
        self.encryptionService = encryptionService
        self.modelContext = modelContext
        self.hasPremiumAccess = hasPremiumAccess
        self.visionService = VisionAnalysisService(encryptionService: encryptionService)
    }

    /// Indexing progress observable for the Ask My Vault UI.
    private(set) var indexingProgress: IndexingProgress?

    /// Attaches the search ingestion service for Ask My Vault indexing.
    func configureSearchIndex(ingestionService: IngestionService, indexingProgress: IndexingProgress) {
        self.ingestionService = ingestionService
        self.indexingProgress = indexingProgress
    }

    // MARK: - Import Result

    struct ImportResult {
        let items: [VaultItem]
        let assetIdentifiers: [String]
    }

    // MARK: - Import from PHPicker

    func importPhotos(
        from results: [PHPickerResult],
        album: Album?,
        isDecoyMode: Bool = false,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> ImportResult {
        var importedItems: [VaultItem] = []
        var assetIdentifiers: [String] = []

        for (index, result) in results.enumerated() {
            let provider = result.itemProvider

            var didImport = false
            do {
                // Prefer image first so Live Photos are treated as photos.
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let item = try await importImage(from: provider, album: album, isDecoyMode: isDecoyMode)
                    importedItems.append(item)
                    didImport = true
                } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    let item = try await importVideo(from: provider, album: album, isDecoyMode: isDecoyMode)
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

    private func importImage(from provider: NSItemProvider, album: Album?, isDecoyMode: Bool) async throws -> VaultItem {
        let imageData = try await loadImageData(from: provider)
        return try await importPhotoData(
            imageData,
            filename: provider.suggestedName,
            album: album,
            isDecoyMode: isDecoyMode
        )
    }

    private func importVideo(from provider: NSItemProvider, album: Album?, isDecoyMode: Bool) async throws -> VaultItem {
        let tempURL = try await loadVideoURL(from: provider)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let suggested = provider.suggestedName ?? tempURL.deletingPathExtension().lastPathComponent
        return try await importVideo(at: tempURL, filename: suggested, album: album, isDecoyMode: isDecoyMode)
    }

    // MARK: - Import from Camera

    func importPhotoData(
        _ data: Data,
        filename: String?,
        album: Album?,
        isDecoyMode: Bool = false
    ) async throws -> VaultItem {
        try enforceImportLimit()
        let resolvedName: String
        if let trimmed = filename?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            resolvedName = trimmed
        } else {
            resolvedName = "Photo"
        }
        let targetAlbum = try resolveAlbum(requested: album, isDecoyMode: isDecoyMode)

        let (pixelWidth, pixelHeight) = photoDimensions(from: data)

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileID = UUID()
        let relativePath = "\(fileID).\(Constants.encryptedFileExtension)"
        let fileURL = vaultDir.appendingPathComponent(relativePath)

        let encryptedData = try await encryptionService.encryptData(data)
        try encryptedData.write(to: fileURL)

        let encryptedThumbnail = try await encryptionService.generateEncryptedThumbnail(
            from: data,
            maxSize: Constants.thumbnailMaxSize
        )

        let item = VaultItem(
            type: .photo,
            originalFilename: resolvedName,
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(data.count)
        )
        item.encryptedThumbnailData = encryptedThumbnail
        item.pixelWidth = pixelWidth
        item.pixelHeight = pixelHeight
        item.album = targetAlbum

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    func importFromCamera(
        _ image: UIImage,
        album: Album?,
        isDecoyMode: Bool = false
    ) async throws -> VaultItem {
        try enforceImportLimit()
        guard let jpegData = image.jpegData(compressionQuality: 1.0) else {
            throw VaultError.importFailed
        }
        let targetAlbum = try resolveAlbum(requested: album, isDecoyMode: isDecoyMode)

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
        item.album = targetAlbum

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    func importVideo(
        at url: URL,
        filename: String?,
        album: Album?,
        isDecoyMode: Bool = false
    ) async throws -> VaultItem {
        try enforceImportLimit()
        try enforceVideoSizeLimit(for: url)

        let resolvedName: String
        if let trimmed = filename?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            resolvedName = trimmed
        } else {
            resolvedName = "Video"
        }

        let targetAlbum = try resolveAlbum(requested: album, isDecoyMode: isDecoyMode)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)
        let durationSeconds: Double?
        if let duration = try? await asset.load(.duration) {
            let value = CMTimeGetSeconds(duration)
            durationSeconds = value.isFinite ? value : nil
        } else {
            durationSeconds = nil
        }

        var encryptedThumbnail: Data?
        var pixelWidth: Int?
        var pixelHeight: Int?

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        if let (cgImage, _) = try? await imageGenerator.image(at: .zero) {
            let thumbnailImage = UIImage(cgImage: cgImage)
            if let jpegData = thumbnailImage.jpegData(compressionQuality: Constants.thumbnailJPEGQuality) {
                encryptedThumbnail = try await encryptionService.generateEncryptedThumbnail(
                    from: jpegData,
                    maxSize: Constants.thumbnailMaxSize
                )
            }
            pixelWidth = Int(thumbnailImage.size.width * thumbnailImage.scale)
            pixelHeight = Int(thumbnailImage.size.height * thumbnailImage.scale)
        }

        let videoData = try Data(contentsOf: url, options: .mappedIfSafe)

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileID = UUID()
        let relativePath = "\(fileID).\(Constants.encryptedFileExtension)"
        let fileURL = vaultDir.appendingPathComponent(relativePath)

        let encryptedData = try await encryptionService.encryptData(videoData)
        try encryptedData.write(to: fileURL)

        let item = VaultItem(
            type: .video,
            originalFilename: resolvedName,
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(videoData.count)
        )
        item.encryptedThumbnailData = encryptedThumbnail
        item.pixelWidth = pixelWidth
        item.pixelHeight = pixelHeight
        item.durationSeconds = durationSeconds
        item.album = targetAlbum

        modelContext.insert(item)
        try modelContext.save()

        return item
    }

    // MARK: - Import Document

    func importDocument(at url: URL, album: Album?, isDecoyMode: Bool = false) async throws -> VaultItem {
        try enforceImportLimit()
        let targetAlbum = try resolveAlbum(requested: album, isDecoyMode: isDecoyMode)
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

        // Generate thumbnail for documents (PDF first page, image-based docs)
        var encryptedThumbnail: Data?
        if let thumbnail = DocumentThumbnailService.generateThumbnail(from: data, filename: filename),
           let jpegData = thumbnail.jpegData(compressionQuality: Constants.thumbnailJPEGQuality) {
            encryptedThumbnail = try? await encryptionService.encryptData(jpegData)
        }

        let item = VaultItem(
            type: .document,
            originalFilename: filename,
            encryptedFileRelativePath: relativePath,
            fileSize: Int64(data.count)
        )
        item.encryptedThumbnailData = encryptedThumbnail
        item.album = targetAlbum

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

    /// Returns raw decrypted file data for any VaultItem type (photo, video, document).
    func decryptFileData(for item: VaultItem) async throws -> Data {
        let fileURL = try await buildFileURL(for: item)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound
        }

        return try await encryptionService.decryptFile(at: fileURL)
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

    /// Decrypts a document to a temporary file URL for viewing.
    /// Caller is responsible for deleting the temp file when done.
    func decryptDocumentURL(for item: VaultItem) async throws -> URL {
        let fileURL = try await buildFileURL(for: item)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw VaultError.fileNotFound
        }

        let decryptedData = try await encryptionService.decryptFile(at: fileURL)

        let ext = (item.originalFilename as NSString).pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID()).\(ext.isEmpty ? "dat" : ext)")
        try decryptedData.write(to: tempURL)

        return tempURL
    }

    // MARK: - Custom Album Cover

    /// Encrypts a cover image (resized to thumbnail size) for an album.
    func encryptAlbumCoverImage(_ imageData: Data) async throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw VaultError.importFailed
        }
        let maxSize = Constants.thumbnailMaxSize
        let thumbnail = image.preparingThumbnail(of: coverThumbnailSize(for: image.size, maxSize: maxSize)) ?? image
        guard let jpegData = thumbnail.jpegData(compressionQuality: Constants.thumbnailJPEGQuality) else {
            throw VaultError.importFailed
        }
        return try await encryptionService.encryptData(jpegData)
    }

    /// Decrypts a custom album cover image.
    func decryptAlbumCoverImage(_ encryptedData: Data) async throws -> UIImage {
        let decryptedData = try await encryptionService.decryptData(encryptedData)
        guard let image = UIImage(data: decryptedData) else {
            throw VaultError.thumbnailNotFound
        }
        return image
    }

    private func coverThumbnailSize(for originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scale = max(widthRatio, heightRatio)
        return CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
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
        removeSearchIndex(for: items)
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

    // MARK: - iCloud Restore

    /// Restores all backed-up items from iCloud that don't already exist locally.
    /// Returns the restored `VaultItem` array.
    func restoreFromiCloud(
        cloudService: CloudService,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [VaultItem] {
        let records = try await cloudService.fetchAllCloudRecords()
        guard !records.isEmpty else { return [] }

        // Build a set of existing item IDs to avoid duplicates
        let allDescriptor = FetchDescriptor<VaultItem>()
        let existingItems = (try? modelContext.fetch(allDescriptor)) ?? []
        let existingIDs = Set(existingItems.map { $0.id.uuidString })

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        var restoredItems: [VaultItem] = []
        let total = records.count

        await cloudService.setDownloadProgress(completed: 0, total: total)

        for (index, record) in records.enumerated() {
            guard let itemIDString = record["itemID"] as? String,
                  let itemID = UUID(uuidString: itemIDString),
                  let itemTypeRaw = record["itemType"] as? String,
                  let itemType = VaultItem.ItemType(rawValue: itemTypeRaw),
                  let originalFilename = record["originalFilename"] as? String,
                  let fileSize = record["fileSize"] as? Int64 else {
                progress(index + 1, total)
                await cloudService.setDownloadProgress(completed: index + 1, total: total)
                continue
            }

            // Skip if this item already exists locally
            if existingIDs.contains(itemIDString) {
                progress(index + 1, total)
                await cloudService.setDownloadProgress(completed: index + 1, total: total)
                continue
            }

            do {
                // Download encrypted file data from iCloud
                let encryptedData = try await cloudService.downloadItem(recordID: record.recordID.recordName)

                // Save encrypted file to vault directory
                let relativePath = "\(UUID()).\(Constants.encryptedFileExtension)"
                let fileURL = vaultDir.appendingPathComponent(relativePath)
                try encryptedData.write(to: fileURL)

                // Create VaultItem with metadata from CloudKit record
                let item = VaultItem(
                    type: itemType,
                    originalFilename: originalFilename,
                    encryptedFileRelativePath: relativePath,
                    fileSize: fileSize
                )
                // Preserve original ID and dates
                item.id = itemID
                if let createdAt = record["createdAt"] as? Date {
                    item.createdAt = createdAt
                }
                item.importedAt = Date()
                item.isUploaded = true
                item.cloudRecordID = record.recordID.recordName

                // Restore encrypted thumbnail if available
                if let thumbnailData = record["encryptedThumbnail"] as? Data {
                    item.encryptedThumbnailData = thumbnailData
                }

                modelContext.insert(item)
                try modelContext.save()
                restoredItems.append(item)
            } catch {
                // Skip failed items and continue with the rest
                #if DEBUG
                print("[VaultService] Failed to restore item \(itemIDString): \(error)")
                #endif
            }

            progress(index + 1, total)
            await cloudService.setDownloadProgress(completed: index + 1, total: total)
        }

        await cloudService.resetDownloadProgress()
        return restoredItems
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

    private func enforceImportLimit() throws {
        guard !hasPremiumAccess() else { return }
        if isAtFreeLimit() {
            throw VaultError.freeLimitReached
        }
    }

    // MARK: - Vision Analysis

    func queueVisionAnalysis(for items: [VaultItem]) {
        guard let visionService else { return }

        let inputs = items.compactMap { item -> VisionAnalysisInput? in
            guard item.type == .photo || item.type == .document else { return nil }
            return VisionAnalysisInput(
                itemID: item.id,
                encryptedFileRelativePath: item.encryptedFileRelativePath,
                pixelWidth: item.pixelWidth,
                pixelHeight: item.pixelHeight,
                itemType: item.type.rawValue,
                originalFilename: item.originalFilename
            )
        }

        guard !inputs.isEmpty else { return }

        Task {
            await visionService.queueItems(inputs) { result in
                Task { @MainActor in
                    self.applyVisionResult(result)
                }
            }
        }
    }

    private func applyVisionResult(_ result: VisionAnalysisResult) {
        let targetID = result.itemID
        let descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.id == targetID }
        )
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        item.smartTags = result.smartTags
        item.extractedText = result.extractedText
        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[VaultService] Failed to save vision result for \(targetID): \(error)")
            #endif
        }
    }

    // MARK: - Search Indexing (Ask My Vault)

    /// Queues search indexing for newly imported items.
    func queueSearchIndexing(for items: [VaultItem]) {
        guard let ingestionService else { return }

        let inputs = items.compactMap { item -> IngestionInput? in
            guard item.type != .video else { return nil }
            return IngestionInput(
                itemID: item.id,
                encryptedFileRelativePath: item.encryptedFileRelativePath,
                itemType: item.type.rawValue,
                originalFilename: item.originalFilename
            )
        }

        guard !inputs.isEmpty else { return }

        // Update indexing progress for UI
        if let indexingProgress {
            indexingProgress.totalItems += inputs.count
            indexingProgress.isIndexing = true
            indexingProgress.currentItemName = inputs.first?.originalFilename
        }

        Task {
            await ingestionService.indexBatch(inputs) { result in
                Task { @MainActor in
                    self.applyIngestionResult(result)

                    if let progress = self.indexingProgress {
                        progress.completedItems += 1
                        if progress.completedItems >= progress.totalItems {
                            progress.isIndexing = false
                            progress.currentItemName = nil
                            progress.totalItems = 0
                            progress.completedItems = 0
                        } else {
                            // Update current item name for next item
                            let nextIndex = progress.completedItems
                            if nextIndex < inputs.count {
                                progress.currentItemName = inputs[nextIndex].originalFilename
                            }
                        }
                    }
                }
            }
        }

        // Schedule background indexing for items that didn't finish
        VaultBoxApp.scheduleBackgroundIndexing()
    }

    /// Applies the result of search indexing back to the VaultItem model.
    private func applyIngestionResult(_ result: IngestionResult) {
        let targetID = result.itemID
        let descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.id == targetID }
        )
        guard let item = try? modelContext.fetch(descriptor).first else { return }

        item.isIndexed = result.success
        item.indexingFailed = !result.success
        item.chunkCount = result.chunkCount
        item.totalPages = result.totalPages
        if let preview = result.extractedTextPreview {
            item.extractedTextPreview = preview
        }

        do {
            try modelContext.save()
        } catch {
            #if DEBUG
            print("[VaultService] Failed to save ingestion result for \(targetID): \(error)")
            #endif
        }
    }

    /// Indexes all items that haven't been indexed yet. Called on app launch
    /// and after background task wake-ups.
    func indexUnindexedItems() {
        guard ingestionService != nil else { return }

        let descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate<VaultItem> { !$0.isIndexed && !$0.indexingFailed }
        )
        guard let unindexed = try? modelContext.fetch(descriptor), !unindexed.isEmpty else { return }
        queueSearchIndexing(for: unindexed)
    }

    /// Removes search index data for the given items. Called before item deletion.
    private func removeSearchIndex(for items: [VaultItem]) {
        guard let ingestionService else { return }
        for item in items {
            let itemID = item.id
            Task {
                await ingestionService.removeItem(itemID: itemID)
            }
        }
    }

    // MARK: - Private Helpers

    private func buildFileURL(for item: VaultItem) async throws -> URL {
        let vaultDir = try await encryptionService.vaultFilesDirectory()
        return vaultDir.appendingPathComponent(item.encryptedFileRelativePath)
    }

    private func resolveAlbum(requested album: Album?, isDecoyMode: Bool) throws -> Album? {
        if isDecoyMode {
            if let album, album.isDecoy {
                return album
            }
            return try defaultDecoyAlbum()
        }

        if album?.isDecoy == true {
            return nil
        }
        return album
    }

    private func defaultDecoyAlbum() throws -> Album {
        let descriptor = FetchDescriptor<Album>(
            predicate: #Predicate { $0.isDecoy == true },
            sortBy: [SortDescriptor(\Album.createdAt)]
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let count = (try? modelContext.fetchCount(FetchDescriptor<Album>())) ?? 0
        let album = Album(name: "Personal", sortOrder: count, isDecoy: true)
        modelContext.insert(album)
        return album
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

    private func loadVideoURL(from provider: NSItemProvider) async throws -> URL {
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
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    continuation.resume(returning: tempURL)
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

    private func photoDimensions(from data: Data) -> (Int?, Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            let image = UIImage(data: data)
            let width = image.map { Int($0.size.width * $0.scale) }
            let height = image.map { Int($0.size.height * $0.scale) }
            return (width, height)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        return (width, height)
    }

    private func enforceVideoSizeLimit(for url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        let byteCount = values.fileSize ?? values.totalFileAllocatedSize ?? values.fileAllocatedSize
        guard let byteCount else { return }

        let maxBytes = Constants.maxVideoImportBytes
        guard byteCount <= maxBytes else {
            let maxMB = maxBytes / (1024 * 1024)
            throw VaultError.videoTooLarge(maxMB: maxMB)
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
