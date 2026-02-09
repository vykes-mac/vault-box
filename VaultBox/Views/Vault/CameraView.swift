import SwiftUI
@preconcurrency import AVFoundation

// MARK: - CameraView

struct CameraView: View {
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @State private var capturedImage: UIImage?
    @State private var showPreview = false
    @State private var isSaving = false
    @State private var savedCount = 0
    @State private var showSavedBanner = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var cameraPosition: AVCaptureDevice.Position = .back

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewContainer(
                    cameraPosition: $cameraPosition,
                    onCapture: { image in
                        capturedImage = image
                        showPreview = true
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
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPreview) {
                if let image = capturedImage {
                    CameraPreviewSheet(
                        image: image,
                        isSaving: isSaving,
                        onSave: { saveToVault(image) },
                        onRetake: { showPreview = false }
                    )
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "An unexpected error occurred.")
            }
        }
    }

    private func saveToVault(_ image: UIImage) {
        isSaving = true
        Task {
            do {
                _ = try await vaultService.importFromCamera(image, album: nil)
                isSaving = false
                showPreview = false
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
                errorMessage = "Couldn't import this photo. Please try again."
                showError = true
            }
        }
    }
}

// MARK: - Camera Preview Sheet

private struct CameraPreviewSheet: View {
    let image: UIImage
    let isSaving: Bool
    let onSave: () -> Void
    let onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss

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
                .padding(.vertical, 20)
                .background(Color.vaultBackground)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Camera Preview Container

private struct CameraPreviewContainer: UIViewControllerRepresentable {
    @Binding var cameraPosition: AVCaptureDevice.Position
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onCapture = onCapture
        vc.cameraPosition = cameraPosition
        return vc
    }

    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        if vc.cameraPosition != cameraPosition {
            vc.cameraPosition = cameraPosition
            vc.switchCamera()
        }
    }
}

// MARK: - CameraViewController

private final class CameraViewController: UIViewController {
    var onCapture: ((UIImage) -> Void)?
    var cameraPosition: AVCaptureDevice.Position = .back

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentInput: AVCaptureDeviceInput?
    private let captureDelegate = PhotoDelegate()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        captureSession.sessionPreset = .photo

        guard let device = camera(for: cameraPosition),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
            currentInput = input
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func setupUI() {
        // Capture button
        let captureButton = UIButton(type: .system)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)

        // Flip camera button
        let flipButton = UIButton(type: .system)
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        flipButton.setImage(UIImage(systemName: "camera.rotate", withConfiguration: config), for: .normal)
        flipButton.tintColor = .white
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        view.addSubview(flipButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),

            flipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            flipButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            flipButton.widthAnchor.constraint(equalToConstant: 44),
            flipButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        captureDelegate.onCapture = { [weak self] image in
            DispatchQueue.main.async {
                self?.onCapture?(image)
            }
        }
        photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
    }

    @objc private func flipCamera() {
        cameraPosition = (cameraPosition == .back) ? .front : .back
        switchCamera()
    }

    func switchCamera() {
        guard let currentInput else { return }

        captureSession.beginConfiguration()
        captureSession.removeInput(currentInput)

        guard let device = camera(for: cameraPosition),
              let newInput = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(newInput) else {
            captureSession.addInput(currentInput)
            captureSession.commitConfiguration()
            return
        }

        captureSession.addInput(newInput)
        self.currentInput = newInput
        captureSession.commitConfiguration()
    }

    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

// MARK: - PhotoDelegate

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var onCapture: ((UIImage) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        onCapture?(image)
    }
}
