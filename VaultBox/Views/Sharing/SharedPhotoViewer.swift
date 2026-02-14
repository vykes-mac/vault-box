import SwiftUI

// MARK: - SharedPhotoViewer

struct SharedPhotoViewer: View {
    let shareID: String
    let keyBase64URL: String
    let sharingService: SharingService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var decryptedImage: UIImage?
    @State private var allowSave = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var savedToVault = false
    @State private var errorMessage: String?
    @StateObject private var captureMonitor = ScreenCaptureMonitor()

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
                    if allowSave {
                        // Saving permitted — show image normally, no screenshot protection
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // View only — wrap in secure layer to block screenshots and recordings
                        ScreenshotProofView {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }

                // Screenshot detection banner (only when saving is not allowed)
                if captureMonitor.screenshotDetected && !allowSave {
                    VStack {
                        Spacer()
                        Label("Screenshot captured blank", systemImage: "eye.slash")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial.opacity(0.8))
                            .clipShape(Capsule())
                            .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: captureMonitor.screenshotDetected)
            .navigationTitle("Shared Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if decryptedImage != nil && allowSave {
                    ToolbarItem(placement: .topBarTrailing) {
                        if savedToVault {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Button {
                                Task { await saveToVault() }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundStyle(.white)
                            }
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
            let result = try await sharingService.receiveSharedPhoto(
                shareID: shareID,
                keyBase64URL: keyBase64URL
            )
            guard let image = UIImage(data: result.imageData) else {
                errorMessage = "The shared data is not a valid image."
                return
            }
            decryptedImage = image
            allowSave = result.allowSave
        } catch let error as SharingError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load the shared photo. Please try again."
        }
    }

    private func saveToVault() async {
        guard let image = decryptedImage,
              let jpegData = image.jpegData(compressionQuality: 1.0) else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let encryptionService = EncryptionService()
            let vaultService = VaultService(
                encryptionService: encryptionService,
                modelContext: modelContext
            )

            // 1. Import into vault (encrypts, generates thumbnail, creates VaultItem)
            let item = try await vaultService.importPhotoData(
                jpegData,
                filename: "Shared Photo",
                album: nil
            )

            // 2. Queue vision analysis (scene classification, object detection, smart tags)
            vaultService.queueVisionAnalysis(for: [item])

            // 3. Queue search indexing (embeddings for Ask My Vault)
            if let searchIndexService = try? await SearchIndexService.open() {
                let embeddingService = EmbeddingService()
                let ingestionService = IngestionService(
                    encryptionService: encryptionService,
                    searchIndexService: searchIndexService,
                    embeddingService: embeddingService
                )
                vaultService.configureSearchIndex(
                    ingestionService: ingestionService,
                    indexingProgress: IndexingProgress()
                )
                vaultService.queueSearchIndexing(for: [item])
            }

            savedToVault = true
            Haptics.purchaseComplete()
        } catch {
            errorMessage = "Failed to save to vault. Please try again."
        }
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
