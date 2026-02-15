import SwiftUI
import SwiftData
import UIKit

// MARK: - Smart Album Type

enum SmartAlbumType: String, CaseIterable, Identifiable {
    case people = "People"
    case documents = "Documents"
    case screenshots = "Screenshots"
    case qrCodes = "QR Codes"
    case animals = "Animals"
    case plants = "Plants"
    case buildings = "Buildings"
    case landmarks = "Landmarks"
    case food = "Food"
    case vehicles = "Vehicles"
    case nature = "Nature"
    case beach = "Beach"
    case sunset = "Sunset"
    case sports = "Sports"
    case night = "Night"
    case water = "Water"
    case celebration = "Celebration"

    var id: String { rawValue }

    var tag: String {
        switch self {
        case .people: "people"
        case .documents: "document"
        case .screenshots: "screenshot"
        case .qrCodes: "qrcode"
        case .animals: "animals"
        case .plants: "plants"
        case .buildings: "buildings"
        case .landmarks: "landmarks"
        case .food: "food"
        case .vehicles: "vehicles"
        case .nature: "nature"
        case .beach: "beach"
        case .sunset: "sunset"
        case .sports: "sports"
        case .night: "night"
        case .water: "water"
        case .celebration: "celebration"
        }
    }

    var systemImage: String {
        switch self {
        case .people: "person.2.fill"
        case .documents: "doc.text.fill"
        case .screenshots: "rectangle.dashed"
        case .qrCodes: "qrcode"
        case .animals: "pawprint.fill"
        case .plants: "leaf.fill"
        case .buildings: "building.2.fill"
        case .landmarks: "building.columns.fill"
        case .food: "fork.knife"
        case .vehicles: "car.fill"
        case .nature: "mountain.2.fill"
        case .beach: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .sports: "figure.run"
        case .night: "moon.stars.fill"
        case .water: "drop.fill"
        case .celebration: "sparkles"
        }
    }
}

// MARK: - AlbumGridView

struct AlbumGridView: View {
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Query(sort: \Album.sortOrder) private var albums: [Album]
    @Query private var allItems: [VaultItem]
    @Environment(\.modelContext) private var modelContext

    @Environment(PurchaseService.self) private var purchaseService

    @State private var showCreateAlert = false
    @State private var newAlbumName = ""
    @State private var albumToRename: Album?
    @State private var renameText = ""
    @State private var albumToDelete: Album?
    @State private var coverCache: [UUID: UIImage] = [:]
    @State private var albumForCoverPicker: Album?
    @State private var showPaywall = false
    @State private var coverRefreshToken = 0

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

    private var smartAlbumsWithCounts: [(type: SmartAlbumType, count: Int)] {
        SmartAlbumType.allCases.compactMap { smartAlbum in
            let tag = smartAlbum.tag
            let count = visibleItems.filter { $0.smartTags.contains(tag) }.count
            return count > 0 ? (type: smartAlbum, count: count) : nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if visibleAlbums.isEmpty && visibleItems.isEmpty && smartAlbumsWithCounts.isEmpty {
                    emptyState
                        .padding(.top, 120)
                } else {
                    VStack(alignment: .leading, spacing: Constants.standardPadding) {
                        // Smart Albums horizontal row
                        if !smartAlbumsWithCounts.isEmpty {
                            smartAlbumsRow
                        }

                        // Regular albums grid
                        albumsGrid
                    }
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
            .sheet(item: $albumForCoverPicker) { album in
                AlbumCoverPickerView(
                    album: album,
                    vaultService: vaultService
                ) {
                    // Invalidate cache and bump token to re-trigger .task(id:)
                    coverCache[album.id] = nil
                    coverRefreshToken += 1
                }
            }
            .sheet(isPresented: $showPaywall) {
                VaultBoxPaywallView()
            }
        }
    }

    // MARK: - Smart Albums Row

    private var smartAlbumsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Albums")
                .font(.headline)
                .padding(.horizontal, Constants.standardPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(smartAlbumsWithCounts, id: \.type) { entry in
                        NavigationLink {
                            SmartAlbumDetailView(
                                smartAlbumType: entry.type,
                                vaultService: vaultService,
                                isDecoyMode: isDecoyMode
                            )
                        } label: {
                            smartAlbumCard(type: entry.type, count: entry.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Constants.standardPadding)
            }
        }
        .padding(.top, 8)
    }

    private func smartAlbumCard(type: SmartAlbumType, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                    .fill(Color.vaultAccent.opacity(0.15))
                    .frame(width: 120, height: 90)
                Image(systemName: type.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.vaultAccent)
            }

            Text(type.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.vaultTextPrimary)
                .lineLimit(1)

            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(Color.vaultTextSecondary)
        }
        .frame(width: 120)
    }

    // MARK: - Albums Grid

    private var albumsGrid: some View {
        LazyVGrid(columns: columns, spacing: Constants.standardPadding) {
            // "All Items" always first
            NavigationLink {
                AlbumDetailView(album: nil, vaultService: vaultService, isDecoyMode: isDecoyMode)
            } label: {
                albumCard(name: "All Items", itemCount: visibleItems.count, albumID: nil)
            }
            .buttonStyle(.plain)

            // User albums
            ForEach(visibleAlbums) { album in
                NavigationLink {
                    AlbumDetailView(album: album, vaultService: vaultService, isDecoyMode: isDecoyMode)
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

                    Button {
                        if purchaseService.isPremiumRequired(for: .customAlbumCovers) {
                            showPaywall = true
                        } else {
                            albumForCoverPicker = album
                        }
                    } label: {
                        Label("Set Cover", systemImage: "photo.on.rectangle")
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
        .task(id: coverRefreshToken) {
            if let albumID {
                await loadCover(for: albumID)
            }
        }
    }

    // MARK: - Actions

    private func loadCover(for albumID: UUID) async {
        guard coverCache[albumID] == nil else { return }
        guard let album = albums.first(where: { $0.id == albumID }) else { return }

        // Priority: custom cover image > explicit cover item > first item in album
        if let customData = album.customCoverImageData,
           let image = try? await vaultService.decryptAlbumCoverImage(customData) {
            coverCache[albumID] = image
            return
        }

        let coverSource = album.coverItem ?? album.items?.first
        guard let source = coverSource else { return }
        guard let image = try? await vaultService.decryptThumbnail(for: source) else { return }
        coverCache[albumID] = image
    }

    private func createAlbum() {
        let name = newAlbumName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let album = Album(name: name, sortOrder: albums.count, isDecoy: isDecoyMode)
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
        Haptics.deleteConfirmed()
        if deleteContents {
            if let items = album.items {
                Task {
                    try? await vaultService.deleteItems(items)
                }
            }
        } else {
            // In decoy mode, keep contents in decoy space to avoid cross-mode leakage.
            if let items = album.items {
                if isDecoyMode {
                    let fallbackAlbum = fallbackDecoyAlbum(excluding: album)
                    for item in items {
                        item.album = fallbackAlbum
                    }
                } else {
                    // Move items to "All Items" (nil album)
                    for item in items {
                        item.album = nil
                    }
                }
            }
        }
        modelContext.delete(album)
        try? modelContext.save()
        albumToDelete = nil
    }

    private func fallbackDecoyAlbum(excluding album: Album) -> Album {
        if let existing = albums.first(where: { $0.isDecoy && $0.id != album.id }) {
            return existing
        }
        let created = Album(name: "Personal", sortOrder: albums.count, isDecoy: true)
        modelContext.insert(created)
        return created
    }
}

// MARK: - AlbumDetailView

struct AlbumDetailView: View {
    let album: Album?
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]
    @Query(sort: \Album.sortOrder) private var albums: [Album]

    @State private var sortOrder: VaultSortOrder = .dateImported
    @State private var filter: VaultFilter = .all
    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var detailItem: VaultItem?
    @State private var documentDetailItem: VaultItem?

    // Selection state
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var showAlbumPicker = false

    // Drag-to-select state
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var isDragSelecting = false
    @State private var dragAdditive = true
    @State private var dragStartIndex: Int?
    @State private var dragCurrentIndex: Int?
    @State private var preDragSelection: Set<UUID> = []

    // Auto-scroll during drag-select
    @State private var scrollViewHeight: CGFloat = 0
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var autoScrollDirection: Int = 0

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    private var title: String {
        album?.name ?? "All Items"
    }

    private var albumItems: [VaultItem] {
        if let album {
            let items = album.items ?? []
            if isDecoyMode {
                return items.filter { $0.album?.isDecoy == true }
            }
            return items.filter { $0.album?.isDecoy != true }
        }
        if isDecoyMode {
            return allItems.filter { $0.album?.isDecoy == true }
        }
        return allItems.filter { $0.album?.isDecoy != true }
    }

    private var displayedItems: [VaultItem] {
        var items = albumItems

        switch filter {
        case .all: break
        case .photos: items = items.filter { $0.type == .photo }
        case .videos: items = items.filter { $0.type == .video }
        case .documents: items = items.filter { $0.type == .document }
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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                            ForEach(displayedItems) { item in
                                thumbnailCell(for: item)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: GridCellFramePreferenceKey.self,
                                                value: [item.id: geo.frame(in: .named("albumGrid"))]
                                            )
                                        }
                                    )
                                    .onTapGesture { handleTap(item) }
                                    .onLongPressGesture { enterSelectionMode(selecting: item) }
                            }
                        }
                        .onPreferenceChange(GridCellFramePreferenceKey.self) { frames in
                            cellFrames = frames
                        }
                    }
                    .coordinateSpace(name: "albumGrid")
                    .scrollDisabled(isDragSelecting)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { scrollViewHeight = geo.size.height }
                                .onChange(of: geo.size.height) { _, newValue in
                                    scrollViewHeight = newValue
                                }
                        }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .named("albumGrid"))
                            .onChanged { value in
                                guard isSelectionMode else { return }
                                handleDragSelection(value, scrollProxy: proxy)
                            }
                            .onEnded { _ in
                                finishDragSelection()
                            }
                    )
                }

                Text("\(albumItems.count) \(albumItems.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedItems.isEmpty {
                selectionToolbar
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        }
        .confirmationDialog(
            "Delete \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { batchDelete() }
        } message: {
            Text("These items will be permanently deleted from your vault.")
        }
        .sheet(isPresented: $showAlbumPicker) {
            albumPickerSheet
        }
        .fullScreenCover(item: $detailItem) { item in
            let index = displayedItems.firstIndex(where: { $0.id == item.id }) ?? 0
            PhotoDetailView(
                items: displayedItems,
                initialIndex: index,
                vaultService: vaultService
            )
        }
        .fullScreenCover(item: $documentDetailItem) { item in
            DocumentDetailView(item: item, vaultService: vaultService)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            detailItem = nil
            documentDetailItem = nil
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
                ForEach(albums.filter { isDecoyMode ? $0.isDecoy : !$0.isDecoy }) { album in
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
        .presentationBackground(Color.vaultBackground)
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

            // Selection overlay and checkmark
            if isSelectionMode {
                // Dark overlay on selected items
                if selectedItems.contains(item.id) {
                    Color.black.opacity(0.3)
                }

                // Checkmark (top-left)
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
                Haptics.itemSelected()
                selectedItems.insert(item.id)
            }
        } else if item.type == .document {
            documentDetailItem = item
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

    // MARK: - Drag-to-Select

    private func itemIndex(at point: CGPoint) -> Int? {
        let items = displayedItems
        for (id, frame) in cellFrames {
            if frame.contains(point),
               let idx = items.firstIndex(where: { $0.id == id }) {
                return idx
            }
        }
        return nil
    }

    private func handleDragSelection(_ value: DragGesture.Value, scrollProxy: ScrollViewProxy) {
        let items = displayedItems

        if !isDragSelecting {
            guard let startIdx = itemIndex(at: value.startLocation) else { return }
            isDragSelecting = true
            dragStartIndex = startIdx
            preDragSelection = selectedItems

            let startItemId = items[startIdx].id
            dragAdditive = !preDragSelection.contains(startItemId)
        }

        // Auto-scroll when finger is near the top or bottom edge
        updateAutoScroll(fingerY: value.location.y, proxy: scrollProxy)

        guard let startIdx = dragStartIndex,
              let currentIdx = itemIndex(at: value.location) else { return }

        guard currentIdx != dragCurrentIndex else { return }
        let previousIndex = dragCurrentIndex
        dragCurrentIndex = currentIdx

        applyDragSelection(startIdx: startIdx, endIdx: currentIdx)

        if currentIdx != previousIndex {
            Haptics.itemSelected()
        }
    }

    private func applyDragSelection(startIdx: Int, endIdx: Int) {
        let items = displayedItems
        let rangeStart = min(startIdx, endIdx)
        let rangeEnd = min(max(startIdx, endIdx), items.count - 1)

        var updated = preDragSelection
        for idx in rangeStart...rangeEnd {
            let itemId = items[idx].id
            if dragAdditive {
                updated.insert(itemId)
            } else {
                updated.remove(itemId)
            }
        }
        selectedItems = updated
    }

    private func finishDragSelection() {
        guard isDragSelecting else { return }
        stopAutoScroll()
        autoScrollDirection = 0
        isDragSelecting = false
        dragStartIndex = nil
        dragCurrentIndex = nil
        preDragSelection = []
    }

    // MARK: - Auto-Scroll

    private func updateAutoScroll(fingerY: CGFloat, proxy: ScrollViewProxy) {
        let edgeThreshold: CGFloat = 60
        let newDirection: Int

        if fingerY < edgeThreshold && scrollViewHeight > 0 {
            newDirection = -1
        } else if fingerY > scrollViewHeight - edgeThreshold && scrollViewHeight > 0 {
            newDirection = 1
        } else {
            newDirection = 0
        }

        guard newDirection != autoScrollDirection else { return }
        stopAutoScroll()
        autoScrollDirection = newDirection
        if newDirection != 0 {
            beginAutoScroll(direction: newDirection, proxy: proxy)
        }
    }

    private func beginAutoScroll(direction: Int, proxy: ScrollViewProxy) {
        autoScrollTask = Task { @MainActor in
            let colCount = Constants.vaultGridColumns
            while !Task.isCancelled && isDragSelecting {
                let items = displayedItems
                guard let currentIdx = dragCurrentIndex, let startIdx = dragStartIndex else { break }

                let targetIdx: Int
                if direction < 0 {
                    targetIdx = max(0, currentIdx - colCount)
                } else {
                    targetIdx = min(items.count - 1, currentIdx + colCount)
                }
                guard targetIdx != currentIdx else { break }

                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo(items[targetIdx].id, anchor: direction < 0 ? .top : .bottom)
                }

                dragCurrentIndex = targetIdx
                applyDragSelection(startIdx: startIdx, endIdx: targetIdx)
                Haptics.itemSelected()

                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }

    // MARK: - Batch Actions

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
        guard album.isDecoy == isDecoyMode else { return }
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

// MARK: - SmartAlbumDetailView

struct SmartAlbumDetailView: View {
    let smartAlbumType: SmartAlbumType
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var detailItem: VaultItem?
    @State private var documentDetailItem: VaultItem?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    private var matchingItems: [VaultItem] {
        let tag = smartAlbumType.tag
        var items = allItems.filter { $0.smartTags.contains(tag) }
        if isDecoyMode {
            items = items.filter { $0.album?.isDecoy == true }
        } else {
            items = items.filter { $0.album?.isDecoy != true }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            if matchingItems.isEmpty {
                Spacer()
                EmptyStateView(
                    systemImage: smartAlbumType.systemImage,
                    title: "No Items",
                    subtitle: "Items matching this category will appear here"
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                        ForEach(matchingItems) { item in
                            thumbnailCell(for: item)
                                .onTapGesture {
                                    if item.type == .document {
                                        documentDetailItem = item
                                    } else {
                                        detailItem = item
                                    }
                                }
                        }
                    }
                }

                Text("\(matchingItems.count) \(matchingItems.count == 1 ? "item" : "items")")
                    .font(.caption)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle(smartAlbumType.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $detailItem) { item in
            let nonDocumentItems = matchingItems.filter { $0.type != .document }
            let index = nonDocumentItems.firstIndex(where: { $0.id == item.id }) ?? 0
            PhotoDetailView(
                items: nonDocumentItems,
                initialIndex: index,
                vaultService: vaultService
            )
        }
        .fullScreenCover(item: $documentDetailItem) { item in
            DocumentDetailView(item: item, vaultService: vaultService)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            detailItem = nil
            documentDetailItem = nil
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

            if item.type == .document {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(4)
                        Spacer()
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
