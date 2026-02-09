import SwiftUI
import PhotosUI
import StoreKit
import SwiftData

// MARK: - ImportView

struct ImportView: View {
    let vaultService: VaultService
    let album: Album?
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importProgress: Int = 0
    @State private var importTotal: Int = 0
    @State private var showDeletePrompt = false
    @State private var pendingAssetIdentifiers: [String] = []
    @State private var showPicker = true

    var body: some View {
        ZStack {
            if showPicker {
                PhotosPicker(
                    selection: $selectedItems,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Text("Select Photos")
                }
                .photosPickerStyle(.inline)
                .photosPickerDisabledCapabilities(.selectionActions)
                .onChange(of: selectedItems) { _, newValue in
                    if !newValue.isEmpty {
                        showPicker = false
                        startImport()
                    }
                }
            }

            if isImporting {
                importProgressOverlay
            }
        }
        .alert(
            "Delete \(pendingAssetIdentifiers.count) original\(pendingAssetIdentifiers.count == 1 ? "" : "s") from Camera Roll?",
            isPresented: $showDeletePrompt
        ) {
            Button("Delete", role: .destructive) {
                deleteCameraRollOriginals()
            }
            Button("Keep", role: .cancel) {
                onDismiss()
            }
        } message: {
            Text("The imported items are safely encrypted in your vault.")
        }
    }

    // MARK: - Progress Overlay

    private var importProgressOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Importing \(importTotal) item\(importTotal == 1 ? "" : "s")…")
                .font(.headline)
                .foregroundStyle(Color.vaultTextPrimary)

            ProgressView(value: Double(importProgress), total: Double(max(importTotal, 1)))
                .tint(Color.vaultAccent)
                .padding(.horizontal, 40)

            Text("\(importProgress) of \(importTotal)")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vaultBackground)
    }

    // MARK: - Import

    private func startImport() {
        isImporting = true
        importTotal = selectedItems.count
        importProgress = 0

        Task {
            // Convert PhotosPickerItems to PHPickerResults via loadTransferable
            // Since PhotosPicker doesn't give PHPickerResult directly,
            // we import item by item
            var importedItems: [VaultItem] = []
            let identifiers: [String] = []

            for (index, pickerItem) in selectedItems.enumerated() {
                do {
                    if let movie = try await pickerItem.loadTransferable(type: VideoTransferable.self) {
                        let item = try await vaultService.importDocument(at: movie.url, album: album)
                        // Re-type as video
                        item.type = .video
                        importedItems.append(item)
                    } else if let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                        let image = UIImage(data: imageData)
                        let pixelWidth = image.map { Int($0.size.width * $0.scale) }
                        let pixelHeight = image.map { Int($0.size.height * $0.scale) }

                        let item = try await importImageData(imageData, album: album)
                        item.pixelWidth = pixelWidth
                        item.pixelHeight = pixelHeight
                        importedItems.append(item)
                    }
                } catch {
                    // Skip failed items, continue with rest
                }

                importProgress = index + 1
            }

            isImporting = false

            // Track imports for rate prompt (F34)
            incrementImportCount(by: importedItems.count)

            if !identifiers.isEmpty {
                pendingAssetIdentifiers = identifiers
                showDeletePrompt = true
            } else {
                onDismiss()
            }
        }
    }

    private func importImageData(_ data: Data, album: Album?) async throws -> VaultItem {
        guard let image = UIImage(data: data) else {
            throw VaultError.importFailed
        }
        return try await vaultService.importFromCamera(image, album: album)
    }

    private func deleteCameraRollOriginals() {
        Task {
            try? await vaultService.deleteFromCameraRoll(localIdentifiers: pendingAssetIdentifiers)
            onDismiss()
        }
    }

    private func incrementImportCount(by count: Int) {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else { return }
        settings.importCount += count
        try? modelContext.save()

        if settings.importCount >= Constants.ratePromptImportThreshold {
            // Only prompt once
            if settings.importCount - count < Constants.ratePromptImportThreshold {
                if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return Self(url: tempURL)
        }
    }
}
