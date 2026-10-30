# Quick Capture (Lock Screen secure camera)

Lock Screen / Control Center / Action button capture straight into the encrypted
vault. Nothing goes to the Camera Roll and nothing readable is left on disk.

## Pieces

| Target | Deployment | What it does |
| --- | --- | --- |
| `VaultBoxQuickCapture` (ExtensionKit, `com.apple.securecapture`) | iOS 18 | Camera UI shown over the Lock Screen. Seals every photo/video to the app's public key and writes it into the session content directory. |
| `VaultBoxControls` (WidgetKit) | iOS 18 | `QuickCaptureControl`, a `ControlWidgetButton` running `QuickCaptureIntent`. Usable from Control Center, the Lock Screen and the Action button. |
| `VaultBox` | iOS 17 | Owns the key pair, publishes the public key, ingests captures after the real vault unlocks. `LockedCameraCapture` is weak-linked so iOS 17 still launches. |

Shared sources (`QuickCaptureShared/`): `QuickCaptureIntent` (a `CameraCaptureIntent`, which must be in all three targets), `SealedCapture` (file format) and `SecureCameraViewController` (the camera, extracted from `CameraView.swift` and now used by both the in-app camera tab and the extension).

`OpenVaultCameraIntent` ("Open VaultBox Camera") is a plain App Intent for Shortcuts / the Action button that opens the app and selects the camera tab after unlock. It is not exposed through an `AppShortcutsProvider`, so it does not surface in Spotlight or Siri suggestions.

Disguise: the control, extension display name and extension UI only say "Quick Capture", "Saved" and "Open App", with a `camera.aperture` symbol.

## Why HPKE instead of plaintext + ingest-on-unlock

The capture extension cannot read the master key (Keychain, `.whenUnlockedThisDeviceOnly`), the app group or the network. Two options were evaluated:

1. **Plaintext in the session content directory, encrypt on next unlock.** Simple, but a photo the user explicitly hid sits readable on disk until they next open VaultBox, which may be days. Data protection does not close the gap: the device is AFU (after first unlock) for most of its life, so files at the default class are readable to forensic extraction, backups of the extension container, or anyone with a jailbreak. That contradicts what the vault promises.
2. **Seal to a public key (chosen).** The app generates a Curve25519 key pair, keeps the private key in the Keychain next to the master key, and hands only the public key to the extension through `QuickCaptureIntent.updateAppContext` (the only channel the extension can read). The extension seals with HPKE (`Curve25519_SHA256_ChachaPoly`, RFC 9180) before anything touches disk. Unsealing needs the private key, which only the unlocked app can read.

The extra cost is small: one ~250-line format file with tests, and a one-time setup (the app must be opened once on iOS 18 to publish the key; until then the extension shows "Open the app once to turn on Quick Capture"). Option 2 also lets captures wait safely: they are skipped in decoy mode and when the free item limit is reached, and imported on the next real unlock.

### Format (`SealedCapture`)

`"VBQC" | version | kind | encapsulated key` followed by 1 MiB chunks. Each chunk header (`length | final flag`) is the chunk's AAD, so truncating, reordering or flipping the final flag fails authentication. The kind byte is bound through the HPKE `info`. Videos are streamed chunk by chunk, so memory stays flat in the extension.

### Remaining plaintext window

- **Video during recording.** `AVCaptureMovieFileOutput` must write a real file, so the `.mov` exists only while it is being recorded. It goes into a `completeUnlessOpen` directory and is sealed and deleted as soon as recording stops. If the extension is killed mid-recording, the app imports the leftover on next unlock and then deletes it.
- **Video during import.** On unlock the app decrypts a sealed video to a `complete`-protected temp file, because `VaultService.importVideo` takes a URL. The file is removed right after import, the same as the existing picker import path.

Photos are never plaintext on disk.

## Ingestion

`QuickCaptureService.sync(into:)` runs when the route becomes `.main` and on becoming active while unlocked, never in decoy mode. It:

1. creates the key pair if needed and publishes the public key when it has changed;
2. reads `LockedCameraCaptureManager.shared.sessionContentURLs`;
3. runs `QuickCaptureIngestor`, which imports oldest first and deletes each file once it is in the vault. Wrong-key or tampered files are discarded; a transient failure is retried later; `freeLimitReached` stops and leaves the rest sealed;
4. invalidates the session directories that are now empty.

Tests: `VaultBoxTests/QuickCaptureTests.swift`.

## Simulator

The simulator has no camera, so `SecureCameraViewController` generates a timestamped test photo there (`#if targetEnvironment(simulator)` only). That lets the capture → seal → ingest path run end to end.
