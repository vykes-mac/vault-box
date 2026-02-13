import SwiftUI

// MARK: - SharedPhotoViewer

struct SharedPhotoViewer: View {
    let shareID: String
    let keyBase64URL: String
    let sharingService: SharingService

    @Environment(\.dismiss) private var dismiss

    @State private var decryptedImage: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Decrypting shared photo...")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: errorIcon)
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else if let image = decryptedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Shared Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if decryptedImage != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            saveToPhotos()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .task {
            await loadSharedPhoto()
        }
    }

    // MARK: - Actions

    private func loadSharedPhoto() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await sharingService.receiveSharedPhoto(
                shareID: shareID,
                keyBase64URL: keyBase64URL
            )
            guard let image = UIImage(data: data) else {
                errorMessage = "The shared data is not a valid image."
                return
            }
            decryptedImage = image
        } catch let error as SharingError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load the shared photo. Please try again."
        }
    }

    private func saveToPhotos() {
        guard let image = decryptedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        Haptics.purchaseComplete()
    }

    private var errorIcon: String {
        if errorMessage?.contains("expired") == true {
            return "clock.badge.xmark"
        } else if errorMessage?.contains("not found") == true || errorMessage?.contains("revoked") == true {
            return "link.badge.plus"
        }
        return "exclamationmark.triangle"
    }
}
