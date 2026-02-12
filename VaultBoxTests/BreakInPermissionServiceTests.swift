import AVFoundation
import CoreLocation
import Testing
import UserNotifications
@testable import VaultBox

@Suite("BreakInPermissionService Tests")
struct BreakInPermissionServiceTests {
    @MainActor
    private final class MockNotificationPermissionClient: BreakInNotificationPermissionClient {
        var status: UNAuthorizationStatus
        var requestResult: Bool
        private(set) var requestCallCount = 0

        init(status: UNAuthorizationStatus, requestResult: Bool) {
            self.status = status
            self.requestResult = requestResult
        }

        func authorizationStatus() async -> UNAuthorizationStatus {
            status
        }

        func requestAuthorization(options: UNAuthorizationOptions) async -> Bool {
            requestCallCount += 1
            status = requestResult ? .authorized : .denied
            return requestResult
        }
    }

    @MainActor
    private final class MockCameraPermissionClient: BreakInCameraPermissionClient {
        var status: AVAuthorizationStatus
        var requestResult: Bool
        private(set) var requestCallCount = 0

        init(status: AVAuthorizationStatus, requestResult: Bool) {
            self.status = status
            self.requestResult = requestResult
        }

        func authorizationStatus() -> AVAuthorizationStatus {
            status
        }

        func requestAccess() async -> Bool {
            requestCallCount += 1
            status = requestResult ? .authorized : .denied
            return requestResult
        }
    }

    @MainActor
    private final class MockLocationPermissionClient: BreakInLocationPermissionClient {
        var status: CLAuthorizationStatus
        var requestResultStatus: CLAuthorizationStatus
        private(set) var requestCallCount = 0

        init(status: CLAuthorizationStatus, requestResultStatus: CLAuthorizationStatus) {
            self.status = status
            self.requestResultStatus = requestResultStatus
        }

        func authorizationStatus() -> CLAuthorizationStatus {
            status
        }

        func requestWhenInUseAuthorization() async -> CLAuthorizationStatus {
            requestCallCount += 1
            status = requestResultStatus
            return status
        }
    }

    @Test("Requests are issued only when status is not determined")
    @MainActor
    func requestsOnlyForNotDetermined() async {
        let notifications = MockNotificationPermissionClient(status: .notDetermined, requestResult: true)
        let camera = MockCameraPermissionClient(status: .notDetermined, requestResult: true)
        let location = MockLocationPermissionClient(status: .notDetermined, requestResultStatus: .authorizedWhenInUse)

        let service = BreakInPermissionService(
            notificationPermissionClient: notifications,
            cameraPermissionClient: camera,
            locationPermissionClient: location
        )

        let notificationStatus = await service.requestNotificationsIfNeeded()
        let cameraStatus = await service.requestCameraIfNeeded()
        let locationStatus = await service.requestLocationIfNeeded()

        #expect(notifications.requestCallCount == 1)
        #expect(camera.requestCallCount == 1)
        #expect(location.requestCallCount == 1)
        #expect(notificationStatus == .authorized)
        #expect(cameraStatus == .authorized)
        #expect(locationStatus == .authorizedWhenInUse)
    }

    @Test("Denied and restricted statuses do not trigger re-prompts")
    @MainActor
    func deniedOrRestrictedPermissionsDoNotRePrompt() async {
        let notifications = MockNotificationPermissionClient(status: .denied, requestResult: true)
        let camera = MockCameraPermissionClient(status: .restricted, requestResult: true)
        let location = MockLocationPermissionClient(status: .denied, requestResultStatus: .authorizedWhenInUse)

        let service = BreakInPermissionService(
            notificationPermissionClient: notifications,
            cameraPermissionClient: camera,
            locationPermissionClient: location
        )

        let notificationStatus = await service.requestNotificationsIfNeeded()
        let cameraStatus = await service.requestCameraIfNeeded()
        let locationStatus = await service.requestLocationIfNeeded()

        #expect(notifications.requestCallCount == 0)
        #expect(camera.requestCallCount == 0)
        #expect(location.requestCallCount == 0)
        #expect(notificationStatus == .denied)
        #expect(cameraStatus == .restricted)
        #expect(locationStatus == .denied)
    }

    @Test("Permission snapshot skips location when premium-only capture is inactive")
    @MainActor
    func skipsLocationWhenNotPremium() async {
        let notifications = MockNotificationPermissionClient(status: .authorized, requestResult: true)
        let camera = MockCameraPermissionClient(status: .authorized, requestResult: true)
        let location = MockLocationPermissionClient(status: .notDetermined, requestResultStatus: .authorizedWhenInUse)

        let service = BreakInPermissionService(
            notificationPermissionClient: notifications,
            cameraPermissionClient: camera,
            locationPermissionClient: location
        )

        let snapshot = await service.permissionSnapshot(includeLocation: false)

        #expect(location.requestCallCount == 0)
        #expect(snapshot.locationStatus == nil)
        #expect(snapshot.hasMissingPermissions == false)
    }

    @Test("Permission snapshot guidance reflects missing capabilities")
    @MainActor
    func guidanceMessageReflectsMissingCapabilities() async {
        let notifications = MockNotificationPermissionClient(status: .provisional, requestResult: true)
        let camera = MockCameraPermissionClient(status: .denied, requestResult: false)
        let location = MockLocationPermissionClient(status: .authorizedWhenInUse, requestResultStatus: .authorizedWhenInUse)

        let service = BreakInPermissionService(
            notificationPermissionClient: notifications,
            cameraPermissionClient: camera,
            locationPermissionClient: location
        )

        let snapshot = await service.permissionSnapshot(includeLocation: true)

        #expect(snapshot.hasMissingPermissions)
        #expect(snapshot.missingPermissions == Set([.camera]))
        #expect(snapshot.guidanceMessage.contains("Camera"))
        #expect(!snapshot.guidanceMessage.contains("Location"))
        #expect(!snapshot.guidanceMessage.contains("Notifications"))
    }
}
