# VaultBox — Agent Harness

> This file governs **how** the AI agent builds VaultBox. For **what** to build, see `VaultBox-PRD.md`.

---

## Agent Workflow

### Session Startup
1. Run `pwd` — confirm working directory is `/Users/VykesMac/repos/vault-box`
2. Read `claude-progress.txt` for current state
3. Read this file's feature checklist — find the next `"passes": false` feature
4. Run `./init.sh` to validate environment health
5. Run `xcodebuild build` to confirm project compiles before making changes

### Session Work
- **One feature per session.** Do not attempt multiple features.
- Build the feature, then verify it passes its verification steps
- If a feature depends on another that isn't passing, fix the dependency first

### Session Shutdown
1. Run `xcodebuild build` — confirm project still compiles
2. Run tests if applicable: `xcodebuild test -scheme VaultBox -destination 'platform=iOS Simulator,name=iPhone 16'`
3. Git commit with descriptive message: `git add -A && git commit -m "feat: <feature description>"`
4. Update `claude-progress.txt` with what was completed and any blockers
5. Update the feature's `"passes"` to `true` in this file if verified

---

## Session Rules

1. **Never edit feature definitions** in the checklist below — only update `"passes"` status
2. **Never skip verification** — a feature isn't done until its verification steps pass
3. **Commit after every feature** — enables rollback if something breaks
4. **Read before writing** — always read existing files before modifying them
5. **Reuse existing code** — check Services/ and Utilities/ before creating new helpers
6. **Follow PRD exactly** — don't add features, change APIs, or "improve" the spec
7. **Portrait only** — lock all views to portrait orientation
8. **No third-party deps** beyond RevenueCat and KeychainAccess

---

## Environment Setup

### init.sh

Create this file at project root on first session:

```bash
#!/bin/bash
set -e

echo "=== VaultBox Environment Check ==="

# Check Xcode
xcodebuild -version || { echo "ERROR: Xcode not found"; exit 1; }

# Check Swift
swift --version || { echo "ERROR: Swift not found"; exit 1; }

# Resolve SPM dependencies
if [ -d "VaultBox.xcodeproj" ]; then
  xcodebuild -resolvePackageDependencies -project VaultBox.xcodeproj -scheme VaultBox
  echo "=== SPM dependencies resolved ==="
fi

# Build check
if [ -d "VaultBox.xcodeproj" ]; then
  xcodebuild build -project VaultBox.xcodeproj -scheme VaultBox \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  echo "=== Build OK ==="
fi

echo "=== Environment Ready ==="
```

---

## Git Workflow

- **Branch:** Work on `main` (solo developer)
- **Commits:** One per completed feature, prefixed: `feat:`, `fix:`, `refactor:`, `chore:`
- **Init commit:** After project scaffolding (Feature 0), commit as `chore: project scaffolding`
- **Never force push**

---

## Progress File

Maintain `claude-progress.txt` at project root. Format:

```
=== VaultBox Progress ===
Last updated: YYYY-MM-DD HH:MM
Last completed feature: F<number> — <name>
Current status: <compiles | broken | blocked>
Next feature: F<number> — <name>
Blockers: <none | description>
Notes: <any context for next session>
```

---

## Feature Checklist

Each feature is one session's work. Complete them **in order** (F0 → F40).
Verification = how the agent proves the feature works before committing.

```json
[
  {
    "id": "F0",
    "category": "Phase 1 — Setup",
    "description": "Create Xcode project, add SPM deps (RevenueCat, KeychainAccess), create folder structure per PRD Section 3, add Info.plist keys, create init.sh, init git repo",
    "verification": ["Project opens in Xcode without errors", "SPM dependencies resolve", "Folder structure matches PRD Section 3", "init.sh runs without errors", "git log shows initial commit"],
    "passes": false
  },
  {
    "id": "F1",
    "category": "Phase 1 — Setup",
    "description": "Create Constants.swift with all app-wide constants (colors, spacing, haptics, free tier limit, encryption params) per PRD Appendix A",
    "verification": ["File exists at Utilities/Constants.swift", "Project compiles"],
    "passes": false
  },
  {
    "id": "F2",
    "category": "Phase 1 — Models",
    "description": "Create AppSettings SwiftData model per PRD Section 4. Seed default settings on first launch in VaultBoxApp.swift",
    "verification": ["AppSettings.swift exists with all fields from PRD", "Project compiles"],
    "passes": false
  },
  {
    "id": "F3",
    "category": "Phase 1 — Encryption",
    "description": "Implement EncryptionService actor per PRD Section 5.2 — AES-256-GCM encrypt/decrypt, key generation, HKDF derivation, Keychain storage via KeychainAccess, thumbnail encryption",
    "verification": ["EncryptionService.swift compiles", "Unit test: encrypt then decrypt roundtrip returns identical data", "Unit test: different keys produce different ciphertext"],
    "passes": false
  },
  {
    "id": "F4",
    "category": "Phase 1 — Auth",
    "description": "Implement AuthService actor per PRD Section 5.1 — PIN create/verify/change, SHA-256 hashing with salt, lockout logic (3/5/8/10 thresholds), biometric auth via LocalAuthentication, auto-lock",
    "verification": ["AuthService.swift compiles", "Unit test: correct PIN returns .success", "Unit test: wrong PIN returns .failure", "Unit test: 3 failures trigger 30s lockout", "Unit test: decoy PIN returns .decoy"],
    "passes": false
  },
  {
    "id": "F5",
    "category": "Phase 1 — UI",
    "description": "Create PINKeypadView component and PINSetupView per PRD Sections 6.1-6.2 — custom numeric keypad, 4-8 digit dots, confirm flow, biometric prompt after setup",
    "verification": ["Views compile", "Preview renders in Xcode", "Keypad shows digits 0-9 + delete + biometric button"],
    "passes": false
  },
  {
    "id": "F6",
    "category": "Phase 1 — UI",
    "description": "Create LockScreenView per PRD Section 6.1 — PIN entry with dot indicators, auto-verify on last digit, shake on wrong PIN, green on correct, lockout countdown, auto biometric prompt",
    "verification": ["View compiles", "Preview renders", "Correct PIN triggers success animation", "Wrong PIN triggers shake animation"],
    "passes": false
  },
  {
    "id": "F7",
    "category": "Phase 1 — Models",
    "description": "Create VaultItem SwiftData model per PRD Section 4 with ItemType enum",
    "verification": ["VaultItem.swift compiles with all fields from PRD", "ItemType enum has photo/video/document cases"],
    "passes": false
  },
  {
    "id": "F8",
    "category": "Phase 1 — Core",
    "description": "Implement VaultService per PRD Section 5.3 — import from PHPicker (encrypt + store + thumbnail), decrypt thumbnail/full image/video, delete (file + model), free tier limit check. Create VaultData/files/ and VaultData/thumbnails/ directory structure",
    "verification": ["VaultService.swift compiles", "Import flow: PHPickerResult → encrypted file at VaultData/files/{uuid}.enc", "Thumbnails are 300x300 max JPEG at 0.7 quality, encrypted"],
    "passes": false
  },
  {
    "id": "F9",
    "category": "Phase 1 — UI",
    "description": "Create VaultGridView per PRD Section 6.3 — 3-column grid, decrypted thumbnails, video duration badge, favorite heart, empty state, item count label, sorting (date imported/created/size), filtering (all/photos/videos/favorites)",
    "verification": ["View compiles", "Grid displays 3 columns with 1pt spacing", "Empty state shows when no items"],
    "passes": false
  },
  {
    "id": "F10",
    "category": "Phase 1 — UI",
    "description": "Create PhotoDetailView per PRD Section 6.5 — full-screen viewer, pinch zoom up to 5x, double-tap 1x/2x toggle, swipe left/right navigation, tap to toggle bars, share sheet, info panel",
    "verification": ["View compiles", "Photo displays full-screen with aspect-fit", "Zoom gesture works"],
    "passes": false
  },
  {
    "id": "F11",
    "category": "Phase 1 — UI",
    "description": "Create VideoPlayerView per PRD Section 6.6 — decrypt to temp file, AVPlayerViewController, delete temp file on dismiss",
    "verification": ["View compiles", "Video plays from decrypted temp URL", "Temp file deleted on dismiss"],
    "passes": false
  },
  {
    "id": "F12",
    "category": "Phase 1 — Models & UI",
    "description": "Create Album SwiftData model per PRD Section 4. Create AlbumGridView per PRD Section 6.4 — 2-column album cards, create/rename/delete albums, 'All Items' album always first",
    "verification": ["Album.swift compiles with all fields", "AlbumGridView displays 2-column grid", "Can create album via + button"],
    "passes": false
  },
  {
    "id": "F13",
    "category": "Phase 1 — Core",
    "description": "Implement delete flow — delete vault items (remove encrypted file + SwiftData model), optional Camera Roll deletion via PHAssetChangeRequest",
    "verification": ["Delete removes .enc file from disk", "Delete removes VaultItem from SwiftData", "Camera Roll deletion prompt appears after import"],
    "passes": false
  },
  {
    "id": "F14",
    "category": "Phase 1 — UI",
    "description": "Implement selection mode — long-press or 'Select' button, checkmark overlay, bottom toolbar with Move to Album / Favorite / Delete actions",
    "verification": ["Long-press enters selection mode", "Selected items show checkmark", "Batch delete works", "Batch move to album works"],
    "passes": false
  },
  {
    "id": "F15",
    "category": "Phase 1 — Navigation",
    "description": "Create ContentView (auth gate: LockScreen → TabView with 4 tabs per PRD Section 6), ImportView with PHPicker + progress modal, VaultBoxApp.swift entry point with SwiftData container setup",
    "verification": ["App launches to LockScreen on fresh install (PINSetupView)", "After PIN setup, shows TabView", "All 4 tabs navigate correctly", "Import flow shows progress bar"],
    "passes": false
  },
  {
    "id": "F16",
    "category": "Phase 1 — ViewModels",
    "description": "Create all ViewModels per PRD Section 3 — AuthViewModel, VaultViewModel, AlbumViewModel, ImportViewModel. Wire up to views",
    "verification": ["All ViewModels compile", "Views bind to ViewModels correctly", "State updates propagate to UI"],
    "passes": false
  },
  {
    "id": "F17",
    "category": "Phase 2 — Monetization",
    "description": "Implement PurchaseService per PRD Section 5.6 — RevenueCat configure, fetch offerings, purchase, restore, premium status check",
    "verification": ["PurchaseService.swift compiles", "RevenueCat SDK initializes on app launch", "isPremium property available"],
    "passes": false
  },
  {
    "id": "F18",
    "category": "Phase 2 — UI",
    "description": "Create PaywallView per PRD Section 6.9 — hero illustration, feature list, weekly/annual toggle (weekly default), CTA button, restore purchases link",
    "verification": ["View compiles and renders in preview", "Weekly selected by default", "Both pricing options shown", "Restore button visible"],
    "passes": false
  },
  {
    "id": "F19",
    "category": "Phase 2 — Gating",
    "description": "Implement PremiumFeature enum and gating per PRD Section 8 — gate all premium features, show paywall at all trigger points listed in PRD",
    "verification": ["Free tier blocked at 50 items", "Tapping premium features shows paywall", "Premium users bypass all gates"],
    "passes": false
  },
  {
    "id": "F20",
    "category": "Phase 2 — UI",
    "description": "Create SettingsView per PRD Section 6.8 — all sections (Security, Appearance, Backup, Privacy, Storage, About)",
    "verification": ["View compiles", "All sections from PRD visible", "Navigation to sub-settings works"],
    "passes": false
  },
  {
    "id": "F21",
    "category": "Phase 2 — UI",
    "description": "Create SecuritySettingsView — change PIN (requires current PIN), biometrics toggle, auto-lock picker, decoy vault entry (premium gated), panic gesture toggle (premium gated)",
    "verification": ["View compiles", "Change PIN flow works", "Biometrics toggle persists", "Premium features show lock icon for free users"],
    "passes": false
  },
  {
    "id": "F22",
    "category": "Phase 2 — ViewModels",
    "description": "Create SettingsViewModel and PaywallViewModel, wire to views",
    "verification": ["ViewModels compile", "Settings state persists", "Paywall state reflects purchase status"],
    "passes": false
  },
  {
    "id": "F23",
    "category": "Phase 3 — Premium",
    "description": "Create BreakInAttempt SwiftData model per PRD Section 4. Implement BreakInService per PRD Section 5.5 — front camera capture, GPS location, local notification, auto-purge at 20 entries",
    "verification": ["Model compiles", "Service captures photo on 3rd failed attempt", "GPS coordinates recorded", "Max 20 entries retained"],
    "passes": false
  },
  {
    "id": "F24",
    "category": "Phase 3 — UI",
    "description": "Create BreakInLogView per PRD Section 6.10 — list of attempts with intruder photo, timestamp, masked PIN, location. Detail view with full photo + map",
    "verification": ["View compiles", "List shows attempts newest first", "Tap row shows detail with map pin"],
    "passes": false
  },
  {
    "id": "F25",
    "category": "Phase 3 — Premium",
    "description": "Implement decoy vault per PRD Section 7.1 — decoy PIN setup, isDecoyMode filtering, limited settings in decoy mode, data isolation via album.isDecoy",
    "verification": ["Decoy PIN can be set (different from real PIN)", "Entering decoy PIN shows only decoy items", "No visible indicator of decoy mode", "Settings limited in decoy mode"],
    "passes": false
  },
  {
    "id": "F26",
    "category": "Phase 3 — Premium",
    "description": "Implement AppIconService per PRD Section 5.7. Create AppIconPickerView per PRD Section 6.8. Add 8 alternate icon assets to Assets.xcassets",
    "verification": ["8 alternate icons in asset catalog", "Icon picker shows all options", "setAlternateIconName changes app icon", "Premium gated"],
    "passes": false
  },
  {
    "id": "F27",
    "category": "Phase 3 — Premium",
    "description": "Implement panic gesture per PRD Section 7.3 — face-down detection via CMMotionManager, three-finger swipe down, immediate lock + clear temp files",
    "verification": ["Face-down triggers lock", "Three-finger swipe triggers lock", "Heavy haptic on trigger", "Works from any screen"],
    "passes": false
  },
  {
    "id": "F28",
    "category": "Phase 3 — Premium",
    "description": "Implement CloudService actor per PRD Section 5.4 — CloudKit private database, upload/download encrypted items, background sync via BGAppRefreshTask, Wi-Fi only default",
    "verification": ["CloudService.swift compiles", "Upload sends encrypted data to CloudKit", "Download retrieves and stores locally", "Background task registered"],
    "passes": false
  },
  {
    "id": "F29",
    "category": "Phase 3 — UI",
    "description": "Create BackupSettingsView per PRD Section 6.8 — iCloud toggle, sync status, manual backup button, iCloud account status check",
    "verification": ["View compiles", "Toggle enables/disables backup", "Status shows upload progress", "Handles iCloud unavailable gracefully"],
    "passes": false
  },
  {
    "id": "F30",
    "category": "Phase 3 — Feature",
    "description": "Implement built-in camera (Tab 3) — direct-to-vault capture via AVFoundation, encrypt on capture, no Camera Roll save",
    "verification": ["Camera tab opens camera", "Captured photo encrypted and added to vault", "Photo does NOT appear in Camera Roll"],
    "passes": false
  },
  {
    "id": "F31",
    "category": "Phase 4 — Polish",
    "description": "Add EmptyStateView component. Add empty states to all screens — vault, albums, break-in log per PRD Section 3",
    "verification": ["Empty vault shows illustration + 'Tap + to add your first photo'", "Empty albums shows placeholder", "Empty break-in log shows message"],
    "passes": false
  },
  {
    "id": "F32",
    "category": "Phase 4 — Polish",
    "description": "Add Haptics.swift utility. Wire haptic feedback to all events per PRD Appendix A haptics table",
    "verification": ["PIN digit tap: light impact", "PIN correct: success notification", "PIN wrong: error notification", "Delete: medium impact", "All haptic events from PRD table implemented"],
    "passes": false
  },
  {
    "id": "F33",
    "category": "Phase 4 — Polish",
    "description": "Animation polish — PIN dot shake on wrong entry (0.5s), PIN dots green on success (0.3s delay), thumbnail loading shimmer, smooth transitions between views",
    "verification": ["Wrong PIN shake animation visible", "Correct PIN green animation visible", "View transitions are smooth"],
    "passes": false
  },
  {
    "id": "F34",
    "category": "Phase 4 — Polish",
    "description": "Add rate prompt — trigger after 10th import using SKStoreReviewController",
    "verification": ["Counter tracks imports", "Review prompt requested after 10th import"],
    "passes": false
  },
  {
    "id": "F35",
    "category": "Phase 4 — Polish",
    "description": "Create PremiumBadge component, VaultItemThumbnail component, AlbumCoverView component per PRD Section 3",
    "verification": ["All components compile and render in preview", "Premium badge shows 'PRO' text", "Thumbnail shows video duration for videos"],
    "passes": false
  },
  {
    "id": "F36",
    "category": "Phase 4 — Polish",
    "description": "Add View+ConditionalModifier extension, Data+Encryption helpers per PRD Section 3",
    "verification": ["Extensions compile", "Used in at least one view/service"],
    "passes": false
  },
  {
    "id": "F37",
    "category": "Phase 4 — Polish",
    "description": "Error handling — implement all user-facing error messages per PRD Appendix B, never show raw errors",
    "verification": ["All error cases from PRD Appendix B have user-facing messages", "No raw error strings shown to user"],
    "passes": false
  },
  {
    "id": "F38",
    "category": "Phase 4 — Polish",
    "description": "Theme support — System/Light/Dark toggle in settings, named colors in Assets.xcassets per PRD Appendix A color tokens",
    "verification": ["All color tokens from PRD exist in asset catalog", "Theme toggle in settings works", "App respects system/light/dark preference"],
    "passes": false
  },
  {
    "id": "F39",
    "category": "Phase 4 — Store",
    "description": "Add privacy policy and terms of service views (SafariView links), restore purchases in settings, version display",
    "verification": ["Privacy policy link opens", "Terms link opens", "Restore purchases triggers RevenueCat restore", "Version shows in settings"],
    "passes": false
  },
  {
    "id": "F40",
    "category": "Phase 4 — Store",
    "description": "Final build validation — clean build, all tests pass, no warnings, portrait lock confirmed, all Info.plist keys present",
    "verification": ["xcodebuild clean build succeeds with 0 warnings", "All unit tests pass", "All UI tests pass", "App locked to portrait", "All 4 Info.plist usage descriptions present"],
    "passes": false
  }
]
```

---

## Verification Commands

```bash
# Build (no signing)
xcodebuild build -project VaultBox.xcodeproj -scheme VaultBox \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO

# Run tests
xcodebuild test -project VaultBox.xcodeproj -scheme VaultBox \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO

# Clean build
xcodebuild clean build -project VaultBox.xcodeproj -scheme VaultBox \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

---

## Reference

- **Product spec:** `VaultBox-PRD.md` — the single source of truth for all product requirements
- **Progress:** `claude-progress.txt` — updated after every session
- **This file:** `plan.md` — agent workflow and feature tracking (do not edit feature definitions)
