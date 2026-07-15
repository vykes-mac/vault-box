import CoreMotion
import Foundation
import Observation

@MainActor
@Observable
final class DisguiseMotionModel {
    private let manager = CMMotionManager()
    private var timer: Timer?

    private(set) var headingDegrees: Double?
    private(set) var pitchDegrees: Double?
    private(set) var rollDegrees: Double?

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        guard !manager.isDeviceMotionActive else { return }

        manager.deviceMotionUpdateInterval = 1 / 30
        let referenceFrame: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames()
            .contains(.xMagneticNorthZVertical)
            ? .xMagneticNorthZVertical
            : .xArbitraryCorrectedZVertical
        manager.startDeviceMotionUpdates(using: referenceFrame)

        timer = Timer.scheduledTimer(withTimeInterval: 1 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.readLatestMotion()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        manager.stopDeviceMotionUpdates()
    }

    private func readLatestMotion() {
        guard let attitude = manager.deviceMotion?.attitude else { return }
        headingDegrees = normalizedDegrees(attitude.yaw * 180 / .pi)
        pitchDegrees = attitude.pitch * 180 / .pi
        rollDegrees = attitude.roll * 180 / .pi
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}
