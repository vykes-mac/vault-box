import SwiftUI
import RevenueCatUI

struct VaultBoxPaywallView: View {
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let offering = purchaseService.currentOffering {
                RevenueCatUI.PaywallView(
                    offering: offering,
                    displayCloseButton: true
                )
                .onPurchaseCompleted { _ in
                    Haptics.purchaseComplete()
                    purchaseService.isPremium = true
                    dismiss()
                }
                .onRestoreCompleted { _ in
                    Haptics.purchaseComplete()
                    purchaseService.isPremium = true
                    dismiss()
                }
                .onAppear {
                    #if DEBUG
                    print(
                        "[RevenueCat] Presenting paywall with offering '\(offering.identifier)' " +
                        "(explicit=\(purchaseService.isUsingExplicitOffering))"
                    )
                    #endif
                }
            } else {
                loadingStateView
            }
        }
        .task {
            await loadOfferingsIfNeeded()
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading subscription options...")
                .font(.headline)

            if let offeringsLoadError = purchaseService.offeringsLoadError {
                Text(offeringsLoadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Retry") {
                Task {
                    await loadOfferingsIfNeeded(force: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(purchaseService.isLoading)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private func loadOfferingsIfNeeded(force: Bool = false) async {
        if purchaseService.isLoading { return }
        if !force, purchaseService.currentOffering != nil { return }

        do {
            try await purchaseService.fetchOfferings()
        } catch {
            // Error is stored in PurchaseService.offeringsLoadError.
        }
    }
}
