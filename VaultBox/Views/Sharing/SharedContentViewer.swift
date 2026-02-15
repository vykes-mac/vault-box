import SwiftUI
import PDFKit

// MARK: - SharedContentViewer

struct SharedContentViewer: View {
    let shareID: String
    let keyBase64URL: String
    let sharingService: SharingService

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    @State private var decryptedImage: UIImage?
    @State private var tempFileURL: URL?
    @State private var mimeType: String = ""
    @State private var originalFilename: String = ""
    @State private var allowSave = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var savedToVault = false
    @State private var errorMessage: String?
    @StateObject private var captureMonitor = ScreenCaptureMonitor()

    private var isImage: Bool { mimeType.hasPrefix("image/") }
    private var isPDF: Bool { mimeType == "application/pdf" }
    private var hasContent: Bool { decryptedImage != nil || tempFileURL != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Decrypting shared file...")
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
                    imageContent(image: image)
                } else if let url = tempFileURL {
                    documentContent(url: url)
                }

                // Screenshot detection banner (only when saving is not allowed)
                if captureMonitor.screenshotDetected && !allowSave && hasContent {
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
            .navigationTitle("Shared File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if hasContent && allowSave {
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
            await loadSharedFile()
        }
        .onDisappear {
            cleanupTempFile()
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private func imageContent(image: UIImage) -> some View {
        if allowSave {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScreenshotProofView {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func documentContent(url: URL) -> some View {
        if isPDF {
            if allowSave {
                PDFViewRepresentable(url: url)
            } else {
                ScreenshotProofView {
                    PDFViewRepresentable(url: url)
                }
            }
        } else {
            // Other document types - show file icon and filename
            VStack(spacing: 16) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.7))
                Text(originalFilename)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("Preview not available for this file type.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func loadSharedFile() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await sharingService.receiveSharedFile(
                shareID: shareID,
                keyBase64URL: keyBase64URL
            )

            mimeType = result.mimeType
            originalFilename = result.originalFilename
            allowSave = result.allowSave

            if result.mimeType.hasPrefix("image/") {
                guard let image = UIImage(data: result.fileData) else {
                    errorMessage = "The shared data is not a valid image."
                    return
                }
                decryptedImage = image
            } else {
                // Write to temp file for PDF/document display and save
                let ext = (result.originalFilename as NSString).pathExtension
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID()).\(ext.isEmpty ? "dat" : ext)")
                try result.fileData.write(to: tempURL)
                tempFileURL = tempURL
            }
        } catch let error as SharingError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Failed to load the shared file. Please try again."
        }
    }

    private func saveToVault() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let encryptionService = EncryptionService()
            let vaultService = VaultService(
                encryptionService: encryptionService,
                modelContext: modelContext,
                hasPremiumAccess: { purchaseService.isPremium }
            )

            if let image = decryptedImage {
                // Save as photo
                guard let imageData = image.jpegData(compressionQuality: 1.0) else {
                    errorMessage = "Failed to prepare the image for saving."
                    return
                }
                let item = try await vaultService.importPhotoData(
                    imageData,
                    filename: originalFilename.isEmpty ? "Shared Photo" : originalFilename,
                    album: nil
                )
                vaultService.queueVisionAnalysis(for: [item])
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
            } else if let url = tempFileURL {
                // Save as document
                let item = try await vaultService.importDocument(at: url, album: nil)
                vaultService.queueVisionAnalysis(for: [item])
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
            } else {
                errorMessage = "No content to save."
                return
            }

            savedToVault = true
            Haptics.purchaseComplete()
        } catch {
            errorMessage = "Failed to save to vault. Please try again."
        }
    }

    private func cleanupTempFile() {
        guard let url = tempFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        tempFileURL = nil
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
