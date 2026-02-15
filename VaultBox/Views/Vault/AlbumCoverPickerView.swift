import SwiftUI
import PhotosUI
import SwiftData

// MARK: - AlbumCoverPickerView

struct AlbumCoverPickerView: View {
    let album: Album
    let vaultService: VaultService
    var onCoverChanged: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    @State private var showVaultItemPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images
                    ) {
                        Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isProcessing)

                    Button {
                        showVaultItemPicker = true
                    } label: {
                        Label("Choose from Vault", systemImage: "lock.rectangle.stack")
                    }
                    .disabled(isProcessing)
                } header: {
                    Text("Set Album Cover")
                }

                if album.customCoverImageData != nil || album.coverItem != nil {
                    Section {
                        Button(role: .destructive) {
                            removeCover()
                        } label: {
                            Label("Remove Custom Cover", systemImage: "xmark.circle")
                        }
                        .disabled(isProcessing)
                    }
                }

                if isProcessing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Setting cover...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Album Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                if let newValue {
                    Task {
                        await setCoverFromPhotos(newValue)
                    }
                }
            }
            .sheet(isPresented: $showVaultItemPicker) {
                VaultItemPickerView(
                    vaultService: vaultService,
                    items: allItems.filter { $0.type == .photo }
                ) { selectedItem in
                    setCoverFromVaultItem(selectedItem)
                }
            }
        }
    }

    // MARK: - Actions

    private func setCoverFromPhotos(_ pickerItem: PhotosPickerItem) async {
        isProcessing = true
        errorMessage = nil
        defer {
            isProcessing = false
            selectedPhotoItem = nil
        }

        do {
            guard let imageData = try await pickerItem.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't load the selected photo."
                return
            }
            let encryptedData = try await vaultService.encryptAlbumCoverImage(imageData)
            album.customCoverImageData = encryptedData
            album.coverItem = nil
            try modelContext.save()
            onCoverChanged?()
            dismiss()
        } catch {
            errorMessage = "Failed to set cover. Please try again."
        }
    }

    private func setCoverFromVaultItem(_ item: VaultItem) {
        album.coverItem = item
        album.customCoverImageData = nil
        try? modelContext.save()
        onCoverChanged?()
        dismiss()
    }

    private func removeCover() {
        album.customCoverImageData = nil
        album.coverItem = nil
        try? modelContext.save()
        onCoverChanged?()
        dismiss()
    }
}

// MARK: - VaultItemPickerView

struct VaultItemPickerView: View {
    let vaultService: VaultService
    let items: [VaultItem]
    let onSelect: (VaultItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var thumbnailCache: [UUID: UIImage] = [:]

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "photo.on.rectangle.angled",
                        title: "No Photos",
                        subtitle: "Import photos to use as album covers"
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                            ForEach(items) { item in
                                thumbnailCell(for: item)
                                    .onTapGesture {
                                        Haptics.itemSelected()
                                        onSelect(item)
                                        dismiss()
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func thumbnailCell(for item: VaultItem) -> some View {
        ZStack {
            if let image = thumbnailCache[item.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.vaultSurface
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius))
        .task {
            guard thumbnailCache[item.id] == nil else { return }
            guard let image = try? await vaultService.decryptThumbnail(for: item) else { return }
            thumbnailCache[item.id] = image
        }
    }
}
