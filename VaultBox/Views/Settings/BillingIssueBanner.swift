import SwiftUI
import UIKit

/// Shown while Apple is retrying a failed subscription charge. Premium access is
/// still granted during this window, so the banner is the only signal the customer
/// gets that it is about to be revoked.
struct BillingIssueBanner: View {
    let expirationDate: Date?
    var onManageSubscription: (() -> Void)?

    /// Apple's billing page is the only place a payment method can actually be
    /// fixed — Customer Center cannot do it.
    private static let billingURL = URL(string: "https://apps.apple.com/account/billing")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Payment problem")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.vaultDestructive)
            }
            .foregroundStyle(Color.vaultTextPrimary)

            Text(message)
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    UIApplication.shared.open(Self.billingURL)
                } label: {
                    Text("Update Payment Method")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.vaultAccent)

                if let onManageSubscription {
                    Button(action: onManageSubscription) {
                        Text("Manage")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var message: String {
        guard let expirationDate else {
            return String(
                localized: "We couldn't renew your VaultBox subscription. Update your payment method to keep premium features."
            )
        }

        return String(
            format: String(
                localized: "We couldn't renew your VaultBox subscription. Update your payment method by %@ to keep premium features."
            ),
            locale: Locale.current,
            expirationDate.formatted(date: .abbreviated, time: .shortened)
        )
    }
}
