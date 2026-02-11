import SwiftData
import Foundation

@Model
final class AppSettings {
    var id: UUID = UUID()
    var isSetupComplete: Bool = false
    var pinHash: String = ""
    var pinSalt: String = ""
    var biometricsEnabled: Bool = false
    var decoyPINHash: String?
    var decoyPINSalt: String?
    var freeItemLimit: Int = Constants.freeItemLimit
    var selectedAltIconName: String?
    var iCloudBackupEnabled: Bool = false
    var autoLockSeconds: Int = 0
    var panicGestureEnabled: Bool = false
    var breakInAlertsEnabled: Bool = true
    var lastUnlockedAt: Date?
    var pinLength: Int = Constants.pinMinLength
    var failedAttemptCount: Int = 0
    var lockoutUntil: Date?
    var importCount: Int = 0
    var themeMode: String = "system" // "system", "light", "dark"

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
        self.pinLength = Constants.pinMinLength
        self.failedAttemptCount = 0
        self.importCount = 0
        self.themeMode = "system"
    }
}
