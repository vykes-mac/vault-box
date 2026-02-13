import Foundation

enum FeatureVoteValue: Int, Sendable {
    case down = -1
    case up = 1
}

enum FeatureStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case inProgress = "in_progress"
    case closed
}

struct FeatureRequestDTO: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let details: String
    let status: FeatureStatus
    let upVotes: Int
    let downVotes: Int
    let score: Int
    let createdAt: Date
}
