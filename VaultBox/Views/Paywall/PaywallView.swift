import SwiftUI
import RevenueCatUI

struct VaultBoxPaywallView: View {
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView(
            displayCloseButton: true
        )
        .onPurchaseCompleted { _ in
            purchaseService.isPremium = true
            dismiss()
        }
        .onRestoreCompleted { _ in
            purchaseService.isPremium = true
            dismiss()
        }
    }
}
