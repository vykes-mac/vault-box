import SwiftUI

struct AlbumCoverView: View {
    let name: String
    let itemCount: Int
    let coverImage: UIImage?
    let isAllItems: Bool

    init(name: String, itemCount: Int, coverImage: UIImage? = nil, isAllItems: Bool = false) {
        self.name = name
        self.itemCount = itemCount
        self.coverImage = coverImage
        self.isAllItems = isAllItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color.vaultAccent.opacity(0.3), Color.vaultAccent.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: isAllItems ? "photo.on.rectangle.angled" : "rectangle.stack")
                            .font(.title)
                            .foregroundStyle(Color.vaultAccent.opacity(0.5))
                    )
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))

            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.vaultTextPrimary)
                .lineLimit(1)

            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }
}
