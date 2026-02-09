import SwiftUI

struct PremiumBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.vaultPremium)
            .clipShape(Capsule())
    }
}
