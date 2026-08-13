import SwiftUI

struct AppIconPickerView: View {
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AppPrivacyShield.self) private var privacyShield
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
            VaultBoxPaywallView(placement: .settings)
        }
        .sheet(item: $unlockGuideDisguise) { disguise in
            DisguiseUnlockGuideView(disguise: disguise) {
                hasLearnedPrivateUnlock = true
            }
        }
    }

    private func selectIcon(_ iconID: String?) {
        if iconID != nil, !availableIcons.contains(where: { $0.id == iconID }) {
            errorMessage = String(localized: "This app icon is not available in the current build.")
            showError = true
            return
        }
        // Returning to the default icon is always free. Premium buys a disguise; it must
        // never be what stands between a lapsed user and taking one off their own Home
        // Screen — that would trap them in the opposite of the problem they paid to fix.
        if iconID != nil, purchaseService.isPremiumRequired(for: .fakeAppIcon) {
            showPaywall = true
            return
        }
        Task {
            privacyShield.beginIconChange()
            defer { privacyShield.completeIconChangeRequest() }

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
