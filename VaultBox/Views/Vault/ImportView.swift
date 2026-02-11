import SwiftUI
import PhotosUI
import StoreKit
import SwiftData
import UIKit
import UniformTypeIdentifiers

// MARK: - ImportView

struct ImportView: View {
    let vaultService: VaultService
    let album: Album?
    let isDecoyMode: Bool
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showPicker = true
    @State private var isImporting = false
    @State private var importProgress: Int = 0
    @State private var importTotal: Int = 0
    @State private var showDeletePrompt = false
    @State private var pendingAssetIdentifiers: [String] = []
    @State private var showDeletePermissionAlert = false
    @State private var showErrorAlert = false
    @State private var errorAlertTitle = "Couldn't Delete Originals"
    @State private var errorAlertMessage = "VaultBox couldn't delete one or more originals. Your imported items are still safe in the vault."
    @State private var pendingDeletePromptAfterError = false
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            if showPicker {
                VStack(spacing: 12) {
                    Text("VaultBox imports only what you select. Originals stay in Photos unless you choose Delete after import.")
                        .font(.footnote)
                        .foregroundStyle(Color.vaultTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    PhotosPicker(
                        selection: $selectedItems,
                        matching: .any(of: [.images, .videos]),
                        preferredItemEncoding: .current,
                        photoLibrary: .shared()
                    ) {
                        Text("Select Photos")
                    }
                    .photosPickerStyle(.inline)
                    .photosPickerDisabledCapabilities(.selectionActions)
                    .onChange(of: selectedItems) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        showPicker = false
                        startImport()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if isImporting {
                importProgressOverlay
            }
        }
        .background(Color.vaultBackground.ignoresSafeArea())
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
        .alert(errorAlertTitle, isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                if pendingDeletePromptAfterError {
                    pendingDeletePromptAfterError = false
                    showDeletePrompt = true
                } else {
                    onDismiss()
                }
            }
        } message: {
            Text(errorAlertMessage)
        }
        .alert("Photos Access Needed", isPresented: $showDeletePermissionAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
                onDismiss()
            }
            Button("Keep", role: .cancel) {
                onDismiss()
            }
        } message: {
            Text("VaultBox needs Photos access to delete originals. You can keep originals or allow access in Settings.")
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
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

        Task { @MainActor in
            var importedItems: [VaultItem] = []
            var identifiers: [String] = []
            var hitFreeLimit = false
            var tooLargeMessage: String?

            for (index, pickerItem) in selectedItems.enumerated() {
                var didImport = false

                do {
                    let supportsImage = pickerItem.supportedContentTypes.contains { $0.conforms(to: .image) }
                    let supportsVideo = pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }

                    // Prefer image bytes first so Live Photos import as photos (eligible for vision tags).
                    if supportsImage,
                       let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                        let item = try await vaultService.importPhotoData(
                            imageData,
                            filename: nil,
                            album: album,
                            isDecoyMode: isDecoyMode
                        )
                        importedItems.append(item)
                        didImport = true
                    } else if supportsVideo,
                              let movie = try await pickerItem.loadTransferable(type: VideoTransferable.self) {
                        defer { try? FileManager.default.removeItem(at: movie.url) }
                        let item = try await vaultService.importVideo(
                            at: movie.url,
                            filename: movie.filename,
                            album: album,
                            isDecoyMode: isDecoyMode
                        )
                        importedItems.append(item)
                        didImport = true
                    } else if let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                        let item = try await vaultService.importPhotoData(
                            imageData,
                            filename: nil,
                            album: album,
                            isDecoyMode: isDecoyMode
                        )
                        importedItems.append(item)
                        didImport = true
                    } else if let movie = try await pickerItem.loadTransferable(type: VideoTransferable.self) {
                        defer { try? FileManager.default.removeItem(at: movie.url) }
                        let item = try await vaultService.importVideo(
                            at: movie.url,
                            filename: movie.filename,
                            album: album,
                            isDecoyMode: isDecoyMode
                        )
                        importedItems.append(item)
                        didImport = true
                    }
                } catch {
                    if let vaultError = error as? VaultError, case .freeLimitReached = vaultError {
                        hitFreeLimit = true
                        break
                    }
                    if let vaultError = error as? VaultError,
                       case .videoTooLarge = vaultError {
                        tooLargeMessage = vaultError.errorDescription
                    }
                    // Skip failed items and continue with the remainder.
                }

                if didImport, let itemIdentifier = pickerItem.itemIdentifier {
                    identifiers.append(itemIdentifier)
                }

                importProgress = index + 1
            }

            isImporting = false
            incrementImportCount(by: importedItems.count)

            // Queue vision analysis in background (does not block UI)
            if !importedItems.isEmpty {
                vaultService.queueVisionAnalysis(for: importedItems)
            }

            if hitFreeLimit && identifiers.isEmpty {
                showPaywall = true
                return
            }

            if let tooLargeMessage {
                errorAlertTitle = "Video Too Large"
                errorAlertMessage = tooLargeMessage
                pendingDeletePromptAfterError = !identifiers.isEmpty
                pendingAssetIdentifiers = identifiers
                showErrorAlert = true
                return
            }

            if !identifiers.isEmpty {
                pendingAssetIdentifiers = identifiers
                showDeletePrompt = true
            } else {
                onDismiss()
            }
        }
    }

    private func deleteCameraRollOriginals() {
        guard !pendingAssetIdentifiers.isEmpty else {
            onDismiss()
            return
        }

        Task { @MainActor in
            do {
                try await vaultService.deleteFromCameraRoll(localIdentifiers: pendingAssetIdentifiers)
                onDismiss()
            } catch {
                if let vaultError = error as? VaultError, case .photosPermissionDenied = vaultError {
                    showDeletePermissionAlert = true
                } else {
                    errorAlertTitle = "Couldn't Delete Originals"
                    errorAlertMessage = (error as? LocalizedError)?.errorDescription ??
                        "VaultBox couldn't delete one or more originals. You can remove them manually in Photos."
                    showErrorAlert = true
                }
            }
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
    let filename: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return Self(url: tempURL, filename: received.file.lastPathComponent)
        }
    }
}
