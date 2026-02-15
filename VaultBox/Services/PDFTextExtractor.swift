import Foundation
import PDFKit
import Vision
import UIKit

// MARK: - PDFTextExtractor

enum PDFTextExtractor {

    struct PageText: Sendable {
        let pageNumber: Int  // 1-based
        let text: String
        let wasOCR: Bool
    }

    struct ExtractionResult: Sendable {
        let pages: [PageText]
        let totalPages: Int
    }

    /// Extracts text from all pages of a PDF.
    /// Uses PDFKit native text first, falls back to OCR for scanned pages.
    static func extract(from pdfData: Data) -> ExtractionResult {
        guard let document = PDFDocument(data: pdfData) else {
            return ExtractionResult(pages: [], totalPages: 0)
        }

        let totalPages = document.pageCount
        var pages: [PageText] = []

        for pageIndex in 0..<totalPages {
            autoreleasepool {
                guard let page = document.page(at: pageIndex) else { return }
                let pageNumber = pageIndex + 1

                // Try PDFKit native text extraction first
                let nativeText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if nativeText.count >= Constants.ocrMinCharsForTextPage {
                    pages.append(PageText(pageNumber: pageNumber, text: nativeText, wasOCR: false))
                } else {
                    // Fall back to OCR for scanned/image-based pages
                    if let ocrText = ocrPage(page), !ocrText.isEmpty {
                        pages.append(PageText(pageNumber: pageNumber, text: ocrText, wasOCR: true))
                    } else if !nativeText.isEmpty {
                        // Use whatever native text we got
                        pages.append(PageText(pageNumber: pageNumber, text: nativeText, wasOCR: false))
                    }
                }
            }
        }

        return ExtractionResult(pages: pages, totalPages: totalPages)
    }

    // MARK: - OCR Fallback

    private static func ocrPage(_ page: PDFPage) -> String? {
        guard let cgImage = renderPageToImage(page) else { return nil }
        return performOCR(on: cgImage)
    }

    private static func renderPageToImage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 300.0 / 72.0  // 300 DPI
        let renderSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        guard renderSize.width > 0, renderSize.height > 0 else { return nil }

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: renderSize))
            ctx.cgContext.translateBy(x: 0, y: renderSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image.cgImage
    }

    private static func performOCR(on cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        // Sort top-to-bottom (bounding box y is from bottom, so descending)
        let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        let strings = sorted.compactMap { $0.topCandidates(1).first?.string }
        let text = strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
