import Foundation

// MARK: - WordPieceTokenizer

final class WordPieceTokenizer: Sendable {
    private let vocab: [String: Int32]
    private let unkTokenID: Int32
    private let clsTokenID: Int32
    private let sepTokenID: Int32
    private let padTokenID: Int32

    init(vocabFileURL: URL) throws {
        let content = try String(contentsOf: vocabFileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        var vocab: [String: Int32] = [:]
        vocab.reserveCapacity(lines.count)
        for (index, token) in lines.enumerated() {
            vocab[token] = Int32(index)
        }
        self.vocab = vocab

        guard let unk = vocab["[UNK]"],
              let cls = vocab["[CLS]"],
              let sep = vocab["[SEP]"],
              let pad = vocab["[PAD]"] else {
            throw TokenizerError.missingSpecialTokens
        }
        self.unkTokenID = unk
        self.clsTokenID = cls
        self.sepTokenID = sep
        self.padTokenID = pad
    }

    /// Tokenizes text into token IDs for MiniLM model input.
    /// Returns array of token IDs padded/truncated to maxLength.
    func tokenize(_ text: String, maxLength: Int = Constants.tokenizerMaxLength) -> [Int32] {
        let normalized = text.lowercased()
        let words = basicTokenize(normalized)

        var tokenIDs: [Int32] = [clsTokenID]
        let maxContentTokens = maxLength - 2  // Reserve space for [CLS] and [SEP]

        for word in words {
            guard tokenIDs.count - 1 < maxContentTokens else { break }

            let subTokens = wordPieceSplit(word)
            for subToken in subTokens {
                guard tokenIDs.count - 1 < maxContentTokens else { break }
                tokenIDs.append(vocab[subToken] ?? unkTokenID)
            }
        }

        tokenIDs.append(sepTokenID)

        // Pad to maxLength
        while tokenIDs.count < maxLength {
            tokenIDs.append(padTokenID)
        }

        return tokenIDs
    }

    /// Creates attention mask for token IDs (1 for real tokens, 0 for padding).
    func attentionMask(for tokenIDs: [Int32]) -> [Int32] {
        tokenIDs.map { $0 != padTokenID ? Int32(1) : Int32(0) }
    }

    // MARK: - Basic Tokenization

    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in text {
            if char.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if isPunctuation(char) {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    // MARK: - WordPiece Subword Splitting

    private func wordPieceSplit(_ word: String) -> [String] {
        if vocab[word] != nil {
            return [word]
        }

        var tokens: [String] = []
        var start = word.startIndex
        var isFirst = true

        while start < word.endIndex {
            var end = word.endIndex
            var found: String?

            while start < end {
                let substr = String(word[start..<end])
                let candidate = isFirst ? substr : "##\(substr)"

                if vocab[candidate] != nil {
                    found = candidate
                    break
                }

                // Move end back one character
                end = word.index(before: end)
            }

            if let found {
                tokens.append(found)
                start = end
                isFirst = false
            } else {
                // Unknown subword — mark entire remaining as [UNK]
                tokens.append("[UNK]")
                break
            }
        }

        return tokens
    }

    // MARK: - Helpers

    private func isPunctuation(_ char: Character) -> Bool {
        let scalar = char.unicodeScalars.first!
        let category = scalar.properties.generalCategory
        switch category {
        case .connectorPunctuation, .dashPunctuation, .closePunctuation,
             .finalPunctuation, .initialPunctuation, .otherPunctuation,
             .openPunctuation:
            return true
        default:
            return false
        }
    }
}

// MARK: - Errors

enum TokenizerError: Error, LocalizedError {
    case missingSpecialTokens

    var errorDescription: String? {
        switch self {
        case .missingSpecialTokens:
            return "Vocabulary file is missing required special tokens ([CLS], [SEP], [UNK], [PAD])"
        }
    }
}
