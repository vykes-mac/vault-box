import Foundation
import Vision
import ImageIO

// MARK: - ImageOCRExtractor

enum ImageOCRExtractor {

    /// Extracts text from an image using Vision OCR.
    /// Returns nil if no text is found.
    static func extract(from imageData: Data) -> String? {
        guard let cgImage = createCGImage(from: imageData) else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: imageOrientation(from: imageData),
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        // Sort observations top-to-bottom (y descending in normalized coords)
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        let strings = sorted.compactMap { $0.topCandidates(1).first?.string }
        let text = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Helpers

    private static func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return cgImage
    }

    private static func imageOrientation(from data: Data) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: rawValue) else {
            return .up
        }
        return orientation
    }
}
