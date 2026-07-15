import SwiftUI

struct AppIconPickerView: View {
    @Environment(PurchaseService.self) private var purchaseService
    @AppStorage("disguise.hasLearnedPrivateUnlock") private var hasLearnedPrivateUnlock = false

    private let iconService = AppIconService()
    @State private var availableIcons = [AppIconService.IconOption]()
    @State private var currentIcon: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPaywall = false
    @State private var unlockGuideDisguise: AppDisguise?

    var body: some View {
        List {
            Section {
                ForEach(availableIcons, id: \.displayName) { icon in
                    Button {
                        selectIcon(icon.id)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: icon.systemImage)
                                .font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color.vaultSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text(icon.displayName)
                                .foregroundStyle(Color.vaultTextPrimary)

                            Spacer()

                            if currentIcon == icon.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.vaultAccent)
                            }
                        }
                    }
                }
            } footer: {
                if availableIcons.count <= 1 {
                    Text("No alternate app icons are configured in this build.")
                } else {
                    Text("A disguise opens as a small utility. iOS keeps the Home Screen label “VaultBox”; only a user-created Shortcut can use a different label.")
                }
            }

            if let activeDisguise = AppDisguise(iconName: currentIcon) {
                Section {
                    Button {
                        unlockGuideDisguise = activeDisguise
                    } label: {
                        Label("Practice the private unlock gesture", systemImage: "hand.tap.fill")
                    }
                    Label("Then use your PIN or biometrics", systemImage: "faceid")
                        .foregroundStyle(Color.vaultTextPrimary)
                } header: {
                    Text("Private unlock")
                } footer: {
                    Text("The gesture instructions appear only here in VaultBox settings, never on the utility cover.")
                }
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            availableIcons = iconService.availableIcons()
            currentIcon = iconService.getCurrentIcon()
            if purchaseService.isPremiumRequired(for: .fakeAppIcon) {
                showPaywall = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Failed to change app icon.")
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
        }
        .sheet(item: $unlockGuideDisguise) { disguise in
            DisguiseUnlockGuideView(disguise: disguise) {
                hasLearnedPrivateUnlock = true
            }
        }
    }

    private func selectIcon(_ iconID: String?) {
        if iconID != nil, !availableIcons.contains(where: { $0.id == iconID }) {
            errorMessage = "This app icon is not available in the current build."
            showError = true
            return
        }
        if purchaseService.isPremiumRequired(for: .fakeAppIcon) {
            showPaywall = true
            return
        }
        Task {
            do {
                try await iconService.setIcon(iconID)
                currentIcon = iconID
                if shouldPresentDisguiseUnlockGuide(
                    iconName: iconID,
                    hasLearnedGesture: hasLearnedPrivateUnlock
                ) {
                    unlockGuideDisguise = AppDisguise(iconName: iconID)
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

private struct DisguiseUnlockGuideView: View {
    @Environment(\.dismiss) private var dismiss

    let disguise: AppDisguise
    let onCompleted: () -> Void

    @State private var didPracticeGesture = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.vaultAccent)
                    .frame(width: 82, height: 82)
                    .background(Color.vaultAccent.opacity(0.12), in: Circle())

                VStack(spacing: 8) {
                    Text("Remember Your Private Unlock")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Practice it here before leaving VaultBox. No instructions or unlock symbol will appear on the utility cover.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                practiceCard

                Spacer(minLength: 0)

                Button(didPracticeGesture ? "Done" : "Press and hold the title above") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(!didPracticeGesture)
            }
            .padding(24)
            .navigationTitle("Disguise Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(!didPracticeGesture)
    }

    private var practiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PRACTICE AREA")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: disguise.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(disguise.accentColor)
                    .frame(width: 40, height: 40)
                    .background(disguise.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                Text(disguise.coverTitle)
                    .font(.headline)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.8) {
                        guard !didPracticeGesture else { return }
                        Haptics.pinCorrect()
                        onCompleted()
                        withAnimation(.snappy) {
                            didPracticeGesture = true
                        }
                    }
                    .accessibilityLabel("Practice unlock using \(disguise.coverTitle)")

                Spacer()

                if didPracticeGesture {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(didPracticeGesture ? "Gesture learned. Use the same hold on the utility title." : "Press and hold “\(disguise.coverTitle)” until you feel the confirmation.")
                .font(.callout)
                .foregroundStyle(didPracticeGesture ? .green : .secondary)
        }
        .padding(18)
        .background(Color.vaultSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
