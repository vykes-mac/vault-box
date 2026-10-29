import UIKit
@preconcurrency import AVFoundation

// MARK: - SecureCameraViewController

/// Camera preview + shutter shared by the in-app camera tab and the Lock Screen
/// capture extension. It never touches the photo library: photos are handed back as
/// encoded file data and videos are recorded into `movieRecordingDirectory`.
final class SecureCameraViewController: UIViewController {
    enum Mode {
        case photo
        case video
    }

    var onPhotoCaptured: ((Data) -> Void)?
    var onVideoRecorded: ((URL) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    var cameraPosition: AVCaptureDevice.Position = .back
    /// Where in-progress recordings are written. `nil` hides video mode entirely.
    var movieRecordingDirectory: URL?
    /// Caps a single recording so the app can always import it later.
    var maxRecordingBytes: Int64 = 240 * 1024 * 1024

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private let captureDelegate = PhotoDelegate()
    private let recordingDelegate = MovieDelegate()
    private var mode: Mode = .photo
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
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private var supportsVideo: Bool {
        movieRecordingDirectory != nil && !isSimulatedCamera
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

        if movieRecordingDirectory != nil, captureSession.canAddOutput(movieOutput) {
            movieOutput.maxRecordedFileSize = maxRecordingBytes
            captureSession.addOutput(movieOutput)
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

        guard supportsVideo else { return }

        let modePicker = UISegmentedControl(items: [String(localized: "Photo"), String(localized: "Video")])
        modePicker.translatesAutoresizingMaskIntoConstraints = false
        modePicker.selectedSegmentIndex = 0
        modePicker.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.35)
        modePicker.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modePicker.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        modePicker.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        view.addSubview(modePicker)

        NSLayoutConstraint.activate([
            modePicker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modePicker.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -20),
            modePicker.widthAnchor.constraint(equalToConstant: 180)
        ])
    }

    @objc private func captureTapped() {
        switch mode {
        case .photo:
            capturePhoto()
        case .video:
            toggleRecording()
        }
    }

    private func capturePhoto() {
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

    private func toggleRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            return
        }
        guard let movieRecordingDirectory else { return }

        let url = movieRecordingDirectory.appendingPathComponent("\(Self.captureFileStem()).mov")
        recordingDelegate.onFinish = { [weak self] url, succeeded in
            DispatchQueue.main.async {
                self?.setRecordingAppearance(false)
                if succeeded {
                    self?.onVideoRecorded?(url)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        movieOutput.startRecording(to: url, recordingDelegate: recordingDelegate)
        setRecordingAppearance(true)
    }

    private func setRecordingAppearance(_ isRecording: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.captureButton.backgroundColor = isRecording
                ? UIColor.systemRed
                : (self.mode == .video ? UIColor.systemRed.withAlphaComponent(0.5) : UIColor.white.withAlphaComponent(0.3))
        }
        captureButton.accessibilityLabel = isRecording
            ? String(localized: "Stop Recording")
            : (mode == .video ? String(localized: "Record Video") : String(localized: "Take Photo"))
        onRecordingStateChanged?(isRecording)
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        guard !movieOutput.isRecording else {
            sender.selectedSegmentIndex = mode == .photo ? 0 : 1
            return
        }
        mode = sender.selectedSegmentIndex == 0 ? .photo : .video

        captureSession.beginConfiguration()
        captureSession.sessionPreset = mode == .photo ? .photo : .high
        captureSession.commitConfiguration()

        if mode == .video {
            attachMicrophoneIfAllowed()
        }
        setRecordingAppearance(false)
    }

    /// Videos get sound only when microphone access was already granted or is granted
    /// now; otherwise they record silently rather than blocking capture.
    private func attachMicrophoneIfAllowed() {
        guard audioInput == nil else { return }
        let session = captureSession
        Task { @MainActor [weak self] in
            guard await AVCaptureDevice.requestAccess(for: .audio),
                  let self, self.audioInput == nil,
                  let mic = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: mic) else { return }
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
                self.audioInput = input
            }
            session.commitConfiguration()
        }
    }

    @objc private func flipCamera() {
        guard !movieOutput.isRecording else { return }
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

    /// Sortable, collision-free name so captures are ingested in the order they were taken.
    static func captureFileStem() -> String {
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        return "\(millis)-\(UUID().uuidString)"
    }

    // MARK: Simulator

    #if targetEnvironment(simulator)
    /// The simulator has no camera; show a placeholder and hand back a generated photo so
    /// the capture → seal → ingest pipeline can still be exercised end to end.
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

// MARK: - MovieDelegate

private final class MovieDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onFinish: ((URL, Bool) -> Void)?

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // Hitting maxRecordedFileSize reports an error but still finalizes a playable file.
        let succeeded: Bool
        if let error = error as NSError? {
            succeeded = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        } else {
            succeeded = true
        }
        onFinish?(outputFileURL, succeeded)
    }
}
