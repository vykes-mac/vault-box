import SwiftUI
import UIKit

/// Shown to lifetime owners whose old subscription is still set to renew. Apple never
/// cancels it on their behalf, and a surprise renewal after paying for lifetime is a
/// refund request and a 1-star review.
struct LifetimeSubscriptionBanner: View {
    /// Apple's subscription list is the only place the renewal can be turned off.
    private static let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("You're still subscribed")
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.vaultPremium)
            }
            .foregroundStyle(Color.vaultTextPrimary)

            Text("You own Lifetime Premium, but your VaultBox subscription will still renew. Cancel it so you aren't charged again.")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UIApplication.shared.open(Self.subscriptionsURL)
            } label: {
                Text("Cancel Subscription")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vaultAccent)
        }
        .padding(.vertical, 4)
    }
}
