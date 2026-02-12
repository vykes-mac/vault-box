import SwiftUI
import UIKit

@MainActor
struct BreakInPermissionSetupView: View {
    let includeLocation: Bool
    let title: String
    let subtitle: String
    let continueButtonTitle: String?
    let onContinue: (() -> Void)?

    @State private var snapshot: BreakInPermissionSnapshot?
    @State private var inFlightPermissions = Set<BreakInPermissionKind>()

    private var permissionRows: [BreakInPermissionKind] {
        var rows: [BreakInPermissionKind] = [.camera, .notifications]
        if includeLocation {
            rows.append(.location)
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.vaultTextPrimary)

                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(Color.vaultTextSecondary)
                    }

                    ForEach(permissionRows, id: \.self) { permission in
                        permissionRow(permission)
                    }
                }
                .padding(Constants.standardPadding)
            }

            if let continueButtonTitle, let onContinue {
                Button(continueButtonTitle) {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.vaultAccent)
                .padding(.horizontal, Constants.standardPadding)
                .padding(.bottom, 24)
            }
        }
        .background(Color.vaultBackground.ignoresSafeArea())
        .task {
            await refreshSnapshot()
        }
    }

    private func permissionRow(_ permission: BreakInPermissionKind) -> some View {
        let state = state(for: permission)
        let isRequesting = inFlightPermissions.contains(permission)
        let actionTitle = actionTitle(for: permission, state: state, isRequesting: isRequesting)
        let isDisabled = state == .enabled || isRequesting

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconName(for: permission))
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.displayName)
                        .font(.headline)
                        .foregroundStyle(Color.vaultTextPrimary)
                    Text(description(for: permission))
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                }

                Spacer(minLength: 8)

                Text(state.displayLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(for: state))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(for: state).opacity(0.12), in: Capsule())
            }

            Button(actionTitle) {
                handleTap(for: permission, state: state)
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
        .padding(14)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func state(for permission: BreakInPermissionKind) -> BreakInPermissionState {
        guard let snapshot else { return .notSet }

        switch permission {
        case .notifications:
            return snapshot.notificationState
        case .camera:
            return snapshot.cameraState
        case .location:
            return snapshot.locationState ?? .notSet
        }
    }

    private func description(for permission: BreakInPermissionKind) -> String {
        switch permission {
        case .notifications:
            return "Get instant break-in alerts."
        case .camera:
            return "Capture intruder photos at lockout thresholds."
        case .location:
            return "Record GPS evidence when premium is active."
        }
    }

    private func iconName(for permission: BreakInPermissionKind) -> String {
        switch permission {
        case .notifications:
            return "bell.badge"
        case .camera:
            return "camera.fill"
        case .location:
            return "location.fill"
        }
    }

    private func statusColor(for state: BreakInPermissionState) -> Color {
        switch state {
        case .enabled:
            return .green
        case .notSet:
            return .orange
        case .denied:
            return .red
        }
    }

    private func actionTitle(
        for permission: BreakInPermissionKind,
        state: BreakInPermissionState,
        isRequesting: Bool
    ) -> String {
        if isRequesting {
            return "Requesting..."
        }
        switch state {
        case .enabled:
            return "Enabled"
        case .notSet:
            return "Allow \(permission.displayName)"
        case .denied:
            return "Open Settings"
        }
    }

    private func handleTap(for permission: BreakInPermissionKind, state: BreakInPermissionState) {
        switch state {
        case .enabled:
            return
        case .denied:
            openAppSettings()
        case .notSet:
            request(permission: permission)
        }
    }

    private func request(permission: BreakInPermissionKind) {
        guard !inFlightPermissions.contains(permission) else { return }

        Task { @MainActor in
            inFlightPermissions.insert(permission)
            let service = BreakInPermissionService()

            switch permission {
            case .notifications:
                _ = await service.requestNotificationsIfNeeded()
            case .camera:
                _ = await service.requestCameraIfNeeded()
            case .location:
                _ = await service.requestLocationIfNeeded()
            }

            snapshot = await service.permissionSnapshot(includeLocation: includeLocation)
            inFlightPermissions.remove(permission)
        }
    }

    private func refreshSnapshot() async {
        let service = BreakInPermissionService()
        snapshot = await service.permissionSnapshot(includeLocation: includeLocation)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
