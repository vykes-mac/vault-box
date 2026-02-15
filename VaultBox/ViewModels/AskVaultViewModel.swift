import SwiftUI
import SwiftData

@MainActor
@Observable
class AskVaultViewModel {
    let vaultService: VaultService
    private let searchEngine: SearchEngine

    // MARK: - Search State

    var searchText = ""
    var results: [SearchResult] = []
    var isSearching = false
    var hasSearched = false
    var errorMessage: String?

    // MARK: - Item Lookup Cache

    /// Maps item UUIDs to (name, type) for displaying results.
    private(set) var itemLookup: [UUID: (name: String, type: VaultItem.ItemType)] = [:]

    /// Item IDs that are allowed in the current vault context (decoy vs regular).
    /// Search results are post-filtered against this set.
    private(set) var allowedItemIDs: Set<UUID> = []

    // MARK: - Indexing Progress

    let indexingProgress: IndexingProgress

    // MARK: - Suggestions

    static let suggestions: [String] = [
        "What's my passport number?",
        "Find the contract end date",
        "Show receipts from January",
        "When does my lease expire?"
    ]

    // MARK: - Debounce

    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        vaultService: VaultService,
        searchEngine: SearchEngine,
        indexingProgress: IndexingProgress
    ) {
        self.vaultService = vaultService
        self.searchEngine = searchEngine
        self.indexingProgress = indexingProgress
    }

    // MARK: - Search

    /// Called whenever `searchText` changes. Cancels any in-flight search and
    /// starts a new one after the debounce interval.
    func onSearchTextChanged() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            hasSearched = false
            isSearching = false
            errorMessage = nil
            return
        }

        searchTask = Task {
            // Debounce
            try? await Task.sleep(for: .milliseconds(Constants.searchDebounceMs))
            guard !Task.isCancelled else { return }

            isSearching = true
            errorMessage = nil

            do {
                let searchResults = try await searchEngine.search(query: query)
                guard !Task.isCancelled else { return }
                results = searchResults.filter { allowedItemIDs.contains($0.itemID) }
                hasSearched = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                results = []
                hasSearched = true
            }

            isSearching = false
        }
    }

    /// Fills the search bar with a suggestion and triggers search.
    func selectSuggestion(_ suggestion: String) {
        searchText = suggestion
        onSearchTextChanged()
    }

    /// Performs an immediate search (no debounce), e.g. for "Search" button tap.
    func performSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        searchTask = Task {
            isSearching = true
            errorMessage = nil

            do {
                let searchResults = try await searchEngine.search(query: query)
                guard !Task.isCancelled else { return }
                results = searchResults.filter { allowedItemIDs.contains($0.itemID) }
                hasSearched = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                results = []
                hasSearched = true
            }

            isSearching = false
        }
    }

    // MARK: - Item Lookup

    /// Populates name/type lookup from SwiftData so result cards can display metadata.
    /// Called from the view when items query changes.
    func updateItemLookup(from items: [VaultItem]) {
        var lookup: [UUID: (name: String, type: VaultItem.ItemType)] = [:]
        for item in items {
            lookup[item.id] = (name: item.originalFilename, type: item.type)
        }
        itemLookup = lookup
        allowedItemIDs = Set(items.map { $0.id })
    }

    /// The current query split into terms for highlight matching.
    var queryTerms: [String] {
        searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
    }
}
