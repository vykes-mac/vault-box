import SwiftUI
import SwiftData

func localizedDaysUntilPurge(_ days: Int) -> String {
    if days == 1 {
        return String(localized: "1 day")
    }
    return String(localized: "\(days) days")
}

func localizedPermanentlyDeleteItemsTitle(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "Permanently delete 1 item?")
    }
    return String(localized: "Permanently delete \(count) items?")
}

// MARK: - RecentlyDeletedView

/// The Recently Deleted bin for the vault that is currently unlocked. Presented as a
/// sheet so locking (including the panic gesture) dismisses it along with every other
/// presentation before the lock screen or a decoy session can show.
struct RecentlyDeletedView: View {
    let vaultService: VaultService
    var isDecoyMode: Bool = false

    @Query(
        filter: #Predicate<VaultItem> { $0.deletedAt != nil },
        sort: \VaultItem.deletedAt,
        order: .reverse
    ) private var trashedItems: [VaultItem]

    @Environment(\.dismiss) private var dismiss

    @State private var thumbnailCache: [UUID: UIImage] = [:]
    @State private var isSelectionMode = false
    @State private var selectedItems: Set<UUID> = []
    @State private var actionItem: VaultItem?
    @State private var pendingPermanentDelete: [VaultItem] = []
    @State private var showPermanentDeleteConfirm = false
    @State private var errorMessage: String?

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Constants.vaultGridSpacing),
        count: Constants.vaultGridColumns
    )

    private var items: [VaultItem] {
        trashedItems.filter { $0.isInRecentlyDeleted(inDecoyMode: isDecoyMode) }
    }

    private var selectedVaultItems: [VaultItem] {
        items.filter { selectedItems.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "trash",
                        title: String(localized: "No Recently Deleted Items"),
                        subtitle: String(localized: "Deleted items stay here for 30 days before they're permanently removed.")
                    )
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text("Items show the days remaining before they're permanently deleted. After that, they can't be recovered.")
                            .font(.footnote)
                            .foregroundStyle(Color.vaultTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Constants.standardPadding)
                            .padding(.top, 8)

                        LazyVGrid(columns: columns, spacing: Constants.vaultGridSpacing) {
                            ForEach(items) { item in
                                cell(for: item)
                            }
                        }
                        .padding(.horizontal, Constants.vaultGridSpacing)
                    }
                    .safeAreaInset(edge: .bottom) {
                        bottomBar
                    }
                }
            }
            .background(Color.vaultBackground)
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelectionMode ? String(localized: "Cancel") : String(localized: "Select")) {
                            isSelectionMode.toggle()
                            selectedItems.removeAll()
                        }
                    }
                }
            }
            .confirmationDialog(
                actionItem.map { $0.originalFilename } ?? "",
                isPresented: .init(
                    get: { actionItem != nil },
                    set: { if !$0 { actionItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: actionItem
            ) { item in
                Button("Restore") { restore([item]) }
                Button("Delete Permanently", role: .destructive) {
                    confirmPermanentDelete([item])
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                localizedPermanentlyDeleteItemsTitle(pendingPermanentDelete.count),
                isPresented: $showPermanentDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    permanentlyDelete(pendingPermanentDelete)
                }
                Button("Cancel", role: .cancel) { pendingPermanentDelete = [] }
            } message: {
                Text("This can't be undone. Items are also removed from your iCloud backup.")
            }
            .alert(
                "Error",
                isPresented: .init(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: items.isEmpty) { _, isEmpty in
                if isEmpty { isSelectionMode = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                dismiss()
            }
        }
    }

    // MARK: - Cell

    private func cell(for item: VaultItem) -> some View {
        Button {
            if isSelectionMode {
                if selectedItems.contains(item.id) {
                    selectedItems.remove(item.id)
                } else {
                    selectedItems.insert(item.id)
                }
            } else {
                actionItem = item
            }
        } label: {
            VaultItemThumbnail(
                image: thumbnailCache[item.id],
                isFavorite: false,
                isVideo: item.type == .video,
                durationSeconds: item.durationSeconds,
                isSelected: selectedItems.contains(item.id),
                selectionMode: isSelectionMode
            )
            .overlay(alignment: .bottomLeading) {
                if let deletedAt = item.deletedAt {
                    Text(localizedDaysUntilPurge(VaultItem.daysUntilPurge(deletedAt: deletedAt, now: Date())))
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
            .overlay(alignment: .topTrailing) {
                if item.type == .document {
                    Image(systemName: "doc.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.originalFilename)
        .task {
            await loadThumbnail(for: item)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        let targets = isSelectionMode ? selectedVaultItems : items
        return HStack {
            Button(role: .destructive) {
                confirmPermanentDelete(targets)
            } label: {
                Text(isSelectionMode ? String(localized: "Delete") : String(localized: "Delete All"))
            }
            .foregroundStyle(Color.vaultDestructive)

            Spacer()

            Button {
                restore(targets)
            } label: {
                Text(isSelectionMode ? String(localized: "Restore") : String(localized: "Restore All"))
            }
            .foregroundStyle(Color.vaultAccent)
        }
        .disabled(targets.isEmpty)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func restore(_ targets: [VaultItem]) {
        guard !targets.isEmpty else { return }
        Task {
            do {
                try await vaultService.restoreItems(targets)
                exitSelectionMode()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func confirmPermanentDelete(_ targets: [VaultItem]) {
        guard !targets.isEmpty else { return }
        pendingPermanentDelete = targets
        showPermanentDeleteConfirm = true
    }

    private func permanentlyDelete(_ targets: [VaultItem]) {
        Haptics.deleteConfirmed()
        pendingPermanentDelete = []
        for item in targets {
            thumbnailCache[item.id] = nil
        }
        Task {
            do {
                try await vaultService.permanentlyDeleteItems(targets)
                exitSelectionMode()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedItems.removeAll()
    }

    private func loadThumbnail(for item: VaultItem) async {
        guard thumbnailCache[item.id] == nil else { return }
        guard let image = try? await vaultService.decryptThumbnail(for: item) else { return }
        thumbnailCache[item.id] = image
    }
}
