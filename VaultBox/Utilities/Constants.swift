import SwiftUI

enum Constants {

    // MARK: - Free Tier

    static let freeItemLimit = 50

    // MARK: - Encryption

    static let masterKeySize = 32 // 256-bit
    static let nonceSizeBytes = 12
    static let gcmTagSizeBytes = 16
    static let pinSaltSize = 32
    static let thumbnailMaxSize = CGSize(width: 300, height: 300)
    static let thumbnailJPEGQuality: CGFloat = 0.7

    // MARK: - PIN

    static let pinMinLength = 4
    static let pinMaxLength = 8

    // MARK: - Lockout Thresholds

    static let lockoutThresholds: [(attempts: Int, seconds: Int)] = [
        (3, 30),
        (5, 120),
        (8, 900),
        (10, 3600)
    ]
    static let breakInCaptureThreshold = 3

    // MARK: - Break-In

    static let maxBreakInAttempts = 20

    // MARK: - Auto-Lock Options (seconds)

    static let autoLockOptions: [(label: String, seconds: Int)] = [
        ("Immediately", 0),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300)
    ]

    // MARK: - Grid Layout

    static let vaultGridColumns = 3
    static let vaultGridSpacing: CGFloat = 1
    static let albumGridColumns = 2
    static let standardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 24
    static let cardCornerRadius: CGFloat = 12
    static let thumbnailCornerRadius: CGFloat = 4

    // MARK: - Keypad

    static let keypadButtonSize: CGFloat = 75

    // MARK: - Photo Zoom

    static let maxZoomScale: CGFloat = 5.0
    static let doubleTapZoomScale: CGFloat = 2.0

    // MARK: - Animation

    static let pinSuccessDelay: TimeInterval = 0.3
    static let pinShakeDuration: TimeInterval = 0.5

    // MARK: - Cloud

    static let cloudRecordType = "EncryptedVaultItem"

    // MARK: - Wi-Fi Transfer

    static let wifiTransferPort: UInt16 = 8080
    static let wifiTransferTimeoutMinutes = 10

    // MARK: - RevenueCat

    static let revenueCatAPIKey: String = Bundle.main.infoDictionary?["RevenueCatAPIKey"] as? String ?? ""
    static let primaryOfferingID = "default"
    static let premiumEntitlementID = "VaultBox Premium"
    static let weeklyProductID = "vaultbox_premium_weekly"
    static let annualProductID = "vaultbox_premium_annual"

    // MARK: - Rate Prompt

    static let ratePromptImportThreshold = 10

    // MARK: - Vision Analysis

    static let visionAnalysisTimeout: TimeInterval = 3.0

    // MARK: - File Storage

    static let vaultDataDirectory = "VaultData"
    static let filesSubdirectory = "files"
    static let thumbnailsSubdirectory = "thumbnails"
    static let encryptedFileExtension = "enc"

    // MARK: - Keychain Keys

    static let keychainMasterKeyID = "com.vaultbox.masterKey"
    static let keychainServiceID = "com.vaultbox.app"
}

// MARK: - Notifications

extension Notification.Name {
    static let themeDidChange = Notification.Name("com.vaultbox.themeDidChange")
}

// MARK: - Colors

extension Color {
    static let vaultBackground = Color("background")
    static let vaultSurface = Color("surface")
    static let vaultSurfaceSecondary = Color("surfaceSecondary")
    static let vaultTextPrimary = Color("textPrimary")
    static let vaultTextSecondary = Color("textSecondary")
    static let vaultAccent = Color("accent")
    static let vaultDestructive = Color("destructive")
    static let vaultSuccess = Color("success")
    static let vaultPremium = Color("premium")
}
