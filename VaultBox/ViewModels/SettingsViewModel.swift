import SwiftUI
import SwiftData

@MainActor
@Observable
class SettingsViewModel {
    let authService: AuthService
    let vaultService: VaultService

    var showChangePIN = false
    var showDecoySetup = false
    var showBreakInLog = false
    var showAppIconPicker = false
    var showBackupSettings = false
    var showPaywall = false
    var showClearBreakInConfirm = false
    var errorMessage: String?
    var showError = false

    init(authService: AuthService, vaultService: VaultService) {
        self.authService = authService
        self.vaultService = vaultService
    }

    // MARK: - Settings Access

    func loadSettings(modelContext: ModelContext) -> AppSettings? {
        let descriptor = FetchDescriptor<AppSettings>()
        return try? modelContext.fetch(descriptor).first
    }

    // MARK: - Biometrics

    func toggleBiometrics(enabled: Bool, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.biometricsEnabled = enabled
        try? modelContext.save()
    }

    // MARK: - Auto-Lock

    func setAutoLock(seconds: Int, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.autoLockSeconds = seconds
        try? modelContext.save()
    }

    // MARK: - Panic Gesture

    func togglePanicGesture(enabled: Bool, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.panicGestureEnabled = enabled
        try? modelContext.save()
    }

    // MARK: - Break-In Alerts

    func toggleBreakInAlerts(enabled: Bool, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.breakInAlertsEnabled = enabled
        try? modelContext.save()
    }

    // MARK: - iCloud Backup

    func toggleiCloudBackup(enabled: Bool, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.iCloudBackupEnabled = enabled
        try? modelContext.save()
    }

    // MARK: - Storage Info

    func itemCountText(purchaseService: PurchaseService) -> String {
        let count = vaultService.getTotalItemCount()
        if purchaseService.isPremium {
            return "\(count) item\(count == 1 ? "" : "s")"
        }
        return "\(count) of \(Constants.freeItemLimit) items"
    }

    func storageUsedText() -> String {
        let bytes = vaultService.getTotalStorageUsed()
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Clear Break-In Log

    func clearBreakInLog(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<BreakInAttempt>()
        guard let attempts = try? modelContext.fetch(descriptor) else { return }
        for attempt in attempts {
            modelContext.delete(attempt)
        }
        try? modelContext.save()
    }
}
