import SwiftUI

enum Constants {

    // MARK: - Free Tier

    static let freeItemLimit = 25

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
    static let cloudKeyBackupRecordType = "VaultKeyBackup"
    static let featureRequestRecordType = "FeatureRequest"
    static let featureVoteRecordType = "FeatureVote"

    // MARK: - Wi-Fi Transfer

    static let wifiTransferPort: UInt16 = 8080
    static let wifiTransferTimeoutMinutes = 10
    static let wifiTransferMaxRequestBytes = 250 * 1024 * 1024
    static let maxVideoImportBytes = 250 * 1024 * 1024

    // MARK: - RevenueCat

    static let revenueCatAPIKey: String = Bundle.main.infoDictionary?["RevenueCatAPIKey"] as? String ?? ""
    static let primaryOfferingID = "default"
    static let premiumEntitlementID = "VaultBox Premium"
    static let weeklyProductID = "vaultbox_premium_weekly"
    static let annualProductID = "vaultbox_premium_annual"

    // MARK: - App Store

    static let appStoreURL = "https://apps.apple.com/app/id6758970966"

    // MARK: - Rate Prompt

    static let ratePromptImportThreshold = 10

    // MARK: - Vision Analysis

    static let visionAnalysisTimeout: TimeInterval = 3.0
    static let visionAnalysisMaxDimension: CGFloat = 2048
    static let visionSceneClassificationMinConfidence: Float = 0.55
    static let visionSceneClassificationMaxLabels: Int = 8
    static let visionSceneClassificationFallbackMaxDimension: CGFloat = 1024

    // MARK: - Time-Limited Sharing

    static let sharedFileRecordType = "SharedFile"
    static let shareBaseURL = "https://vaultbox.pacsix.com/s"

    /// Duration options for time-limited sharing (in seconds).
    static let shareDurations: [(label: String, seconds: TimeInterval)] = [
        ("1 Minute", 60),
        ("5 Minutes", 300),
        ("30 Minutes", 1800),
        ("1 Hour", 3600),
        ("24 Hours", 86400),
        ("7 Days", 604800)
    ]

    // MARK: - Document Storage

    static let maxDocumentImportBytes = 100 * 1024 * 1024 // 100 MB

    // MARK: - Ask My Vault

    static let searchIndexDatabaseName = "search_index.db"
    static let chunkTargetWords = 175
    static let chunkMaxWords = 200
    static let chunkMinWords = 20
    static let chunkOverlapWords = 30
    static let embeddingDimension = 384
    static let searchFTSWeight: Float = 0.4
    static let searchVectorWeight: Float = 0.6
    static let searchMaxResults = 10
    static let searchDebounceMs = 300
    /// Minimum cosine similarity for a vector result to be considered relevant.
    /// MiniLM L2-normalized embeddings produce dot products in [-1, 1].
    /// Matches above ~0.35 are typically topically related.
    static let searchMinVectorScore: Float = 0.3
    /// Minimum combined hybrid score (after merge) to be shown to the user.
    /// Prevents showing irrelevant results when nothing in the vault matches.
    static let searchMinCombinedScore: Float = 0.25
    static let ocrMinCharsForTextPage = 50
    static let bgTaskIdentifier = "com.vaultbox.searchIndexing"
    static let tokenizerMaxLength = 128

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
