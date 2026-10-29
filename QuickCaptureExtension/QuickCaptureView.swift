import SwiftUI
import CryptoKit
import LockedCameraCapture
@preconcurrency import AVFoundation

// MARK: - QuickCaptureView

/// Camera shown over the Lock Screen. Every capture is sealed to the app's public key
/// before it is written, so nothing readable is left on disk if the app is never opened.
/// Copy stays neutral ("Quick Capture", "Saved") so the screen doesn't reveal the vault.
struct QuickCaptureView: View {
    let session: LockedCameraCaptureSession

    @State private var setupState: SetupState = .loading
    @State private var savedCount = 0
    @State private var showSavedBanner = false
    @State private var isRecording = false
    @State private var cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private enum SetupState {
        case loading
        case ready(Curve25519.KeyAgreement.PublicKey)
        case needsApp
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch setupState {
            case .loading:
                ProgressView().tint(.white)
            case .needsApp:
                messageView(
                    systemImage: "camera.aperture",
                    title: "Finish setting up Quick Capture",
                    message: "Open the app once to turn on Quick Capture."
                )
            case .ready(let recipientKey):
                if cameraAuthStatus == .authorized {
                    cameraView(recipientKey: recipientKey)
                } else if cameraAuthStatus == .notDetermined {
                    Color.black.ignoresSafeArea()
                } else {
                    messageView(
                        systemImage: "camera.fill",
                        title: "Camera Access Required",
                        message: "Allow camera access in Settings to use Quick Capture."
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadSetup() }
    }

    // MARK: Camera

    private func cameraView(recipientKey: Curve25519.KeyAgreement.PublicKey) -> some View {
        ZStack(alignment: .top) {
            QuickCaptureCameraContainer(
                recordingDirectory: recordingDirectory,
                onPhotoCaptured: { data in
                    store(photo: data, recipientKey: recipientKey)
                },
                onVideoRecorded: { url in
                    store(videoAt: url, recipientKey: recipientKey)
                },
                onRecordingStateChanged: { isRecording = $0 }
            )
            .ignoresSafeArea()

            HStack {
                if savedCount > 0 {
                    Label("\(savedCount)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("\(savedCount) saved")
                }
                Spacer()
                if !isRecording {
                    openAppButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if showSavedBanner {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var openAppButton: some View {
        Button {
            openApp()
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Open App")
    }

    private func messageView(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open App") { openApp() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    // MARK: Setup

    private var recordingDirectory: URL {
        session.sessionContentURL.appendingPathComponent("recording", isDirectory: true)
    }

    private func loadSetup() async {
        if cameraAuthStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthStatus = granted ? .authorized : .denied
        }

        try? FileManager.default.createDirectory(
            at: recordingDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )

        guard let context = try? await QuickCaptureIntent.appContext,
              let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: context.recipientPublicKey) else {
            setupState = .needsApp
            return
        }
        setupState = .ready(key)
    }

    private func openApp() {
        Task {
            let activity = NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture)
            try? await session.openApplication(for: activity)
        }
    }

    // MARK: Storing

    private func store(photo data: Data, recipientKey: Curve25519.KeyAgreement.PublicKey) {
        let destination = sealedDestination()
        Task {
            let stored = await Task.detached(priority: .userInitiated) {
                do {
                    let sealed = try SealedCapture.seal(data, kind: .photo, to: recipientKey)
                    try sealed.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
                    return true
                } catch {
                    return false
                }
            }.value
            if stored { await didStore() }
        }
    }

    /// The recording is plaintext only while it is being written; it is sealed and
    /// removed as soon as recording stops.
    private func store(videoAt url: URL, recipientKey: Curve25519.KeyAgreement.PublicKey) {
        let destination = sealedDestination()
        Task {
            let stored = await Task.detached(priority: .userInitiated) {
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    try SealedCapture.sealFile(at: url, kind: .video, to: recipientKey, destination: destination)
                    return true
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    return false
                }
            }.value
            if stored { await didStore() }
        }
    }

    private func sealedDestination() -> URL {
        session.sessionContentURL
            .appendingPathComponent(SecureCameraViewController.captureFileStem())
            .appendingPathExtension(SealedCapture.fileExtension)
    }

    @MainActor
    private func didStore() async {
        savedCount += 1
        withAnimation { showSavedBanner = true }
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation { showSavedBanner = false }
    }
}

// MARK: - Camera Container

private struct QuickCaptureCameraContainer: UIViewControllerRepresentable {
    let recordingDirectory: URL
    let onPhotoCaptured: (Data) -> Void
    let onVideoRecorded: (URL) -> Void
    let onRecordingStateChanged: (Bool) -> Void

    func makeUIViewController(context: Context) -> SecureCameraViewController {
        let vc = SecureCameraViewController()
        vc.movieRecordingDirectory = recordingDirectory
        vc.onPhotoCaptured = onPhotoCaptured
        vc.onVideoRecorded = onVideoRecorded
        vc.onRecordingStateChanged = onRecordingStateChanged
        return vc
    }

    func updateUIViewController(_ vc: SecureCameraViewController, context: Context) {}
}
