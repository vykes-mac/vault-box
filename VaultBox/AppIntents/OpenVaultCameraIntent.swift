import AppIntents

/// Shortcuts / Action button action that opens the in-app camera. It still goes through
/// the PIN lock; the camera tab is selected once the vault is unlocked.
///
/// Deliberately not exposed through an `AppShortcutsProvider`, so it doesn't surface in
/// Spotlight or Siri suggestions — people add it from the Shortcuts app themselves.
struct OpenVaultCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open VaultBox Camera"
    static let description = IntentDescription("Opens the VaultBox camera so photos go straight into your vault.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureLaunchRequest.markPending()
        return .result()
    }
}
