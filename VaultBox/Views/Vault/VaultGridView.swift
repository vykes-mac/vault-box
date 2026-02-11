import SwiftUI
import SwiftData

// MARK: - Sort & Filter

enum VaultSortOrder: String, CaseIterable {
    case dateImported = "Date Imported"
    case dateCreated = "Date Created"
    case fileSize = "File Size"
}

enum VaultFilter: String, CaseIterable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    case favorites = "Favorites"
}

// MARK: - VaultGridView

struct VaultGridView: View {
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    @State private var sortOrder: VaultSortOrder = .dateImported
    @State private var filter: VaultFilter = .all
    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showImporter = false
    @State private var detailItem: VaultItem?
    @State private var showDeleteConfirm = false
    @State private var showAlbumPicker = false
    @State private var showPaywall = false

    @Query(sort: \Album.sortOrder) private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    private var displayedItems: [VaultItem] {
        var items = allItems

        // Decoy mode filtering: show only items in decoy albums
        if isDecoyMode {
            items = items.filter { $0.album?.isDecoy == true }
        } else {
            items = items.filter { $0.album?.isDecoy != true }
        }

        switch filter {
        case .all: break
        case .photos: items = items.filter { $0.type == .photo }
        case .videos: items = items.filter { $0.type == .video }
        case .favorites: items = items.filter { $0.isFavorite }
        }

        switch sortOrder {
        case .dateImported:
            items.sort { $0.importedAt > $1.importedAt }
        case .dateCreated:
            items.sort { $0.createdAt > $1.createdAt }
        case .fileSize:
            items.sort { $0.fileSize > $1.fileSize }
        }

        return items
    }

    private var filteredItems: [VaultItem] {
        if isDecoyMode {
            return allItems.filter { $0.album?.isDecoy == true }
        } else {
            return allItems.filter { $0.album?.isDecoy != true }
        }
    }

    private var itemCountText: String {
        let count = filteredItems.count
        if purchaseService.isPremium {
            return "\(count) item\(count == 1 ? "" : "s")"
        }
        return "\(count) of \(Constants.freeItemLimit) items"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if filteredItems.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    gridContent
                    itemCountBar
                }
            }
            .navigationTitle("Vault")
            .toolbar { toolbarContent }
            .fullScreenCover(item: $detailItem) { item in
                let index = displayedItems.firstIndex(where: { $0.id == item.id }) ?? 0
                PhotoDetailView(
                    items: displayedItems,
                    initialIndex: index,
                    vaultService: vaultService
                )
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectionMode && !selectedItems.isEmpty {
                    selectionToolbar
                }
            }
            .confirmationDialog(
                "Delete \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    batchDelete()
                }
            } message: {
                Text("These items will be permanently deleted from your vault.")
            }
            .sheet(isPresented: $showAlbumPicker) {
                albumPickerSheet
            }
            .sheet(isPresented: $showImporter) {
                ImportView(
                    vaultService: vaultService,
                    album: nil,
                    onDismiss: { showImporter = false }
                )
            }
            .sheet(isPresented: $showPaywall) {
                VaultBoxPaywallView()
            }
        }
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        HStack {
            Button {
                showAlbumPicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "folder")
                    Text("Move").font(.caption2)
                }
            }

            Spacer()

            Button {
                batchFavorite()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "heart")
                    Text("Favorite").font(.caption2)
                }
            }

            Spacer()

            Button {
                showDeleteConfirm = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete").font(.caption2)
                }
                .foregroundStyle(Color.vaultDestructive)
            }
        }
        .foregroundStyle(Color.vaultAccent)
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Album Picker

    private var albumPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(albums.filter { !$0.isDecoy }) { album in
                    Button {
                        batchMoveToAlbum(album)
                        showAlbumPicker = false
                    } label: {
                        Label(album.name, systemImage: "folder")
                    }
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showAlbumPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "photo.on.rectangle.angled",
            title: "No Items Yet",
            subtitle: "Tap + to add your first photo"
        )
    }

    // MARK: - Grid

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                ForEach(displayedItems) { item in
                    thumbnailCell(for: item)
                        .onTapGesture { handleTap(item) }
                        .onLongPressGesture { enterSelectionMode(selecting: item) }
                }
            }
        }
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(for item: VaultItem) -> some View {
        ZStack {
            // Thumbnail image
            if let image = thumbnailCache[item.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.vaultSurface
            }

            // Favorite badge (top-right)
            if item.isFavorite && !isSelectionMode {
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
            if item.type == .video, let duration = item.durationSeconds {
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
            if isSelectionMode {
                VStack {
                    HStack {
                        if selectedItems.contains(item.id) {
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
        .task {
            await loadThumbnail(for: item)
        }
    }

    // MARK: - Item Count Bar

    private var itemCountBar: some View {
        Text(itemCountText)
            .font(.caption)
            .foregroundStyle(Color.vaultTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation {
                    isSelectionMode.toggle()
                    if !isSelectionMode {
                        selectedItems.removeAll()
                    }
                }
            } label: {
                Text(isSelectionMode ? "Cancel" : "Select")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort By", selection: $sortOrder) {
                    ForEach(VaultSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }

                Picker("Filter", selection: $filter) {
                    ForEach(VaultFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if purchaseService.isPremiumRequired(for: .unlimitedItems, itemCount: allItems.count) {
                    showPaywall = true
                } else {
                    showImporter = true
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    // MARK: - Actions

    private func loadThumbnail(for item: VaultItem) async {
        guard thumbnailCache[item.id] == nil else { return }
        guard let image = try? await vaultService.decryptThumbnail(for: item) else { return }
        thumbnailCache[item.id] = image
    }

    private func handleTap(_ item: VaultItem) {
        if isSelectionMode {
            if selectedItems.contains(item.id) {
                selectedItems.remove(item.id)
            } else {
                selectedItems.insert(item.id)
            }
        } else {
            detailItem = item
        }
    }

    private func enterSelectionMode(selecting item: VaultItem) {
        if !isSelectionMode {
            Haptics.itemSelected()
            isSelectionMode = true
            selectedItems.insert(item.id)
        }
    }

    private func selectedVaultItems() -> [VaultItem] {
        allItems.filter { selectedItems.contains($0.id) }
    }

    private func batchDelete() {
        Haptics.deleteConfirmed()
        let items = selectedVaultItems()
        Task {
            try? await vaultService.deleteItems(items)
            selectedItems.removeAll()
            isSelectionMode = false
        }
    }

    private func batchFavorite() {
        let items = selectedVaultItems()
        Task {
            for item in items {
                await vaultService.toggleFavorite(item)
            }
            selectedItems.removeAll()
            isSelectionMode = false
        }
    }

    private func batchMoveToAlbum(_ album: Album) {
        let items = selectedVaultItems()
        Task {
            try? await vaultService.moveItems(items, to: album)
            selectedItems.removeAll()
            isSelectionMode = false
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
