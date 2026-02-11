# VaultBox — Product Requirements Document

> **Purpose:** This document is the single source of truth for building VaultBox, a private photo vault iOS app. It is designed to be consumed by an AI coding agent (Claude Code) to implement the full application.

-----

## Table of Contents

1. [Project Overview](#1-project-overview)
1. [Technical Stack & Setup](#2-technical-stack--setup)
1. [Project Structure](#3-project-structure)
1. [Data Models](#4-data-models)
1. [Core Services](#5-core-services)
1. [Screens & Navigation](#6-screens--navigation)
1. [Feature Specifications](#7-feature-specifications)
1. [Paywall & Monetization](#8-paywall--monetization)
1. [App Store Configuration](#9-app-store-configuration)
1. [Testing Requirements](#10-testing-requirements)
1. [Implementation Order](#11-implementation-order)

-----

## 1. Project Overview

### What We’re Building

VaultBox is a photo and video vault app for iOS. Users import photos/videos from their Camera Roll into an encrypted, PIN/biometric-protected vault. The app encrypts all media locally using AES-256-GCM before storing it. Premium users get unlimited storage, iCloud encrypted backup, decoy vaults, fake app icons, and more.

### Core Value Proposition

- **Privacy-first:** AES-256 encryption, all processing on-device, iCloud-native backup (no proprietary servers)
- **Modern design:** SwiftUI, iOS 17+ design language, smooth animations
- **Fair pricing:** Generous free tier (50 items), $24.99/year premium

### Target User

Anyone who wants to hide private photos/videos behind a separate lock from their device passcode. Primary demographics: ages 18–35, privacy-conscious, global market.

-----

## 2. Technical Stack & Setup

### Requirements

|Requirement |Value                                  |
|------------|---------------------------------------|
|Language    |Swift 6                                |
|UI Framework|SwiftUI                                |
|Minimum iOS |17.0                                   |
|Xcode       |16.0+                                  |
|Architecture|MVVM with Services layer               |
|Concurrency |Swift Concurrency (async/await, actors)|

### Dependencies (Swift Package Manager only)

|Package       |Purpose                                   |URL                                                 |
|--------------|------------------------------------------|----------------------------------------------------|
|RevenueCat    |In-app purchases & subscription management|`https://github.com/RevenueCat/purchases-ios`       |
|KeychainAccess|Secure keychain storage for master key    |`https://github.com/kishikawakatsumi/KeychainAccess`|


> **No other third-party dependencies.** Use Apple frameworks for everything else. No Firebase, no analytics SDKs, no Alamofire, no Kingfisher.

### Apple Frameworks Used

|Framework          |Purpose                                              |
|-------------------|-----------------------------------------------------|
|SwiftUI            |All UI                                               |
|SwiftData          |Local persistent storage (metadata)                  |
|CryptoKit          |AES-256-GCM encryption/decryption                    |
|LocalAuthentication|Face ID / Touch ID                                   |
|PhotosUI           |PHPickerViewController for photo import              |
|AVFoundation       |Built-in camera, video playback                      |
|CloudKit           |iCloud encrypted backup (private database)           |
|CoreLocation       |Break-in GPS coordinates                             |
|WidgetKit          |Home screen widget (quick-open, no sensitive content)|
|BackgroundTasks    |Background iCloud sync                               |
|UserNotifications  |Break-in alert push notifications                    |
|Vision             |On-device image analysis (OCR, face detection, barcodes)|

### Xcode Project Setup

```
Project Name: VaultBox
Bundle ID: com.vaultbox.app
Team: (developer's team)
Capabilities to enable:
  - iCloud (CloudKit — check "CloudKit" container: iCloud.com.vaultbox.app)
  - Push Notifications
  - Background Modes (Background fetch, Remote notifications)
  - App Groups (group.com.vaultbox.app — for widget)
  - Face ID Usage Description
  - Camera Usage Description
  - Photo Library Usage Description
  - Location When In Use Usage Description
```

### Info.plist Keys

```xml
NSFaceIDUsageDescription: "VaultBox uses Face ID to securely unlock your vault."
NSCameraUsageDescription: "VaultBox uses the camera to capture photos directly into your vault."
NSPhotoLibraryUsageDescription: "VaultBox needs access to import photos into your encrypted vault."
NSLocationWhenInUseUsageDescription: "VaultBox records location data when an unauthorized access attempt is detected."
```

-----

## 3. Project Structure

```
VaultBox/
├── VaultBoxApp.swift                    # App entry point, scene setup
├── ContentView.swift                    # Root view — auth gate
│
├── Models/
│   ├── VaultItem.swift                  # SwiftData model for photos/videos/docs
│   ├── Album.swift                      # SwiftData model for albums
│   ├── BreakInAttempt.swift             # SwiftData model for intrusion logs
│   └── AppSettings.swift               # SwiftData model for user preferences
│
├── Services/
│   ├── AuthService.swift                # PIN management, biometric auth, lockout logic
│   ├── EncryptionService.swift          # AES-256-GCM encrypt/decrypt, key derivation
│   ├── VaultService.swift               # Import, export, delete vault items
│   ├── CloudService.swift               # CloudKit sync for encrypted backups
│   ├── BreakInService.swift             # Intruder photo capture, GPS, notifications
│   ├── PurchaseService.swift            # RevenueCat wrapper
│   └── AppIconService.swift             # Alternate app icon management
│
├── ViewModels/
│   ├── AuthViewModel.swift              # Lock screen state
│   ├── VaultViewModel.swift             # Main vault grid state
│   ├── AlbumViewModel.swift             # Album detail state
│   ├── ImportViewModel.swift            # Photo import flow state
│   ├── SettingsViewModel.swift          # Settings state
│   └── PaywallViewModel.swift           # Purchase state
│
├── Views/
│   ├── Auth/
│   │   ├── LockScreenView.swift         # PIN entry + biometric prompt
│   │   ├── PINSetupView.swift           # First-time PIN creation
│   │   └── PINKeypadView.swift          # Custom numeric keypad component
│   │
│   ├── Vault/
│   │   ├── VaultGridView.swift          # Main grid of all items / albums
│   │   ├── AlbumGridView.swift          # Grid of items within an album
│   │   ├── PhotoDetailView.swift        # Full-screen photo viewer
│   │   ├── VideoPlayerView.swift        # Full-screen video player
│   │   └── ImportView.swift             # PHPicker wrapper + import progress
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift           # Main settings screen
│   │   ├── SecuritySettingsView.swift   # PIN change, biometrics toggle, decoy
│   │   ├── AppIconPickerView.swift      # Fake app icon selector
│   │   ├── BackupSettingsView.swift     # iCloud backup toggle + status
│   │   └── BreakInLogView.swift         # View intrusion attempts
│   │
│   ├── Paywall/
│   │   └── PaywallView.swift            # Premium purchase screen
│   │
│   └── Components/
│       ├── VaultItemThumbnail.swift      # Encrypted thumbnail cell
│       ├── AlbumCoverView.swift          # Album card with cover image
│       ├── PremiumBadge.swift            # "PRO" badge indicator
│       └── EmptyStateView.swift          # Empty vault / album placeholder
│
├── Utilities/
│   ├── Constants.swift                  # App-wide constants
│   ├── Extensions/
│   │   ├── Data+Encryption.swift        # Data encryption helpers
│   │   ├── UIImage+Thumbnail.swift      # Thumbnail generation
│   │   └── View+ConditionalModifier.swift
│   └── Haptics.swift                    # Haptic feedback helpers
│
├── Resources/
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/          # Primary app icon
│   │   ├── AltIcons/                    # Alternate icons (Calculator, Notes, etc.)
│   │   └── Colors/                      # Named colors
│   └── Localizable.xcstrings            # Localization strings
│
└── VaultBoxWidget/                      # Widget extension
    ├── VaultBoxWidget.swift
    └── VaultBoxWidgetBundle.swift
```

-----

## 4. Data Models

All models use SwiftData (`@Model` macro). Sensitive string/data fields are stored encrypted in the database via the EncryptionService.

### VaultItem

```swift
import SwiftData
import Foundation

@Model
final class VaultItem {
    #Unique<VaultItem>([\.id])
    
    var id: UUID
    var type: ItemType            // .photo, .video, .document
    var originalFilename: String
    var encryptedFileRelativePath: String   // relative path within app sandbox
    var encryptedThumbnailData: Data?       // encrypted thumbnail (300x300 max)
    var album: Album?
    var fileSize: Int64
    var durationSeconds: Double?  // video only
    var pixelWidth: Int?
    var pixelHeight: Int?
    var createdAt: Date           // original creation date from EXIF (if available)
    var importedAt: Date
    var isFavorite: Bool
    var isUploaded: Bool          // synced to iCloud
    var cloudRecordID: String?    // CKRecord.ID name

    enum ItemType: String, Codable {
        case photo
        case video
        case document
    }
    
    init(type: ItemType, originalFilename: String, encryptedFileRelativePath: String, fileSize: Int64) {
        self.id = UUID()
        self.type = type
        self.originalFilename = originalFilename
        self.encryptedFileRelativePath = encryptedFileRelativePath
        self.fileSize = fileSize
        self.createdAt = Date()
        self.importedAt = Date()
        self.isFavorite = false
        self.isUploaded = false
    }
}
```

### Album

```swift
@Model
final class Album {
    #Unique<Album>([\.id])
    
    var id: UUID
    var name: String
    var coverItem: VaultItem?
    var items: [VaultItem]?
    var sortOrder: Int
    var isLocked: Bool            // album-level PIN (premium)
    var albumPINHash: String?     // separate PIN for this album (premium)
    var isDecoy: Bool             // true = this is the decoy vault
    var createdAt: Date

    init(name: String, sortOrder: Int = 0, isDecoy: Bool = false) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.isLocked = false
        self.isDecoy = isDecoy
        self.createdAt = Date()
    }
}
```

### BreakInAttempt

```swift
@Model
final class BreakInAttempt {
    var id: UUID
    var intruderPhotoData: Data?  // front camera snapshot (encrypted)
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var attemptedPIN: String      // the wrong PIN they entered

    init(attemptedPIN: String) {
        self.id = UUID()
        self.attemptedPIN = attemptedPIN
        self.timestamp = Date()
    }
}
```

### AppSettings

```swift
@Model
final class AppSettings {
    var id: UUID
    var pinHash: String                    // SHA-256 hash of user's PIN
    var pinSalt: String                    // random salt for PIN hashing
    var biometricsEnabled: Bool
    var decoyPINHash: String?              // hash of decoy vault PIN
    var decoyPINSalt: String?
    var freeItemLimit: Int                 // 50 for free tier
    var selectedAltIconName: String?       // nil = default icon
    var iCloudBackupEnabled: Bool
    var autoLockSeconds: Int               // 0 = immediate, 30, 60, 300
    var panicGestureEnabled: Bool          // face-down lock
    var breakInAlertsEnabled: Bool
    var lastUnlockedAt: Date?
    var hasCompletedOnboarding: Bool       // tracks whether user has seen onboarding
    var failedAttemptCount: Int            // resets on successful auth
    var lockoutUntil: Date?               // progressive lockout

    init(pinHash: String, pinSalt: String) {
        self.id = UUID()
        self.pinHash = pinHash
        self.pinSalt = pinSalt
        self.biometricsEnabled = false
        self.freeItemLimit = 50
        self.iCloudBackupEnabled = false
        self.autoLockSeconds = 0
        self.panicGestureEnabled = false
        self.hasCompletedOnboarding = false
        self.breakInAlertsEnabled = true
        self.failedAttemptCount = 0
    }
}
```

-----

## 5. Core Services

### 5.1 AuthService

Manages all authentication logic. This is the gatekeeper for the entire app.

```swift
actor AuthService {
    // State
    var isUnlocked: Bool
    var isDecoyMode: Bool  // true = user entered decoy PIN
    
    // PIN Management
    func createPIN(_ pin: String) async throws
    func verifyPIN(_ pin: String) async -> AuthResult  // .success, .failure, .locked, .decoy
    func changePIN(old: String, new: String) async throws
    func setupDecoyPIN(_ pin: String) async throws
    
    // Biometrics
    func authenticateWithBiometrics() async -> Bool
    func isBiometricsAvailable() -> Bool
    
    // Lockout
    func handleFailedAttempt(_ pin: String) async  // increment counter, check lockout
    func getLockoutRemainingSeconds() -> Int?
    func resetFailedAttempts() async
    
    // Auto-lock
    func recordUnlockTime() async
    func shouldAutoLock() -> Bool
}
```

**PIN Rules:**

- PIN must be 4–8 digits (numeric only)
- Store as SHA-256(salt + pin), never plaintext
- Salt is a 32-byte random value generated at PIN creation
- Decoy PIN must differ from real PIN
- PIN stored in Keychain via KeychainAccess (not in SwiftData)

**Lockout Rules:**

- 3 failed attempts → 30 second lockout
- 5 failed attempts → 2 minute lockout
- 8 failed attempts → 15 minute lockout
- 10 failed attempts → 1 hour lockout
- After each lockout, counter does NOT reset (only resets on successful auth)
- During lockout, display countdown timer, disable PIN entry
- Each failed attempt (after first 3) triggers break-in capture if enabled

**Biometric Rules:**

- Only offer biometrics if user has enabled them in settings
- If biometrics fail, fall back to PIN entry
- Biometrics bypass the lockout timer (prevents lockout-by-prank)
- On app launch, always try biometrics first if enabled

**Auto-lock Rules:**

- When app enters background, record timestamp
- When app enters foreground, check elapsed time vs `autoLockSeconds`
- If exceeded, require re-authentication
- If `autoLockSeconds == 0`, always require auth on foreground

### 5.2 EncryptionService

All file encryption/decryption. This service MUST be an actor for thread safety.

```swift
actor EncryptionService {
    // Key Management
    func generateMasterKey() -> SymmetricKey          // 256-bit
    func deriveMasterKey(from pin: String, salt: Data) -> SymmetricKey  // HKDF
    func storeMasterKey(_ key: SymmetricKey) async throws   // → Keychain
    func loadMasterKey() async throws -> SymmetricKey       // ← Keychain
    func rotateMasterKey(oldPIN: String, newPIN: String) async throws
    
    // File Encryption
    func encryptFile(at sourceURL: URL) async throws -> URL       // returns encrypted file URL
    func decryptFile(at encryptedURL: URL) async throws -> Data   // returns decrypted data
    func encryptData(_ data: Data) async throws -> Data
    func decryptData(_ data: Data) async throws -> Data
    
    // Thumbnail
    func generateEncryptedThumbnail(from imageData: Data, maxSize: CGSize) async throws -> Data
}
```

**Encryption Spec:**

- Algorithm: AES-256-GCM (via CryptoKit `AES.GCM`)
- Each file gets a unique random 12-byte nonce
- Nonce is prepended to the ciphertext: `[nonce (12 bytes)][ciphertext][tag (16 bytes)]`
- Master key is derived from PIN using HKDF with a device-unique salt
- Master key is stored in iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- On PIN change, re-derive master key and re-encrypt all per-file keys (NOT re-encrypt all files)

**File Storage Layout:**

```
App Sandbox/
└── VaultData/
    ├── files/
    │   ├── {uuid}.enc          # encrypted photo/video/document files
    │   └── ...
    └── thumbnails/
        ├── {uuid}_thumb.enc    # encrypted thumbnails
        └── ...
```

### 5.3 VaultService

Manages the vault contents — import, export, organize, delete.

```swift
@Observable
class VaultService {
    let encryptionService: EncryptionService
    let modelContext: ModelContext
    
    // Import
    func importPhotos(from results: [PHPickerResult], album: Album?) async throws -> [VaultItem]
    func importFromCamera(_ image: UIImage, album: Album?) async throws -> VaultItem
    func importDocument(at url: URL, album: Album?) async throws -> VaultItem
    
    // Read
    func decryptThumbnail(for item: VaultItem) async throws -> UIImage
    func decryptFullImage(for item: VaultItem) async throws -> UIImage
    func decryptVideoURL(for item: VaultItem) async throws -> URL  // temp decrypted file
    
    // Organize
    func moveItems(_ items: [VaultItem], to album: Album) async throws
    func removeFromAlbum(_ items: [VaultItem]) async throws
    func toggleFavorite(_ item: VaultItem) async
    
    // Delete
    func deleteItems(_ items: [VaultItem]) async throws  // removes encrypted file + model
    func deleteFromCameraRoll(localIdentifiers: [String]) async throws
    
    // Stats
    func getTotalItemCount() -> Int
    func getTotalStorageUsed() -> Int64
    func isAtFreeLimit() -> Bool  // check against AppSettings.freeItemLimit
}
```

**Import Flow (step by step):**

1. User taps “+” button → PHPickerViewController presented (multi-select enabled)
1. User selects photos/videos → dismiss picker
1. For each selected item:
   a. Load full-resolution data from PHPickerResult via `loadTransferable(type:)`
   b. Strip EXIF metadata (remove GPS, device info — keep date if present)
   c. Generate 300×300 thumbnail (aspect-fill, JPEG at 0.7 quality)
   d. Encrypt full-resolution file → save to `VaultData/files/{uuid}.enc`
   e. Encrypt thumbnail → store as `encryptedThumbnailData` on VaultItem
   f. Create VaultItem in SwiftData
   g. Record original `localIdentifier` for Camera Roll deletion
1. Show import progress (determinate progress bar per item)
1. After all imports complete, show prompt: “Delete originals from Camera Roll?”
- If yes, delete via PHAssetChangeRequest using stored localIdentifiers
- If no, dismiss
1. If user is on free tier and import would exceed 50 items, show paywall BEFORE starting import

**Thumbnail Spec:**

- Max 300×300 pixels, aspect-fill crop from center
- JPEG compression at quality 0.7
- Encrypted with same scheme as full files
- Stored as Data blob on the VaultItem model (not separate file) for fast grid loading
- Generate on background thread, never block UI

### 5.4 CloudService

iCloud backup via CloudKit private database. Premium only.

```swift
actor CloudService {
    // Sync
    func uploadItem(_ item: VaultItem) async throws
    func downloadItem(recordID: String) async throws -> Data  // encrypted data
    func deleteItem(recordID: String) async throws
    
    // Bulk
    func syncAllPendingUploads() async throws  // upload items where isUploaded == false
    func fetchAllCloudRecords() async throws -> [CKRecord]  // for restore
    func restoreFromCloud() async throws -> Int  // returns count of restored items
    
    // Status
    func getICloudAccountStatus() async -> CKAccountStatus
    func getUploadProgress() -> (completed: Int, total: Int)
}
```

**CloudKit Schema:**

Record Type: `EncryptedVaultItem`

|Field               |Type  |Description                 |
|--------------------|------|----------------------------|
|`itemID`            |String|UUID of VaultItem           |
|`encryptedFile`     |Asset |The encrypted file blob     |
|`encryptedThumbnail`|Bytes |Encrypted thumbnail data    |
|`itemType`          |String|“photo”, “video”, “document”|
|`originalFilename`  |String|Original filename           |
|`fileSize`          |Int64 |File size in bytes          |
|`createdAt`         |Date  |Original creation date      |

**Rules:**

- ALL data uploaded to CloudKit is already encrypted locally. CloudKit never sees plaintext.
- Use CloudKit private database only (user’s own iCloud, zero server cost to us)
- Upload on Wi-Fi only by default (add setting to allow cellular)
- Background upload via BGAppRefreshTask
- On restore: download all records, decrypt locally, recreate VaultItem models
- Handle iCloud account changes gracefully (show warning if account changed)

### 5.5 BreakInService

Captures intruder evidence on failed PIN attempts.

```swift
class BreakInService {
    func captureIntruder() async -> BreakInAttempt  // front camera + GPS
    func getRecentAttempts(limit: Int) -> [BreakInAttempt]
    func clearAllAttempts() async
}
```

**Rules:**

- Triggered after 3rd consecutive failed PIN attempt
- Silently capture front camera image (no shutter sound, no flash)
- Request GPS location at time of capture
- Store encrypted intruder photo in BreakInAttempt model
- If break-in alerts are enabled, send local notification: “Someone tried to access VaultBox”
- Show break-in log in Settings with photo, location on map, timestamp, and attempted PIN
- Keep last 20 attempts, auto-purge older ones

### 5.6 PurchaseService

RevenueCat wrapper for subscription management.

```swift
@Observable
class PurchaseService {
    var isPremium: Bool
    var currentOffering: Offering?
    
    func configure() async                    // call on app launch
    func fetchOfferings() async throws
    func purchase(_ package: Package) async throws -> Bool
    func restorePurchases() async throws -> Bool
    func checkPremiumStatus() async -> Bool
}
```

**RevenueCat Setup:**

- Product ID: `vaultbox_premium_annual` — $24.99/year
- Product ID: `vaultbox_premium_weekly` — $2.99/week (introductory trial)
- Entitlement ID: `premium`
- Show weekly as the default selection on paywall (higher conversion), with annual shown as “best value”

### 5.7 AppIconService

Manages alternate app icons for disguise feature.

```swift
class AppIconService {
    static let availableIcons: [(id: String?, displayName: String, previewImage: String)] = [
        (nil, "VaultBox (Default)", "icon_default"),
        ("CalculatorIcon", "Calculator", "icon_calculator"),
        ("NotesIcon", "Notes", "icon_notes"),
        ("WeatherIcon", "Weather", "icon_weather"),
        ("CompassIcon", "Compass", "icon_compass"),
        ("ClockIcon", "Clock", "icon_clock"),
        ("StocksIcon", "Stocks", "icon_stocks"),
        ("TranslateIcon", "Translate", "icon_translate"),
        ("MeasureIcon", "Measure", "icon_measure"),
    ]
    
    func setIcon(_ iconName: String?) async throws  // nil = default
    func getCurrentIcon() -> String?
}
```

**Rules:**

- Alternate icons must be included in the app bundle (Assets.xcassets or Info.plist `CFBundleAlternateIcons`)
- Use `UIApplication.shared.setAlternateIconName()` — this shows a system alert “You have changed the icon for VaultBox” which cannot be suppressed
- Icons should closely resemble stock iOS app icons but NOT be identical (App Store rejection risk)
- Premium feature only

-----

## 6. Screens & Navigation

### Navigation Architecture

```
App Launch
    │
    ▼
┌──────────────────┐
│ OnboardingView    │ ← First launch only (2-page value hook + permissions)
└───────┬──────────┘
        │ "Continue"
        ▼
┌──────────────────┐
│ PINSetupView      │ ← Create PIN (sets hasCompletedOnboarding = true)
└───────┬──────────┘
        │ (PIN created)
        ▼
┌─────────────────────────────────────┐
│ TabView                              │
│  ...                                 │
└─────────────────────────────────────┘

Returning users:

App Launch
    │
    ▼
┌─────────────┐
│ LockScreen   │ ← PIN + biometrics gate
└──────┬──────┘
       │ (authenticated)
       ▼
┌─────────────────────────────────────┐
│ TabView                              │
│  ├── Tab 1: Vault (VaultGridView)    │
│  ├── Tab 2: Albums                   │
│  ├── Tab 3: Camera (direct-to-vault) │
│  └── Tab 4: Settings                 │
└─────────────────────────────────────┘
```

### Screen Specs

#### 6.0 OnboardingView

Shown only on first app launch (`hasCompletedOnboarding == false && isSetupComplete == false`). Existing users who already have a PIN skip this screen entirely.

**Layout — Screen 1 (Value Hook):**

- SF Symbol `lock.shield.fill` at 120pt, `Color.vaultPremium` (#FFD60A)
- Title: "Your Hidden Album isn't private" — `.largeTitle`, bold
- Body: "Anyone with your passcode can open it. VaultBox encrypts every photo with AES-256 so only you can see them." — `.body`, `Color.vaultTextSecondary`
- "Get Started" CTA — full-width, gold background (`Color.vaultPremium`), black text, 50pt height, 12pt corner radius
- 32pt bottom padding

**Layout — Screen 2 (Permissions Primer):**

- Title: "VaultBox needs a few permissions" — `.title2`, bold
- Subtitle: "We'll ask one at a time — you can change these later in Settings." — `.callout`, `Color.vaultTextSecondary`
- Three info rows:
  - `faceid` — "Face ID / Touch ID" / "Unlock your vault in a flash"
  - `photo.on.rectangle` — "Photo Library" / "Import photos & videos to encrypt"
  - `camera.fill` — "Camera" / "Capture directly into your vault"
- "Continue" CTA — same style as Screen 1
- 32pt bottom padding

**Navigation:**

- Two-page `TabView` with `.tabViewStyle(.page)`, swipe enabled
- Page indicator: two dots above CTA showing current page
- "Get Started" animates to Screen 2
- "Continue" presents `PINSetupView` via `.fullScreenCover`
- After PIN creation completes, `hasCompletedOnboarding` is set to `true` and routing transitions to `.main`

#### 6.1 LockScreenView

**Layout:**

- App name/logo centered at top (30% from top)
- 4–8 dot indicators showing PIN length (filled dots for entered digits)
- Custom numeric keypad (1–9, biometric button, 0, delete)
- Biometric button shows Face ID or Touch ID icon depending on device
- If locked out, replace keypad with countdown timer and “Try again in X:XX”

**Behavior:**

- On appear: if biometrics enabled, trigger biometric prompt automatically
- Each digit tap: fill next dot, haptic light impact
- When all digits entered: verify PIN immediately (no “submit” button)
- Correct PIN: success haptic, dots turn green, 0.3s delay, transition to TabView
- Wrong PIN: error haptic, dots shake horizontally (0.5s), clear after shake
- Decoy PIN entered: success haptic, transition to TabView with `isDecoyMode = true`
- Lockout: keypad disabled, dots replaced with lock icon, countdown timer shown

**Design:**

- Dark background (pure black for OLED)
- White dots and keypad
- Keypad buttons: 75×75pt circles with subtle gray background on press
- No visible app name if user has set a fake app icon (show the fake icon instead)

#### 6.2 PINSetupView

**Shown on:** First app launch only.

**Layout:**

- Title: “Create a PIN”
- Subtitle: “Choose a 4-8 digit PIN to protect your vault”
- Same dot indicators + keypad as LockScreen
- After entering PIN: “Confirm your PIN” — must match

**Behavior:**

- Minimum 4 digits, maximum 8
- User taps digits, then taps a “Continue” button (appears after 4+ digits entered)
- Confirm screen: if match → save PIN, enable biometrics prompt, proceed to VaultGridView
- If mismatch: shake animation, “PINs don’t match. Try again.” reset to first entry
- After PIN set, immediately prompt: “Enable Face ID?” (if available)

#### 6.3 VaultGridView (Tab 1: Vault)

**Layout:**

- Navigation title: “Vault”
- Toolbar: left = “Select” button, right = “+” (import) button
- Grid: 3 columns, 1pt spacing, square cells
- Each cell shows decrypted thumbnail with rounded corners (4pt)
- Video items show duration badge in bottom-right (e.g. “0:34”)
- Favorite items show small heart icon in top-right
- If vault is empty: EmptyStateView with illustration + “Tap + to add your first photo”
- Bottom: item count label (“47 of 50 items” for free tier, or “342 items” for premium)

**Behavior:**

- Tap thumbnail → push PhotoDetailView (or VideoPlayerView for videos)
- Long-press thumbnail → enter selection mode (same as tapping “Select”)
- Selection mode: checkmark overlay on selected items, bottom toolbar with [Move to Album] [Favorite] [Delete]
- Pull to refresh: re-decrypt all visible thumbnails (edge case: data corruption recovery)
- “+” button: if free tier and at limit → show PaywallView. Otherwise → present PHPicker

**Sorting:**

- Default: newest first (by `importedAt`)
- Option in toolbar menu: sort by date imported, date created, file size

**Filtering:**

- Toolbar menu: All / Photos only / Videos only / Favorites

#### 6.4 AlbumGridView (Tab 2: Albums)

**Layout:**

- Navigation title: “Albums”
- Grid: 2 columns, album cards
- Each card: rounded rectangle with cover thumbnail (or gradient placeholder), album name below, item count
- “+” button in toolbar → create new album (text field alert)
- “All Items” album always appears first (not deletable)

**Behavior:**

- Tap album → push to grid of items in that album (same layout as VaultGridView but filtered)
- Long-press album → context menu: Rename, Set Cover, Lock Album (premium), Delete Album
- Delete album: “Delete album only” (items move to All Items) or “Delete album and contents”
- Locked album (premium): requires album-specific PIN or biometric to view contents

#### 6.5 PhotoDetailView

**Layout:**

- Full-screen, black background
- Photo fills screen (aspect-fit)
- Top bar (fades in/out on tap): back button, share button, favorite button, more menu (…)
- Bottom: swipe-up for info panel (filename, date, dimensions, file size)
- Pinch to zoom (up to 5×), double-tap to toggle 1×/2×

**Behavior:**

- Swipe left/right to navigate between items (in current context — album or all items)
- Tap toggles top/bottom bars visibility
- Share button: decrypt photo → present UIActivityViewController (standard share sheet)
- More menu: “Move to Album”, “Copy Photo”, “Delete”, “Export to Camera Roll”
- If item is video, auto-transition to VideoPlayerView

#### 6.6 VideoPlayerView

**Layout:**

- Full-screen AVPlayerViewController presentation
- Standard playback controls (play/pause, scrub, volume, AirPlay)

**Behavior:**

- Decrypt video to temporary file → play from temp URL
- On dismiss: delete temporary decrypted file immediately
- Support 0.5×, 1×, 1.5×, 2× playback speed (premium)

#### 6.7 ImportView

**Layout:**

- Uses native PHPickerViewController (not custom UI)
- After selection: modal progress view
  - “Importing X items…”
  - Determinate progress bar
  - Current item thumbnail + filename
  - Cancel button (cancels remaining, keeps completed)

**Behavior:**

- PHPicker config: `filter = .any(of: [.images, .videos])`, `selectionLimit = 0` (unlimited)
- After import completes: prompt “Delete X originals from Camera Roll?”
  - “Delete” button (destructive red)
  - “Keep” button
- If deleting: use `PHAssetChangeRequest.deleteAssets()` — requires separate Photos permission confirmation from iOS

#### 6.8 SettingsView (Tab 4: Settings)

**Sections:**

```
SECURITY
  ├── Change PIN                    → PINSetupView (requires current PIN first)
  ├── Face ID / Touch ID            → Toggle
  ├── Auto-Lock                     → Picker: Immediately / 30 sec / 1 min / 5 min
  ├── Decoy Vault                   → SecuritySettingsView (premium, lock icon if free)
  └── Panic Gesture                 → Toggle (premium)

APPEARANCE
  ├── App Icon                      → AppIconPickerView (premium)
  └── Theme                         → System / Light / Dark

BACKUP
  ├── iCloud Backup                 → Toggle (premium) + status text
  └── Backup Now                    → Manual sync trigger

PRIVACY
  ├── Break-in Alerts               → Toggle
  ├── View Break-in Log             → BreakInLogView
  └── Clear Break-in Log            → Confirmation alert

STORAGE
  ├── Items: 47 of 50 (free) or 342 items (premium)
  ├── Storage Used: 1.2 GB
  └── [Upgrade to Premium button if free tier]

ABOUT
  ├── Rate VaultBox                 → App Store link
  ├── Privacy Policy                → SafariView
  ├── Terms of Service              → SafariView
  ├── Restore Purchases             → RevenueCat restore
  └── Version 1.0.0 (1)
```

#### 6.9 PaywallView

**Shown when:**

- Free tier user hits 50-item limit and tries to import
- User taps any premium feature (decoy, icon, iCloud backup, etc.)
- User taps “Upgrade” in Settings

**Layout:**

- Dismiss “X” button in top-left
- Hero illustration at top (vault with shield icon)
- “Unlock VaultBox Premium” title
- Feature list with checkmarks:
  - ✓ Unlimited photos & videos
  - ✓ iCloud encrypted backup
  - ✓ Decoy vault
  - ✓ Fake app icon disguise
  - ✓ Break-in alerts with GPS
  - ✓ Panic gesture
  - ✓ Wi-Fi transfer
- Two pricing options (toggle/segment):
  - Weekly: $2.99/week (selected by default — “Start Free Trial”)
  - Annual: $24.99/year (shown as “$0.48/week — Best Value” badge)
- Large CTA button: “Start Free Trial” or “Subscribe”
- Fine print: “Cancel anytime. Subscription auto-renews.”
- “Restore Purchases” text button below

**Behavior:**

- Default selection: weekly (higher trial conversion)
- On purchase success: dismiss paywall, unlock features immediately, celebration haptic
- On purchase failure: show error alert, keep paywall open
- “Restore Purchases” → RevenueCat restore → if found, dismiss + unlock

#### 6.10 BreakInLogView

**Layout:**

- List of BreakInAttempt entries, newest first
- Each row: intruder photo (small circle), timestamp, attempted PIN (masked as “••X•”), location text
- Tap row → detail view with full photo + map pin

-----

## 7. Feature Specifications

### 7.1 Decoy Vault (Premium)

**Setup:**

1. User goes to Settings → Security → Decoy Vault
1. Prompt to set a separate decoy PIN (must differ from real PIN)
1. Add a few “decoy” photos to make it look real

**How it works:**

- On lock screen, if user enters the DECOY pin, app opens showing ONLY albums/items marked `isDecoy = true`
- All real vault items are completely hidden
- The decoy vault looks and functions exactly like the real vault (same UI)
- There is NO visible indicator that decoy mode is active
- Settings in decoy mode: show limited settings (no break-in log, no backup section, no decoy settings)

**Data isolation:**

- Decoy items stored in same SwiftData store but with `album.isDecoy = true`
- VaultViewModel filters by `isDecoyMode` from AuthService
- Encryption uses the same master key (decoy items are still encrypted)

### 7.2 Fake App Icon (Premium)

**Available icons:**
8 alternate icons that mimic stock iOS apps (but are NOT identical — slightly different to avoid App Store rejection):

1. Calculator (gray background, white +/- buttons)
1. Notes (yellow notepad)
1. Weather (blue gradient, sun)
1. Compass (white face, red needle)
1. Clock (white face, black hands)
1. Stocks (black background, green line)
1. Translate (blue background, speech bubble)
1. Measure (yellow background, ruler)

**Rules:**

- After switching, iOS shows system alert: “You have changed the icon for VaultBox” — we cannot suppress this
- The app name under the icon will still show “VaultBox” — recommend user rename their Home Screen folder or use a Shortcut to rename
- When fake icon is active, the lock screen hides the VaultBox logo and shows the fake icon instead

### 7.3 Panic Gesture (Premium)

**Triggers:**

- Place phone face-down on a surface (detected via accelerometer/gyroscope)
- Three-finger swipe down on screen

**Behavior:**

- Immediately lock the app (return to LockScreenView)
- Clear any temporary decrypted files
- Success haptic feedback
- Works from any screen in the app

**Implementation:**

- Use `CMMotionManager` or device orientation notifications to detect face-down
- Three-finger gesture: custom `UIGestureRecognizer` attached to the window

### 7.4 Wi-Fi Transfer (Premium)

**How it works:**

1. User opens Settings → Wi-Fi Transfer
1. App starts a local HTTP server (GCDWebServer or custom NWListener)
1. Displays: “Open http://192.168.X.X:8080 on your computer”
1. Computer browser shows simple upload/download interface
1. Upload: files are encrypted on receipt and added to vault
1. Download: files are decrypted and served to browser

**Rules:**

- Only works on local network (not accessible from internet)
- Require PIN re-entry before starting server
- Auto-stop server after 10 minutes of inactivity
- Show connected device count while active

> **Note for Claude Code:** Use `NWListener` from the Network framework for the local HTTP server. Do NOT add a third-party dependency for this. If implementing a full HTTP server from scratch is too complex for MVP, defer this feature to Phase 3 and just scaffold the settings entry.

### 7.5 Smart Albums (v1)

On-device Vision analysis runs automatically during import. No user action required.

**Tagging pipeline (runs per item, background thread):**

1. After encryption + thumbnail generation, decrypt the full image temporarily in memory
2. Run Vision requests concurrently:
   - `VNRecognizeTextRequest` → if significant text detected → tag: "document"
   - `VNDetectFaceRectanglesRequest` → if 1+ faces → tag: "people"
   - `VNDetectBarcodesRequest` → if QR/barcode found → tag: "qrcode"
   - Check image dimensions == device screen size → tag: "screenshot"
3. Store tags on VaultItem as: `var smartTags: [String]` (array of tag strings)
4. Wipe decrypted image from memory immediately after analysis

**Smart Albums display:**
- Shown at the top of the Albums tab in a horizontal scroll row
- Each smart album is a filtered view (query VaultItems where smartTags contains X)
- Smart albums only appear if they contain 1+ items
- Not deletable or renameable by user

**Search:**
- Search bar at top of Vault tab
- Searches: filename, smart tags, and OCR-extracted text
- OCR text stored as `var extractedText: String?` on VaultItem (encrypted in DB)
- Example: user searches "passport" → finds photo of passport via OCR text match

**Performance rules:**
- Vision analysis must not block import progress UI
- Process in background after import completes
- If user imports 50 photos, queue all 50 and process sequentially
- Timeout: 3 seconds per image max, skip on failure

**Data model addition to VaultItem:**

```swift
var smartTags: [String]      // ["document", "people", "screenshot", "qrcode"]
var extractedText: String?   // OCR text for search (encrypted)
```

**Privacy:**
- ALL processing is on-device via Apple Vision framework
- No data leaves the device
- No third-party AI APIs
- Extracted text is encrypted at rest like all other vault data

-----

## 8. Paywall & Monetization

### RevenueCat Configuration

```swift
// In PurchaseService.configure()
Purchases.configure(withAPIKey: "YOUR_REVENUECAT_API_KEY")
```

**Products (configure in App Store Connect + RevenueCat):**

|Product ID               |Type                       |Price      |Description                       |
|-------------------------|---------------------------|-----------|----------------------------------|
|`vaultbox_premium_weekly`|Auto-renewable subscription|$2.99/week |Weekly premium access             |
|`vaultbox_premium_annual`|Auto-renewable subscription|$24.99/year|Annual premium access (best value)|

**Subscription Group:** `vaultbox_premium`

**Entitlement:** `premium` — grants access to all premium features

### Free vs Premium Feature Gate

```swift
// Use this pattern throughout the app to gate features:
func isPremiumRequired(for feature: PremiumFeature) -> Bool {
    switch feature {
    case .unlimitedItems: return vaultService.getTotalItemCount() >= settings.freeItemLimit
    case .iCloudBackup: return true
    case .decoyVault: return true
    case .fakeAppIcon: return true
    case .panicGesture: return true
    case .wifiTransfer: return true
    case .albumLock: return true
    case .videoSpeedControl: return true
    case .breakInGPS: return true   // basic break-in photo is free, GPS is premium
    }
}

enum PremiumFeature {
    case unlimitedItems
    case iCloudBackup
    case decoyVault
    case fakeAppIcon
    case panicGesture
    case wifiTransfer
    case albumLock
    case videoSpeedControl
    case breakInGPS
}
```

### Paywall Trigger Points

1. Import flow: user has 50 items and tries to import more
1. Settings: tapping any premium toggle (iCloud, decoy, panic, icon)
1. Album: tapping “Lock Album” in context menu
1. Settings: explicit “Upgrade to Premium” button
1. Video player: tapping speed control button

-----

## 9. App Store Configuration

### App Store Listing

**App Name:** VaultBox — Photo Vault & Lock

**Subtitle:** Hide Private Photos & Videos

**Category:** Photo & Video (primary), Utilities (secondary)

**Keywords (100 characters max):**

```
photo,vault,hide,photos,private,secret,album,lock,pictures,locker,safe,hidden,gallery,encrypt,secure
```

**Description (first 3 lines most important — shown before “more”):**

```
Keep your private photos and videos locked away in an encrypted vault. VaultBox uses AES-256 encryption to protect your most personal moments — only you can see them.

Unlike other vault apps, VaultBox stores encrypted backups in YOUR iCloud — not on our servers. Your data never leaves your control.

FEATURES:
• Military-grade AES-256 encryption
• Face ID & Touch ID unlock
• PIN-protected vault with custom 4-8 digit code
• Import photos & videos from Camera Roll
• Break-in detection — see who tried to access your vault
• Dark mode optimized
• Decoy vault — show a fake vault when someone watches you unlock
• Disguise the app icon as Calculator, Notes, or Weather
• iCloud encrypted backup — syncs across your devices
• Panic gesture — flip your phone to instantly lock
```

**Privacy Nutrition Label:**

- Data Not Collected (our strongest selling point — we collect zero user data)
- If using RevenueCat: “Purchase History — Linked to Identity” (required by Apple)

### Age Rating

**17+** — the app stores private content. Apple may require this rating for vault/privacy apps.

### Review Notes for App Store Review

```
This app allows users to securely store private photos and videos behind PIN/biometric protection with AES-256 encryption. 

Demo credentials for review:
- PIN: 1234
- The app will prompt you to create a PIN on first launch.

The "Decoy Vault" feature shows a separate, harmless photo collection when a different PIN is entered. This is a privacy feature, not intended to facilitate illegal activity.

The "Break-in Detection" feature captures a photo using the front camera when incorrect PINs are entered. This is clearly disclosed to the user during onboarding and in the app description. Users can disable this feature in Settings.
```

-----

## 10. Testing Requirements

### Unit Tests

|Service            |What to Test                                                                                                                                                                          |
|-------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
|`EncryptionService`|Encrypt→decrypt roundtrip produces identical data; different keys produce different ciphertext; corrupted ciphertext throws error; key derivation from same PIN+salt produces same key|
|`AuthService`      |Correct PIN unlocks; wrong PIN fails; lockout triggers at correct thresholds; lockout timer decrements; biometric fallback works; decoy PIN returns `.decoy`                          |
|`VaultService`     |Import creates VaultItem with correct metadata; delete removes file from disk; free tier limit enforced at 50; favorite toggle persists                                               |
|`PurchaseService`  |Premium check gates features correctly; restore surfaces existing entitlement                                                                                                         |

### UI Tests

|Flow        |Test                                                                      |
|------------|--------------------------------------------------------------------------|
|First launch|PIN setup → confirm → biometric prompt → empty vault shown                |
|Import      |Tap + → select photo → progress → delete prompt → item appears in grid    |
|Lock/unlock |Background app → foreground → lock screen shown → enter PIN → vault shown |
|Decoy       |Enter decoy PIN → only decoy items shown → settings limited               |
|Break-in    |Enter wrong PIN 3x → intruder photo captured → appears in break-in log    |
|Paywall     |Free user at 50 items → tap + → paywall shown → purchase → import proceeds|

### Manual QA Checklist (before submission)

- [ ] Fresh install: PIN setup flow works
- [ ] PIN entry: correct PIN unlocks
- [ ] PIN entry: wrong PIN shows error, lockout works
- [ ] Face ID: prompts on launch if enabled
- [ ] Import: photos import and thumbnails display correctly
- [ ] Import: videos import and play correctly
- [ ] Full-screen viewer: zoom, swipe, share work
- [ ] Albums: create, rename, delete, set cover
- [ ] Delete: items removed from vault and disk
- [ ] Free tier: blocked at 50 items, paywall shows
- [ ] Premium: purchase completes, features unlock
- [ ] Restore: existing subscription detected
- [ ] iCloud backup: toggle on, items upload
- [ ] Decoy vault: separate PIN shows decoy items only
- [ ] Fake icon: changes icon successfully
- [ ] Break-in: wrong PIN → front camera capture → log entry
- [ ] Auto-lock: app backgrounds → foregrounds → requires auth
- [ ] Panic gesture: face-down locks app
- [ ] Dark mode: all screens render correctly
- [ ] Memory: import 100+ photos without crash
- [ ] Orientation: portrait only (lock to portrait)

-----

## 11. Implementation Order

Build in this exact order. Each phase should be fully functional before starting the next.

### Phase 1: Core Vault (Weeks 1–2)

**Goal:** A working encrypted photo vault with PIN protection.

```
1.  Project setup: Xcode project, SPM dependencies, folder structure
2.  Constants.swift — app-wide constants
3.  AppSettings model + seed on first launch
4.  EncryptionService — full implementation
5.  AuthService — PIN create, verify, lockout logic
6.  PINSetupView + PINKeypadView — first launch flow
7.  LockScreenView — PIN entry + biometric auth
8.  VaultItem model
9.  VaultService — import flow (PHPicker → encrypt → store)
10. VaultGridView — thumbnail grid with encrypted thumbnail decryption
11. PhotoDetailView — full-screen viewer with zoom
12. VideoPlayerView — basic video playback from decrypted temp file
13. Album model + AlbumGridView
14. Delete flow (vault items + optional Camera Roll deletion)
15. Selection mode (multi-select → move/delete)
16. ContentView (auth gate: LockScreen → TabView)
17. VaultBoxApp entry point + SwiftData container setup
```

### Phase 2: Monetization + Premium (Week 3)

```
18. PurchaseService — RevenueCat integration
19. PaywallView — UI + purchase flow
20. Premium feature gating throughout app
21. Free tier limit enforcement (50 items)
22. SettingsView — basic settings screen
23. SecuritySettingsView — change PIN, biometrics toggle
```

### Phase 3: Premium Features (Weeks 4–5)

```
24. BreakInService + BreakInAttempt model
25. BreakInLogView
26. Decoy vault (decoy PIN + filtered content)
27. AppIconService + AppIconPickerView + alternate icon assets
28. Panic gesture implementation
29. CloudService — iCloud encrypted backup
30. BackupSettingsView + sync status
31. Built-in camera (direct-to-vault capture)
```

### Phase 4: Polish + Submit (Week 5–6)

```
32. Empty states for all screens
33. Haptic feedback throughout
34. Animation polish (transitions, thumbnail loading)
35. Rate prompt (after 10th import)
36. App Store screenshots (use Xcode previews or simulator)
37. Privacy policy + terms pages
38. App Store Connect configuration
39. TestFlight beta
40. Submit for review
```

-----

## Appendix A: Design Tokens

### Colors

|Token             |Light    |Dark     |Usage                   |
|------------------|---------|---------|------------------------|
|`background`      |`#FFFFFF`|`#000000`|Primary background      |
|`surface`         |`#F2F2F7`|`#1C1C1E`|Cards, cells            |
|`surfaceSecondary`|`#E5E5EA`|`#2C2C2E`|Nested surfaces         |
|`textPrimary`     |`#000000`|`#FFFFFF`|Headings, body          |
|`textSecondary`   |`#8E8E93`|`#8E8E93`|Captions, metadata      |
|`accent`          |`#007AFF`|`#0A84FF`|Buttons, links          |
|`destructive`     |`#FF3B30`|`#FF453A`|Delete actions          |
|`success`         |`#34C759`|`#30D158`|PIN correct, upload done|
|`premium`         |`#FFD60A`|`#FFD60A`|Premium badges          |

### Typography

Use system font (SF Pro) throughout. Never specify a custom font.

|Style     |Weight  |Size|Usage               |
|----------|--------|----|--------------------|
|largeTitle|Bold    |34pt|Screen titles       |
|title2    |Bold    |22pt|Section headers     |
|headline  |Semibold|17pt|Cell titles         |
|body      |Regular |17pt|Body text           |
|callout   |Regular |16pt|Secondary info      |
|caption1  |Regular |12pt|Metadata, timestamps|

### Spacing

- Grid gap: 1pt (tight photo grid like Photos app)
- Standard padding: 16pt
- Section spacing: 24pt
- Card corner radius: 12pt
- Thumbnail corner radius: 4pt

### Haptics

|Event                  |Haptic                 |
|-----------------------|-----------------------|
|PIN digit tap          |`.light` impact        |
|PIN correct            |`.success` notification|
|PIN wrong              |`.error` notification  |
|Item selected          |`.light` impact        |
|Delete confirmed       |`.medium` impact       |
|Purchase complete      |`.success` notification|
|Panic gesture triggered|`.heavy` impact        |

-----

## Appendix B: Error Handling

All errors should be user-facing with clear messages. Never show raw error strings.

|Error Case              |User Message                                               |Action                    |
|------------------------|-----------------------------------------------------------|--------------------------|
|Photo import fails      |“Couldn’t import this photo. Please try again.”            |Skip item, continue others|
|Decryption fails        |“This item couldn’t be opened. It may be corrupted.”       |Offer to delete item      |
|iCloud unavailable      |“iCloud is not available. Check your Apple ID in Settings.”|Link to iOS Settings      |
|iCloud full             |“Your iCloud storage is full. Backup paused.”              |Link to manage storage    |
|Camera permission denied|“VaultBox needs camera access for this feature.”           |Link to iOS Settings      |
|Photos permission denied|“VaultBox needs photo access to import your photos.”       |Link to iOS Settings      |
|Purchase failed         |“Purchase couldn’t be completed. Please try again.”        |Keep paywall open         |
|Network error (cloud)   |“Backup paused — no internet connection.”                  |Auto-retry when connected |
