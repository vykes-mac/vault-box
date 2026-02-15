import SwiftUI
import SwiftData
import UIKit

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
    case documents = "Documents"
    case favorites = "Favorites"
}

// MARK: - Grid Cell Frame Tracking

struct GridCellFramePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
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
    @State private var showDocumentPicker = false
    @State private var detailItem: VaultItem?
    @State private var documentDetailItem: VaultItem?
    @State private var showDeleteConfirm = false
    @State private var showAlbumPicker = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var isImportingDocuments = false
    @State private var showDocumentDeletePrompt = false
    @State private var pendingDocumentURLs: [URL] = []

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

    @Query(sort: \Album.sortOrder) private var albums: [Album]
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    // Month names for date-based search (computed once)
    private static let monthNames: [String] = Calendar.current.monthSymbols.map { $0.lowercased() }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// All unique smart tags present across visible vault items (for search suggestions).
    private var allAvailableTags: [String] {
        Set(filteredItems.flatMap { $0.smartTags }).sorted()
    }

    private var displayedItems: [VaultItem] {
        var items = allItems

        // Decoy mode filtering: show only items in decoy albums
        if isDecoyMode {
            items = items.filter { $0.album?.isDecoy == true }
        } else {
            items = items.filter { $0.album?.isDecoy != true }
        }

        // Search filtering — multi-word AND logic
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            let searchTerms = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            items = items.filter { item in
                searchTerms.allSatisfy { term in
                    matchesSearchTerm(item: item, term: term)
                }
            }
        }

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

    private var filteredItems: [VaultItem] {
        if isDecoyMode {
            return allItems.filter { $0.album?.isDecoy == true }
        } else {
            return allItems.filter { $0.album?.isDecoy != true }
        }
    }

    private var itemCountText: String {
        let total = filteredItems.count
        let displayed = displayedItems.count
        if isSearchActive || filter != .all {
            return "\(displayed) of \(total) item\(total == 1 ? "" : "s")"
        }
        if purchaseService.isPremium {
            return "\(total) item\(total == 1 ? "" : "s")"
        }
        return "\(total) of \(Constants.freeItemLimit) items"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Vault")
                .searchable(text: $searchText, prompt: "Search tags, albums, dates…")
                .searchSuggestions { searchSuggestionsContent }
                .toolbar { toolbarContent }
                .overlay { sheetAndAlertModifiers }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if filteredItems.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else if displayedItems.isEmpty {
                Spacer()
                noResultsState
                Spacer()
            } else {
                gridContent
                itemCountBar
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedItems.isEmpty {
                selectionToolbar
            }
        }
    }

    /// Invisible overlay carrier for sheets, alerts, and full-screen covers.
    private var sheetAndAlertModifiers: some View {
        Color.clear
            .allowsHitTesting(false)
            .fullScreenCover(item: $detailItem) { item in
                PhotoDetailView(
                    items: displayedItems,
                    initialIndex: displayedItems.firstIndex(where: { $0.id == item.id }) ?? 0,
                    vaultService: vaultService
                )
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
            .fullScreenCover(isPresented: $showImporter) {
                ImportView(
                    vaultService: vaultService,
                    album: nil,
                    isDecoyMode: isDecoyMode,
                    onDismiss: { showImporter = false }
                )
            }
            .fullScreenCover(item: $documentDetailItem) { item in
                DocumentDetailView(item: item, vaultService: vaultService)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPickerView { urls in
                    showDocumentPicker = false
                    importDocuments(urls)
                } onCancel: {
                    showDocumentPicker = false
                }
            }
            .alert(
                "Delete from Files?",
                isPresented: $showDocumentDeletePrompt
            ) {
                Button("Delete", role: .destructive) { deleteOriginalDocuments() }
                Button("Keep", role: .cancel) { pendingDocumentURLs = [] }
            } message: {
                Text("Delete \(pendingDocumentURLs.count) original\(pendingDocumentURLs.count == 1 ? "" : "s")? The imported documents are safely encrypted in your vault.")
            }
            .fullScreenCover(isPresented: $showPaywall) {
                VaultBoxPaywallView()
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
            title: "No Items Yet",
            subtitle: "Tap + to add your first photo"
        )
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.vaultTextSecondary)

            Text("No Results")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.vaultTextPrimary)

            Group {
                let tags = allAvailableTags
                if tags.isEmpty {
                    Text("Try searching by type, album name, or date")
                } else {
                    Text("Try \"\(tags.prefix(3).joined(separator: "\", \""))\" or search by album name or date")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.vaultTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                    ForEach(displayedItems) { item in
                        thumbnailCell(for: item)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: GridCellFramePreferenceKey.self,
                                        value: [item.id: geo.frame(in: .named("vaultGrid"))]
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
            .coordinateSpace(name: "vaultGrid")
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
                DragGesture(minimumDistance: 10, coordinateSpace: .named("vaultGrid"))
                    .onChanged { value in
                        guard isSelectionMode else { return }
                        handleDragSelection(value, scrollProxy: proxy)
                    }
                    .onEnded { _ in
                        finishDragSelection()
                    }
            )
        }
    }

    // MARK: - Thumbnail Cell

    private func thumbnailCell(for item: VaultItem) -> some View {
        ZStack {
            // Thumbnail image or document placeholder
            if let image = thumbnailCache[item.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if item.type == .document {
                // Document placeholder with icon
                Color.vaultSurface
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: DocumentThumbnailService.placeholderIcon(for: item.originalFilename))
                                .font(.title2)
                                .foregroundStyle(Color.vaultAccent.opacity(0.6))
                            Text(item.originalFilename)
                                .font(.system(size: 8))
                                .foregroundStyle(Color.vaultTextSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                    )
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

            // Document type badge (bottom-left)
            if item.type == .document {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "doc.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(4)
                        Spacer()
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
            Menu {
                Button {
                    if purchaseService.isPremiumRequired(for: .unlimitedItems, itemCount: allItems.count) {
                        showPaywall = true
                    } else {
                        showImporter = true
                    }
                } label: {
                    Label("Import Photos & Videos", systemImage: "photo.on.rectangle.angled")
                }

                Button {
                    if purchaseService.isPremiumRequired(for: .documentStorage) {
                        showPaywall = true
                    } else if purchaseService.isPremiumRequired(for: .unlimitedItems, itemCount: allItems.count) {
                        showPaywall = true
                    } else {
                        showDocumentPicker = true
                    }
                } label: {
                    Label("Import Documents", systemImage: "doc.badge.plus")
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

    /// Apply selection for all items in the range between startIdx and endIdx.
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
            newDirection = -1 // up
        } else if fingerY > scrollViewHeight - edgeThreshold && scrollViewHeight > 0 {
            newDirection = 1  // down
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

    private func importDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImportingDocuments = true
        Task {
            var importedItems: [VaultItem] = []
            var successfulURLs: [URL] = []
            for url in urls {
                if let item = try? await vaultService.importDocument(at: url, album: nil, isDecoyMode: isDecoyMode) {
                    importedItems.append(item)
                    successfulURLs.append(url)
                }
            }
            // Queue vision analysis so documents get smart-tagged (e.g. "document" smart album)
            if !importedItems.isEmpty {
                vaultService.queueVisionAnalysis(for: importedItems)
                vaultService.queueSearchIndexing(for: importedItems)
            }
            isImportingDocuments = false

            if !successfulURLs.isEmpty {
                pendingDocumentURLs = successfulURLs
                showDocumentDeletePrompt = true
            }
        }
    }

    // MARK: - Search Helpers

    @ViewBuilder
    private var searchSuggestionsContent: some View {
        let candidates = searchSuggestionCandidates
        ForEach(candidates, id: \.completion) { entry in
            Label(entry.label, systemImage: entry.icon)
                .searchCompletion(entry.completion)
        }
    }

    private var searchSuggestionCandidates: [(label: String, icon: String, completion: String)] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let words = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let lastWord = words.last ?? ""
        let previousWords = Set(words.dropLast())
        let prefix = words.dropLast().joined(separator: " ")

        let tags = allAvailableTags
        let matched: [String]
        if lastWord.isEmpty {
            matched = Array(tags.prefix(8))
        } else {
            matched = tags.filter { !previousWords.contains($0) && $0.hasPrefix(lastWord) }
        }

        return matched.map { tag in
            let completion = prefix.isEmpty ? tag : "\(prefix) \(tag)"
            return (label: tag.capitalized, icon: iconForTag(tag), completion: completion)
        }
    }

    private func matchesSearchTerm(item: VaultItem, term: String) -> Bool {
        // Match filename
        if item.originalFilename.lowercased().contains(term) { return true }

        // Match smart tags
        if item.smartTags.contains(where: { $0.contains(term) }) { return true }

        // Match OCR extracted text
        if let text = item.extractedText, text.lowercased().contains(term) { return true }

        // Match item type (photo/video/document) — prefix match handles plurals
        let typeName = item.type.rawValue
        if typeName.hasPrefix(term) || term.hasPrefix(typeName) { return true }

        // Match album name
        if let albumName = item.album?.name.lowercased(), albumName.contains(term) { return true }

        // Match favorites
        if item.isFavorite && "favorite".hasPrefix(term) { return true }

        // Match date — month name or year
        let components = Calendar.current.dateComponents([.month, .year], from: item.createdAt)
        if let month = components.month, Self.monthNames[month - 1].hasPrefix(term) { return true }
        if let year = components.year, String(year).contains(term) { return true }

        // Also check import date
        let importComponents = Calendar.current.dateComponents([.month, .year], from: item.importedAt)
        if let month = importComponents.month, month != components.month,
           Self.monthNames[month - 1].hasPrefix(term) { return true }
        if let year = importComponents.year, year != components.year,
           String(year).contains(term) { return true }

        return false
    }

    private func iconForTag(_ tag: String) -> String {
        switch tag {
        case "people": return "person.2.fill"
        case "animals": return "pawprint.fill"
        case "plants": return "leaf.fill"
        case "buildings": return "building.2.fill"
        case "landmarks": return "building.columns.fill"
        case "document": return "doc.text.fill"
        case "screenshot": return "rectangle.dashed"
        case "qrcode": return "qrcode"
        case "food": return "fork.knife"
        case "vehicles": return "car.fill"
        case "nature": return "mountain.2.fill"
        case "beach": return "sun.max.fill"
        case "sunset": return "sunset.fill"
        case "sports": return "figure.run"
        case "night": return "moon.stars.fill"
        case "water": return "drop.fill"
        case "celebration": return "sparkles"
        default: return "tag"
        }
    }

    private func deleteOriginalDocuments() {
        let urls = pendingDocumentURLs
        pendingDocumentURLs = []
        Task {
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
