import CoreGraphics
import Foundation
import ImageIO
import Vision

struct RecognizedImageText: Sendable, Equatable {
    let text: String
    let lineCount: Int
}

struct SensitiveImageLayout: Sendable, Equatable {
    static let empty = SensitiveImageLayout()

    let textLineCount: Int
    let hasDocumentRectangle: Bool
    let hasCardAspectRectangle: Bool

    init(
        textLineCount: Int = 0,
        hasDocumentRectangle: Bool = false,
        hasCardAspectRectangle: Bool = false
    ) {
        self.textLineCount = textLineCount
        self.hasDocumentRectangle = hasDocumentRectangle
        self.hasCardAspectRectangle = hasCardAspectRectangle
    }

    func withTextLineCount(_ lineCount: Int) -> SensitiveImageLayout {
        SensitiveImageLayout(
            textLineCount: lineCount,
            hasDocumentRectangle: hasDocumentRectangle,
            hasCardAspectRectangle: hasCardAspectRectangle
        )
    }
}

extension ImageSignalDetectors {
    static func detectLayout(
        on cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> SensitiveImageLayout {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 6
        request.minimumConfidence = 0.55
        request.minimumAspectRatio = 0.25
        request.quadratureTolerance = 25

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .empty
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let observations = request.results ?? []
        return SensitiveImageLayout(
            hasDocumentRectangle: observations.contains { looksLikeDocument($0, imageSize: imageSize) },
            hasCardAspectRectangle: observations.contains { looksLikeCard($0, imageSize: imageSize) }
        )
    }

    private static func looksLikeDocument(
        _ observation: VNRectangleObservation,
        imageSize: CGSize
    ) -> Bool {
        let area = observation.boundingBox.width * observation.boundingBox.height
        let aspect = aspectRatio(for: observation, imageSize: imageSize)
        return area >= 0.22 && aspect >= 0.65 && aspect <= 1.65
    }

    private static func looksLikeCard(
        _ observation: VNRectangleObservation,
        imageSize: CGSize
    ) -> Bool {
        let area = observation.boundingBox.width * observation.boundingBox.height
        let aspect = aspectRatio(for: observation, imageSize: imageSize)
        return area >= 0.08 && aspect >= 1.35 && aspect <= 1.9
    }

    private static func aspectRatio(
        for observation: VNRectangleObservation,
        imageSize: CGSize
    ) -> CGFloat {
        let width = observation.boundingBox.width * imageSize.width
        let height = observation.boundingBox.height * imageSize.height
        guard width > 0, height > 0 else { return 0 }
        let ratio = width / height
        return max(ratio, 1 / ratio)
    }
}
