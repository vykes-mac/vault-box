import SwiftData
import Foundation

// MARK: - Panic Action

enum PanicAction: String, CaseIterable, Identifiable {
    case lockOnly = "lockOnly"
    case launchMusic = "launchMusic"
    case launchMessages = "launchMessages"
    case launchSafari = "launchSafari"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lockOnly: "Lock Only"
        case .launchMusic: "Open Music"
        case .launchMessages: "Open Messages"
        case .launchSafari: "Open Safari"
        }
    }

    var systemImage: String {
        switch self {
        case .lockOnly: "lock.fill"
        case .launchMusic: "music.note"
        case .launchMessages: "message.fill"
        case .launchSafari: "safari"
        }
    }

    var appURL: URL? {
        switch self {
        case .lockOnly: nil
        case .launchMusic: URL(string: "music://")
        case .launchMessages: URL(string: "sms://")
        case .launchSafari: URL(string: "https://apple.com")
        }
    }
}

@Model
final class AppSettings {
    var id: UUID = UUID()
    var isSetupComplete: Bool = false
    var pinHash: String = ""
    var pinSalt: String = ""
    var biometricsEnabled: Bool = false
    var decoyPINHash: String?
    var decoyPINSalt: String?
    var recoveryCodeHash: String?
    var recoveryCodeSalt: String?
    var recoveryCodeUsedAt: Date?
    var freeItemLimit: Int = Constants.freeItemLimit
    var selectedAltIconName: String?
    var iCloudBackupEnabled: Bool = false
    var autoLockSeconds: Int = 0
    var panicGestureEnabled: Bool = false
    var panicAction: String = "lockOnly"
    var breakInAlertsEnabled: Bool = true
    var lastUnlockedAt: Date?
    var pinLength: Int = Constants.pinMinLength
    var failedAttemptCount: Int = 0
    var lockoutUntil: Date?
    var importCount: Int = 0
    var hasCompletedOnboarding: Bool = false
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
        self.panicAction = "lockOnly"
        self.breakInAlertsEnabled = true
        self.pinLength = Constants.pinMinLength
        self.failedAttemptCount = 0
        self.importCount = 0
        self.hasCompletedOnboarding = false
        self.themeMode = "system"
    }
}
