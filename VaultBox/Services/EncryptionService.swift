import Foundation
import CryptoKit
@preconcurrency import KeychainAccess
import UIKit

// MARK: - Key Storage Protocol

protocol KeyStorage: Sendable {
    func set(_ data: Data, forKey key: String) throws
    func getData(_ key: String) throws -> Data?
    func remove(_ key: String) throws
}

final class KeychainKeyStorage: KeyStorage {
    private let keychain: Keychain

    init() {
        self.keychain = Keychain(service: Constants.keychainServiceID)
            .accessibility(.whenUnlockedThisDeviceOnly)
    }

    func set(_ data: Data, forKey key: String) throws {
        try keychain.set(data, key: key)
    }

    func getData(_ key: String) throws -> Data? {
        try keychain.getData(key)
    }

    func remove(_ key: String) throws {
        try keychain.remove(key)
    }
}

/// Keychain storage that syncs through iCloud Keychain, which is end-to-end
/// encrypted. Holds the secret that locks the iCloud key backup, so the
/// backup can be restored on a new device signed into the same Apple ID.
final class SyncedKeychainKeyStorage: KeyStorage {
    private let keychain: Keychain

    init() {
        self.keychain = Keychain(service: Constants.keychainServiceID)
            .synchronizable(true)
            .accessibility(.afterFirstUnlock)
    }

    func set(_ data: Data, forKey key: String) throws {
        try keychain.set(data, key: key)
    }

    func getData(_ key: String) throws -> Data? {
        try keychain.getData(key)
    }

    func remove(_ key: String) throws {
        try keychain.remove(key)
    }
}

final class InMemoryKeyStorage: KeyStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: Data] = [:]

    func set(_ data: Data, forKey key: String) throws {
        lock.withLock { store[key] = data }
    }

    func getData(_ key: String) throws -> Data? {
        lock.withLock { store[key] }
    }

    func remove(_ key: String) throws {
        lock.withLock { store[key] = nil }
    }
}

// MARK: - EncryptionService

actor EncryptionService {
    private let keyStorage: KeyStorage
    private let backupSecretStorage: KeyStorage

    init(
        keyStorage: KeyStorage = KeychainKeyStorage(),
        backupSecretStorage: KeyStorage = SyncedKeychainKeyStorage()
    ) {
        self.keyStorage = keyStorage
        self.backupSecretStorage = backupSecretStorage
    }

    // MARK: - Key Generation

    func generateMasterKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func deriveMasterKey(from pin: String, salt: Data) -> SymmetricKey {
        let pinData = Data(pin.utf8)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pinData),
            salt: salt,
            info: Data("com.vaultbox.masterkey".utf8),
            outputByteCount: Constants.masterKeySize
        )
        return derivedKey
    }

    func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: Constants.pinSaltSize)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: - Key Storage (Keychain)

    func storeMasterKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        try keyStorage.set(keyData, forKey: Constants.keychainMasterKeyID)
    }

    func loadMasterKey() throws -> SymmetricKey {
        guard let keyData = try keyStorage.getData(Constants.keychainMasterKeyID) else {
            throw EncryptionError.masterKeyNotFound
        }
        return SymmetricKey(data: keyData)
    }

    func deleteMasterKey() throws {
        try keyStorage.remove(Constants.keychainMasterKeyID)
    }

    func hasMasterKey() -> Bool {
        (try? keyStorage.getData(Constants.keychainMasterKeyID)) != nil
    }

    // MARK: - Data Encryption / Decryption

    func encryptData(_ data: Data) throws -> Data {
        let key = try loadMasterKey()
        return try encryptData(data, using: key)
    }

    func decryptData(_ data: Data) throws -> Data {
        let key = try loadMasterKey()
        return try decryptData(data, using: key)
    }

    func encryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }

    func decryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - File Encryption / Decryption

    func encryptFile(at sourceURL: URL) throws -> Data {
        let plainData = try Data(contentsOf: sourceURL)
        return try encryptData(plainData)
    }

    func decryptFile(at encryptedURL: URL) throws -> Data {
        let encryptedData = try Data(contentsOf: encryptedURL)
        return try decryptData(encryptedData)
    }

    // MARK: - Thumbnail

    func generateEncryptedThumbnail(from imageData: Data, maxSize: CGSize) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw EncryptionError.thumbnailGenerationFailed
        }

        let thumbnail = image.preparingThumbnail(of: thumbnailTargetSize(for: image.size, maxSize: maxSize))
            ?? image

        guard let jpegData = thumbnail.jpegData(compressionQuality: Constants.thumbnailJPEGQuality) else {
            throw EncryptionError.thumbnailGenerationFailed
        }

        return try encryptData(jpegData)
    }

    private func thumbnailTargetSize(for originalSize: CGSize, maxSize: CGSize) -> CGSize {
        let widthRatio = maxSize.width / originalSize.width
        let heightRatio = maxSize.height / originalSize.height
        let scale = max(widthRatio, heightRatio) // aspect-fill
        return CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
    }

    // MARK: - PIN Hashing

    func hashPIN(_ pin: String, salt: Data) -> String {
        hashSecret(pin, salt: salt)
    }

    func hashSecret(_ value: String, salt: Data) -> String {
        let valueData = Data(value.utf8)
        var combined = salt
        combined.append(valueData)
        let hash = SHA256.hash(data: combined)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Key Wrapping (for iCloud Backup)

    /// Exports the master key wrapped for CloudKit (current backup format).
    /// The wrapping key mixes the PIN with a random 256-bit secret kept in
    /// iCloud Keychain, so the blob can't be brute-forced through the short PIN
    /// by anyone who only has access to the CloudKit data.
    func exportWrappedMasterKey(pin: String, salt: Data) throws -> Data {
        let masterKey = try loadMasterKey()
        let wrappingKey = backupWrappingKey(pin: pin, salt: salt, secret: try loadOrCreateBackupSecret())
        let masterKeyData = masterKey.withUnsafeBytes { Data($0) }
        return try encryptData(masterKeyData, using: wrappingKey)
    }

    /// Unwraps a CloudKit key backup and stores the master key in the Keychain.
    func importWrappedMasterKey(_ wrappedData: Data, pin: String, salt: Data, formatVersion: Int) throws {
        let masterKey = try unwrapMasterKey(wrappedData, pin: pin, salt: salt, formatVersion: formatVersion)
        try storeMasterKey(masterKey)
    }

    /// Unwraps a CloudKit key backup without storing it.
    func unwrapMasterKey(_ wrappedData: Data, pin: String, salt: Data, formatVersion: Int) throws -> SymmetricKey {
        let wrappingKey: SymmetricKey
        if formatVersion >= Constants.keyBackupFormatVersion {
            guard let secret = try backupSecretStorage.getData(Constants.keychainBackupSecretID) else {
                throw EncryptionError.backupSecretUnavailable
            }
            wrappingKey = backupWrappingKey(pin: pin, salt: salt, secret: secret)
        } else {
            // Format 1 backups were wrapped with the PIN alone.
            wrappingKey = deriveMasterKey(from: pin, salt: salt)
        }
        return SymmetricKey(data: try decryptData(wrappedData, using: wrappingKey))
    }

    /// Identifies the vault key without revealing it, so a key backup can be
    /// matched to the vault it belongs to.
    func masterKeyFingerprint() throws -> Data {
        Self.fingerprint(of: try loadMasterKey())
    }

    static func fingerprint(of key: SymmetricKey) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("com.vaultbox.key-fingerprint".utf8), using: key)
        return Data(mac.prefix(16))
    }

    private func backupWrappingKey(pin: String, salt: Data, secret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret + Data(pin.utf8)),
            salt: salt,
            info: Data("com.vaultbox.keybackup.v2".utf8),
            outputByteCount: Constants.masterKeySize
        )
    }

    private func loadOrCreateBackupSecret() throws -> Data {
        if let secret = try backupSecretStorage.getData(Constants.keychainBackupSecretID) {
            return secret
        }
        let secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try backupSecretStorage.set(secret, forKey: Constants.keychainBackupSecretID)
        return secret
    }

    // MARK: - File Paths

    func vaultFilesDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent(Constants.vaultDataDirectory)
            .appendingPathComponent(Constants.filesSubdirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func vaultThumbnailsDirectory() throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs
            .appendingPathComponent(Constants.vaultDataDirectory)
            .appendingPathComponent(Constants.thumbnailsSubdirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case masterKeyNotFound
    case encryptionFailed
    case decryptionFailed
    case thumbnailGenerationFailed
    case backupSecretUnavailable

    var errorDescription: String? {
        switch self {
        case .masterKeyNotFound:
            String(localized: "Encryption key not found. Please re-enter your PIN.")
        case .encryptionFailed:
            String(localized: "Failed to encrypt data. Please try again.")
        case .decryptionFailed:
            String(localized: "This item couldn't be opened. It may be corrupted.")
        case .thumbnailGenerationFailed:
            String(localized: "Couldn't generate thumbnail for this item.")
        case .backupSecretUnavailable:
            String(localized: "Your backup key isn't on this device yet. Turn on iCloud Keychain (Settings > [your name] > iCloud > Passwords & Keychain), wait a minute for it to sync, then try again.")
        }
    }
}
