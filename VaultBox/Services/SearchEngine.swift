import Foundation

// MARK: - SearchResult

struct SearchResult: Sendable, Identifiable {
    let id: Int64  // chunk ID
    let itemID: UUID
    let textExcerpt: String
    let pageNumber: Int?
    let score: Float
    let matchType: MatchType

    enum MatchType: Sendable {
        case keyword
        case semantic
        case hybrid
    }
}

// MARK: - SearchEngine

actor SearchEngine {
    private let searchIndexService: SearchIndexService
    private let embeddingService: EmbeddingService

    init(searchIndexService: SearchIndexService, embeddingService: EmbeddingService) {
        self.searchIndexService = searchIndexService
        self.embeddingService = embeddingService
    }

    /// Performs hybrid FTS + vector search, merges and ranks results.
    func search(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. Run FTS5 keyword search
        let ftsResults = try await searchIndexService.ftsSearch(query: trimmed, limit: 20)

        // 2. Run vector search
        var vectorResults: [(chunkID: Int64, itemID: UUID, text: String, pageNumber: Int?, score: Float)] = []
        do {
            try await embeddingService.loadModel()
            let queryVector = try await embeddingService.embed(trimmed)
            let allEmbeddings = try await searchIndexService.loadAllEmbeddings()

            if !allEmbeddings.isEmpty {
                let candidates = allEmbeddings.map { $0.vector }
                let scores = VectorMath.batchDotProduct(query: queryVector, candidates: candidates)

                var scored: [(index: Int, score: Float)] = []
                for (i, score) in scores.enumerated() {
                    // Filter out chunks below the minimum cosine similarity threshold
                    if score >= Constants.searchMinVectorScore {
                        scored.append((i, score))
                    }
                }
                scored.sort { $0.score > $1.score }
                let topK = scored.prefix(20)

                for item in topK {
                    let record = allEmbeddings[item.index]
                    if let detail = try? await searchIndexService.chunkDetail(for: record.chunkID) {
                        vectorResults.append((
                            chunkID: record.chunkID,
                            itemID: record.itemID,
                            text: detail.text,
                            pageNumber: detail.pageNumber,
                            score: item.score
                        ))
                    }
                }
            }
        } catch {
            debugLog("Vector search failed: \(error). Falling back to FTS-only results.")
        }

        // 3. Merge and rank
        return mergeResults(ftsResults: ftsResults, vectorResults: vectorResults)
    }

    // MARK: - Merge & Rank

    private func mergeResults(
        ftsResults: [FTSResult],
        vectorResults: [(chunkID: Int64, itemID: UUID, text: String, pageNumber: Int?, score: Float)]
    ) -> [SearchResult] {
        // Normalize FTS scores to [0, 1] range.
        // BM25 rank is negative — more negative = better match.
        // We use min-max normalization but only among results that FTS already
        // deemed relevant enough to return (SQLite FTS5 already filters).
        let ftsScores: [Int64: Float]
        if ftsResults.isEmpty {
            ftsScores = [:]
        } else {
            let ranks = ftsResults.map { Float($0.rank) }
            let minRank = ranks.min() ?? 0
            let maxRank = ranks.max() ?? 0
            let range = maxRank - minRank

            if range > 0 {
                // More negative = better match, so invert: best match gets score 1.0
                ftsScores = Dictionary(
                    ftsResults.map { ($0.chunkID, (maxRank - Float($0.rank)) / range) },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                ftsScores = Dictionary(
                    ftsResults.map { ($0.chunkID, Float(1.0)) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }

        // Use raw cosine similarity as vector scores (already in [0, 1] for
        // L2-normalized embeddings with positive similarity). This preserves
        // the absolute relevance signal — low-similarity results won't be
        // inflated by min-max normalization.
        let vecScores: [Int64: Float] = Dictionary(
            vectorResults.map { ($0.chunkID, $0.score) },
            uniquingKeysWith: { first, _ in first }
        )

        // Collect all unique chunk IDs
        var allChunkIDs = Set<Int64>()
        let ftsLookup = Dictionary(ftsResults.map { ($0.chunkID, $0) }, uniquingKeysWith: { first, _ in first })
        let vecLookup = Dictionary(vectorResults.map { ($0.chunkID, $0) }, uniquingKeysWith: { first, _ in first })

        for result in ftsResults { allChunkIDs.insert(result.chunkID) }
        for result in vectorResults { allChunkIDs.insert(result.chunkID) }

        // Compute combined scores
        var merged: [SearchResult] = []
        for chunkID in allChunkIDs {
            let fScore = ftsScores[chunkID] ?? 0
            let vScore = vecScores[chunkID] ?? 0
            let combined = fScore * Constants.searchFTSWeight + vScore * Constants.searchVectorWeight

            // Skip results below the minimum relevance threshold
            guard combined >= Constants.searchMinCombinedScore else { continue }

            let matchType: SearchResult.MatchType
            if fScore > 0 && vScore > 0 {
                matchType = .hybrid
            } else if fScore > 0 {
                matchType = .keyword
            } else {
                matchType = .semantic
            }

            // Get text and metadata
            let text: String
            let itemID: UUID
            let pageNumber: Int?

            if let fts = ftsLookup[chunkID] {
                text = fts.textContent
                itemID = fts.itemID
                pageNumber = fts.pageNumber
            } else if let vec = vecLookup[chunkID] {
                text = vec.text
                itemID = vec.itemID
                pageNumber = vec.pageNumber
            } else {
                continue
            }

            merged.append(SearchResult(
                id: chunkID,
                itemID: itemID,
                textExcerpt: text,
                pageNumber: pageNumber,
                score: combined,
                matchType: matchType
            ))
        }

        // Sort by score descending
        merged.sort { $0.score > $1.score }

        // Deduplicate: keep highest-scoring chunk per vault item
        var seenItems = Set<UUID>()
        var deduplicated: [SearchResult] = []
        for result in merged {
            if seenItems.insert(result.itemID).inserted {
                deduplicated.append(result)
            }
        }

        return Array(deduplicated.prefix(Constants.searchMaxResults))
    }

    // MARK: - Helpers

    private nonisolated func debugLog(_ message: String) {
        #if DEBUG
        print("[SearchEngine] \(message)")
        #endif
    }
}
