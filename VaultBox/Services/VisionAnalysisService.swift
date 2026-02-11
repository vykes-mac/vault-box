import Foundation
import Vision
import UIKit

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
            if let result = await analyzeItem(input) {
                onResult(result)
            }
        }
        isProcessing = false
    }

    // MARK: - Single Item Analysis

    private func analyzeItem(_ input: VisionAnalysisInput) async -> VisionAnalysisResult? {
        guard input.itemType == "photo" else { return nil }

        // Decrypt the full image temporarily
        guard let imageData = await decryptItemData(input) else { return nil }

        guard let cgImage = UIImage(data: imageData)?.cgImage else { return nil }

        let screenBounds = await MainActor.run { UIScreen.main.nativeBounds.size }

        // Run analysis with timeout
        let result = await withTaskGroup(of: VisionAnalysisResult?.self) { group in
            group.addTask {
                Self.runAnalysis(on: cgImage, input: input, screenBounds: screenBounds)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Constants.visionAnalysisTimeout))
                return nil // timeout sentinel
            }

            // Return first non-nil result, or nil if timeout fires first
            var analysisResult: VisionAnalysisResult?
            for await taskResult in group {
                if let taskResult {
                    analysisResult = taskResult
                    group.cancelAll()
                    break
                } else if analysisResult == nil {
                    // Timeout fired, cancel remaining
                    group.cancelAll()
                    break
                }
            }
            return analysisResult
        }

        return result
    }

    // MARK: - Analysis (nonisolated — runs off-actor for true concurrency)

    private nonisolated static func runAnalysis(
        on cgImage: CGImage,
        input: VisionAnalysisInput,
        screenBounds: CGSize
    ) -> VisionAnalysisResult {
        var tags: [String] = []
        var ocrText: String?

        // Run all three Vision requests on the same image handler for efficiency
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        let faceRequest = VNDetectFaceRectanglesRequest()
        let barcodeRequest = VNDetectBarcodesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([textRequest, faceRequest, barcodeRequest])
        } catch {
            return VisionAnalysisResult(itemID: input.itemID, smartTags: [], extractedText: nil)
        }

        // Process text results
        let textObservations = textRequest.results ?? []
        let strings = textObservations.compactMap { $0.topCandidates(1).first?.string }
        if !strings.isEmpty {
            let allText = strings.joined(separator: " ")
            ocrText = allText
            if allText.count > 20 {
                tags.append("document")
            }
        }

        // Process face results
        if let faceResults = faceRequest.results, !faceResults.isEmpty {
            tags.append("people")
        }

        // Process barcode results
        if let barcodeResults = barcodeRequest.results, !barcodeResults.isEmpty {
            tags.append("qrcode")
        }

        // Screenshot detection
        if let width = input.pixelWidth, let height = input.pixelHeight {
            let screenW = Int(screenBounds.width)
            let screenH = Int(screenBounds.height)
            if (width == screenW && height == screenH) ||
               (width == screenH && height == screenW) {
                tags.append("screenshot")
            }
        }

        return VisionAnalysisResult(
            itemID: input.itemID,
            smartTags: tags,
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
}
