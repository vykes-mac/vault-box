import AVFoundation
import CoreLocation
import Foundation
import UserNotifications

enum BreakInPermissionKind: String, CaseIterable, Hashable, Sendable {
    case notifications
    case camera
    case location

    var displayName: String {
        switch self {
        case .notifications:
            "Notifications"
        case .camera:
            "Camera"
        case .location:
            "Location"
        }
    }

    var usageDescription: String {
        switch self {
        case .notifications:
            "security alerts"
        case .camera:
            "intruder photos"
        case .location:
            "GPS evidence"
        }
    }
}

enum BreakInPermissionState: String, Sendable, Equatable {
    case enabled
    case notSet
    case denied

    var displayLabel: String {
        switch self {
        case .enabled:
            "Enabled"
        case .notSet:
            "Not Set"
        case .denied:
            "Denied"
        }
    }
}

struct BreakInPermissionSnapshot: Sendable, Equatable {
    let notificationStatus: UNAuthorizationStatus
    let cameraStatus: AVAuthorizationStatus
    let locationStatus: CLAuthorizationStatus?
    let includeLocation: Bool

    var notificationState: BreakInPermissionState {
        BreakInPermissionService.notificationState(for: notificationStatus)
    }

    var cameraState: BreakInPermissionState {
        BreakInPermissionService.cameraState(for: cameraStatus)
    }

    var locationState: BreakInPermissionState? {
        guard includeLocation, let locationStatus else { return nil }
        return BreakInPermissionService.locationState(for: locationStatus)
    }

    var missingPermissions: Set<BreakInPermissionKind> {
        var missing = Set<BreakInPermissionKind>()

        if notificationState != .enabled {
            missing.insert(.notifications)
        }
        if cameraState != .enabled {
            missing.insert(.camera)
        }
        if includeLocation, locationState != .enabled {
            missing.insert(.location)
        }

        return missing
    }

    var hasMissingPermissions: Bool {
        !missingPermissions.isEmpty
    }

    var guidanceMessage: String {
        guard hasMissingPermissions else { return "" }

        let orderedMissing = BreakInPermissionKind.allCases.filter { missingPermissions.contains($0) }
        let permissionList = orderedMissing
            .map { "\($0.displayName) (\($0.usageDescription))" }
            .joined(separator: ", ")

        return "Break-in Alerts are enabled, but some protections are limited. Missing permissions: \(permissionList). You can enable them in iOS Settings."
    }
}

@MainActor
protocol BreakInNotificationPermissionClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool
}

@MainActor
protocol BreakInCameraPermissionClient {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess() async -> Bool
}

@MainActor
protocol BreakInLocationPermissionClient {
    func authorizationStatus() -> CLAuthorizationStatus
    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus
}

@MainActor
struct SystemBreakInNotificationPermissionClient: BreakInNotificationPermissionClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }
}

@MainActor
struct SystemBreakInCameraPermissionClient: BreakInCameraPermissionClient {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

@MainActor
final class SystemBreakInLocationPermissionClient: NSObject, BreakInLocationPermissionClient {
    private let locationManager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func authorizationStatus() -> CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
        let status = authorizationStatus()
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }
}

extension SystemBreakInLocationPermissionClient: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }

        Task { @MainActor in
            guard let continuation = self.authorizationContinuation else { return }
            self.authorizationContinuation = nil
            continuation.resume(returning: status)
        }
    }
}

@MainActor
final class BreakInPermissionService {
    private let notificationPermissionClient: BreakInNotificationPermissionClient
    private let cameraPermissionClient: BreakInCameraPermissionClient
    private let locationPermissionClient: BreakInLocationPermissionClient

    init(
        notificationPermissionClient: BreakInNotificationPermissionClient = SystemBreakInNotificationPermissionClient(),
        cameraPermissionClient: BreakInCameraPermissionClient = SystemBreakInCameraPermissionClient(),
        locationPermissionClient: BreakInLocationPermissionClient = SystemBreakInLocationPermissionClient()
    ) {
        self.notificationPermissionClient = notificationPermissionClient
        self.cameraPermissionClient = cameraPermissionClient
        self.locationPermissionClient = locationPermissionClient
    }

    func permissionSnapshot(includeLocation: Bool) async -> BreakInPermissionSnapshot {
        let notificationStatus = await notificationPermissionClient.authorizationStatus()
        let cameraStatus = cameraPermissionClient.authorizationStatus()
        let locationStatus = includeLocation ? locationPermissionClient.authorizationStatus() : nil

        return BreakInPermissionSnapshot(
            notificationStatus: notificationStatus,
            cameraStatus: cameraStatus,
            locationStatus: locationStatus,
            includeLocation: includeLocation
        )
    }

    func requestNotificationsIfNeeded() async -> UNAuthorizationStatus {
        var status = await notificationPermissionClient.authorizationStatus()
        guard status == .notDetermined else { return status }

        _ = await notificationPermissionClient.requestAuthorization(options: [.alert, .sound])
        status = await notificationPermissionClient.authorizationStatus()
        return status
    }

    func requestCameraIfNeeded() async -> AVAuthorizationStatus {
        var status = cameraPermissionClient.authorizationStatus()
        guard status == .notDetermined else { return status }

        _ = await cameraPermissionClient.requestAccess()
        status = cameraPermissionClient.authorizationStatus()
        return status
    }

    func requestLocationIfNeeded() async -> CLAuthorizationStatus {
        let status = locationPermissionClient.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await locationPermissionClient.requestWhenInUseAuthorization()
    }

    nonisolated static func isNotificationAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated static func notificationState(for status: UNAuthorizationStatus) -> BreakInPermissionState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .enabled
        case .notDetermined:
            return .notSet
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    nonisolated static func cameraState(for status: AVAuthorizationStatus) -> BreakInPermissionState {
        switch status {
        case .authorized:
            return .enabled
        case .notDetermined:
            return .notSet
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    nonisolated static func isLocationAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined, .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }

    nonisolated static func locationState(for status: CLAuthorizationStatus) -> BreakInPermissionState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .enabled
        case .notDetermined:
            return .notSet
        case .restricted, .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }
}
