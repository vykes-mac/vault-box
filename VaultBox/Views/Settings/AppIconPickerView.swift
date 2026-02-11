import SwiftUI

struct AppIconPickerView: View {
    @Environment(PurchaseService.self) private var purchaseService

    @State private var iconService = AppIconService()
    @State private var currentIcon: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPaywall = false

    var body: some View {
        List {
            ForEach(AppIconService.availableIcons, id: \.displayName) { icon in
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
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
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
        if purchaseService.isPremiumRequired(for: .fakeAppIcon) {
            showPaywall = true
            return
        }
        Task {
            do {
                try await iconService.setIcon(iconID)
                currentIcon = iconID
            } catch {
                errorMessage = "Couldn't change the app icon. Please try again."
                showError = true
            }
        }
    }
}
