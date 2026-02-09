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

    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    @State private var sortOrder: VaultSortOrder = .dateImported
    @State private var filter: VaultFilter = .all
    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showImporter = false
    @State private var detailItem: VaultItem?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    private var displayedItems: [VaultItem] {
        var items = allItems

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

    private var itemCountText: String {
        let count = allItems.count
        let limit = Constants.freeItemLimit
        return "\(count) of \(limit) items"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if allItems.isEmpty {
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
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(Color.vaultTextSecondary)

            Text("No Items Yet")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.vaultTextPrimary)

            Text("Tap + to add your first photo")
                .font(.body)
                .foregroundStyle(Color.vaultTextSecondary)
        }
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
                showImporter = true
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
            isSelectionMode = true
            selectedItems.insert(item.id)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
