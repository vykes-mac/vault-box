import Foundation

// MARK: - ChunkingEngine

enum ChunkingEngine {

    struct PageInput: Sendable {
        let text: String
        let pageNumber: Int?  // nil for single-page items (images)
    }

    /// Splits page-segmented text into overlapping chunks.
    /// Pages are chunked independently (never merges across page boundaries).
    static func chunk(pages: [PageInput]) -> [TextChunk] {
        var allChunks: [TextChunk] = []
        var globalChunkIndex = 0

        for page in pages {
            let trimmed = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let words = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= Constants.chunkMinWords else {
                // Too short to split — emit as a single chunk
                allChunks.append(TextChunk(
                    chunkIndex: globalChunkIndex,
                    pageNumber: page.pageNumber,
                    textContent: trimmed,
                    wordCount: words.count
                ))
                globalChunkIndex += 1
                continue
            }

            let pageChunks = chunkWords(
                words,
                pageNumber: page.pageNumber,
                startChunkIndex: globalChunkIndex
            )
            allChunks.append(contentsOf: pageChunks)
            globalChunkIndex += pageChunks.count
        }

        return allChunks
    }

    // MARK: - Sliding Window Chunking

    private static func chunkWords(
        _ words: [String],
        pageNumber: Int?,
        startChunkIndex: Int
    ) -> [TextChunk] {
        var chunks: [TextChunk] = []
        var position = 0
        var chunkIndex = startChunkIndex

        while position < words.count {
            let targetEnd = min(position + Constants.chunkTargetWords, words.count)
            var endPosition = targetEnd

            // Look ahead for a sentence boundary within target..max range
            if endPosition < words.count {
                let maxEnd = min(position + Constants.chunkMaxWords, words.count)
                if let sentenceEnd = findSentenceBoundary(in: words, from: targetEnd, to: maxEnd) {
                    endPosition = sentenceEnd
                }
            }

            // Hard cap at max words
            endPosition = min(endPosition, position + Constants.chunkMaxWords)
            endPosition = min(endPosition, words.count)

            let chunkWords = Array(words[position..<endPosition])
            let text = chunkWords.joined(separator: " ")

            chunks.append(TextChunk(
                chunkIndex: chunkIndex,
                pageNumber: pageNumber,
                textContent: text,
                wordCount: chunkWords.count
            ))
            chunkIndex += 1

            // Advance by chunk length minus overlap
            let advance = max(1, chunkWords.count - Constants.chunkOverlapWords)
            position += advance

            // If remaining words after advance would be too short, extend previous chunk
            if position < words.count && (words.count - position) < Constants.chunkMinWords {
                // Merge remaining words into the last chunk
                let remainingWords = Array(words[position...])
                let mergedText = text + " " + remainingWords.joined(separator: " ")
                chunks[chunks.count - 1] = TextChunk(
                    chunkIndex: chunks[chunks.count - 1].chunkIndex,
                    pageNumber: pageNumber,
                    textContent: mergedText,
                    wordCount: chunkWords.count + remainingWords.count
                )
                break
            }
        }

        return chunks
    }

    /// Looks for a sentence boundary (period, question mark, exclamation, newline)
    /// in the word range [from..<to]. Returns the position after the sentence-ending word.
    private static func findSentenceBoundary(in words: [String], from: Int, to: Int) -> Int? {
        for i in from..<to where i < words.count {
            let word = words[i]
            if word.hasSuffix(".") || word.hasSuffix("?") || word.hasSuffix("!") || word.hasSuffix("\n") {
                return i + 1
            }
        }
        return nil
    }
}
