import SwiftUI
import SwiftData

// MARK: - SharedItemsView

struct SharedItemsView: View {
    let sharingService: SharingService

    @Query(sort: \SharedItem.createdAt, order: .reverse) private var sharedItems: [SharedItem]
    @Environment(\.modelContext) private var modelContext

    @State private var itemToRevoke: SharedItem?
    @State private var showRevokeConfirm = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if activeShares.isEmpty && expiredShares.isEmpty {
                emptyState
            }

            if !activeShares.isEmpty {
                Section("Active Shares") {
                    ForEach(activeShares) { item in
                        shareRow(item, isActive: true)
                    }
                }
            }

            if !expiredShares.isEmpty {
                Section("Expired") {
                    ForEach(expiredShares) { item in
                        shareRow(item, isActive: false)
                    }
                }
            }

            if !sharedItems.isEmpty {
                Section {
                    Button("Clear Expired", role: .destructive) {
                        clearExpired()
                    }
                    .disabled(expiredShares.isEmpty)
                }
            }
        }
        .navigationTitle("Shared Items")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Revoke Share?",
            isPresented: $showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let item = itemToRevoke {
                    revokeShare(item)
                }
            }
        } message: {
            Text("The share link will stop working immediately. This cannot be undone.")
        }
        .onReceive(timer) { _ in
            // Force UI refresh for countdown timers
        }
    }

    // MARK: - Computed

    private var activeShares: [SharedItem] {
        sharedItems.filter { !$0.isExpired }
    }

    private var expiredShares: [SharedItem] {
        sharedItems.filter { $0.isExpired }
    }

    // MARK: - Row

    private func shareRow(_ item: SharedItem, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: isActive ? "link.circle.fill" : "link.circle")
                    .foregroundStyle(isActive ? Color.vaultAccent : Color.vaultTextSecondary)

                Text(item.originalFilename)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                if isActive {
                    Text(formatRemainingTime(item.remainingTime))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(item.remainingTime < 300 ? Color.vaultDestructive : Color.vaultAccent)
                        .monospacedDigit()
                } else {
                    Text(item.isRevoked ? "Revoked" : "Expired")
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                }
            }

            Text("Created \(item.createdAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
        }
        .swipeActions(edge: .trailing) {
            if isActive {
                Button("Revoke", role: .destructive) {
                    itemToRevoke = item
                    showRevokeConfirm = true
                }
            } else {
                Button("Delete", role: .destructive) {
                    deleteLocalRecord(item)
                }
            }
        }
        .swipeActions(edge: .leading) {
            if isActive {
                Button("Copy Link") {
                    UIPasteboard.general.string = item.shareURL
                    Haptics.itemSelected()
                }
                .tint(Color.vaultAccent)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.vaultTextSecondary)
            Text("No Shared Items")
                .font(.headline)
                .foregroundStyle(Color.vaultTextPrimary)
            Text("When you share a photo with a time-limited link, it will appear here.")
                .font(.callout)
                .foregroundStyle(Color.vaultTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func revokeShare(_ item: SharedItem) {
        Task {
            try? await sharingService.revokeShare(cloudRecordName: item.cloudRecordName)
            item.isRevoked = true
            try? modelContext.save()
            itemToRevoke = nil
        }
    }

    private func deleteLocalRecord(_ item: SharedItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func clearExpired() {
        for item in expiredShares {
            // Also try to clean up CloudKit record if not already revoked
            if !item.isRevoked {
                Task {
                    try? await sharingService.revokeShare(cloudRecordName: item.cloudRecordName)
                }
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    // MARK: - Formatting

    private func formatRemainingTime(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total <= 0 { return "Expired" }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
