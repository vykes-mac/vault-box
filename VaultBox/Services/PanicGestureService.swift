import Foundation
import CoreMotion
import UIKit

@MainActor
@Observable
class PanicGestureService {
    private let motionManager = CMMotionManager()
    private var isMonitoring = false
    var onPanicTriggered: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring, motionManager.isDeviceMotionAvailable else { return }
        isMonitoring = true

        motionManager.deviceMotionUpdateInterval = 0.3
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let gravity = motion?.gravity else { return }

            // Face-down detection: z gravity > 0.9 means face-down
            if gravity.z > 0.9 {
                Task { @MainActor in
                    self?.triggerPanic()
                }
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        motionManager.stopDeviceMotionUpdates()
        isMonitoring = false
    }

    private func triggerPanic() {
        Haptics.panicTriggered()

        // Clear temp files
        clearTempFiles()

        onPanicTriggered?()
    }

    private func clearTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - Three-Finger Swipe Gesture Recognizer

class ThreeFingerSwipeGestureRecognizer: UISwipeGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        numberOfTouchesRequired = 3
        direction = .down
    }
}
