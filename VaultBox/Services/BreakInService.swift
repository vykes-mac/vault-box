import Foundation
import AVFoundation
import CoreLocation
import SwiftData
import UIKit
import UserNotifications

@MainActor
@Observable
class BreakInService: NSObject {
    private let modelContext: ModelContext
    private let hasPremiumAccess: () -> Bool
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    init(modelContext: ModelContext, hasPremiumAccess: @escaping () -> Bool = { false }) {
        self.modelContext = modelContext
        self.hasPremiumAccess = hasPremiumAccess
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Capture Intruder

    func captureIntruder(attemptedPIN: String) async -> BreakInAttempt {
        let attempt = BreakInAttempt(attemptedPIN: attemptedPIN)

        // Capture front camera photo
        if let photoData = await captureFrontCameraPhoto() {
            attempt.intruderPhotoData = photoData
        }

        // Premium-only GPS capture
        if hasPremiumAccess(), hasLocationAuthorization {
            requestLocationUpdate()
            // Wait briefly for location
            try? await Task.sleep(for: .seconds(1))
            if let location = currentLocation {
                attempt.latitude = location.coordinate.latitude
                attempt.longitude = location.coordinate.longitude
            }
        }

        modelContext.insert(attempt)

        // Auto-purge old attempts
        purgeOldAttempts()

        try? modelContext.save()

        // Send local notification
        await sendBreakInNotificationIfEnabled()

        return attempt
    }

    // MARK: - Front Camera Capture

    private func captureFrontCameraPhoto() async -> Data? {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return nil
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            return nil
        }

        do {
            let session = AVCaptureSession()
            session.sessionPreset = .photo

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return nil }
            session.addInput(input)

            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else { return nil }
            session.addOutput(output)

            session.startRunning()

            let photoData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                let delegate = PhotoCaptureDelegate(continuation: continuation)
                let photoSettings = AVCapturePhotoSettings()
                photoSettings.flashMode = .off
                output.capturePhoto(with: photoSettings, delegate: delegate)
                // Hold reference to delegate
                objc_setAssociatedObject(output, "captureDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            }

            session.stopRunning()
            return photoData
        } catch {
            return nil
        }
    }

    // MARK: - Location

    private var hasLocationAuthorization: Bool {
        BreakInPermissionService.isLocationAuthorized(locationManager.authorizationStatus)
    }

    private func requestLocationUpdate() {
        locationManager.requestLocation()
    }

    // MARK: - Notification

    private func sendBreakInNotificationIfEnabled() async {
        guard areBreakInAlertsEnabled() else { return }

        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        guard BreakInPermissionService.isNotificationAuthorized(notificationSettings.authorizationStatus) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Security Alert"
        content.body = "Someone tried to access VaultBox"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    private func areBreakInAlertsEnabled() -> Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else {
            return true
        }
        return settings.breakInAlertsEnabled
    }

    // MARK: - Purge

    private func purgeOldAttempts() {
        let descriptor = FetchDescriptor<BreakInAttempt>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let allAttempts = try? modelContext.fetch(descriptor) else { return }

        if allAttempts.count > Constants.maxBreakInAttempts {
            let toRemove = allAttempts.suffix(from: Constants.maxBreakInAttempts)
            for attempt in toRemove {
                modelContext.delete(attempt)
            }
        }
    }

    // MARK: - Query

    func getRecentAttempts() -> [BreakInAttempt] {
        var descriptor = FetchDescriptor<BreakInAttempt>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = Constants.maxBreakInAttempts
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - CLLocationManagerDelegate

extension BreakInService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.currentLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location unavailable — proceed without it
    }
}

// MARK: - Photo Capture Delegate

private class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<Data?, Error>?

    init(continuation: CheckedContinuation<Data?, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: photo.fileDataRepresentation())
        }
        continuation = nil
    }
}
