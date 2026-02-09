import Foundation
import LocalAuthentication
import SwiftData

enum AuthResult {
    case success
    case failure
    case locked
    case decoy
}

@MainActor
@Observable
class AuthService {
    private let encryptionService: EncryptionService
    private let modelContext: ModelContext

    private(set) var isUnlocked: Bool = false
    private(set) var isDecoyMode: Bool = false

    init(encryptionService: EncryptionService, modelContext: ModelContext) {
        self.encryptionService = encryptionService
        self.modelContext = modelContext
    }

    // MARK: - Settings Access

    private func loadSettings() throws -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try modelContext.fetch(descriptor).first else {
            throw AuthError.settingsNotFound
        }
        return settings
    }

    // MARK: - PIN Management

    func createPIN(_ pin: String) async throws {
        guard pin.count >= Constants.pinMinLength,
              pin.count <= Constants.pinMaxLength,
              pin.allSatisfy(\.isNumber) else {
            throw AuthError.invalidPIN
        }

        let settings = try loadSettings()
        let salt = await encryptionService.generateSalt()
        let hash = await encryptionService.hashPIN(pin, salt: salt)

        settings.pinHash = hash
        settings.pinSalt = salt.base64EncodedString()
        settings.pinLength = pin.count
        settings.isSetupComplete = true

        // Generate and store master key derived from PIN
        let masterKey = await encryptionService.deriveMasterKey(from: pin, salt: salt)
        try await encryptionService.storeMasterKey(masterKey)

        try modelContext.save()
    }

    func verifyPIN(_ pin: String) async -> AuthResult {
        guard let settings = try? loadSettings() else { return .failure }

        // Check lockout
        if let lockoutUntil = settings.lockoutUntil, lockoutUntil > Date() {
            return .locked
        }

        guard let saltData = Data(base64Encoded: settings.pinSalt) else { return .failure }
        let hash = await encryptionService.hashPIN(pin, salt: saltData)

        // Check decoy PIN
        if let decoyHash = settings.decoyPINHash,
           let decoySaltString = settings.decoyPINSalt,
           let decoySalt = Data(base64Encoded: decoySaltString) {
            let decoyComputedHash = await encryptionService.hashPIN(pin, salt: decoySalt)
            if decoyComputedHash == decoyHash {
                await resetFailedAttempts()
                isUnlocked = true
                isDecoyMode = true
                settings.lastUnlockedAt = Date()
                try? modelContext.save()
                return .decoy
            }
        }

        // Check real PIN
        if hash == settings.pinHash {
            await resetFailedAttempts()
            isUnlocked = true
            isDecoyMode = false
            settings.lastUnlockedAt = Date()
            try? modelContext.save()
            return .success
        }

        // Failed attempt
        await handleFailedAttempt(pin)
        return settings.lockoutUntil != nil && settings.lockoutUntil! > Date() ? .locked : .failure
    }

    func changePIN(old: String, new: String) async throws {
        let result = await verifyPIN(old)
        guard result == .success else {
            throw AuthError.incorrectPIN
        }

        guard new.count >= Constants.pinMinLength,
              new.count <= Constants.pinMaxLength,
              new.allSatisfy(\.isNumber) else {
            throw AuthError.invalidPIN
        }

        let settings = try loadSettings()
        let oldSaltData = Data(base64Encoded: settings.pinSalt) ?? Data()
        let newSalt = await encryptionService.generateSalt()
        let newHash = await encryptionService.hashPIN(new, salt: newSalt)

        try await encryptionService.rotateMasterKey(
            oldPIN: old, oldSalt: oldSaltData,
            newPIN: new, newSalt: newSalt
        )

        settings.pinHash = newHash
        settings.pinSalt = newSalt.base64EncodedString()
        try modelContext.save()
    }

    func setupDecoyPIN(_ pin: String) async throws {
        guard pin.count >= Constants.pinMinLength,
              pin.count <= Constants.pinMaxLength,
              pin.allSatisfy(\.isNumber) else {
            throw AuthError.invalidPIN
        }

        let settings = try loadSettings()

        // Decoy PIN must differ from real PIN
        guard let realSalt = Data(base64Encoded: settings.pinSalt) else {
            throw AuthError.settingsNotFound
        }
        let realHash = await encryptionService.hashPIN(pin, salt: realSalt)
        if realHash == settings.pinHash {
            throw AuthError.decoyMatchesReal
        }

        let salt = await encryptionService.generateSalt()
        let hash = await encryptionService.hashPIN(pin, salt: salt)

        settings.decoyPINHash = hash
        settings.decoyPINSalt = salt.base64EncodedString()
        try modelContext.save()
    }

    func getPINLength() -> Int {
        guard let settings = try? loadSettings() else { return Constants.pinMinLength }
        return settings.pinLength
    }

    func isBiometricsEnabled() -> Bool {
        guard let settings = try? loadSettings() else { return false }
        return settings.biometricsEnabled
    }

    // MARK: - Biometrics

    func isBiometricsAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter PIN"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your vault"
            )
            if success {
                isUnlocked = true
                isDecoyMode = false
                let settings = try? loadSettings()
                settings?.biometricsEnabled = true
                settings?.lastUnlockedAt = Date()
                try? modelContext.save()
            }
            return success
        } catch {
            return false
        }
    }

    // MARK: - Lockout

    func handleFailedAttempt(_ pin: String) async {
        guard let settings = try? loadSettings() else { return }

        settings.failedAttemptCount += 1
        let count = settings.failedAttemptCount

        // Find applicable lockout threshold
        for threshold in Constants.lockoutThresholds.reversed() {
            if count >= threshold.attempts {
                settings.lockoutUntil = Date().addingTimeInterval(TimeInterval(threshold.seconds))
                break
            }
        }

        try? modelContext.save()
    }

    func getLockoutRemainingSeconds() -> Int? {
        guard let settings = try? loadSettings(),
              let lockoutUntil = settings.lockoutUntil else { return nil }

        let remaining = lockoutUntil.timeIntervalSinceNow
        return remaining > 0 ? Int(ceil(remaining)) : nil
    }

    func resetFailedAttempts() async {
        guard let settings = try? loadSettings() else { return }
        settings.failedAttemptCount = 0
        settings.lockoutUntil = nil
        try? modelContext.save()
    }

    // MARK: - Auto-Lock

    func recordUnlockTime() async {
        guard let settings = try? loadSettings() else { return }
        settings.lastUnlockedAt = Date()
        try? modelContext.save()
    }

    func shouldAutoLock() -> Bool {
        guard let settings = try? loadSettings() else { return true }
        guard let lastUnlocked = settings.lastUnlockedAt else { return true }

        let elapsed = Date().timeIntervalSince(lastUnlocked)
        if settings.autoLockSeconds == 0 { return true }
        return elapsed >= TimeInterval(settings.autoLockSeconds)
    }

    // MARK: - Lock

    func lock() {
        isUnlocked = false
        isDecoyMode = false
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case settingsNotFound
    case invalidPIN
    case incorrectPIN
    case decoyMatchesReal

    var errorDescription: String? {
        switch self {
        case .settingsNotFound:
            "App settings not found. Please reinstall VaultBox."
        case .invalidPIN:
            "PIN must be 4-8 digits."
        case .incorrectPIN:
            "Incorrect PIN. Please try again."
        case .decoyMatchesReal:
            "Decoy PIN must be different from your real PIN."
        }
    }
}
