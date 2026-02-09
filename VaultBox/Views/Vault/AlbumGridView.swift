import SwiftUI
import SwiftData

// MARK: - AlbumGridView

struct AlbumGridView: View {
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Query(sort: \Album.sortOrder) private var albums: [Album]
    @Query private var allItems: [VaultItem]
    @Environment(\.modelContext) private var modelContext

    @State private var showCreateAlert = false
    @State private var newAlbumName = ""
    @State private var albumToRename: Album?
    @State private var renameText = ""
    @State private var albumToDelete: Album?
    @State private var coverCache: [UUID: UIImage] = [:]

    private var visibleAlbums: [Album] {
        if isDecoyMode {
            return albums.filter { $0.isDecoy }
        } else {
            return albums.filter { !$0.isDecoy }
        }
    }

    private var visibleItems: [VaultItem] {
        if isDecoyMode {
            return allItems.filter { $0.album?.isDecoy == true }
        } else {
            return allItems.filter { $0.album?.isDecoy != true }
        }
    }

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.standardPadding),
        count: Constants.albumGridColumns
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                if visibleAlbums.isEmpty && visibleItems.isEmpty {
                    emptyState
                        .padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, spacing: Constants.standardPadding) {
                        // "All Items" always first
                        NavigationLink {
                            AlbumDetailView(album: nil, vaultService: vaultService)
                        } label: {
                            albumCard(name: "All Items", itemCount: visibleItems.count, albumID: nil)
                        }
                        .buttonStyle(.plain)

                        // User albums
                        ForEach(visibleAlbums) { album in
                            NavigationLink {
                                AlbumDetailView(album: album, vaultService: vaultService)
                            } label: {
                                albumCard(
                                    name: album.name,
                                    itemCount: album.items?.count ?? 0,
                                    albumID: album.id
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    renameText = album.name
                                    albumToRename = album
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    albumToDelete = album
                                } label: {
                                    Label("Delete Album", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(Constants.standardPadding)
                }
            }
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newAlbumName = ""
                        showCreateAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Album", isPresented: $showCreateAlert) {
                TextField("Album Name", text: $newAlbumName)
                Button("Cancel", role: .cancel) { }
                Button("Create") { createAlbum() }
            }
            .alert("Rename Album", isPresented: .init(
                get: { albumToRename != nil },
                set: { if !$0 { albumToRename = nil } }
            )) {
                TextField("Album Name", text: $renameText)
                Button("Cancel", role: .cancel) { albumToRename = nil }
                Button("Save") { renameAlbum() }
            }
            .confirmationDialog(
                "Delete Album?",
                isPresented: .init(
                    get: { albumToDelete != nil },
                    set: { if !$0 { albumToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Album Only", role: .destructive) {
                    deleteAlbum(deleteContents: false)
                }
                Button("Delete Album and Contents", role: .destructive) {
                    deleteAlbum(deleteContents: true)
                }
                Button("Cancel", role: .cancel) { albumToDelete = nil }
            } message: {
                Text("Items in this album will be moved to All Items, or deleted permanently.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "rectangle.stack",
            title: "No Albums",
            subtitle: "Tap + to create your first album"
        )
    }

    // MARK: - Album Card

    private func albumCard(name: String, itemCount: Int, albumID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let albumID, let image = coverCache[albumID] {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color.vaultAccent.opacity(0.3), Color.vaultAccent.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: name == "All Items" ? "photo.on.rectangle.angled" : "rectangle.stack")
                            .font(.title)
                            .foregroundStyle(Color.vaultAccent.opacity(0.5))
                    )
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))

            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.vaultTextPrimary)
                .lineLimit(1)

            Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
        }
        .task {
            if let albumID {
                await loadCover(for: albumID)
            }
        }
    }

    // MARK: - Actions

    private func loadCover(for albumID: UUID) async {
        guard coverCache[albumID] == nil else { return }
        guard let album = albums.first(where: { $0.id == albumID }) else { return }

        // Use explicit cover item, or first item in album
        let coverSource = album.coverItem ?? album.items?.first
        guard let source = coverSource else { return }
        guard let image = try? await vaultService.decryptThumbnail(for: source) else { return }
        coverCache[albumID] = image
    }

    private func createAlbum() {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let album = Album(name: name, sortOrder: albums.count)
        modelContext.insert(album)
        try? modelContext.save()
    }

    private func renameAlbum() {
        guard let album = albumToRename else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        album.name = name
        try? modelContext.save()
        albumToRename = nil
    }

    private func deleteAlbum(deleteContents: Bool) {
        guard let album = albumToDelete else { return }
        if deleteContents {
            if let items = album.items {
                Task {
                    try? await vaultService.deleteItems(items)
                }
            }
        } else {
            // Move items to "All Items" (nil album)
            if let items = album.items {
                for item in items {
                    item.album = nil
                }
            }
        }
        modelContext.delete(album)
        try? modelContext.save()
        albumToDelete = nil
    }
}

// MARK: - AlbumDetailView

struct AlbumDetailView: View {
    let album: Album?
    let vaultService: VaultService

    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    @State private var sortOrder: VaultSortOrder = .dateImported
    @State private var filter: VaultFilter = .all
    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var detailItem: VaultItem?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    private var title: String {
        album?.name ?? "All Items"
    }

    private var albumItems: [VaultItem] {
        if let album {
            return album.items ?? []
        }
        return allItems
    }

    private var displayedItems: [VaultItem] {
        var items = albumItems

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

    var body: some View {
        VStack(spacing: 0) {
            if displayedItems.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                        ForEach(displayedItems) { item in
                            thumbnailCell(for: item)
                                .onTapGesture {
                                    detailItem = item
                                }
                        }
                    }
                }

                Text("\(albumItems.count) \(albumItems.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        }
        .fullScreenCover(item: $detailItem) { item in
            let index = displayedItems.firstIndex(where: { $0.id == item.id }) ?? 0
            PhotoDetailView(
                items: displayedItems,
                initialIndex: index,
                vaultService: vaultService
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "photo.on.rectangle.angled",
            title: "No Items",
            subtitle: "Items added to this album will appear here"
        )
    }

    // MARK: - Thumbnail Cell

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

            if item.isFavorite {
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
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius))
        .task {
            await loadThumbnail(for: item)
        }
    }

    private func loadThumbnail(for item: VaultItem) async {
        guard thumbnailCache[item.id] == nil else { return }
        guard let image = try? await vaultService.decryptThumbnail(for: item) else { return }
        thumbnailCache[item.id] = image
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
