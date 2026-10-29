import AppIntents
import Foundation

// MARK: - Quick Capture Context

/// What the app hands the Lock Screen capture extension. The extension can't read the
/// app's Keychain or containers, so this is its only configuration channel.
struct QuickCaptureContext: Codable, Sendable, Equatable {
    /// Raw Curve25519 public key the extension seals captures to.
    var recipientPublicKey: Data
}

// MARK: - Quick Capture Intent

/// Launches the secure capture extension from Control Center, the Lock Screen or the
/// Action button. The title is deliberately neutral so the control doesn't reveal the vault.
///
/// Compiled into the app, the capture extension and the controls extension, as
/// `CameraCaptureIntent` requires.
@available(iOS 18.0, *)
struct QuickCaptureIntent: CameraCaptureIntent {
    typealias AppContext = QuickCaptureContext

    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription("Take photos and videos privately.")

    /// Runs in the app when the device is already unlocked; the app opens its own camera.
    @MainActor
    func perform() async throws -> some IntentResult {
        QuickCaptureLaunchRequest.markPending()
        return .result()
    }
}

// MARK: - Launch Request

/// Set when an intent asks the app to open its camera; the app consumes it once the
/// vault is unlocked.
enum QuickCaptureLaunchRequest {
    @MainActor private static var isPending = false

    @MainActor
    static func markPending() {
        isPending = true
        NotificationCenter.default.post(name: .quickCaptureCameraRequested, object: nil)
    }

    @MainActor
    static func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}

extension Notification.Name {
    static let quickCaptureCameraRequested = Notification.Name("quickCaptureCameraRequested")
}
