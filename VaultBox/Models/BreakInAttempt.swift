import SwiftData
import Foundation

@Model
final class BreakInAttempt {
    var id: UUID
    var intruderPhotoData: Data?
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var attemptedPIN: String

    init(attemptedPIN: String) {
        self.id = UUID()
        self.attemptedPIN = attemptedPIN
        self.timestamp = Date()
    }
}
