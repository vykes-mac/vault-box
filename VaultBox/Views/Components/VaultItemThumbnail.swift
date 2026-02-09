import SwiftUI

struct VaultItemThumbnail: View {
    let image: UIImage?
    let isFavorite: Bool
    let isVideo: Bool
    var durationSeconds: Double?
    var isSelected: Bool = false
    var selectionMode: Bool = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.vaultSurface
            }

            // Favorite badge (top-right)
            if isFavorite && !selectionMode {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(6)
                    }
                    Spacer()
                }
            }

            // Video duration badge (bottom-right)
            if isVideo, let duration = durationSeconds {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(duration))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(4)
                    }
                }
            }

            // Selection checkmark (top-left)
            if selectionMode {
                VStack {
                    HStack {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white, Color.vaultAccent)
                                .font(.title3)
                        } else {
                            Circle()
                                .strokeBorder(.white, lineWidth: 1.5)
                                .frame(width: 24, height: 24)
                                .shadow(color: .black.opacity(0.3), radius: 1)
                        }
                        Spacer()
                    }
                    .padding(6)
                    Spacer()
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
