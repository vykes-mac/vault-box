import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(Color.vaultTextSecondary)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.vaultTextPrimary)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
