import Foundation
import CoreML

// MARK: - EmbeddingService

actor EmbeddingService {
    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?

    /// Loads the Core ML model and tokenizer from app bundle.
    func loadModel() throws {
        guard model == nil else { return }

        guard let modelURL = Bundle.main.url(forResource: "MiniLM", withExtension: "mlmodelc") else {
            throw EmbeddingError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        model = try MLModel(contentsOf: modelURL, configuration: config)

        guard let vocabURL = Bundle.main.url(forResource: "vocab", withExtension: "txt") else {
            throw EmbeddingError.vocabNotFound
        }
        tokenizer = try WordPieceTokenizer(vocabFileURL: vocabURL)
    }

    /// Unloads the model to free memory (~80MB). Call after batch processing completes.
    func unloadModel() {
        model = nil
        tokenizer = nil
    }

    /// Embeds a single text string, returning a 384-dimensional float vector.
    func embed(_ text: String) throws -> [Float] {
        guard let model, let tokenizer else {
            throw EmbeddingError.modelNotLoaded
        }

        let maxLength = Constants.tokenizerMaxLength
        let tokenIDs = tokenizer.tokenize(text, maxLength: maxLength)
        let attentionMask = tokenizer.attentionMask(for: tokenIDs)

        // Create MLMultiArray inputs
        let inputIDs = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)
        let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxLength)], dataType: .int32)

        for i in 0..<maxLength {
            inputIDs[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: tokenIDs[i])
            maskArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: attentionMask[i])
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: maskArray)
        ])

        let output = try model.prediction(from: provider)

        // Extract embedding from output (expected shape: [1, 384])
        guard let embeddingFeature = output.featureValue(for: "embeddings")
                ?? output.featureValue(for: "last_hidden_state")
                ?? output.featureValue(for: "sentence_embedding"),
              let embeddingArray = embeddingFeature.multiArrayValue else {
            throw EmbeddingError.unexpectedOutput
        }

        var vector = extractVector(from: embeddingArray)

        // L2-normalize so dot product equals cosine similarity
        VectorMath.l2Normalize(&vector)

        return vector
    }

    /// Embeds multiple texts sequentially. More memory-efficient for batch operations.
    func embedBatch(_ texts: [String]) throws -> [[Float]] {
        try texts.map { try embed($0) }
    }

    // MARK: - Helpers

    private func extractVector(from multiArray: MLMultiArray) -> [Float] {
        let dimension = Constants.embeddingDimension
        let totalCount = multiArray.count

        if totalCount == dimension {
            // Shape [384] — direct embedding
            return (0..<dimension).map { multiArray[$0].floatValue }
        } else if totalCount == dimension * Constants.tokenizerMaxLength {
            // Shape [1, 128, 384] — need mean pooling over token dimension
            return meanPool(multiArray, sequenceLength: Constants.tokenizerMaxLength, dimension: dimension)
        } else if totalCount >= dimension {
            // Shape [1, 384] — take first 384 values
            return (0..<dimension).map { multiArray[$0].floatValue }
        }

        // Fallback: take what we can
        let count = min(totalCount, dimension)
        var vector = (0..<count).map { multiArray[$0].floatValue }
        while vector.count < dimension {
            vector.append(0)
        }
        return vector
    }

    /// Mean pooling: average the token embeddings to get a sentence embedding.
    private func meanPool(_ multiArray: MLMultiArray, sequenceLength: Int, dimension: Int) -> [Float] {
        var result = [Float](repeating: 0, count: dimension)
        for tokenIdx in 0..<sequenceLength {
            for dimIdx in 0..<dimension {
                let index = tokenIdx * dimension + dimIdx
                result[dimIdx] += multiArray[index].floatValue
            }
        }
        let divisor = Float(sequenceLength)
        for i in 0..<dimension {
            result[i] /= divisor
        }
        return result
    }
}

// MARK: - Errors

enum EmbeddingError: Error, LocalizedError {
    case modelNotFound
    case vocabNotFound
    case modelNotLoaded
    case unexpectedOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "MiniLM.mlmodelc not found in app bundle"
        case .vocabNotFound: return "vocab.txt not found in app bundle"
        case .modelNotLoaded: return "Embedding model not loaded. Call loadModel() first."
        case .unexpectedOutput: return "Unexpected model output format"
        }
    }
}
