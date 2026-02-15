import SwiftUI

struct SuggestionChipView: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.vaultAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.vaultAccent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.vaultAccent.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
