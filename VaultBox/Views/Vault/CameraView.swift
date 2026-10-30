import SwiftUI
import SwiftData
@preconcurrency import AVFoundation

// MARK: - CameraView

struct CameraView: View {
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Environment(PurchaseService.self) private var purchaseService
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<VaultItem> { $0.deletedAt == nil }) private var allItems: [VaultItem]

    @State private var capturedPhoto: CapturedPhoto?
    @State private var isSaving = false
    @State private var savedCount = 0
    @State private var showSavedBanner = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPaywall = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var cameraAuthStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        NavigationStack {
            ZStack {
                if cameraAuthStatus == .authorized {
                    CameraPreviewContainer(
                        cameraPosition: $cameraPosition,
                        onCapture: { image in
                            capturedPhoto = CapturedPhoto(image: image)
                        }
                    )
                    .ignoresSafeArea()

                    // Save banner
                    if showSavedBanner {
                        VStack {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.vaultSuccess)
                                Text("Saved to vault")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.top, 60)

                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } else if cameraAuthStatus == .denied || cameraAuthStatus == .restricted {
                    cameraPermissionDeniedView
                } else {
                    // .notDetermined — waiting for permission request
                    Color.black.ignoresSafeArea()
                }
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await checkAndRequestCameraPermission()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
                }
            }
            .sheet(item: $capturedPhoto) { photo in
                CameraPreviewSheet(
                    image: photo.image,
                    isSaving: isSaving,
                    onSave: { saveToVault(photo.image) },
                    onRetake: { capturedPhoto = nil }
                )
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
            .fullScreenCover(isPresented: $showPaywall) {
                VaultBoxPaywallView()
            }
        }
    }

    // MARK: - Camera Permission

    private var cameraPermissionDeniedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.vaultTextSecondary)

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.vaultTextPrimary)

            Text("VaultBox needs camera access to capture photos into your vault. You can enable it in Settings.")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 44)
                    .background(Color.vaultAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vaultBackground.ignoresSafeArea())
    }

    private func checkAndRequestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuthStatus = granted ? .authorized : .denied
        } else {
            cameraAuthStatus = status
        }
    }

    private func saveToVault(_ image: UIImage) {
        if purchaseService.isPremiumRequired(for: .unlimitedItems, itemCount: allItems.count) {
            capturedPhoto = nil
            showPaywall = true
            return
        }

        isSaving = true
        Task {
            do {
                let item = try await vaultService.importFromCamera(
                    image,
                    album: nil,
                    isDecoyMode: isDecoyMode
                )
                vaultService.queueVisionAnalysis(for: [item])
                vaultService.queueSearchIndexing(for: [item])
                isSaving = false
                capturedPhoto = nil
                savedCount += 1

                withAnimation {
                    showSavedBanner = true
                }
                try? await Task.sleep(for: .seconds(2))
                withAnimation {
                    showSavedBanner = false
                }
            } catch {
                isSaving = false
                if let vaultError = error as? VaultError, case .freeLimitReached = vaultError {
                    capturedPhoto = nil
                    showPaywall = true
                } else {
                    errorMessage = String(localized: "Couldn't import this photo. Please try again.")
                    showError = true
                }
            }
        }
    }
}

private struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Camera Preview Sheet

private struct CameraPreviewSheet: View {
    let image: UIImage
    let isSaving: Bool
    let onSave: () -> Void
    let onRetake: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                HStack(spacing: 40) {
                    Button("Retake") {
                        onRetake()
                    }
                    .foregroundStyle(Color.vaultTextPrimary)

                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 120, height: 44)
                                .background(Color.vaultAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Text("Save to Vault")
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 120, height: 44)
                                .background(Color.vaultAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .disabled(isSaving)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Color.vaultBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationBackground(Color.black)
    }
}

// MARK: - Camera Preview Container

private struct CameraPreviewContainer: UIViewControllerRepresentable {
    @Binding var cameraPosition: AVCaptureDevice.Position
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> SecureCameraViewController {
        let vc = SecureCameraViewController()
        vc.onPhotoCaptured = { data in
            guard let image = UIImage(data: data) else { return }
            onCapture(image)
        }
        vc.cameraPosition = cameraPosition
        return vc
    }

    func updateUIViewController(_ vc: SecureCameraViewController, context: Context) {
        if vc.cameraPosition != cameraPosition {
            vc.cameraPosition = cameraPosition
            vc.switchCamera()
        }
    }
}
