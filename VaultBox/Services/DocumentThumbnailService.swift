import UIKit
import PDFKit

// MARK: - DocumentThumbnailService

enum DocumentThumbnailService {

    /// Generates a thumbnail image for a document.
    /// For PDFs, renders the first page. For images, returns a resized version.
    static func generateThumbnail(from data: Data, filename: String, maxSize: CGSize = Constants.thumbnailMaxSize) -> UIImage? {
        let lowercasedName = filename.lowercased()

        if lowercasedName.hasSuffix(".pdf") {
            return pdfThumbnail(from: data, maxSize: maxSize)
        }

        // For image-based documents (scanned IDs, etc.), use UIImage directly
        if let image = UIImage(data: data) {
            return image.preparingThumbnail(of: thumbnailTargetSize(for: image.size, maxSize: maxSize)) ?? image
        }

        return nil
    }

    /// Returns a generic SF Symbol icon for documents that can't generate a visual thumbnail.
    static func placeholderIcon(for filename: String) -> String {
        let lowercasedName = filename.lowercased()
        if lowercasedName.hasSuffix(".pdf") {
            return "doc.fill"
        }
        return "doc.text.fill"
    }

    // MARK: - Private

    private static func pdfThumbnail(from data: Data, maxSize: CGSize) -> UIImage? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            return nil
        }
        return page.thumbnail(of: maxSize, for: .mediaBox)
    }

    private static func thumbnailTargetSize(for originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scale = max(widthRatio, heightRatio)
        return CGSize(width: originalSize.width * scale, height: originalSize.height * scale)
    }
}
