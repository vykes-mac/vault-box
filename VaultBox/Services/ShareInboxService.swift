import Foundation
import CryptoKit
import SwiftData

// MARK: - Ingest Summary

struct ShareInboxIngestSummary: Equatable, Sendable {
    var imported = 0
    /// Left in the inbox because the free item limit or the premium-only document import
    /// blocked them; they import once the user upgrades.
    var waitingForPremium = 0
    /// Unreadable or rejected payloads, removed from the inbox.
    var failed = 0

    var isEmpty: Bool { imported == 0 && waitingForPremium == 0 && failed == 0 }
}

// MARK: - ShareInboxService

/// Bridges the share extension and the vault. The extension seals shared files to this
/// service's public key; on unlock the app opens them and imports them through
/// `VaultService`, so shared items get the same encryption, limits and indexing as any
/// other import.
@MainActor
@Observable
class ShareInboxService {
    private let vaultService: VaultService
    private let modelContext: ModelContext
    private let keyStorage: KeyStorage
    private let hasPremiumAccess: () -> Bool
    private let rootDirectory: URL?

    private(set) var isIngesting = false

    init(
        vaultService: VaultService,
        modelContext: ModelContext,
        keyStorage: KeyStorage = KeychainKeyStorage(),
        hasPremiumAccess: @escaping () -> Bool = { false },
        rootDirectory: URL? = ShareInbox.rootDirectory()
    ) {
        self.vaultService = vaultService
        self.modelContext = modelContext
        self.keyStorage = keyStorage
        self.hasPremiumAccess = hasPremiumAccess
        self.rootDirectory = rootDirectory
    }

    // MARK: - Configuration

    /// Writes what the extension needs to gate and seal shares: the inbox public key plus
    /// the PIN verifiers. Called on unlock and on backgrounding so PIN, biometric and
    /// premium changes reach the extension.
    func publishConfiguration() {
        guard let rootDirectory else { return }
        guard let settings = try? modelContext.fetch(FetchDescriptor<AppSettings>()).first,
              settings.isSetupComplete,
              !settings.pinHash.isEmpty,
              let pinSalt = Data(base64Encoded: settings.pinSalt) else {
            ShareInboxConfiguration.remove(from: rootDirectory)
            return
        }

        var decoyPIN: ShareInboxConfiguration.PINVerifier?
        if hasPremiumAccess(),
           let decoyHash = settings.decoyPINHash,
           let decoySalt = settings.decoyPINSalt.flatMap({ Data(base64Encoded: $0) }) {
            decoyPIN = .init(salt: decoySalt, hash: decoyHash)
        }

        do {
            let configuration = ShareInboxConfiguration(
                recipientPublicKey: try inboxPrivateKey().publicKey.rawRepresentation,
                pin: .init(salt: pinSalt, hash: settings.pinHash),
                decoyPIN: decoyPIN,
                pinLength: settings.pinLength,
                biometricsEnabled: settings.biometricsEnabled,
                lockoutUntil: settings.lockoutUntil,
                canImportDocuments: hasPremiumAccess()
            )
            if ShareInboxConfiguration.read(from: rootDirectory) != configuration {
                try configuration.write(to: rootDirectory)
            }
        } catch {
            #if DEBUG
            print("[ShareInboxService] Failed to publish configuration: \(error)")
            #endif
        }
    }

    // MARK: - Ingestion

    /// Imports every pending payload that belongs to the vault being unlocked. Payloads
    /// shared with the decoy PIN only import in decoy mode and vice versa, so neither
    /// vault reveals that the other received anything.
    func ingestPendingItems(isDecoyMode: Bool) async -> ShareInboxIngestSummary {
        var summary = ShareInboxIngestSummary()
        guard !isIngesting, let rootDirectory else { return summary }
        isIngesting = true
        defer { isIngesting = false }

        ShareInbox.removeStalePartials(in: rootDirectory)
        let payloads = ShareInbox.pendingPayloads(in: rootDirectory)
        guard !payloads.isEmpty else { return summary }

        guard let privateKey = try? existingInboxPrivateKey() else {
            // Without the key nothing in the inbox can ever be opened.
            for url in payloads { try? FileManager.default.removeItem(at: url) }
            summary.failed = payloads.count
            return summary
        }
        let privateKeyData = privateKey.rawRepresentation

        var importedItems: [VaultItem] = []
        for payloadURL in payloads {
            let workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ShareInbox-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            do {
                let metadata = try await Task.detached {
                    try ShareInboxPayload.readMetadata(at: payloadURL, privateKey: privateKeyData)
                }.value
                guard metadata.isDecoy == isDecoyMode else { continue }

                try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
                let filename = ShareInbox.sanitizedFilename(
                    metadata.filename,
                    fallback: String(localized: "Shared Item")
                )
                let plaintextURL = workDirectory.appendingPathComponent(filename)
                _ = try await Task.detached {
                    try ShareInboxPayload.open(
                        at: payloadURL,
                        privateKey: privateKeyData,
                        writingContentsTo: plaintextURL
                    )
                }.value

                let item = try await importDecrypted(
                    at: plaintextURL,
                    filename: filename,
                    kind: metadata.kind,
                    isDecoyMode: isDecoyMode
                )
                importedItems.append(item)
                try? FileManager.default.removeItem(at: payloadURL)
                summary.imported += 1
            } catch let error as VaultError where error == .premiumRequired || error == .freeLimitReached {
                summary.waitingForPremium += 1
            } catch {
                try? FileManager.default.removeItem(at: payloadURL)
                summary.failed += 1
            }
        }

        if !importedItems.isEmpty {
            vaultService.queueVisionAnalysis(for: importedItems)
            vaultService.queueSearchIndexing(for: importedItems)
        }
        return summary
    }

    private func importDecrypted(
        at url: URL,
        filename: String,
        kind: ShareInboxItemMetadata.Kind,
        isDecoyMode: Bool
    ) async throws -> VaultItem {
        switch kind {
        case .photo:
            let data = try Data(contentsOf: url)
            return try await vaultService.importPhotoData(
                data,
                filename: filename,
                album: nil,
                isDecoyMode: isDecoyMode
            )
        case .video:
            return try await vaultService.importVideo(
                at: url,
                filename: filename,
                album: nil,
                isDecoyMode: isDecoyMode
            )
        case .document:
            return try await vaultService.importDocument(at: url, album: nil, isDecoyMode: isDecoyMode)
        }
    }

    // MARK: - Inbox Key

    private func existingInboxPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey? {
        guard let data = try keyStorage.getData(Constants.keychainShareInboxKeyID) else { return nil }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private func inboxPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try existingInboxPrivateKey() {
            return existing
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try keyStorage.set(key.rawRepresentation, forKey: Constants.keychainShareInboxKeyID)
        return key
    }
}
