import SwiftUI
import SwiftData

struct AskVaultView: View {
    let vaultService: VaultService
    let searchEngine: SearchEngine?
    let indexingProgress: IndexingProgress
    var isDecoyMode: Bool = false

    @Environment(PurchaseService.self) private var purchaseService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    private var filteredItems: [VaultItem] {
        if isDecoyMode {
            return allItems.filter { $0.album?.isDecoy == true }
        } else {
            return allItems.filter { $0.album?.isDecoy != true }
        }
    }

    @State private var viewModel: AskVaultViewModel?
    @State private var searchText = ""
    @State private var showPaywall = false
    @State private var detailItem: VaultItem?
    @State private var documentDetailItem: VaultItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaultBackground.ignoresSafeArea()

                if let searchEngine {
                    Group {
                        if let viewModel {
                            mainContent(viewModel: viewModel)
                        } else {
                            ProgressView()
                                .onAppear {
                                    initializeViewModel(searchEngine: searchEngine)
                                }
                        }
                    }
                } else {
                    loadingState
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Ask My Vault")
                            .font(.headline)
                        if purchaseService.isPremiumRequired(for: .askMyVault) {
                            PremiumBadge()
                        }
                    }
                }
            }
            .toolbarBackground(Color.vaultBackground, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Ask your vault...")
            .onSubmit(of: .search) {
                guard let viewModel else { return }
                viewModel.searchText = searchText
                viewModel.performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                guard let viewModel else { return }
                viewModel.searchText = newValue
                viewModel.onSearchTextChanged()
            }
            .fullScreenCover(isPresented: $showPaywall) {
                VaultBoxPaywallView()
            }
            .fullScreenCover(item: $detailItem) { item in
                let nonDocItems = filteredItems.filter { $0.type != .document }
                let index = nonDocItems.firstIndex(where: { $0.id == item.id }) ?? 0
                PhotoDetailView(
                    items: nonDocItems,
                    initialIndex: index,
                    vaultService: vaultService
                )
            }
            .fullScreenCover(item: $documentDetailItem) { item in
                DocumentDetailView(item: item, vaultService: vaultService)
            }
        }
    }

    private func initializeViewModel(searchEngine: SearchEngine) {
        guard viewModel == nil else { return }
        viewModel = AskVaultViewModel(
            vaultService: vaultService,
            searchEngine: searchEngine,
            indexingProgress: indexingProgress
        )
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.vaultAccent)
            Text("Preparing search...")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(viewModel: AskVaultViewModel) -> some View {
        VStack(spacing: 0) {
            // Indexing progress bar
            if indexingProgress.isIndexing {
                indexingProgressBar
            }

            ScrollView {
                VStack(spacing: Constants.sectionSpacing) {
                    if viewModel.isSearching {
                        searchingIndicator
                    } else if let error = viewModel.errorMessage {
                        errorState(message: error)
                    } else if viewModel.hasSearched && viewModel.results.isEmpty {
                        noResultsState
                    } else if viewModel.hasSearched {
                        resultsList(viewModel: viewModel)
                    } else {
                        emptyState(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, Constants.standardPadding)
                .padding(.top, 8)
                .padding(.bottom, Constants.sectionSpacing)
            }
        }
        .onChange(of: filteredItems) { _, newItems in
            viewModel.updateItemLookup(from: newItems)
        }
        .onAppear {
            viewModel.updateItemLookup(from: filteredItems)
        }
        // Premium gate: dismisses search and shows paywall when free user taps search bar
        .background {
            SearchPremiumGate(
                showPaywall: $showPaywall,
                isPremiumRequired: purchaseService.isPremiumRequired(for: .askMyVault)
            )
        }
    }

    // MARK: - Premium Upsell Card

    private var askVaultUpsellCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.vaultPremium)
                Spacer()
                PremiumBadge()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Search Your Entire Vault")
                    .font(.headline)
                    .foregroundStyle(Color.vaultTextPrimary)

                Text("Ask questions about your photos, documents, and screenshots with AI-powered search.")
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
            }

            Button {
                showPaywall = true
            } label: {
                Label("Upgrade to Premium", systemImage: "star.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vaultPremium)
        }
        .padding(Constants.standardPadding)
        .background(Color.vaultSurface)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.cardCornerRadius)
                .stroke(Color.vaultPremium.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Constants.cardCornerRadius))
    }

    // MARK: - Indexing Progress

    private var indexingProgressBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.vaultAccent.opacity(0.15))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.vaultAccent)
                        .frame(
                            width: geometry.size.width * indexingProgress.fractionComplete,
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.3), value: indexingProgress.fractionComplete)
                }
            }
            .frame(height: 4)

            if let name = indexingProgress.currentItemName {
                Text("Indexing \(name)...")
                    .font(.caption2)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Constants.standardPadding)
        .padding(.vertical, 6)
    }

    // MARK: - States

    private func emptyState(viewModel: AskVaultViewModel) -> some View {
        VStack(spacing: Constants.sectionSpacing) {
            Spacer()
                .frame(height: 40)

            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.vaultAccent.opacity(0.6))

                Text("Search Your Vault")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.vaultTextPrimary)

                Text("Ask questions about your documents, photos, and screenshots. VaultBox searches the text in all your files.")
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Premium upsell card for free users; suggestion chips for premium users
            if purchaseService.isPremiumRequired(for: .askMyVault) {
                askVaultUpsellCard
            } else {
                VStack(spacing: 10) {
                    Text("Try asking")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.vaultTextSecondary)
                        .textCase(.uppercase)

                    FlowLayout(spacing: 8) {
                        ForEach(AskVaultViewModel.suggestions, id: \.self) { suggestion in
                            SuggestionChipView(text: suggestion) {
                                searchText = suggestion
                                viewModel.selectSuggestion(suggestion)
                            }
                        }
                    }
                }
            }
        }
    }

    private var searchingIndicator: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 60)
            ProgressView()
                .tint(Color.vaultAccent)
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.vaultTextSecondary.opacity(0.6))

            Text("No Results Found")
                .font(.headline)
                .foregroundStyle(Color.vaultTextPrimary)

            Text("Try different keywords or a more general question.")
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.vaultDestructive)

            Text("Search Error")
                .font(.headline)
                .foregroundStyle(Color.vaultTextPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Results

    private func resultsList(viewModel: AskVaultViewModel) -> some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.results) { result in
                let info = viewModel.itemLookup[result.itemID]
                SearchResultCard(
                    result: result,
                    itemName: info?.name ?? "Unknown",
                    itemType: info?.type ?? .document,
                    queryTerms: viewModel.queryTerms
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateToItem(result.itemID)
                }
            }
        }
    }

    // MARK: - Navigation

    private func navigateToItem(_ itemID: UUID) {
        guard let item = filteredItems.first(where: { $0.id == itemID }) else { return }
        switch item.type {
        case .document:
            documentDetailItem = item
        case .photo, .video:
            detailItem = item
        }
    }
}

// MARK: - SearchPremiumGate

/// Monitors the native `.searchable()` activation state. When a free-tier user
/// taps the search bar, this immediately dismisses the search and presents the paywall.
/// Must be placed as a child of the view that has `.searchable()`.
private struct SearchPremiumGate: View {
    @Environment(\.isSearching) private var isSearching
    @Environment(\.dismissSearch) private var dismissSearch
    @Binding var showPaywall: Bool
    let isPremiumRequired: Bool

    var body: some View {
        EmptyView()
            .onChange(of: isSearching) { _, isActive in
                if isActive && isPremiumRequired {
                    dismissSearch()
                    showPaywall = true
                }
            }
    }
}

// MARK: - FlowLayout

/// A simple horizontal wrapping layout for suggestion chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (positions: [CGPoint], sizes: [CGSize], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = currentY + rowHeight
        }

        return (positions, sizes, CGSize(width: totalWidth, height: totalHeight))
    }
}
