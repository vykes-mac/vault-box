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
    private let hasPremiumAccess: () -> Bool
    private let onBreakInThresholdReached: (@MainActor @Sendable (_ attemptedPIN: String, _ failedAttemptCount: Int) async -> Void)?

    private(set) var isSetupComplete: Bool = false
    private(set) var isUnlocked: Bool = false
    private(set) var isDecoyMode: Bool = false
    private var lastBackgroundAt: Date?
    private var biometricRecoveryAuthorizedUntil: Date?

    init(
        encryptionService: EncryptionService,
        modelContext: ModelContext,
        hasPremiumAccess: @escaping () -> Bool = { false },
        onBreakInThresholdReached: (@MainActor @Sendable (_ attemptedPIN: String, _ failedAttemptCount: Int) async -> Void)? = nil
    ) {
        self.encryptionService = encryptionService
        self.modelContext = modelContext
        self.hasPremiumAccess = hasPremiumAccess
        self.onBreakInThresholdReached = onBreakInThresholdReached
        isSetupComplete = (try? loadSettings().isSetupComplete) == true
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

    func createPIN(_ pin: String) async throws -> String {
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

        let recoveryCode = generateRecoveryCode()
        let recoverySalt = await encryptionService.generateSalt()
        let recoveryHash = await encryptionService.hashSecret(recoveryCode, salt: recoverySalt)
        settings.recoveryCodeHash = recoveryHash
        settings.recoveryCodeSalt = recoverySalt.base64EncodedString()
        settings.recoveryCodeUsedAt = nil

        // Generate and store master key derived from PIN
        let masterKey = await encryptionService.deriveMasterKey(from: pin, salt: salt)
        try await encryptionService.storeMasterKey(masterKey)

        try modelContext.save()
        return recoveryCode
    }

    func verifyRecoveryCode(_ code: String) async -> Bool {
        guard let settings = try? loadSettings(),
              let storedHash = settings.recoveryCodeHash,
              let saltString = settings.recoveryCodeSalt,
              settings.recoveryCodeUsedAt == nil,
              let salt = Data(base64Encoded: saltString) else {
            return false
        }

        let computed = await encryptionService.hashSecret(code, salt: salt)
        return computed == storedHash
    }

    func resetPINUsingRecoveryCode(_ code: String, newPIN: String) async throws {
        guard newPIN.count >= Constants.pinMinLength,
              newPIN.count <= Constants.pinMaxLength,
              newPIN.allSatisfy(\.isNumber) else {
            throw AuthError.invalidPIN
        }

        guard await verifyRecoveryCode(code) else {
            throw AuthError.invalidRecoveryCode
        }

        let settings = try loadSettings()
        let newSalt = await encryptionService.generateSalt()
        let newHash = await encryptionService.hashPIN(newPIN, salt: newSalt)

        settings.pinHash = newHash
        settings.pinSalt = newSalt.base64EncodedString()
        settings.pinLength = newPIN.count
        settings.failedAttemptCount = 0
        settings.lockoutUntil = nil
        settings.recoveryCodeUsedAt = Date()

        // Preserve existing vault encryption key so previously encrypted
        // items remain decryptable after a recovery-code PIN reset.
        if await !encryptionService.hasMasterKey() {
            let masterKey = await encryptionService.deriveMasterKey(from: newPIN, salt: newSalt)
            try await encryptionService.storeMasterKey(masterKey)
        }

        try modelContext.save()
        isUnlocked = true
        isDecoyMode = false
        lastBackgroundAt = nil
    }

    func regenerateRecoveryCode() async throws -> String {
        let settings = try loadSettings()
        let recoveryCode = generateRecoveryCode()
        let salt = await encryptionService.generateSalt()
        settings.recoveryCodeHash = await encryptionService.hashSecret(recoveryCode, salt: salt)
        settings.recoveryCodeSalt = salt.base64EncodedString()
        settings.recoveryCodeUsedAt = nil
        try modelContext.save()
        return recoveryCode
    }

    func revokeRecoveryCode() throws {
        let settings = try loadSettings()
        settings.recoveryCodeHash = nil
        settings.recoveryCodeSalt = nil
        settings.recoveryCodeUsedAt = nil
        try modelContext.save()
    }

    func isRecoveryCodeAvailable() -> Bool {
        guard let settings = try? loadSettings() else { return false }
        return settings.recoveryCodeHash != nil && settings.recoveryCodeSalt != nil
    }

    func isRecoveryCodeUsed() -> Bool {
        guard let settings = try? loadSettings() else { return false }
        return settings.recoveryCodeUsedAt != nil
    }

    private func generateRecoveryCode(length: Int = 16) -> String {
        let charset = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        return String((0..<max(length, 12)).compactMap { _ in charset.randomElement() })
    }

    func completeInitialSetup() throws {
        let settings = try loadSettings()
        settings.isSetupComplete = true
        settings.hasCompletedOnboarding = true
        settings.lastUnlockedAt = Date()
        try modelContext.save()

        isSetupComplete = true
        isUnlocked = true
        isDecoyMode = false
        lastBackgroundAt = nil
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
        if hasPremiumAccess(),
           let decoyHash = settings.decoyPINHash,
           let decoySaltString = settings.decoyPINSalt,
           let decoySalt = Data(base64Encoded: decoySaltString) {
            let decoyComputedHash = await encryptionService.hashPIN(pin, salt: decoySalt)
            if decoyComputedHash == decoyHash {
                await resetFailedAttempts()
                isUnlocked = true
                isDecoyMode = true
                lastBackgroundAt = nil
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
            lastBackgroundAt = nil
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
        let newSalt = await encryptionService.generateSalt()
        let newHash = await encryptionService.hashPIN(new, salt: newSalt)

        // Keep existing master key so previously encrypted items remain decryptable.
        if await !encryptionService.hasMasterKey() {
            let masterKey = await encryptionService.deriveMasterKey(from: new, salt: newSalt)
            try await encryptionService.storeMasterKey(masterKey)
        }

        settings.pinHash = newHash
        settings.pinSalt = newSalt.base64EncodedString()
        settings.pinLength = new.count
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

    func authenticateWithBiometrics(
        localizedReason: String = "Unlock your vault",
        unlockSession: Bool = true,
        enableForFutureUnlocks: Bool = true
    ) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter PIN"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: localizedReason
            )
            if success {
                if unlockSession {
                    isUnlocked = true
                    isDecoyMode = false
                    lastBackgroundAt = nil
                }
                let settings = try? loadSettings()
                if enableForFutureUnlocks {
                    settings?.biometricsEnabled = true
                }
                if unlockSession {
                    settings?.lastUnlockedAt = Date()
                }
                try? modelContext.save()
            }
            return success
        } catch {
            return false
        }
    }

    func beginBiometricRecoveryReset() async -> Bool {
        let success = await authenticateWithBiometrics(
            localizedReason: "Verify your identity to reset your PIN",
            unlockSession: false,
            enableForFutureUnlocks: false
        )

        biometricRecoveryAuthorizedUntil = success
            ? Date().addingTimeInterval(60)
            : nil
        return success
    }

    func completeBiometricRecoveryReset(newPIN: String) async throws {
        guard biometricRecoveryAuthorizedUntil.map({ $0 > Date() }) == true else {
            throw AuthError.biometricVerificationRequired
        }

        guard newPIN.count >= Constants.pinMinLength,
              newPIN.count <= Constants.pinMaxLength,
              newPIN.allSatisfy(\.isNumber) else {
            throw AuthError.invalidPIN
        }

        let settings = try loadSettings()
        let newSalt = await encryptionService.generateSalt()
        let newHash = await encryptionService.hashPIN(newPIN, salt: newSalt)
        // Preserve the existing master key for provisioned users so previously
        // encrypted vault data remains decryptable after PIN recovery reset.
        if await !encryptionService.hasMasterKey() {
            let masterKey = await encryptionService.deriveMasterKey(from: newPIN, salt: newSalt)
            try await encryptionService.storeMasterKey(masterKey)
        }

        settings.pinHash = newHash
        settings.pinSalt = newSalt.base64EncodedString()
        settings.pinLength = newPIN.count
        settings.failedAttemptCount = 0
        settings.lockoutUntil = nil
        settings.lastUnlockedAt = Date()

        isUnlocked = true
        isDecoyMode = false
        lastBackgroundAt = nil
        biometricRecoveryAuthorizedUntil = nil

        try modelContext.save()
    }

    // MARK: - Lockout

    func handleFailedAttempt(_ pin: String) async {
        guard let settings = try? loadSettings() else { return }

        settings.failedAttemptCount += 1
        let count = settings.failedAttemptCount
        let isBreakInThreshold = Constants.lockoutThresholds.contains { $0.attempts == count }

        // Find applicable lockout threshold
        for threshold in Constants.lockoutThresholds.reversed() {
            if count >= threshold.attempts {
                settings.lockoutUntil = Date().addingTimeInterval(TimeInterval(threshold.seconds))
                break
            }
        }

        try? modelContext.save()

        if isBreakInThreshold, let onBreakInThresholdReached {
            Task { @MainActor in
                await onBreakInThresholdReached(pin, count)
            }
        }
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
        guard let lastBackgroundAt else { return false }
        if settings.autoLockSeconds == 0 { return true }
        let elapsed = Date().timeIntervalSince(lastBackgroundAt)
        return elapsed >= TimeInterval(settings.autoLockSeconds)
    }

    func recordBackgroundEntry() {
        guard isUnlocked else { return }
        lastBackgroundAt = Date()
    }

    // MARK: - Lock

    func lock() {
        isUnlocked = false
        isDecoyMode = false
        lastBackgroundAt = nil
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case settingsNotFound
    case invalidPIN
    case incorrectPIN
    case decoyMatchesReal
    case invalidRecoveryCode
    case biometricVerificationRequired

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
        case .invalidRecoveryCode:
            "Recovery code is invalid, missing, or already used."
        case .biometricVerificationRequired:
            "Biometric verification is required before resetting PIN."
        }
    }
}
