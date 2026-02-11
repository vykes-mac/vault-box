import SwiftUI
import PhotosUI
import StoreKit
import SwiftData
import UIKit

// MARK: - ImportView

struct ImportView: View {
    let vaultService: VaultService
    let album: Album?
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
                onDismiss()
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

            for (index, pickerItem) in selectedItems.enumerated() {
                var didImport = false

                do {
                    // Prefer image bytes first so Live Photos import as photos (eligible for vision tags).
                    if let imageData = try await pickerItem.loadTransferable(type: Data.self) {
                        let item = try await vaultService.importPhotoData(
                            imageData,
                            filename: nil,
                            album: album
                        )
                        importedItems.append(item)
                        didImport = true
                    } else if let movie = try await pickerItem.loadTransferable(type: VideoTransferable.self) {
                        let item = try await vaultService.importDocument(at: movie.url, album: album)
                        item.type = .video
                        importedItems.append(item)
                        didImport = true
                    }
                } catch {
                    if let vaultError = error as? VaultError, case .freeLimitReached = vaultError {
                        hitFreeLimit = true
                        break
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
