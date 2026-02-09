import Testing
import Foundation
import CryptoKit
@testable import VaultBox

@Suite("EncryptionService Tests")
struct EncryptionServiceTests {

    private func makeService() -> EncryptionService {
        EncryptionService(keyStorage: InMemoryKeyStorage())
    }

    @Test("Encrypt then decrypt roundtrip returns identical data")
    func encryptDecryptRoundtrip() async throws {
        let service = makeService()
        let key = await service.generateMasterKey()

        let original = Data("Hello, VaultBox! This is secret data.".utf8)
        let encrypted = try await service.encryptData(original, using: key)
        let decrypted = try await service.decryptData(encrypted, using: key)

        #expect(decrypted == original)
        #expect(encrypted != original)
    }

    @Test("Different keys produce different ciphertext")
    func differentKeysProduceDifferentCiphertext() async throws {
        let service = makeService()
        let data = Data("Same plaintext".utf8)

        let key1 = await service.generateMasterKey()
        let encrypted1 = try await service.encryptData(data, using: key1)

        let key2 = await service.generateMasterKey()
        let encrypted2 = try await service.encryptData(data, using: key2)

        #expect(encrypted1 != encrypted2)
    }

    @Test("Corrupted ciphertext throws error")
    func corruptedCiphertextThrows() async throws {
        let service = makeService()
        let key = await service.generateMasterKey()

        let original = Data("Sensitive data".utf8)
        var encrypted = try await service.encryptData(original, using: key)

        // Corrupt the ciphertext
        if encrypted.count > 20 {
            encrypted[20] ^= 0xFF
        }

        await #expect(throws: (any Error).self) {
            try await service.decryptData(encrypted, using: key)
        }
    }

    @Test("Decryption with wrong key fails")
    func decryptionWithWrongKeyFails() async throws {
        let service = makeService()
        let correctKey = await service.generateMasterKey()
        let wrongKey = await service.generateMasterKey()

        let original = Data("Secret message".utf8)
        let encrypted = try await service.encryptData(original, using: correctKey)

        await #expect(throws: (any Error).self) {
            try await service.decryptData(encrypted, using: wrongKey)
        }
    }

    @Test("Key derivation from same PIN and salt is deterministic")
    func keyDerivationDeterministic() async {
        let service = makeService()
        let salt = Data(repeating: 0xAB, count: 32)
        let pin = "1234"

        let key1 = await service.deriveMasterKey(from: pin, salt: salt)
        let key2 = await service.deriveMasterKey(from: pin, salt: salt)

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        #expect(data1 == data2)
    }

    @Test("Different PINs produce different derived keys")
    func differentPinsProduceDifferentKeys() async {
        let service = makeService()
        let salt = Data(repeating: 0xAB, count: 32)

        let key1 = await service.deriveMasterKey(from: "1234", salt: salt)
        let key2 = await service.deriveMasterKey(from: "5678", salt: salt)

        let data1 = key1.withUnsafeBytes { Data($0) }
        let data2 = key2.withUnsafeBytes { Data($0) }
        #expect(data1 != data2)
    }

    @Test("PIN hashing is deterministic with same salt")
    func pinHashDeterministic() async {
        let service = makeService()
        let salt = Data(repeating: 0xCD, count: 32)

        let hash1 = await service.hashPIN("1234", salt: salt)
        let hash2 = await service.hashPIN("1234", salt: salt)
        #expect(hash1 == hash2)
    }

    @Test("PIN hashing produces different hashes for different PINs")
    func pinHashDifferentPins() async {
        let service = makeService()
        let salt = Data(repeating: 0xCD, count: 32)

        let hash1 = await service.hashPIN("1234", salt: salt)
        let hash2 = await service.hashPIN("5678", salt: salt)
        #expect(hash1 != hash2)
    }

    @Test("Salt generation produces unique values")
    func saltGenerationUnique() async {
        let service = makeService()
        let salt1 = await service.generateSalt()
        let salt2 = await service.generateSalt()
        #expect(salt1 != salt2)
        #expect(salt1.count == 32)
    }
}
