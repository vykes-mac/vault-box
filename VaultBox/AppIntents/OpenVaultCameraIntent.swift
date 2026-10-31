import AppIntents
import Foundation

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
        CameraLaunchRequest.markPending()
        return .result()
    }
}

// MARK: - Launch Request

/// Set when an intent asks the app to open its camera; the app consumes it once the
/// vault is unlocked.
enum CameraLaunchRequest {
    @MainActor private static var isPending = false

    @MainActor
    static func markPending() {
        isPending = true
        NotificationCenter.default.post(name: .cameraLaunchRequested, object: nil)
    }

    @MainActor
    static func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}

extension Notification.Name {
    static let cameraLaunchRequested = Notification.Name("cameraLaunchRequested")
}
