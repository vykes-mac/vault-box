import Testing
import Foundation
import CryptoKit
import SwiftData
import UIKit
@testable import VaultBox

@Suite("Share Inbox Tests")
struct ShareInboxTests {

    enum TestError: Error {
        case failedToCreateImageData
        case missingConfiguration
    }

    private struct Harness {
        let inbox: ShareInboxService
        let vault: VaultService
        let encryption: EncryptionService
        let context: ModelContext
        let container: ModelContainer
        let root: URL
    }

    @MainActor
    private func makeHarness(hasPremiumAccess: Bool = true) async throws -> Harness {
        let schema = Schema([AppSettings.self, VaultItem.self, Album.self, BreakInAttempt.self, DocumentReminder.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let encryption = EncryptionService(keyStorage: InMemoryKeyStorage())
        try await encryption.storeMasterKey(encryption.generateMasterKey())

        let salt = await encryption.generateSalt()
        let settings = AppSettings()
        settings.isSetupComplete = true
        settings.pinSalt = salt.base64EncodedString()
        settings.pinHash = await encryption.hashPIN("1234", salt: salt)
        settings.pinLength = 4
        context.insert(settings)
        try context.save()

        let vault = VaultService(
            encryptionService: encryption,
            modelContext: context,
            hasPremiumAccess: { hasPremiumAccess }
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxTests-\(UUID().uuidString)", isDirectory: true)
        let inbox = ShareInboxService(
            vaultService: vault,
            modelContext: context,
            keyStorage: InMemoryKeyStorage(),
            hasPremiumAccess: { hasPremiumAccess },
            rootDirectory: root
        )
        return Harness(inbox: inbox, vault: vault, encryption: encryption, context: context, container: container, root: root)
    }

    private func makeImageData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        guard let data = image.pngData() else { throw TestError.failedToCreateImageData }
        return data
    }

    private func metadata(_ kind: ShareInboxItemMetadata.Kind, _ filename: String, isDecoy: Bool = false) -> ShareInboxItemMetadata {
        ShareInboxItemMetadata(kind: kind, filename: filename, isDecoy: isDecoy, sharedAt: Date())
    }

    // MARK: - Ingestion

    @Test("Shared photo is ingested into the vault encrypted and removed from the inbox")
    @MainActor
    func ingestsSharedPhoto() async throws {
        let harness = try await makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        harness.inbox.publishConfiguration()
        let configuration = try #require(ShareInboxConfiguration.read(from: harness.root))
        #expect(configuration.pin.matches("1234"))
        #expect(!configuration.pin.matches("9999"))

        let imageData = try makeImageData()
        try ShareInbox.enqueue(
            .data(imageData),
            metadata: metadata(.photo, "IMG_0001.png"),
            recipientPublicKey: configuration.recipientPublicKey,
            root: harness.root
        )
        #expect(ShareInbox.pendingPayloads(in: harness.root).count == 1)

        let summary = await harness.inbox.ingestPendingItems(isDecoyMode: false)

        #expect(summary == ShareInboxIngestSummary(imported: 1, waitingForPremium: 0, failed: 0))
        #expect(ShareInbox.pendingPayloads(in: harness.root).isEmpty)

        let items = try harness.context.fetch(FetchDescriptor<VaultItem>())
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.type == .photo)
        #expect(item.originalFilename == "IMG_0001.png")
        #expect(item.encryptedThumbnailData != nil)

        let decrypted = try await harness.vault.decryptFileData(for: item)
        #expect(decrypted == imageData)
    }

    @Test("Documents wait in the inbox for free users instead of being dropped")
    @MainActor
    func documentsWaitForPremium() async throws {
        let harness = try await makeHarness(hasPremiumAccess: false)
        defer { try? FileManager.default.removeItem(at: harness.root) }

        harness.inbox.publishConfiguration()
        let configuration = try #require(ShareInboxConfiguration.read(from: harness.root))
        #expect(configuration.canImportDocuments == false)

        try ShareInbox.enqueue(
            .data(Data("%PDF-1.4 private".utf8)),
            metadata: metadata(.document, "passport.pdf"),
            recipientPublicKey: configuration.recipientPublicKey,
            root: harness.root
        )

        let summary = await harness.inbox.ingestPendingItems(isDecoyMode: false)

        #expect(summary == ShareInboxIngestSummary(imported: 0, waitingForPremium: 1, failed: 0))
        #expect(ShareInbox.pendingPayloads(in: harness.root).count == 1)
        #expect(try harness.context.fetchCount(FetchDescriptor<VaultItem>()) == 0)
    }

    @Test("Decoy shares only import while the decoy vault is open")
    @MainActor
    func decoySharesStayOutOfRealVault() async throws {
        let harness = try await makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.root) }

        harness.inbox.publishConfiguration()
        let configuration = try #require(ShareInboxConfiguration.read(from: harness.root))
        try ShareInbox.enqueue(
            .data(try makeImageData()),
            metadata: metadata(.photo, "decoy.png", isDecoy: true),
            recipientPublicKey: configuration.recipientPublicKey,
            root: harness.root
        )

        let realSummary = await harness.inbox.ingestPendingItems(isDecoyMode: false)
        #expect(realSummary.isEmpty)
        #expect(ShareInbox.pendingPayloads(in: harness.root).count == 1)

        let decoySummary = await harness.inbox.ingestPendingItems(isDecoyMode: true)
        #expect(decoySummary.imported == 1)
        let item = try #require(try harness.context.fetch(FetchDescriptor<VaultItem>()).first)
        #expect(item.album?.isDecoy == true)
    }

    // MARK: - Payload Format

    @Test("Multi-chunk payload round-trips and tampering is rejected")
    func payloadRoundTripAndTamper() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareInboxPayload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let content = Data((0..<(ShareInboxPayload.chunkSize * 2 + 123)).map { UInt8($0 % 251) })
        let source = dir.appendingPathComponent("source.bin")
        try content.write(to: source)

        let payload = dir.appendingPathComponent("item.vbshare")
        let sharedMetadata = metadata(.video, "clip.mov")
        try ShareInboxPayload.seal(
            .file(source),
            metadata: sharedMetadata,
            recipientPublicKey: privateKey.publicKey.rawRepresentation,
            to: payload
        )

        let output = dir.appendingPathComponent("out.bin")
        let opened = try ShareInboxPayload.open(
            at: payload,
            privateKey: privateKey.rawRepresentation,
            writingContentsTo: output
        )
        #expect(opened == sharedMetadata)
        #expect(try Data(contentsOf: output) == content)

        // Dropping the last record must not pass as a shorter, valid file.
        var sealed = try Data(contentsOf: payload)
        let truncated = dir.appendingPathComponent("truncated.vbshare")
        try sealed.prefix(sealed.count - 200).write(to: truncated)
        #expect(throws: (any Error).self) {
            try ShareInboxPayload.open(at: truncated, privateKey: privateKey.rawRepresentation, writingContentsTo: output)
        }

        sealed[sealed.count / 2] ^= 0xFF
        let tampered = dir.appendingPathComponent("tampered.vbshare")
        try sealed.write(to: tampered)
        #expect(throws: (any Error).self) {
            try ShareInboxPayload.open(at: tampered, privateKey: privateKey.rawRepresentation, writingContentsTo: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))

        let wrongKey = Curve25519.KeyAgreement.PrivateKey()
        #expect(throws: (any Error).self) {
            try ShareInboxPayload.readMetadata(at: payload, privateKey: wrongKey.rawRepresentation)
        }
    }

    @Test("PIN verifier matches EncryptionService hashing and limits match app constants")
    func verifierAndLimitsMatchApp() async {
        let encryption = EncryptionService(keyStorage: InMemoryKeyStorage())
        let salt = await encryption.generateSalt()
        let appHash = await encryption.hashPIN("482913", salt: salt)
        #expect(ShareInboxConfiguration.PINVerifier.hash("482913", salt: salt) == appHash)
        #expect(ShareInbox.maxVideoBytes == Int64(Constants.maxVideoImportBytes))
        #expect(ShareInbox.maxDocumentBytes == Int64(Constants.maxDocumentImportBytes))
    }

    @Test("Shared filenames can't escape the work directory")
    func filenameSanitizing() {
        #expect(ShareInbox.sanitizedFilename("../../etc/passwd", fallback: "x") == "passwd")
        #expect(ShareInbox.sanitizedFilename("  ", fallback: "Shared Item") == "Shared Item")
        #expect(ShareInbox.sanitizedFilename("..", fallback: "x") == "x")
        #expect(ShareInbox.sanitizedFilename(nil, fallback: "x") == "x")
    }
}
