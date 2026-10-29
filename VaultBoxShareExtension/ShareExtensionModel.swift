import Foundation
import LocalAuthentication

/// Drives the share sheet: confirm it's the vault owner (Face ID or the VaultBox PIN), then
/// seal each attachment into the inbox the app imports from on its next unlock.
@MainActor
@Observable
final class ShareExtensionModel {
    enum Phase: Equatable {
        case loading
        /// No configuration yet: the vault hasn't been set up, or never unlocked since
        /// this version was installed.
        case unavailable
        case locked
        case lockedOut(until: Date)
        case saving(completed: Int, total: Int)
        case finished(saved: Int, skipped: Int)
    }

    enum BiometricKind {
        case faceID
        case touchID
        case opticID
    }

    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 5 * 60
    private static let failedAttemptsKey = "shareExtension.failedPINAttempts"
    private static let lockoutUntilKey = "shareExtension.lockoutUntil"

    private(set) var phase: Phase = .loading
    private(set) var enteredPIN = ""
    private(set) var showsPINError = false
    private(set) var biometricKind: BiometricKind?

    var pinLength: Int { configuration?.pinLength ?? 4 }
    var itemCount: Int { providers.count }
    var showsDocumentPremiumNote: Bool {
        guard let configuration, !configuration.canImportDocuments else { return false }
        return providers.contains { SharedItemLoader.classify(typeIdentifiers: $0.registeredTypeIdentifiers)?.kind == .document }
    }

    private let providers: [NSItemProvider]
    private let rootDirectory: URL?
    private let defaults: UserDefaults?
    private let onComplete: () -> Void
    private let onCancel: () -> Void
    private var configuration: ShareInboxConfiguration?

    init(
        providers: [NSItemProvider],
        rootDirectory: URL? = ShareInbox.rootDirectory(),
        defaults: UserDefaults? = UserDefaults(suiteName: ShareInbox.appGroupIdentifier),
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.providers = providers
        self.rootDirectory = rootDirectory
        self.defaults = defaults
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    func start() {
        guard let rootDirectory, let configuration = ShareInboxConfiguration.read(from: rootDirectory) else {
            phase = .unavailable
            return
        }
        self.configuration = configuration

        if configuration.biometricsEnabled {
            let context = LAContext()
            var error: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                biometricKind = switch context.biometryType {
                case .faceID: .faceID
                case .touchID: .touchID
                case .opticID: .opticID
                default: nil
                }
            }
        }

        if let until = lockoutUntil() {
            phase = .lockedOut(until: until)
            return
        }
        phase = .locked
        if biometricKind != nil {
            Task { await authenticateWithBiometrics() }
        }
    }

    func cancel() {
        onCancel()
    }

    // MARK: - PIN

    func appendDigit(_ digit: String) {
        guard phase == .locked, enteredPIN.count < pinLength else { return }
        showsPINError = false
        enteredPIN.append(digit)
        if enteredPIN.count == pinLength {
            verifyPIN()
        }
    }

    func deleteDigit() {
        guard phase == .locked, !enteredPIN.isEmpty else { return }
        enteredPIN.removeLast()
    }

    private func verifyPIN() {
        guard let configuration else { return }
        let pin = enteredPIN
        enteredPIN = ""

        if configuration.pin.matches(pin) {
            unlocked(isDecoy: false)
        } else if configuration.decoyPIN?.matches(pin) == true {
            unlocked(isDecoy: true)
        } else {
            recordFailedAttempt()
        }
    }

    private func recordFailedAttempt() {
        showsPINError = true
        let attempts = (defaults?.integer(forKey: Self.failedAttemptsKey) ?? 0) + 1
        if attempts >= Self.maxFailedAttempts {
            let until = Date().addingTimeInterval(Self.lockoutDuration)
            defaults?.set(until, forKey: Self.lockoutUntilKey)
            defaults?.set(0, forKey: Self.failedAttemptsKey)
            phase = .lockedOut(until: until)
        } else {
            defaults?.set(attempts, forKey: Self.failedAttemptsKey)
        }
    }

    private func lockoutUntil() -> Date? {
        let now = Date()
        let candidates = [configuration?.lockoutUntil, defaults?.object(forKey: Self.lockoutUntilKey) as? Date]
        return candidates.compactMap { $0 }.filter { $0 > now }.max()
    }

    // MARK: - Biometrics

    func authenticateWithBiometrics() async {
        guard phase == .locked, biometricKind != nil else { return }
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Enter PIN")
        let success = (try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: String(localized: "Add items to your vault")
        )) ?? false
        // Biometrics always opens the real vault, same as the app's lock screen.
        if success, phase == .locked {
            unlocked(isDecoy: false)
        }
    }

    // MARK: - Saving

    private func unlocked(isDecoy: Bool) {
        defaults?.removeObject(forKey: Self.failedAttemptsKey)
        defaults?.removeObject(forKey: Self.lockoutUntilKey)
        Task { await save(isDecoy: isDecoy) }
    }

    private func save(isDecoy: Bool) async {
        guard let configuration, let rootDirectory else { return }
        let total = providers.count
        phase = .saving(completed: 0, total: total)

        var saved = 0
        for (index, provider) in providers.enumerated() {
            let outcome = await SharedItemLoader.enqueue(
                provider,
                isDecoy: isDecoy,
                recipientPublicKey: configuration.recipientPublicKey,
                root: rootDirectory
            )
            if outcome == .saved { saved += 1 }
            phase = .saving(completed: index + 1, total: total)
        }

        phase = .finished(saved: saved, skipped: total - saved)
        try? await Task.sleep(for: .seconds(saved == total ? 1.2 : 2.5))
        onComplete()
    }
}
