import Foundation
import CryptoKit

// Compiled into both the app and the share extension. The extension never sees the vault
// master key: it seals each shared file to a Curve25519 public key the app publishes in the
// app group, and the app (which keeps the private key in its own Keychain) opens the
// payload and runs it through the normal import path on the next unlock.

// MARK: - Inbox Locations

enum ShareInbox {
    static let appGroupIdentifier = "group.com.vaultbox.app"
    static let directoryName = "ShareInbox"
    static let configurationFilename = "configuration.json"
    static let pendingSubdirectory = "pending"
    static let payloadExtension = "vbshare"
    static let partialExtension = "partial"

    /// Mirrors `Constants.maxVideoImportBytes`; the extension rejects larger videos up front
    /// instead of encrypting something the app will refuse to import.
    static let maxVideoBytes: Int64 = 250 * 1024 * 1024
    /// Mirrors `Constants.maxDocumentImportBytes`.
    static let maxDocumentBytes: Int64 = 100 * 1024 * 1024

    /// Partial payloads older than this were abandoned by an extension that got killed.
    static let stalePartialInterval: TimeInterval = 24 * 60 * 60

    static func rootDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func pendingDirectory(in root: URL) throws -> URL {
        let dir = root.appendingPathComponent(pendingSubdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Finished payloads, oldest first so imports keep the order things were shared in.
    static func pendingPayloads(in root: URL) -> [URL] {
        let dir = root.appendingPathComponent(pendingSubdirectory, isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension == payloadExtension }
            .sorted { creationDate(of: $0) < creationDate(of: $1) }
    }

    static func removeStalePartials(in root: URL, now: Date = Date()) {
        let dir = root.appendingPathComponent(pendingSubdirectory, isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        for url in urls where url.pathExtension == partialExtension {
            if now.timeIntervalSince(creationDate(of: url)) > stalePartialInterval {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Seals `source` into the pending folder. The payload is written under a `.partial`
    /// name and renamed once complete, so the app never ingests a half-written file.
    @discardableResult
    static func enqueue(
        _ source: ShareInboxPayload.Source,
        metadata: ShareInboxItemMetadata,
        recipientPublicKey: Data,
        root: URL
    ) throws -> URL {
        let dir = try pendingDirectory(in: root)
        let id = UUID().uuidString
        let partialURL = dir.appendingPathComponent(id).appendingPathExtension(partialExtension)
        let finalURL = dir.appendingPathComponent(id).appendingPathExtension(payloadExtension)
        do {
            try ShareInboxPayload.seal(
                source,
                metadata: metadata,
                recipientPublicKey: recipientPublicKey,
                to: partialURL
            )
            try FileManager.default.moveItem(at: partialURL, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
        return finalURL
    }

    /// Strips any path components so a payload can't name a file outside its work folder.
    static func sanitizedFilename(_ name: String?, fallback: String) -> String {
        let last = ((name ?? "") as NSString).lastPathComponent
        let cleaned = last
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return fallback }
        return cleaned
    }

    private static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

// MARK: - Configuration (published by the app, read by the extension)

struct ShareInboxConfiguration: Codable, Equatable, Sendable {
    struct PINVerifier: Codable, Equatable, Sendable {
        var salt: Data
        /// Hex SHA-256 of salt || PIN, the same verifier `EncryptionService.hashPIN` stores.
        var hash: String

        func matches(_ pin: String) -> Bool {
            Self.hash(pin, salt: salt) == hash
        }

        static func hash(_ pin: String, salt: Data) -> String {
            var combined = salt
            combined.append(Data(pin.utf8))
            return SHA256.hash(data: combined).map { String(format: "%02x", $0) }.joined()
        }
    }

    static let currentVersion = 1

    var version: Int = Self.currentVersion
    /// Raw Curve25519 key-agreement public key the extension seals payloads to.
    var recipientPublicKey: Data
    var pin: PINVerifier
    /// Only present while the decoy vault is available (premium), so a decoy PIN typed
    /// into the share sheet files items into the decoy vault exactly like the app does.
    var decoyPIN: PINVerifier?
    var pinLength: Int
    var biometricsEnabled: Bool
    /// The app's own PIN lockout, so the share sheet can't be used to keep guessing.
    var lockoutUntil: Date?
    /// Documents are a premium import; free users can still share them, they just wait.
    var canImportDocuments: Bool

    static func read(from root: URL) -> ShareInboxConfiguration? {
        let url = root.appendingPathComponent(ShareInbox.configurationFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let config = try? JSONDecoder().decode(Self.self, from: data),
              config.version == currentVersion else { return nil }
        return config
    }

    func write(to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(ShareInbox.configurationFilename)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func remove(from root: URL) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(ShareInbox.configurationFilename))
    }
}

// MARK: - Item Metadata (sealed inside the payload)

struct ShareInboxItemMetadata: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case photo
        case video
        case document
    }

    var kind: Kind
    var filename: String
    var isDecoy: Bool
    var sharedAt: Date
}

// MARK: - Payload Format

/// File layout:
///
///     magic "VBSHARE1" (8) | ephemeral X25519 public key (32)
///     record*: UInt32 big-endian length | AES-GCM combined box (nonce | ciphertext | tag)
///
/// Record 0 is the JSON metadata, the rest are file content in chunks of at most
/// `chunkSize` bytes. Each record's AAD is header | UInt64 index | UInt8 isFinal, so records
/// can't be reordered, dropped or truncated without failing authentication. Content is
/// streamed a chunk at a time, which keeps a large video well inside the extension's
/// memory limit.
enum ShareInboxPayload {
    enum Source: Sendable {
        case file(URL)
        case data(Data)
    }

    enum PayloadError: Error, Equatable {
        case invalidHeader
        case truncated
        case trailingData
        case recordTooLarge
    }

    static let magic = Data("VBSHARE1".utf8)
    static let chunkSize = 1024 * 1024
    private static let headerSize = 8 + 32
    private static let keyInfo = Data("com.vaultbox.share-inbox.v1".utf8)
    /// Guards the length prefix so a corrupt file can't ask for a huge allocation.
    private static let maxRecordSize = chunkSize + 1024 * 64

    // MARK: Sealing

    static func seal(
        _ source: Source,
        metadata: ShareInboxItemMetadata,
        recipientPublicKey: Data,
        to destination: URL
    ) throws {
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        var header = magic
        header.append(ephemeral.publicKey.rawRepresentation)
        let key = try deriveKey(
            sharedSecret: ephemeral.sharedSecretFromKeyAgreement(with: recipient),
            header: header,
            recipientPublicKey: recipientPublicKey
        )

        guard FileManager.default.createFile(
            atPath: destination.path,
            contents: nil,
            // Keeps writing if the phone locks halfway through a long video.
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.write(contentsOf: header)

        let reader = try ChunkReader(source)
        defer { reader.close() }

        var current = try reader.next()
        let metadataData = try JSONEncoder().encode(metadata)
        try writeRecord(metadataData, index: 0, isFinal: current.isEmpty, key: key, header: header, to: output)

        var index: UInt64 = 1
        while !current.isEmpty {
            try autoreleasepool {
                let next = try reader.next()
                try writeRecord(current, index: index, isFinal: next.isEmpty, key: key, header: header, to: output)
                current = next
            }
            index += 1
        }
    }

    // MARK: Opening

    static func readMetadata(at url: URL, privateKey: Data) throws -> ShareInboxItemMetadata {
        try open(at: url, privateKey: privateKey, writingContentsTo: nil)
    }

    /// Authenticates the whole payload. Content goes to `destination` when given; on any
    /// failure the partly written destination is removed.
    @discardableResult
    static func open(
        at url: URL,
        privateKey privateKeyData: Data,
        writingContentsTo destination: URL?
    ) throws -> ShareInboxItemMetadata {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }

        let header = try input.read(upToCount: headerSize) ?? Data()
        guard header.count == headerSize, header.prefix(magic.count) == magic else {
            throw PayloadError.invalidHeader
        }
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: header.suffix(32))
        let key = try deriveKey(
            sharedSecret: privateKey.sharedSecretFromKeyAgreement(with: ephemeral),
            header: header,
            recipientPublicKey: privateKey.publicKey.rawRepresentation
        )

        let (metadataData, metadataIsFinal) = try readRecord(index: 0, key: key, header: header, from: input)
        let metadata = try JSONDecoder().decode(ShareInboxItemMetadata.self, from: metadataData)

        guard let destination else {
            return metadata
        }

        guard FileManager.default.createFile(
            atPath: destination.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }

            var isFinal = metadataIsFinal
            var index: UInt64 = 1
            while !isFinal {
                try autoreleasepool {
                    let (chunk, final) = try readRecord(index: index, key: key, header: header, from: input)
                    try output.write(contentsOf: chunk)
                    isFinal = final
                }
                index += 1
            }
            guard (try input.read(upToCount: 1) ?? Data()).isEmpty else {
                throw PayloadError.trailingData
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return metadata
    }

    // MARK: Helpers

    private static func deriveKey(
        sharedSecret: SharedSecret,
        header: Data,
        recipientPublicKey: Data
    ) throws -> SymmetricKey {
        var info = keyInfo
        info.append(recipientPublicKey)
        return sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: header,
            sharedInfo: info,
            outputByteCount: 32
        )
    }

    private static func aad(header: Data, index: UInt64, isFinal: Bool) -> Data {
        var data = header
        withUnsafeBytes(of: index.bigEndian) { data.append(contentsOf: $0) }
        data.append(isFinal ? 1 : 0)
        return data
    }

    private static func writeRecord(
        _ plaintext: Data,
        index: UInt64,
        isFinal: Bool,
        key: SymmetricKey,
        header: Data,
        to output: FileHandle
    ) throws {
        let box = try AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: aad(header: header, index: index, isFinal: isFinal)
        )
        guard let combined = box.combined else { throw CocoaError(.fileWriteUnknown) }
        var length = UInt32(combined.count).bigEndian
        try output.write(contentsOf: Data(bytes: &length, count: 4))
        try output.write(contentsOf: combined)
    }

    /// Opens the next record, trying both values of the final flag: only the one the
    /// writer used authenticates, which tells us whether more records follow.
    private static func readRecord(
        index: UInt64,
        key: SymmetricKey,
        header: Data,
        from input: FileHandle
    ) throws -> (Data, Bool) {
        let lengthData = try input.read(upToCount: 4) ?? Data()
        guard lengthData.count == 4 else { throw PayloadError.truncated }
        let length = lengthData.reduce(0) { ($0 << 8) | Int($1) }
        guard length <= maxRecordSize else { throw PayloadError.recordTooLarge }
        let combined = try input.read(upToCount: length) ?? Data()
        guard combined.count == length else { throw PayloadError.truncated }

        let box = try AES.GCM.SealedBox(combined: combined)
        if let plaintext = try? AES.GCM.open(box, using: key, authenticating: aad(header: header, index: index, isFinal: false)) {
            return (plaintext, false)
        }
        let plaintext = try AES.GCM.open(box, using: key, authenticating: aad(header: header, index: index, isFinal: true))
        return (plaintext, true)
    }

    private final class ChunkReader {
        private let handle: FileHandle?
        private let data: Data?
        private var offset = 0

        init(_ source: Source) throws {
            switch source {
            case .file(let url):
                handle = try FileHandle(forReadingFrom: url)
                data = nil
            case .data(let data):
                handle = nil
                self.data = data
            }
        }

        func next() throws -> Data {
            if let handle {
                return try handle.read(upToCount: ShareInboxPayload.chunkSize) ?? Data()
            }
            guard let data, offset < data.count else { return Data() }
            let end = min(offset + ShareInboxPayload.chunkSize, data.count)
            let chunk = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))
            offset = end
            return chunk
        }

        func close() {
            try? handle?.close()
        }
    }
}
