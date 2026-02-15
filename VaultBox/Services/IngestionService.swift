import Foundation
import PDFKit

// MARK: - Data Types

struct IngestionInput: Sendable {
    let itemID: UUID
    let encryptedFileRelativePath: String
    let itemType: String  // "photo", "video", "document"
    let originalFilename: String
}

struct IngestionResult: Sendable {
    let itemID: UUID
    let success: Bool
    let chunkCount: Int
    let totalPages: Int?
    let extractedTextPreview: String?
}

// MARK: - IndexingProgress

@MainActor
@Observable
class IndexingProgress {
    var totalItems: Int = 0
    var completedItems: Int = 0
    var currentItemName: String?
    var isIndexing: Bool = false

    var fractionComplete: Double {
        guard totalItems > 0 else { return 0 }
        return Double(completedItems) / Double(totalItems)
    }
}

// MARK: - IngestionService

actor IngestionService {
    private let encryptionService: EncryptionService
    private let searchIndexService: SearchIndexService
    private let embeddingService: EmbeddingService
    private(set) var isProcessing = false

    init(
        encryptionService: EncryptionService,
        searchIndexService: SearchIndexService,
        embeddingService: EmbeddingService
    ) {
        self.encryptionService = encryptionService
        self.searchIndexService = searchIndexService
        self.embeddingService = embeddingService
    }

    /// Process a single vault item.
    func indexItem(_ input: IngestionInput) async -> IngestionResult {
        isProcessing = true
        defer { isProcessing = false }
        return await processItem(input)
    }

    /// Process a batch of unindexed items sequentially.
    /// Calls onProgress after each item completes.
    func indexBatch(
        _ inputs: [IngestionInput],
        onProgress: @escaping @Sendable (IngestionResult) -> Void
    ) async {
        guard !inputs.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        // Load embedding model once for the entire batch
        do {
            try await embeddingService.loadModel()
        } catch {
            debugLog("Failed to load embedding model: \(error)")
            // Continue — chunks will be stored without embeddings (FTS still works)
        }

        for input in inputs {
            guard !Task.isCancelled else { break }
            let result = await processItem(input)
            onProgress(result)
        }

        // Unload model to free memory after batch
        await embeddingService.unloadModel()
    }

    /// Remove all index data for a deleted item.
    func removeItem(itemID: UUID) async {
        do {
            try await searchIndexService.deleteChunks(for: itemID)
        } catch {
            debugLog("Failed to remove index for \(itemID): \(error)")
        }
    }

    /// Remove all index data.
    func removeAllData() async {
        do {
            try await searchIndexService.deleteAllData()
        } catch {
            debugLog("Failed to remove all index data: \(error)")
        }
    }

    // MARK: - Item Processing

    private func processItem(_ input: IngestionInput) async -> IngestionResult {
        // Skip videos in v1
        guard input.itemType != "video" else {
            return IngestionResult(
                itemID: input.itemID,
                success: true,
                chunkCount: 0,
                totalPages: nil,
                extractedTextPreview: nil
            )
        }

        // 1. Decrypt file
        var fileData: Data
        do {
            let vaultDir = try await encryptionService.vaultFilesDirectory()
            let fileURL = vaultDir.appendingPathComponent(input.encryptedFileRelativePath)
            fileData = try await encryptionService.decryptFile(at: fileURL)
        } catch {
            debugLog("Decrypt failed for \(input.itemID): \(error)")
            return IngestionResult(
                itemID: input.itemID,
                success: false,
                chunkCount: 0,
                totalPages: nil,
                extractedTextPreview: nil
            )
        }
        defer { wipeData(&fileData) }

        // 2. Extract text
        let isPDF = input.originalFilename.lowercased().hasSuffix(".pdf")
        var pages: [ChunkingEngine.PageInput] = []
        var totalPages: Int?

        if input.itemType == "document" && isPDF {
            let result = PDFTextExtractor.extract(from: fileData)
            totalPages = result.totalPages
            pages = result.pages.map { ChunkingEngine.PageInput(text: $0.text, pageNumber: $0.pageNumber) }
        } else {
            // Photo or image-based document
            if let text = ImageOCRExtractor.extract(from: fileData) {
                pages = [ChunkingEngine.PageInput(text: text, pageNumber: nil)]
            }
        }

        guard !pages.isEmpty else {
            debugLog("No text extracted for \(input.itemID)")
            return IngestionResult(
                itemID: input.itemID,
                success: false,
                chunkCount: 0,
                totalPages: totalPages,
                extractedTextPreview: nil
            )
        }

        // 3. Generate preview from first page text
        let fullText = pages.map(\.text).joined(separator: " ")
        let preview = String(fullText.prefix(200))

        // 4. Chunk text
        let chunks = ChunkingEngine.chunk(pages: pages)
        guard !chunks.isEmpty else {
            return IngestionResult(
                itemID: input.itemID,
                success: true,
                chunkCount: 0,
                totalPages: totalPages,
                extractedTextPreview: preview
            )
        }

        // 5. Insert chunks into search index
        let rowIDs: [Int64]
        do {
            rowIDs = try await searchIndexService.insertChunks(chunks, for: input.itemID)
        } catch {
            debugLog("Failed to insert chunks for \(input.itemID): \(error)")
            return IngestionResult(
                itemID: input.itemID,
                success: false,
                chunkCount: 0,
                totalPages: totalPages,
                extractedTextPreview: preview
            )
        }

        // 6. Generate and store embeddings (best effort — FTS works without them)
        for (index, chunk) in chunks.enumerated() {
            guard index < rowIDs.count else { break }
            do {
                let vector = try await embeddingService.embed(chunk.textContent)
                try await searchIndexService.insertEmbedding(chunkID: rowIDs[index], vector: vector)
            } catch {
                debugLog("Embedding failed for chunk \(index) of \(input.itemID): \(error)")
                // Continue — FTS still works
            }
        }

        debugLog("Indexed \(input.itemID): \(chunks.count) chunks, \(totalPages ?? 1) pages")

        return IngestionResult(
            itemID: input.itemID,
            success: true,
            chunkCount: chunks.count,
            totalPages: totalPages,
            extractedTextPreview: preview
        )
    }

    // MARK: - Helpers

    private func wipeData(_ data: inout Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeMutableBytes { buffer in
            guard !buffer.isEmpty else { return }
            _ = buffer.initializeMemory(as: UInt8.self, repeating: 0)
        }
        data.removeAll(keepingCapacity: false)
    }

    private nonisolated func debugLog(_ message: String) {
        #if DEBUG
        print("[IngestionService] \(message)")
        #endif
    }
}
