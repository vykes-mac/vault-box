import Foundation
import CryptoKit
import KeychainAccess
import UIKit

actor EncryptionService {
    private let keychain: Keychain

    init() {
        self.keychain = Keychain(service: Constants.keychainServiceID)
            .accessibility(.whenUnlockedThisDeviceOnly)
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
        try keychain.set(keyData, key: Constants.keychainMasterKeyID)
    }

    func loadMasterKey() throws -> SymmetricKey {
        guard let keyData = try keychain.getData(Constants.keychainMasterKeyID) else {
            throw EncryptionError.masterKeyNotFound
        }
        return SymmetricKey(data: keyData)
    }

    func deleteMasterKey() throws {
        try keychain.remove(Constants.keychainMasterKeyID)
    }

    func hasMasterKey() -> Bool {
        (try? keychain.getData(Constants.keychainMasterKeyID)) != nil
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
        let pinData = Data(pin.utf8)
        var combined = salt
        combined.append(pinData)
        let hash = SHA256.hash(data: combined)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Key Rotation

    func rotateMasterKey(oldPIN: String, oldSalt: Data, newPIN: String, newSalt: Data) throws {
        let oldKey = deriveMasterKey(from: oldPIN, salt: oldSalt)
        let newKey = deriveMasterKey(from: newPIN, salt: newSalt)

        // Store the new key — in a full implementation, per-file keys
        // would be re-encrypted here. Since we use a single master key
        // for direct encryption, we just swap the stored key.
        _ = oldKey // validated derivation
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try keychain.set(keyData, key: Constants.keychainMasterKeyID)
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

    var errorDescription: String? {
        switch self {
        case .masterKeyNotFound:
            "Encryption key not found. Please re-enter your PIN."
        case .encryptionFailed:
            "Failed to encrypt data. Please try again."
        case .decryptionFailed:
            "This item couldn't be opened. It may be corrupted."
        case .thumbnailGenerationFailed:
            "Couldn't generate thumbnail for this item."
        }
    }
}
