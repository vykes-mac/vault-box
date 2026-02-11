import Foundation
import Vision
import UIKit
import ImageIO
import CoreImage

// MARK: - Analysis Types

struct VisionAnalysisInput: Sendable {
    let itemID: UUID
    let encryptedFileRelativePath: String
    let pixelWidth: Int?
    let pixelHeight: Int?
    let itemType: String
}

struct VisionAnalysisResult: Sendable {
    let itemID: UUID
    let smartTags: [String]
    let extractedText: String?
}

// MARK: - VisionAnalysisService

actor VisionAnalysisService {
    private let encryptionService: EncryptionService
    private var pendingItems: [VisionAnalysisInput] = []
    private var isProcessing = false

    init(encryptionService: EncryptionService) {
        self.encryptionService = encryptionService
    }

    // MARK: - Public API

    func queueItems(_ inputs: [VisionAnalysisInput], onResult: @escaping @Sendable (VisionAnalysisResult) -> Void) {
        pendingItems.append(contentsOf: inputs)
        if !isProcessing {
            isProcessing = true
            Task {
                await processQueue(onResult: onResult)
            }
        }
    }

    // MARK: - Processing Queue

    private func processQueue(onResult: @escaping @Sendable (VisionAnalysisResult) -> Void) async {
        while !pendingItems.isEmpty {
            let input = pendingItems.removeFirst()
            Self.debugLog("Starting analysis for item \(input.itemID.uuidString)")
            if let result = await analyzeItem(input) {
                onResult(result)
            }
        }
        isProcessing = false
    }

    // MARK: - Single Item Analysis

    private func analyzeItem(_ input: VisionAnalysisInput) async -> VisionAnalysisResult? {
        guard input.itemType == "photo" else { return nil }

        // Decrypt the full image temporarily.
        guard var imageData = await decryptItemData(input) else {
            Self.debugLog("Decrypt failed for item \(input.itemID.uuidString)")
            return VisionAnalysisResult(itemID: input.itemID, smartTags: [], extractedText: nil)
        }
        defer { wipeDecryptedBytes(&imageData) }

        guard let context = Self.makeImageContext(from: imageData) else {
            Self.debugLog("Image decode failed for item \(input.itemID.uuidString)")
            return VisionAnalysisResult(itemID: input.itemID, smartTags: [], extractedText: nil)
        }

        let screenBounds = await MainActor.run { UIScreen.main.nativeBounds.size }
        let result = await Self.runAnalysis(
            on: context.cgImage,
            orientation: context.orientation,
            input: input,
            screenBounds: screenBounds,
            timeoutSeconds: Constants.visionAnalysisTimeout
        )
        Self.debugLog("Finished item \(input.itemID.uuidString). Tags: \(result.smartTags.joined(separator: ",")) OCR chars: \(result.extractedText?.count ?? 0)")
        return result
    }

    // MARK: - Analysis (nonisolated — runs off-actor)

    private nonisolated static func runAnalysis(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        input: VisionAnalysisInput,
        screenBounds: CGSize,
        timeoutSeconds: TimeInterval
    ) async -> VisionAnalysisResult {
        let prepared = Self.prepareImageForVision(cgImage: cgImage, orientation: orientation)
        let analysisImage = prepared.cgImage
        let analysisOrientation = prepared.orientation

        let clock = ContinuousClock()
        let start = clock.now
        let timeout = Duration.milliseconds(Int64(timeoutSeconds * 1_000))
        var tags = Set<String>()
        var ocrText: String?

        var timeoutReached = false

        await withTaskGroup(of: DetectorOutcome.self) { group in
            group.addTask {
                .face(Self.detectFaces(on: analysisImage, orientation: analysisOrientation))
            }
            group.addTask {
                .barcode(Self.detectBarcodes(on: analysisImage, orientation: analysisOrientation))
            }
            group.addTask {
                .fastOCR(Self.recognizeText(on: analysisImage, orientation: analysisOrientation, level: .fast))
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timeout
            }

            var completedDetectors = 0
            while let outcome = await group.next() {
                switch outcome {
                case .face(let hasFaces):
                    completedDetectors += 1
                    if hasFaces {
                        tags.insert("people")
                    }

                case .barcode(let hasBarcode):
                    completedDetectors += 1
                    if hasBarcode {
                        tags.insert("qrcode")
                    }

                case .fastOCR(let text):
                    completedDetectors += 1
                    ocrText = Self.normalizedOCRText(text)

                case .timeout:
                    timeoutReached = true
                    Self.debugLog("Analysis timeout hit for item \(input.itemID.uuidString). Returning partial results.")
                    group.cancelAll()
                }

                if timeoutReached || completedDetectors == 3 {
                    group.cancelAll()
                    break
                }
            }
        }

        let elapsed = start.duration(to: clock.now)
        let remaining = timeout - elapsed

        if !timeoutReached,
           Self.shouldRunAccurateOCR(ocrText),
           remaining > .milliseconds(150) {
            let accurateResult = await Self.runAccurateOCRWithTimeout(
                on: analysisImage,
                orientation: analysisOrientation,
                timeout: remaining
            )
            switch accurateResult {
            case .text(let text):
                let normalized = Self.normalizedOCRText(text)
                if let normalized {
                    ocrText = normalized
                }
            case .timeout:
                timeoutReached = true
                Self.debugLog("Accurate OCR timed out. Keeping prior OCR result.")
            }
        }

        if let ocrText, Self.isSignificantDocumentText(ocrText) {
            tags.insert("document")
        }

        // Screenshot detection.
        if let width = input.pixelWidth, let height = input.pixelHeight {
            let screenW = Int(screenBounds.width)
            let screenH = Int(screenBounds.height)
            if (width == screenW && height == screenH) ||
               (width == screenH && height == screenW) {
                tags.insert("screenshot")
            }
        }

        return VisionAnalysisResult(
            itemID: input.itemID,
            smartTags: Array(tags).sorted(),
            extractedText: ocrText
        )
    }

    // MARK: - Decryption Helper

    private func decryptItemData(_ input: VisionAnalysisInput) async -> Data? {
        do {
            let vaultDir = try await encryptionService.vaultFilesDirectory()
            let fileURL = vaultDir.appendingPathComponent(input.encryptedFileRelativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return try await encryptionService.decryptFile(at: fileURL)
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func wipeDecryptedBytes(_ data: inout Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeMutableBytes { buffer in
            guard !buffer.isEmpty else { return }
            _ = buffer.initializeMemory(as: UInt8.self, repeating: 0)
        }
        data.removeAll(keepingCapacity: false)
    }

    private nonisolated static func makeImageContext(from data: Data) -> ImageContext? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return ImageContext(cgImage: cgImage, orientation: imageOrientation(from: source))
    }

    private nonisolated static func prepareImageForVision(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> (cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        let maxInputDimension = max(cgImage.width, cgImage.height)
        let targetMaxDimension = Int(Constants.visionAnalysisMaxDimension)
        if orientation == .up, maxInputDimension <= targetMaxDimension {
            return (cgImage, .up)
        }

        var image = CIImage(cgImage: cgImage)
        if orientation != .up {
            image = image.oriented(forExifOrientation: Int32(orientation.rawValue))
        }

        let sourceExtent = image.extent
        let sourceMaxDimension = max(sourceExtent.width, sourceExtent.height)
        if sourceMaxDimension > Constants.visionAnalysisMaxDimension {
            let scale = Constants.visionAnalysisMaxDimension / sourceMaxDimension
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let outputRect = image.extent.integral
        guard outputRect.width > 0,
              outputRect.height > 0 else {
            Self.debugLog("Prepared image had invalid extent. Using original image.")
            return (cgImage, orientation)
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let prepared = context.createCGImage(image, from: outputRect) else {
            Self.debugLog("Failed to build prepared image. Using original image.")
            return (cgImage, orientation)
        }

        return (prepared, .up)
    }

    private nonisolated static func imageOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .up
        }

        if let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: rawValue) {
            return orientation
        }

        if let rawValue = properties[kCGImagePropertyOrientation] as? Int,
           let orientation = CGImagePropertyOrientation(rawValue: UInt32(rawValue)) {
            return orientation
        }

        return .up
    }

    private nonisolated static func detectFaces(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> Bool {
        let orientations = candidateOrientations(primary: orientation)
        for candidate in orientations {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: candidate, options: [:])
            do {
                try handler.perform([request])
                if !(request.results ?? []).isEmpty {
                    return true
                }
            } catch {
                continue
            }
        }
        let coreImageFallback = detectFacesWithCoreImage(on: cgImage, orientation: orientation)
        if coreImageFallback {
            Self.debugLog("Face detector fallback (CoreImage) succeeded.")
        }
        return coreImageFallback
    }

    private nonisolated static func detectFacesWithCoreImage(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> Bool {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        guard let detector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: options) else {
            return false
        }
        let ciImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: Int32(orientation.rawValue))
        let features = detector.features(in: ciImage)
        return !features.isEmpty
    }

    private nonisolated static func detectBarcodes(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> Bool {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            return !(request.results ?? []).isEmpty
        } catch {
            if Self.shouldLogVisionError(error) {
                Self.debugLog("Barcode detector error (orientation=\(orientation.rawValue)): \(error)")
            }
            return false
        }
    }

    private nonisolated static func recognizeText(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        level: VNRequestTextRecognitionLevel
    ) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = (level == .accurate)

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let strings = observations.compactMap { $0.topCandidates(1).first?.string }
            return strings.joined(separator: " ")
        } catch {
            if Self.shouldLogVisionError(error) {
                Self.debugLog("OCR error (level=\(level == .accurate ? "accurate" : "fast"), orientation=\(orientation.rawValue)): \(error)")
            }
            return nil
        }
    }

    private nonisolated static func runAccurateOCRWithTimeout(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        timeout: Duration
    ) async -> AccurateOCROutcome {
        await withTaskGroup(of: AccurateOCROutcome.self) { group in
            group.addTask {
                .text(Self.recognizeText(on: cgImage, orientation: orientation, level: .accurate))
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timeout
            }

            if let first = await group.next() {
                group.cancelAll()
                return first
            }

            group.cancelAll()
            return .timeout
        }
    }

    private nonisolated static func candidateOrientations(
        primary: CGImagePropertyOrientation
    ) -> [CGImagePropertyOrientation] {
        var options: [CGImagePropertyOrientation] = [primary]
        for orientation in [
            CGImagePropertyOrientation.up,
            .upMirrored,
            .right,
            .rightMirrored,
            .left,
            .leftMirrored,
            .down,
            .downMirrored
        ] where !options.contains(orientation) {
            options.append(orientation)
        }
        return options
    }

    private nonisolated static func normalizedOCRText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func shouldRunAccurateOCR(_ fastText: String?) -> Bool {
        guard let fastText = normalizedOCRText(fastText) else { return true }
        return !isSignificantDocumentText(fastText)
    }

    private nonisolated static func isSignificantDocumentText(_ text: String) -> Bool {
        text.count > 20
    }

    private nonisolated static func shouldLogVisionError(_ error: Error) -> Bool {
        #if targetEnvironment(simulator)
        let nsError = error as NSError
        if nsError.domain == VNErrorDomain, nsError.code == 9 {
            return false
        }
        #endif
        return true
    }

    private nonisolated static func debugLog(_ message: String) {
        #if DEBUG
        print("[VisionAnalysisService] \(message)")
        #endif
    }
}

private struct ImageContext {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
}

private enum DetectorOutcome: Sendable {
    case face(Bool)
    case barcode(Bool)
    case fastOCR(String?)
    case timeout
}

private enum AccurateOCROutcome: Sendable {
    case text(String?)
    case timeout
}
