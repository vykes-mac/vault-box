# Physical-device test plan (1.2.6)

These four changes were merged into `main` on 2026-10-29. Unit tests and simulator builds cover the
code paths, but each one has cases that only a real iPhone (or a real iCloud account) can
exercise. Work through this list before submitting 1.2.6.

| Change | Commit | What was verified before merge |
|---|---|---|
| iCloud key backup hardening | `acb104a` | 14 encryption unit tests. No real CloudKit or iCloud Keychain. |
| Share extension ("Save to VaultBox") | `ed4a1dc`, `440fe9d` | 6 unit tests. Simulator: shared a photo from Photos with the PIN, then saw it appear encrypted after unlock. |
| Recently Deleted bin | `4ded261` | 9 unit tests. An empty store from the old build upgraded cleanly. The screen was never tapped through. |
| Lock Screen Quick Capture | `3ecfcb8` | 13 unit tests, plus the build. The simulator hides camera-capture controls, so nothing was run end to end. |

You need:
- **Device A:** an iPhone on iOS 18 or later (an iPhone 15 Pro or later also covers the Action button).
- **Device B:** a second iPhone or iPad signed into the **same Apple ID**.
- Optionally, an iOS 17 device.
- A sandbox Apple account for premium, since the hard paywall blocks most features.
- The CloudKit Console (container `iCloud.com.vaultbox.app`) to inspect records. App Store and TestFlight builds use the **Production** environment. Builds run from Xcode use **Development**, which holds separate data.

---

## 0. Before you can install the build

- [ ] **App IDs:** register App IDs and profiles for the three new bundle IDs:
  - `com.pack6.vaultbox.ShareExtension`, with the App Group `group.com.vaultbox.app`
  - `com.pack6.vaultbox.QuickCapture`
  - `com.pack6.vaultbox.Controls`
- [ ] **Versions:** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must be the same for the app and all three extensions. `project.yml` and the Xcode project are now on `1.2.6` / `1`, so only raise the build number for a later upload. The App Store rejects an extension whose version differs from its app.
- [ ] **Archive:** archive and upload once to check that App Store Connect validation accepts all three extensions.

## 1. iCloud key backup (`acb104a`)

Backups are now locked with the PIN plus a secret stored in iCloud Keychain, which is end-to-end encrypted. Old PIN-only backups upgrade themselves after an unlock with the real PIN.

- [ ] **1.1 Upgrade an old backup.**
  1. On device A, install **1.2.5**, turn on iCloud backup and back up a few photos and a PDF.
  2. Deploy the CloudKit schema to Production so it includes `formatVersion` and `keyFingerprint` on `VaultKeyBackup`, and `encryptedFilename` on `EncryptedVaultItem`. Without these fields, Production will reject the upgrade and new item backups.
  3. Install the new build through **TestFlight** and unlock by **typing** the real PIN, because Face ID doesn't run the upgrade. Stay online for a moment afterwards.
  4. In the CloudKit Console's **Production** environment, `VaultKeyBackup/MasterKeyBackup` should have `formatVersion = 2` and a `keyFingerprint`.
  5. The `EncryptedVaultItem` records should have `encryptedFilename` and **no** `originalFilename`.
  6. If the upgrade fails, Settings → Backup shows "Backup Update Didn't Finish" with the error. Connection errors show no warning and retry on the next PIN unlock.
- [ ] **1.2 Restore on a new device.** On device B with iCloud Keychain on, do a fresh install, then use Settings → Backup → Restore with the PIN. Every item should come back with its original filename (check a PDF's name).
- [ ] **1.3 iCloud Keychain off.** On device B, turn off iCloud Keychain and restore. You should see the "turn on iCloud Keychain" message, with no crash and no partial restore.
- [ ] **1.4 After a PIN change.**
  1. On device A, change the PIN, lock the app and unlock with the new PIN.
  2. Restore on device B: the **new** PIN works and the old PIN is rejected.
- [ ] **1.5 A fresh install must not overwrite the backup.**
  1. On device B, do a fresh install and set up a new vault without restoring.
  2. Turn on backup and unlock.
  3. Then restore on another fresh install with device A's PIN. Device A's data must still come back.
- [ ] **1.6 Decoy PIN.** Unlocking with the decoy PIN must not change the `VaultKeyBackup` record. Check its modification date.
- [ ] **1.7 Offline unlock.** Unlock in airplane mode, then online. The upgrade from 1.1 should happen on the online unlock.

## 2. Share extension (`ed4a1dc`, `440fe9d`)

The basic Photos → share → unlock flow passed on the simulator using the PIN. On a device, check:

- [ ] **2.1 Face ID:** Face ID unlocks inside the share sheet. The simulator only tested the PIN.
- [ ] **2.2 Long video:** share a long 4K video (2–5 min, over 1 GB) from Photos. The extension must not be killed for memory (about a 120 MB limit), and the video must play after it's imported.
- [ ] **2.3 Other apps and several items at once:**
  - [ ] several photos in one share
  - [ ] a PDF from Files
  - [ ] an image from Safari
  - [ ] a photo or video from WhatsApp
- [ ] **2.4 Decoy PIN:** entering the decoy PIN in the extension sends the items to the decoy vault only.
- [ ] **2.5 Free user:** documents shared by a free user stay in the inbox and import after upgrading. Check the free item limit too.
- [ ] **2.6 Wrong PIN:** wrong PINs in the extension count toward lockout and break-in capture the same way they do in the app.
- [ ] **2.7 Disguise in the share sheet:** the share option is now called "Quick Save", and its PIN screen says "Enter your PIN" with no mention of VaultBox.
  - With an icon disguise on, check which icon the share sheet shows next to "Quick Save". If it's the real VaultBox icon, no code can change that. Add a line to the disguise setup telling users how to hide the option from their share sheet.
  - Check which hiding options iOS offers under share sheet → More → Edit (removing from Favorites, and any on/off switch).
  - Still to decide: under a disguised icon, the home screen label is the product name "VaultBox". A neutral name would fix that for everyone, but App Review may question a name that doesn't match the App Store listing.

## 3. Lock Screen Quick Capture (`3ecfcb8`), iOS 18 or later only

Not verified end to end anywhere. Design notes are in `QUICK-CAPTURE.md`.

- [ ] **3.1 Before first open:** on a fresh install, before opening the app, the capture extension shows "Open the app once to turn on Quick Capture". Open the app once and it starts working.
- [ ] **3.2 Adding the control:** add the "Quick Capture" control to each of these:
  - [ ] Control Center
  - [ ] a Lock Screen slot
  - [ ] the Action button (15 Pro or later)
- [ ] **3.3 Photo from a locked phone:** with the phone locked, take a photo with the control. Then unlock VaultBox with the real PIN. The photo is in the vault and **not** in the Camera Roll.
- [ ] **3.4 Video:** take a video. The microphone permission prompt appears, sound is recorded, a long video (over 1 min) imports and plays, and no readable video is left behind.
- [ ] **3.5 Decoy mode:** unlock with the decoy PIN. Pending captures are not imported into the decoy vault and appear after the next real unlock.
- [ ] **3.6 Free limit:** at the free item limit, captures are held back. There's currently no message telling the user this (known gap).
- [ ] **3.7 Shortcuts:** the "Open VaultBox Camera" Shortcuts action works, including from the Action button.
- [ ] **3.8 Disguise:** with an icon disguise on, the control and the capture screen only say "Quick Capture", "Saved" and "Open App".
- [ ] **3.9 In-app camera:** with premium (sandbox purchase), the camera inside the app, which was rebuilt for this change, takes photos and videos into the vault.
- [ ] **3.10 iOS 17:** on an iOS 17 device, the app launches normally and no control is offered.

## 4. Recently Deleted (`4ded261`)

The screen has never been tapped through. Most of this works on a simulator, but 4.2 needs real data.

- [ ] **4.1 Delete and restore:**
  1. Delete a photo, a video and a PDF.
  2. Each one shows up under Albums → Utilities → Recently Deleted with days left.
  3. Restore puts each item back in its original album.
- [ ] **4.2 Upgrade with real data:** install the new build over **1.2.5 with a real vault** of photos, videos, documents and albums. Everything should still be there. The earlier check only used an empty data store.
- [ ] **4.3 Delete Permanently** removes the item, and with backup on, its `EncryptedVaultItem` record in CloudKit.
- [ ] **4.4 Decoy:** the decoy vault's bin only shows decoy items, and the real bin only shows real items.
- [ ] **4.5 Panic gesture:** the panic gesture and going to the background both close the Recently Deleted sheet.
- [ ] **4.6 30-day purge:** delete an item, set the device date 31 days ahead and relaunch. The item is gone. Reset the date afterwards.
- [ ] **4.7 Offline permanent delete:** an iCloud delete that fails is now queued and retried on launch, unlock, delete, backup and restore. Restore skips anything still in the queue.
  1. With backup on, turn on airplane mode and permanently delete a backed-up item. The "Deleted on This Device" note appears.
  2. While still offline, "Restore from iCloud" does nothing (it can't reach iCloud). Back online, "Restore from iCloud" must **not** bring the item back.
  3. Back online, unlock once. The item's `EncryptedVaultItem` record is gone in the CloudKit Console.
  4. Known limit: if the phone never goes back online, a restore on another device can still bring those items back.

## Known gaps found during this work (not fixed)

- Quick Capture text isn't translated, and resetting the vault doesn't delete the Quick Capture key.
- Wi-Fi transfer and the album cover picker's "Choose from Vault" list real and decoy items together. Expiring Documents mixes decoy and real reminders.
- Items in Recently Deleted don't count toward the free limit, so restoring can take a free user over it.
