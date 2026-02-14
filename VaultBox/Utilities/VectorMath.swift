import Foundation
import Accelerate

// MARK: - VectorMath

enum VectorMath {

    /// Dot product of two vectors using Accelerate SIMD operations.
    /// For L2-normalized vectors, this equals cosine similarity.
    static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "Vectors must have equal length")
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    /// Computes dot products between a query vector and an array of candidate vectors.
    /// Returns array of similarity scores in the same order as candidates.
    static func batchDotProduct(query: [Float], candidates: [[Float]]) -> [Float] {
        candidates.map { dotProduct(query, $0) }
    }

    /// L2-normalizes a vector in place so its magnitude equals 1.0.
    /// After normalization, dot product equals cosine similarity.
    static func l2Normalize(_ vector: inout [Float]) {
        var sumOfSquares: Float = 0
        vDSP_svesq(vector, 1, &sumOfSquares, vDSP_Length(vector.count))

        let magnitude = sqrt(sumOfSquares)
        guard magnitude > 0 else { return }

        var divisor = magnitude
        vDSP_vsdiv(vector, 1, &divisor, &vector, 1, vDSP_Length(vector.count))
    }
}
