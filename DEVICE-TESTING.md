# Physical-device test plan (1.2.6)

These three changes were merged into `main` on 2026-10-29. Unit tests and simulator builds cover the
code paths, but each one has cases that only a real iPhone (or a real iCloud account) can
exercise. Work through this list before submitting 1.2.6.

| Change | Commit | What was verified before merge |
|---|---|---|
| iCloud key backup hardening | `acb104a` | 14 encryption unit tests. No real CloudKit or iCloud Keychain. |
| Share extension ("Save to VaultBox") | `ed4a1dc`, `440fe9d` | 6 unit tests. Simulator: shared a photo from Photos with the PIN, then saw it appear encrypted after unlock. |
| Recently Deleted bin | `4ded261` | 9 unit tests. An empty store from the old build upgraded cleanly. The screen was never tapped through. |

You need:
- **Device A:** an iPhone on iOS 18 or later (an iPhone 15 Pro or later also covers the Action button).
- **Device B:** a second iPhone or iPad signed into the **same Apple ID**.
- Optionally, an iOS 17 device.
- A sandbox Apple account for premium, since the hard paywall blocks most features.
- The CloudKit Console (container `iCloud.com.vaultbox.app`) to inspect records. App Store and TestFlight builds use the **Production** environment. Builds run from Xcode use **Development**, which holds separate data.

---

## 0. Before you can install the build

- [ ] **App IDs:** register an App ID and profile for `com.pack6.vaultbox.ShareExtension`, with the App Group `group.com.vaultbox.app`.
- [ ] **Versions:** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must be the same for the app and the share extension. `project.yml` and the Xcode project are now on `1.2.6` / `1`, so only raise the build number for a later upload. The App Store rejects an extension whose version differs from its app.
- [ ] **Archive:** archive and upload once to check that App Store Connect validation accepts the share extension.

## 1. iCloud key backup (`acb104a`)

Backups are now locked with the PIN plus a secret stored in iCloud Keychain, which is end-to-end encrypted. Old PIN-only backups upgrade themselves after an unlock with the real PIN.

- [ ] **1.1 Upgrade an old backup.**
  1. On device A, install **1.2.5**, turn on iCloud backup and back up a few photos and a PDF.
  2. Deploy the CloudKit schema to Production so it includes `formatVersion` and `keyFingerprint` on `VaultKeyBackup`, and `encryptedFilename` on `EncryptedVaultItem`. Without these fields, Production will reject the upgrade and new item backups.
  3. Install the new build through **TestFlight** and unlock by **typing** the real PIN, because Face ID doesn't run the upgrade. Stay online for a moment afterwards.
  4. In the CloudKit Console's **Production** environment, `VaultKeyBackup/MasterKeyBackup` should have `formatVersion = 2` and a `keyFingerprint`.
  5. The `EncryptedVaultItem` records should have `encryptedFilename` and **no** `originalFilename`.
  6. If the upgrade fails, Settings → Backup shows "Backup Update Didn't Finish" with the error. Connection errors show no warning and retry on the next PIN unlock.
- [ ] **1.1b Mismatched keys.** Using an account whose items came from two installs:
  1. Restore on an empty vault. Only items the backup's key opens are restored, and the alert says how many were skipped.
  2. Restore on a vault that has its own items and a different key. It's refused with a message, and existing items still open.
  3. Tap Backup Now on a vault whose key differs from the backup. It offers "Replace iCloud Backup?" with the number of items that would be deleted, and uploads nothing unless you confirm.
  4. Choose Keep Current Backup. Nothing changes in the CloudKit Console.
  5. Tap Backup Now again and choose Replace Backup. A wrong PIN and the decoy PIN are rejected, and nothing is deleted.
  6. Enter the real PIN. In the Console, records this device can't open are gone, records it can open remain, and `MasterKeyBackup` has a new fingerprint. New items upload, and restoring on another device brings back everything left.
  7. With iCloud Keychain off, try the replace. It fails with a message and deletes nothing.
- [ ] **1.1c Delete iCloud Backup.** Use an account you can afford to lose.
  1. In Settings → Backup, tap Delete iCloud Backup and cancel. Nothing changes in the CloudKit Console.
  2. Try again. A wrong PIN and the decoy PIN are rejected, and nothing is deleted.
  3. Enter the real PIN. All `EncryptedVaultItem` records and `MasterKeyBackup` are gone, items on the device still open, "Uploaded" shows 0, and the iCloud Backup toggle is off.
  4. Turn backup back on and tap Backup Now. It asks for your PIN to create a new key backup, then uploads everything again.
  5. Turn on airplane mode and try the delete. It shows an error, the sheet stays open, and retrying online finishes it.
  6. Without premium (a lapsed sandbox subscription), Settings → iCloud Backup opens with the upgrade prompt, and Delete iCloud Backup still works.
- [ ] **1.1d Items removed from iCloud.**
  1. Back up a few items, then delete some of their `EncryptedVaultItem` records in the CloudKit Console.
  2. Tap Backup Now. "Uploaded" drops, then climbs back, and only the deleted items get new records. Records that were still there are untouched.
  3. Tap Backup Now again straight away. Nothing uploads and no duplicates appear.
  4. In airplane mode, tap Backup Now. It shows an error and "Uploaded" doesn't change.
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
- [ ] **2.7 Disguise in the share sheet:** the extension's display name is "Quick Save", but on the simulator (2026-10-31) iOS showed a **VaultBox** tile with the real app icon, and the PIN screen's title is also "VaultBox".
  - Check what the share sheet shows on a device, with and without an icon disguise.
  - Check which hiding options iOS offers under share sheet → More → Edit (removing from Favorites, and any on/off switch). Add a line to the disguise setup telling users how to hide the option.
  - Still to decide: under a disguised icon, the home screen label is the product name "VaultBox". A neutral name would fix that for everyone, but App Review may question a name that doesn't match the App Store listing.

## 3. In-app camera

Lock Screen Quick Capture was removed before release on 2026-10-31. The camera tab and the Shortcuts action stay.

- [ ] **3.1 In-app camera:** with premium (sandbox purchase), the camera tab takes photos into the vault and nothing goes to the Camera Roll. Switching cameras works.
- [ ] **3.2 Shortcuts:** the "Open VaultBox Camera" Shortcuts action opens the app, asks for the PIN and then selects the camera tab, including from the Action button. Leave it on the PIN screen for 30 seconds and check that the app stays open.

## 4. Recently Deleted (`4ded261`)

The screen has never been tapped through. Most of this works on a simulator, but 4.2 needs real data.

- [ ] **4.1 Delete and restore:**
  1. Delete a photo, a video and a PDF.
  2. Each one shows up under Albums → Utilities → Recently Deleted with days left.
  3. Restore puts each item back in its original album.
- [ ] **4.2 Upgrade with real data:** install the new build over **1.2.5 with a real vault** of photos, videos, documents and albums. Everything should still be there. The earlier check only used an empty data store.
- [ ] **4.3 Delete Permanently:**
  1. For an item that was never backed up, there's a single Delete Permanently button.
  2. For a backed-up item, the dialog offers "Delete from This Device Only" and "Delete from Device and iCloud".
  3. Device only: the item leaves the device, its `EncryptedVaultItem` record stays, and "Restore from iCloud" brings it back.
  4. Device and iCloud: the record is gone too, and restore doesn't bring it back.
- [ ] **4.4 Decoy:** the decoy vault's bin only shows decoy items, and the real bin only shows real items.
- [ ] **4.5 Panic gesture:** the panic gesture and going to the background both close the Recently Deleted sheet.
- [ ] **4.6 30-day purge:** delete an item, set the device date 31 days ahead and relaunch. The item is gone from the device, and its iCloud copy stays. Reset the date afterwards.
- [ ] **4.7 Offline permanent delete:** an iCloud delete that fails is now queued and retried on launch, unlock, delete, backup and restore. Restore skips anything still in the queue.
  1. With backup on, turn on airplane mode and choose "Delete from Device and iCloud" for a backed-up item. The "Deleted on This Device" note appears.
  2. While still offline, "Restore from iCloud" does nothing (it can't reach iCloud). Back online, "Restore from iCloud" must **not** bring the item back.
  3. Back online, unlock once. The item's `EncryptedVaultItem` record is gone in the CloudKit Console.
  4. Known limit: if the phone never goes back online, a restore on another device can still bring those items back.

## Known gaps found during this work (not fixed)

- Wi-Fi transfer and the album cover picker's "Choose from Vault" list real and decoy items together. Expiring Documents mixes decoy and real reminders.
- Items in Recently Deleted don't count toward the free limit, so restoring can take a free user over it.
