import Foundation
import CryptoKit

// MARK: - SealedCapture

/// File format for photos and videos captured while the device is locked.
///
/// The capture extension can't read the vault's master key (it lives in the Keychain
/// as `.whenUnlockedThisDeviceOnly`), so it seals every capture to an HPKE public key
/// instead. The matching private key never leaves the main app's Keychain, so a sealed
/// file is unreadable until the user unlocks VaultBox and the app re-encrypts it into
/// the vault.
///
/// Layout:
/// ```
/// "VBQC" | version (1) | kind (1) | encapsulated key length (UInt16 BE) | encapsulated key
/// repeated: chunk header (UInt32 BE: bit 31 = final, bits 0-30 = ciphertext length) | ciphertext
/// ```
/// Each chunk header is the chunk's AAD, so dropping trailing chunks or flipping the
/// final flag fails authentication instead of yielding a silently truncated video.
enum SealedCapture {
    enum Kind: UInt8, Sendable {
        case photo = 0
        case video = 1
    }

    enum FormatError: Error, Equatable {
        case badHeader
        case unsupportedVersion
        case truncated
        case trailingData
    }

    static let fileExtension = "vbqc"
    static let chunkSize = 1 << 20 // 1 MiB of plaintext per chunk

    private static let magic = Data("VBQC".utf8)
    private static let version: UInt8 = 1
    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let finalFlag: UInt32 = 1 << 31

    private static func info(for kind: Kind) -> Data {
        var info = Data("com.vaultbox.quickcapture.v1".utf8)
        info.append(kind.rawValue)
        return info
    }

    // MARK: Sealing

    /// Seals an in-memory capture (photos).
    static func seal(
        _ plaintext: Data,
        kind: Kind,
        to recipient: Curve25519.KeyAgreement.PublicKey
    ) throws -> Data {
        var output = Data()
        var offset = plaintext.startIndex
        try seal(kind: kind, to: recipient, readChunk: {
            let end = plaintext.index(offset, offsetBy: chunkSize, limitedBy: plaintext.endIndex) ?? plaintext.endIndex
            defer { offset = end }
            return plaintext[offset..<end]
        }, write: { output.append($0) })
        return output
    }

    /// Streams a file on disk (videos) into a sealed file without loading it all into memory.
    static func sealFile(
        at source: URL,
        kind: Kind,
        to recipient: Curve25519.KeyAgreement.PublicKey,
        destination: URL
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        try seal(kind: kind, to: recipient, readChunk: {
            try input.read(upToCount: chunkSize) ?? Data()
        }, write: { try output.write(contentsOf: $0) })
    }

    /// `readChunk` returns at most `chunkSize` bytes; a short (or empty) read marks the end.
    private static func seal(
        kind: Kind,
        to recipient: Curve25519.KeyAgreement.PublicKey,
        readChunk: () throws -> Data,
        write: (Data) throws -> Void
    ) throws {
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: ciphersuite, info: info(for: kind))

        var header = magic
        header.append(version)
        header.append(kind.rawValue)
        header.append(contentsOf: UInt16(sender.encapsulatedKey.count).bigEndianBytes)
        header.append(sender.encapsulatedKey)
        try write(header)

        var chunk = try readChunk()
        while true {
            // Look ahead so the last chunk can carry the final flag. A full chunk followed
            // by EOF ends with an empty final chunk, which keeps the logic branch-free.
            let isFinal = chunk.count < chunkSize
            let next = try isFinal ? Data() : readChunk()
            let ciphertextLength = UInt32(chunk.count + 16) // ChaChaPoly tag
            let chunkHeader = Data((isFinal ? ciphertextLength | finalFlag : ciphertextLength).bigEndianBytes)
            let ciphertext = try sender.seal(chunk, authenticating: chunkHeader)
            try write(chunkHeader + ciphertext)
            if isFinal { return }
            chunk = next
        }
    }

    // MARK: Opening

    /// Opens an in-memory sealed capture.
    static func open(
        _ sealed: Data,
        with privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> (kind: Kind, plaintext: Data) {
        var reader = DataReader(data: sealed)
        var plaintext = Data()
        let kind = try open(with: privateKey, read: { try reader.read($0) }, write: { plaintext.append($0) })
        guard reader.isAtEnd else { throw FormatError.trailingData }
        return (kind, plaintext)
    }

    /// Streams a sealed file into a plaintext file.
    @discardableResult
    static func openFile(
        at source: URL,
        with privateKey: Curve25519.KeyAgreement.PrivateKey,
        destination: URL
    ) throws -> Kind {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let kind = try open(with: privateKey, read: { count in
            let data = try input.read(upToCount: count) ?? Data()
            guard data.count == count else { throw FormatError.truncated }
            return data
        }, write: { try output.write(contentsOf: $0) })

        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw FormatError.trailingData }
        return kind
    }

    /// Reads just the header to learn what a sealed file holds, without the private key.
    static func kind(ofFileAt url: URL) throws -> Kind {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let header = try input.read(upToCount: magic.count + 2) ?? Data()
        guard header.count == magic.count + 2, header.prefix(magic.count) == magic else {
            throw FormatError.badHeader
        }
        guard let kind = Kind(rawValue: header[header.startIndex + magic.count + 1]) else {
            throw FormatError.badHeader
        }
        return kind
    }

    /// `read` must return exactly `count` bytes or throw.
    private static func open(
        with privateKey: Curve25519.KeyAgreement.PrivateKey,
        read: (Int) throws -> Data,
        write: (Data) throws -> Void
    ) throws -> Kind {
        guard try read(magic.count) == magic else { throw FormatError.badHeader }
        let versionAndKind = try read(2)
        guard versionAndKind[versionAndKind.startIndex] == version else { throw FormatError.unsupportedVersion }
        guard let kind = Kind(rawValue: versionAndKind[versionAndKind.startIndex + 1]) else {
            throw FormatError.badHeader
        }
        let keyLength = Int(UInt16(bigEndianBytes: try read(2)))
        let encapsulatedKey = try read(keyLength)

        var recipient = try HPKE.Recipient(
            privateKey: privateKey,
            ciphersuite: ciphersuite,
            info: info(for: kind),
            encapsulatedKey: encapsulatedKey
        )

        while true {
            let chunkHeader = try read(4)
            let rawLength = UInt32(bigEndianBytes: chunkHeader)
            let isFinal = rawLength & finalFlag != 0
            let length = Int(rawLength & ~finalFlag)
            guard length >= 16, length <= chunkSize + 16 else { throw FormatError.badHeader }
            let plaintext = try recipient.open(try read(length), authenticating: chunkHeader)
            try write(plaintext)
            if isFinal { return kind }
        }
    }
}

// MARK: - Helpers

private struct DataReader {
    let data: Data
    var offset: Data.Index

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset == data.endIndex }

    mutating func read(_ count: Int) throws -> Data {
        guard let end = data.index(offset, offsetBy: count, limitedBy: data.endIndex) else {
            throw SealedCapture.FormatError.truncated
        }
        defer { offset = end }
        return data[offset..<end]
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }

    init(bigEndianBytes data: Data) {
        self = data.reduce(0) { ($0 << 8) | Self($1) }
    }
}
