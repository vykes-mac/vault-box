import SwiftUI

struct AppIconPickerView: View {
    @Environment(PurchaseService.self) private var purchaseService

    private let iconService = AppIconService()
    @State private var availableIcons = [AppIconService.IconOption]()
    @State private var currentIcon: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPaywall = false

    var body: some View {
        List {
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

            if availableIcons.count <= 1 {
                Text("No alternate app icons are configured in this build.")
                    .font(.footnote)
                    .foregroundStyle(Color.vaultTextSecondary)
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
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
