import Foundation
import CryptoKit
import LockedCameraCapture

// MARK: - Protocols

/// Where ingested Lock Screen captures end up. `VaultService` is the real implementation.
@MainActor
protocol QuickCaptureImporting: AnyObject {
    func importQuickCapturePhoto(_ data: Data) async throws
    func importQuickCaptureVideo(at url: URL) async throws
}

/// The directories the capture extension wrote into, one per capture session.
protocol QuickCaptureContentSource: Sendable {
    func sessionDirectories() async -> [URL]
    func invalidate(_ directory: URL) async
}

@available(iOS 18.0, *)
struct LockedCameraCaptureContentSource: QuickCaptureContentSource {
    func sessionDirectories() async -> [URL] {
        LockedCameraCaptureManager.shared.sessionContentURLs
    }

    func invalidate(_ directory: URL) async {
        try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: directory)
    }
}

/// iOS 17 has no Lock Screen capture, so there is never anything to ingest.
struct EmptyQuickCaptureContentSource: QuickCaptureContentSource {
    func sessionDirectories() async -> [URL] { [] }
    func invalidate(_ directory: URL) async {}
}

// MARK: - QuickCaptureIngestor

struct QuickCaptureIngestReport: Equatable, Sendable {
    var imported = 0
    /// Files that can never be imported (corrupt, wrong key, partial recording) and were removed.
    var discarded = 0
    /// Files left in place to retry on a later unlock (e.g. the free item limit was hit).
    var deferred = 0
}

/// Decrypts sealed Lock Screen captures and imports them into the vault, removing each
/// file once it is safely in the vault.
@MainActor
struct QuickCaptureIngestor {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let importer: any QuickCaptureImporting
    /// Holds a decrypted video only for the duration of its import.
    let scratchDirectory: URL

    private enum Outcome {
        case imported
        case discarded
        case retryLater
        case limitReached
    }

    func ingest(_ directories: [URL]) async -> (report: QuickCaptureIngestReport, drained: [URL]) {
        var report = QuickCaptureIngestReport()
        var drained: [URL] = []

        for directory in directories {
            let files = Self.captureFiles(in: directory)
            for (index, file) in files.enumerated() {
                switch await ingestFile(file) {
                case .imported:
                    report.imported += 1
                case .discarded:
                    report.discarded += 1
                case .retryLater:
                    report.deferred += 1
                case .limitReached:
                    report.deferred += files.count - index
                    return (report, drained)
                }
            }
            if Self.captureFiles(in: directory).isEmpty {
                drained.append(directory)
            }
        }
        return (report, drained)
    }

    private func ingestFile(_ url: URL) async -> Outcome {
        let isSealed = url.pathExtension == SealedCapture.fileExtension
        var decryptedVideoURL: URL?
        defer {
            if let decryptedVideoURL { try? FileManager.default.removeItem(at: decryptedVideoURL) }
        }

        do {
            if isSealed {
                try FileManager.default.createDirectory(
                    at: scratchDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.complete]
                )
                let photoData: Data?
                do {
                    switch try SealedCapture.kind(ofFileAt: url) {
                    case .photo:
                        photoData = try SealedCapture.open(Data(contentsOf: url), with: privateKey).plaintext
                    case .video:
                        let destination = scratchDirectory.appendingPathComponent("\(UUID().uuidString).mov")
                        decryptedVideoURL = destination
                        try SealedCapture.openFile(at: url, with: privateKey, destination: destination)
                        photoData = nil
                    }
                } catch where Self.isUnrecoverable(error) {
                    // A wrong key or tampered file can never succeed later.
                    try? FileManager.default.removeItem(at: url)
                    return .discarded
                }

                if let photoData {
                    try await importer.importQuickCapturePhoto(photoData)
                } else if let decryptedVideoURL {
                    try await importer.importQuickCaptureVideo(at: decryptedVideoURL)
                }
            } else {
                // A recording the extension was killed before it could seal.
                try await importer.importQuickCaptureVideo(at: url)
            }
        } catch VaultError.freeLimitReached {
            return .limitReached
        } catch {
            guard isSealed else {
                // Unsealed leftovers are usually truncated recordings; don't keep plaintext around.
                try? FileManager.default.removeItem(at: url)
                return .discarded
            }
            return .retryLater
        }

        try? FileManager.default.removeItem(at: url)
        return .imported
    }

    private static func isUnrecoverable(_ error: any Error) -> Bool {
        error is SealedCapture.FormatError || error is CryptoKitError || error is HPKE.Errors
    }

    /// Sealed captures plus any unsealed recordings, oldest first.
    static func captureFiles(in directory: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        let recordingExtensions: Set<String> = ["mov", "mp4"]
        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true else { return false }
                let ext = url.pathExtension.lowercased()
                return ext == SealedCapture.fileExtension || recordingExtensions.contains(ext)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

// MARK: - QuickCaptureService

/// Owns the Lock Screen capture key pair and moves captures into the vault after unlock.
///
/// The extension only ever gets the public key (through `QuickCaptureIntent`'s app
/// context). The private key sits in the Keychain next to the master key, readable only
/// while the device is unlocked.
@MainActor
final class QuickCaptureService {
    private let keyStorage: KeyStorage
    private let contentSource: QuickCaptureContentSource
    private let scratchDirectory: URL
    private var isSyncing = false

    init(
        keyStorage: KeyStorage = KeychainKeyStorage(),
        contentSource: QuickCaptureContentSource? = nil,
        scratchDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("QuickCapture", isDirectory: true)
    ) {
        self.keyStorage = keyStorage
        if let contentSource {
            self.contentSource = contentSource
        } else if #available(iOS 18.0, *) {
            self.contentSource = LockedCameraCaptureContentSource()
        } else {
            self.contentSource = EmptyQuickCaptureContentSource()
        }
        self.scratchDirectory = scratchDirectory
    }

    func loadOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let data = try keyStorage.getData(Constants.keychainQuickCaptureKeyID) {
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try keyStorage.set(key.rawRepresentation, forKey: Constants.keychainQuickCaptureKeyID)
        return key
    }

    /// Publishes the public key for the extension and imports anything captured while
    /// the vault was locked. Call only once the real (non-decoy) vault is unlocked.
    @discardableResult
    func sync(into importer: any QuickCaptureImporting) async -> QuickCaptureIngestReport? {
        guard !isSyncing else { return nil }
        isSyncing = true
        defer { isSyncing = false }

        guard let privateKey = try? loadOrCreatePrivateKey() else { return nil }
        await publishRecipientKey(privateKey.publicKey)

        let directories = await contentSource.sessionDirectories()
        guard !directories.isEmpty else { return QuickCaptureIngestReport() }

        let ingestor = QuickCaptureIngestor(
            privateKey: privateKey,
            importer: importer,
            scratchDirectory: scratchDirectory
        )
        let result = await ingestor.ingest(directories)
        for directory in result.drained {
            await contentSource.invalidate(directory)
        }
        return result.report
    }

    private func publishRecipientKey(_ publicKey: Curve25519.KeyAgreement.PublicKey) async {
        guard #available(iOS 18.0, *) else { return }
        let context = QuickCaptureContext(recipientPublicKey: publicKey.rawRepresentation)
        if let current = try? await QuickCaptureIntent.appContext, current == context { return }
        try? await QuickCaptureIntent.updateAppContext(context)
    }
}

// MARK: - VaultService + QuickCaptureImporting

extension VaultService: QuickCaptureImporting {
    func importQuickCapturePhoto(_ data: Data) async throws {
        let item = try await importPhotoData(
            data,
            filename: String(localized: "Camera Photo"),
            album: nil,
            isDecoyMode: false
        )
        queueVisionAnalysis(for: [item])
        queueSearchIndexing(for: [item])
    }

    func importQuickCaptureVideo(at url: URL) async throws {
        _ = try await importVideo(at: url, filename: nil, album: nil, isDecoyMode: false)
    }
}
