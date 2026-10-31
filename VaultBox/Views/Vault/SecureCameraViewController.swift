import UIKit
@preconcurrency import AVFoundation

// MARK: - SecureCameraViewController

/// Camera preview + shutter for the in-app camera tab. It never touches the photo
/// library: photos are handed back as encoded file data.
final class SecureCameraViewController: UIViewController {
    var onPhotoCaptured: ((Data) -> Void)?
    var cameraPosition: AVCaptureDevice.Position = .back

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentInput: AVCaptureDeviceInput?
    private let captureDelegate = PhotoDelegate()
    private let captureButton = UIButton(type: .system)
    private var isSimulatedCamera = false

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
              let input = try? AVCaptureDeviceInput(device: device) else {
            #if targetEnvironment(simulator)
            isSimulatedCamera = true
            setupSimulatedPreview()
            #endif
            return
        }

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
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        captureButton.accessibilityLabel = String(localized: "Take Photo")
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        // Flip camera button
        let flipButton = UIButton(type: .system)
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        flipButton.setImage(UIImage(systemName: "camera.rotate", withConfiguration: config), for: .normal)
        flipButton.tintColor = .white
        flipButton.accessibilityLabel = String(localized: "Switch Camera")
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

    @objc private func captureTapped() {
        let deliver: (Data) -> Void = { [weak self] data in
            DispatchQueue.main.async {
                self?.onPhotoCaptured?(data)
            }
        }

        #if targetEnvironment(simulator)
        if isSimulatedCamera {
            deliver(Self.simulatedPhotoData())
            return
        }
        #endif

        let settings = AVCapturePhotoSettings()
        captureDelegate.onCapture = deliver
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

    // MARK: Simulator

    #if targetEnvironment(simulator)
    /// The simulator has no camera; show a placeholder and hand back a generated photo so
    /// the save path can still be exercised end to end.
    private func setupSimulatedPreview() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Simulated camera"
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private static func simulatedPhotoData() -> Data {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let stamp = Date().formatted(date: .abbreviated, time: .standard) as NSString
            stamp.draw(at: CGPoint(x: 60, y: size.height / 2), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.white
            ])
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
    #endif
}

// MARK: - PhotoDelegate

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var onCapture: ((Data) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        onCapture?(data)
    }
}
