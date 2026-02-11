import Testing
import Foundation
import SwiftData
@testable import VaultBox

@Suite("AuthService Tests")
struct AuthServiceTests {

    @MainActor
    private func makeServices(
        hasPremiumAccess: Bool = false
    ) throws -> (AuthService, EncryptionService, ModelContext) {
        let schema = Schema([AppSettings.self, VaultItem.self, Album.self, BreakInAttempt.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let encryption = EncryptionService(keyStorage: InMemoryKeyStorage())
        let auth = AuthService(
            encryptionService: encryption,
            modelContext: context,
            hasPremiumAccess: { hasPremiumAccess }
        )
        return (auth, encryption, context)
    }

    @Test("Create PIN stores hash and marks setup complete")
    @MainActor
    func createPIN() async throws {
        let (auth, _, context) = try makeServices()

        try await auth.createPIN("1234")

        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first!
        #expect(settings.isSetupComplete == true)
        #expect(!settings.pinHash.isEmpty)
        #expect(!settings.pinSalt.isEmpty)
        #expect(auth.isSetupComplete == true)
        #expect(auth.isUnlocked == true)
    }

    @Test("Correct PIN returns success")
    @MainActor
    func correctPINReturnsSuccess() async throws {
        let (auth, _, _) = try makeServices()
        try await auth.createPIN("5678")

        let result = await auth.verifyPIN("5678")
        #expect(result == .success)
        #expect(auth.isUnlocked == true)
    }

    @Test("Wrong PIN returns failure")
    @MainActor
    func wrongPINReturnsFailure() async throws {
        let (auth, _, _) = try makeServices()
        try await auth.createPIN("1234")
        auth.lock()

        let result = await auth.verifyPIN("9999")
        #expect(result == .failure)
        #expect(auth.isUnlocked == false)
    }

    @Test("Lockout triggers at 3 failed attempts")
    @MainActor
    func lockoutAt3Attempts() async throws {
        let (auth, _, _) = try makeServices()
        try await auth.createPIN("1234")

        for _ in 0..<3 {
            _ = await auth.verifyPIN("0000")
        }

        let remaining = auth.getLockoutRemainingSeconds()
        #expect(remaining != nil)
        #expect(remaining! > 0)
        #expect(remaining! <= 30)
    }

    @Test("Lockout escalates at 5 failed attempts")
    @MainActor
    func lockoutAt5Attempts() async throws {
        let (auth, _, context) = try makeServices()
        try await auth.createPIN("1234")

        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first!
        settings.failedAttemptCount = 4
        try context.save()

        _ = await auth.verifyPIN("0000") // 5th attempt

        let remaining = auth.getLockoutRemainingSeconds()
        #expect(remaining != nil)
        #expect(remaining! > 30) // Should be 120s
    }

    @Test("Successful auth resets failed attempts")
    @MainActor
    func successResetsFailedAttempts() async throws {
        let (auth, _, context) = try makeServices()
        try await auth.createPIN("1234")

        _ = await auth.verifyPIN("0000")
        _ = await auth.verifyPIN("0000")
        _ = await auth.verifyPIN("1234")

        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first!
        #expect(settings.failedAttemptCount == 0)
        #expect(settings.lockoutUntil == nil)
    }

    @Test("Decoy PIN returns decoy result")
    @MainActor
    func decoyPINReturnsDecoy() async throws {
        let (auth, _, _) = try makeServices(hasPremiumAccess: true)
        try await auth.createPIN("1234")
        try await auth.setupDecoyPIN("5678")

        let result = await auth.verifyPIN("5678")
        #expect(result == .decoy)
        #expect(auth.isDecoyMode == true)
    }

    @Test("Decoy PIN is ignored when premium is inactive")
    @MainActor
    func decoyPINIgnoredWithoutPremium() async throws {
        let (auth, _, _) = try makeServices(hasPremiumAccess: false)
        try await auth.createPIN("1234")
        try await auth.setupDecoyPIN("5678")
        auth.lock()

        let result = await auth.verifyPIN("5678")
        #expect(result == .failure)
        #expect(auth.isDecoyMode == false)
    }

    @Test("Decoy PIN cannot match real PIN")
    @MainActor
    func decoyCannotMatchReal() async throws {
        let (auth, _, _) = try makeServices()
        try await auth.createPIN("1234")

        await #expect(throws: AuthError.self) {
            try await auth.setupDecoyPIN("1234")
        }
    }

    @Test("Invalid PIN rejected")
    @MainActor
    func invalidPINRejected() async throws {
        let (auth, _, _) = try makeServices()

        await #expect(throws: AuthError.self) {
            try await auth.createPIN("12")
        }
        await #expect(throws: AuthError.self) {
            try await auth.createPIN("123456789")
        }
        await #expect(throws: AuthError.self) {
            try await auth.createPIN("abcd")
        }
    }

    @Test("Lock resets unlock state")
    @MainActor
    func lockResetsState() async throws {
        let (auth, _, _) = try makeServices()
        try await auth.createPIN("1234")
        _ = await auth.verifyPIN("1234")
        #expect(auth.isUnlocked == true)
        #expect(auth.isSetupComplete == true)

        auth.lock()
        #expect(auth.isUnlocked == false)
        #expect(auth.isSetupComplete == true)
    }

    @Test("Auto-lock with immediate setting always returns true")
    @MainActor
    func autoLockImmediate() async throws {
        let (auth, _, _) = try makeServices()
        try await auth.createPIN("1234")
        _ = await auth.verifyPIN("1234")
        auth.recordBackgroundEntry()

        let shouldLock = auth.shouldAutoLock()
        #expect(shouldLock == true)
    }

    @Test("Route uses setup when setup is incomplete and session is locked")
    func routeUsesSetup() {
        #expect(determineAppRootRoute(
            hasCompletedOnboarding: true,
            isSetupComplete: false,
            isUnlocked: false
        ) == .setupPIN)
    }

    @Test("Route uses lock when setup is complete and session is locked")
    func routeUsesLock() {
        #expect(determineAppRootRoute(
            hasCompletedOnboarding: true,
            isSetupComplete: true,
            isUnlocked: false
        ) == .lock)
    }

    @Test("Route prioritizes main when session is unlocked")
    func routeUsesMainWhenUnlocked() {
        #expect(determineAppRootRoute(
            hasCompletedOnboarding: true,
            isSetupComplete: true,
            isUnlocked: true
        ) == .main)
        #expect(determineAppRootRoute(
            hasCompletedOnboarding: false,
            isSetupComplete: false,
            isUnlocked: true
        ) == .main)
    }

    @Test("Route transitions from setup to main after create PIN")
    @MainActor
    func routeTransitionsToMainAfterCreatePIN() async throws {
        let (auth, _, _) = try makeServices()
        #expect(determineAppRootRoute(
            hasCompletedOnboarding: false,
            isSetupComplete: auth.isSetupComplete,
            isUnlocked: auth.isUnlocked
        ) == .onboarding)

        try await auth.createPIN("1234")

        #expect(determineAppRootRoute(
            hasCompletedOnboarding: true,
            isSetupComplete: auth.isSetupComplete,
            isUnlocked: auth.isUnlocked
        ) == .main)
    }
}
