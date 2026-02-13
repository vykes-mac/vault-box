import SwiftUI
import SwiftData

// MARK: - ShareConfigView

struct ShareConfigView: View {
    let item: VaultItem
    let vaultService: VaultService
    let sharingService: SharingService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDuration: ShareDuration = .twentyFourHours
    @State private var isSharing = false
    @State private var shareURL: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.vaultAccent)

                    Text("Share Securely")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("The recipient needs VaultBox installed to view the photo. The link expires automatically.")
                        .font(.callout)
                        .foregroundStyle(Color.vaultTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 16)

                // Duration picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Expires after")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(ShareDuration.allCases) { duration in
                        Button {
                            selectedDuration = duration
                        } label: {
                            HStack {
                                Image(systemName: iconForDuration(duration))
                                    .font(.title3)
                                    .frame(width: 30)

                                Text(duration.label)
                                    .font(.body)

                                Spacer()

                                if selectedDuration == duration {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.vaultAccent)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedDuration == duration
                                          ? Color.vaultAccent.opacity(0.1)
                                          : Color.vaultSurface)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                }

                Spacer()

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Share URL result + copy
                if let shareURL {
                    shareSuccessView(url: shareURL)
                } else {
                    // Share button
                    Button {
                        Task { await createShare() }
                    } label: {
                        HStack {
                            if isSharing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSharing ? "Encrypting & Uploading..." : "Create Share Link")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.vaultAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSharing)
                    .padding(.horizontal)
                }

                Spacer().frame(height: 8)
            }
            .navigationTitle("Share Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Share Success View

    private func shareSuccessView(url: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(Color.vaultSuccess)

            Text("Link created!")
                .font(.headline)

            Text("Expires in \(selectedDuration.label.lowercased())")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = url
                    Haptics.itemSelected()
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.vaultSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.vaultAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Actions

    @MainActor
    private func createShare() async {
        isSharing = true
        errorMessage = nil
        defer { isSharing = false }

        do {
            // Check iCloud availability
            guard await sharingService.isICloudAvailable() else {
                errorMessage = SharingError.iCloudUnavailable.errorDescription
                return
            }

            // Decrypt the full image
            let imageData: Data
            if item.type == .photo {
                let image = try await vaultService.decryptFullImage(for: item)
                guard let jpeg = image.jpegData(compressionQuality: 0.9) else {
                    errorMessage = "Failed to prepare the photo for sharing."
                    return
                }
                imageData = jpeg
            } else {
                errorMessage = "Only photos can be shared with time-limited links."
                return
            }

            // Create the share
            let result = try await sharingService.sharePhoto(
                imageData: imageData,
                duration: selectedDuration
            )

            // Save locally for tracking
            let sharedItem = SharedItem(
                cloudRecordName: result.cloudRecordName,
                vaultItemID: item.id,
                shareURL: result.shareURL,
                expiresAt: result.expiresAt,
                originalFilename: item.originalFilename
            )
            modelContext.insert(sharedItem)
            try? modelContext.save()

            shareURL = result.shareURL
            Haptics.purchaseComplete()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Sharing failed. Please try again."
        }
    }

    // MARK: - Helpers

    private func iconForDuration(_ duration: ShareDuration) -> String {
        switch duration {
        case .oneHour: "clock"
        case .twentyFourHours: "clock.badge"
        case .sevenDays: "calendar.circle"
        }
    }
}
