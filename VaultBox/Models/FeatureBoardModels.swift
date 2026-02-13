import Foundation

enum FeatureVoteValue: Int, Sendable {
    case down = -1
    case up = 1
}

struct FeatureRequestDTO: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let details: String
    let status: String
    let upVotes: Int
    let downVotes: Int
    let score: Int
    let createdAt: Date
}
