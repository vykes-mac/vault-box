import Foundation
import Photos
import UIKit
import ImageIO

// MARK: - Types

struct SensitiveScanCandidate: Sendable, Identifiable, Equatable {
    /// The `PHAsset.localIdentifier`.
    let id: String
    let reasons: [ImageSignalDetectors.SensitiveReason]
    let creationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
}

// MARK: - SensitiveContentScanService

/// Scans the camera roll **on-device** to flag photos that look sensitive
/// (IDs, payment cards, financial info, credential screenshots, codes) so the
/// user can move them into the vault. No image ever leaves the device, and
/// iCloud-only assets are skipped (network access is disabled) to avoid pulls.
actor SensitiveContentScanService {

    /// Maximum dimension we decode each asset to before running detectors.
    private let analysisMaxPixel = 1024

    enum ScanError: Error {
        case notAuthorized
    }

    /// Scans up to `maxAssets` of the most recent photos.
    /// - Parameters:
    ///   - maxAssets: cap on assets to inspect (newest first).
    ///   - onProgress: called on the main actor with (scanned, total).
    /// - Returns: candidates that matched at least one sensitive signal.
    func scan(
        maxAssets: Int,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [SensitiveScanCandidate] {
        guard isAuthorized() else { throw ScanError.notAuthorized }

        let screenBounds = await MainActor.run { UIScreen.main.nativeBounds.size }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        fetchOptions.fetchLimit = maxAssets

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        let total = assets.count
        guard total > 0 else { return [] }

        var candidates: [SensitiveScanCandidate] = []

        for index in 0..<total {
            if Task.isCancelled { break }
            let asset = assets.object(at: index)

            if let candidate = await analyze(asset: asset, screenBounds: screenBounds) {
                candidates.append(candidate)
            }

            let scanned = index + 1
            onProgress(scanned, total)
        }

        return candidates
    }

    // MARK: - Per-Asset Analysis

    private func analyze(asset: PHAsset, screenBounds: CGSize) async -> SensitiveScanCandidate? {
        guard let payload = await requestImageData(for: asset) else { return nil }

        // Decode + detect entirely within a nonisolated function so no non-Sendable
        // image type crosses the actor boundary — only the Sendable reason set returns.
        let reasons = Self.detectReasons(
            data: payload.data,
            orientation: payload.orientation,
            maxPixel: analysisMaxPixel,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            isPhotoScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            screenBounds: screenBounds
        )
        guard !reasons.isEmpty else { return nil }

        return SensitiveScanCandidate(
            id: asset.localIdentifier,
            reasons: reasons.sorted { $0.rawValue < $1.rawValue },
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight
        )
    }

    private nonisolated static func detectReasons(
        data: Data,
        orientation: CGImagePropertyOrientation,
        maxPixel: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        isPhotoScreenshot: Bool,
        screenBounds: CGSize
    ) -> [ImageSignalDetectors.SensitiveReason] {
        guard let cgImage = downscaledImage(from: data, maxPixel: maxPixel) else { return [] }

        let fastText = ImageSignalDetectors.recognizeTextDetails(on: cgImage, orientation: orientation, level: .fast)
        let hasBarcode = ImageSignalDetectors.detectBarcodes(on: cgImage, orientation: orientation)
        let isScreenshot = isPhotoScreenshot || ImageSignalDetectors.isScreenshot(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            screenBounds: screenBounds
        )
        let layout = ImageSignalDetectors
            .detectLayout(on: cgImage, orientation: orientation)
            .withTextLineCount(fastText?.lineCount ?? 0)

        let fastReasons = ImageSignalDetectors.sensitiveReasons(
            text: fastText?.text,
            isScreenshot: isScreenshot,
            hasBarcode: hasBarcode,
            layout: layout
        )
        guard ImageSignalDetectors.shouldRetryAccurateOCR(
            text: fastText?.text,
            isScreenshot: isScreenshot,
            hasBarcode: hasBarcode,
            layout: layout,
            reasons: fastReasons
        ) else {
            return Array(fastReasons)
        }

        guard let accurateText = ImageSignalDetectors.recognizeTextDetails(
            on: cgImage,
            orientation: orientation,
            level: .accurate
        ) else {
            return Array(fastReasons)
        }

        let accurateLayout = layout.withTextLineCount(accurateText.lineCount)
        let accurateReasons = ImageSignalDetectors.sensitiveReasons(
            text: accurateText.text,
            isScreenshot: isScreenshot,
            hasBarcode: hasBarcode,
            layout: accurateLayout
        )
        return Array(accurateReasons.isEmpty ? fastReasons : accurateReasons)
    }

    // MARK: - Image Loading

    private struct ImagePayload: Sendable {
        let data: Data
        let orientation: CGImagePropertyOrientation
    }

    /// Loads full image data + orientation for an asset without touching the
    /// network (iCloud-only assets resolve to `nil` and are skipped).
    private func requestImageData(for asset: PHAsset) async -> ImagePayload? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.version = .current

        return await withCheckedContinuation { (continuation: CheckedContinuation<ImagePayload?, Never>) in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, orientation, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ImagePayload(data: data, orientation: orientation))
            }
        }
    }

    /// Decodes image data to a CGImage downscaled to `maxPixel` on its longest
    /// edge using ImageIO's thumbnail path (cheap, avoids full decode).
    private nonisolated static func downscaledImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Authorization

    private nonisolated func isAuthorized() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }
}
