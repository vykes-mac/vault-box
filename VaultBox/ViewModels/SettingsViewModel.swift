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

    func togglePanicGesture(enabled: Bool, modelContext: ModelContext, panicGestureService: PanicGestureService?) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.panicGestureEnabled = enabled
        try? modelContext.save()

        if enabled {
            panicGestureService?.startMonitoring()
        } else {
            panicGestureService?.stopMonitoring()
        }
    }

    func setPanicAction(_ action: PanicAction, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.panicAction = action.rawValue
        try? modelContext.save()
    }

    // MARK: - Theme

    func setThemeMode(_ mode: String, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.themeMode = mode
        try? modelContext.save()
        NotificationCenter.default.post(name: .themeDidChange, object: nil)
    }

    // MARK: - Break-In Alerts

    @discardableResult
    func toggleBreakInAlerts(enabled: Bool, modelContext: ModelContext) -> Bool {
        guard let settings = loadSettings(modelContext: modelContext) else { return false }
        settings.breakInAlertsEnabled = enabled
        try? modelContext.save()
        return settings.breakInAlertsEnabled
    }

    // MARK: - iCloud Backup

    func toggleiCloudBackup(enabled: Bool, modelContext: ModelContext) {
        guard let settings = loadSettings(modelContext: modelContext) else { return }
        settings.iCloudBackupEnabled = enabled
        try? modelContext.save()
    }

    // MARK: - Storage Info

    func itemCountText(purchaseService: PurchaseService, isDecoyMode: Bool) -> String {
        let count = vaultService.getItemCount(isDecoyMode: isDecoyMode)
        if purchaseService.isPremium {
            return "\(count) item\(count == 1 ? "" : "s")"
        }
        return "\(count) of \(Constants.freeItemLimit) items"
    }

    func storageUsedText(isDecoyMode: Bool) -> String {
        let bytes = vaultService.getStorageUsed(isDecoyMode: isDecoyMode)
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
