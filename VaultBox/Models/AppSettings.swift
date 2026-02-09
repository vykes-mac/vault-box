import SwiftData
import Foundation

@Model
final class AppSettings {
    var id: UUID
    var isSetupComplete: Bool
    var pinHash: String
    var pinSalt: String
    var biometricsEnabled: Bool
    var decoyPINHash: String?
    var decoyPINSalt: String?
    var freeItemLimit: Int
    var selectedAltIconName: String?
    var iCloudBackupEnabled: Bool
    var autoLockSeconds: Int
    var panicGestureEnabled: Bool
    var breakInAlertsEnabled: Bool
    var lastUnlockedAt: Date?
    var failedAttemptCount: Int
    var lockoutUntil: Date?

    init(pinHash: String = "", pinSalt: String = "") {
        self.id = UUID()
        self.isSetupComplete = false
        self.pinHash = pinHash
        self.pinSalt = pinSalt
        self.biometricsEnabled = false
        self.freeItemLimit = Constants.freeItemLimit
        self.iCloudBackupEnabled = false
        self.autoLockSeconds = 0
        self.panicGestureEnabled = false
        self.breakInAlertsEnabled = true
        self.failedAttemptCount = 0
    }
}
