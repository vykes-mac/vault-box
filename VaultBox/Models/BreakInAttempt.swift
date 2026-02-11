import SwiftData
import Foundation

@Model
final class BreakInAttempt {
    var id: UUID = UUID()
    var intruderPhotoData: Data?
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date = Date()
    var attemptedPIN: String = ""

    init(attemptedPIN: String) {
        self.id = UUID()
        self.attemptedPIN = attemptedPIN
        self.timestamp = Date()
    }
}
