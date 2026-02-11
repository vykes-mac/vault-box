import SwiftUI
import SwiftData
import CloudKit

struct BackupSettingsView: View {
    let vaultService: VaultService

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    @Query private var settingsQuery: [AppSettings]
    @Query(sort: \VaultItem.importedAt, order: .reverse) private var allItems: [VaultItem]

    @State private var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @State private var isSyncing = false
    @State private var syncStatusText = "Ready"
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPaywall = false

    private var settings: AppSettings? { settingsQuery.first }

    private var uploadedCount: Int {
        allItems.filter(\.isUploaded).count
    }

    var body: some View {
        List {
            if purchaseService.isPremium {
                Section {
                    if let settings {
                        Toggle(isOn: Binding(
                            get: { settings.iCloudBackupEnabled },
                            set: { newValue in
                                settings.iCloudBackupEnabled = newValue
                                try? modelContext.save()
                            }
                        )) {
                            Label("iCloud Backup", systemImage: "icloud")
                        }
                        .disabled(iCloudStatus != .available)
                    }

                    statusRow
                } footer: {
                    Text("All data is encrypted before uploading to your private iCloud storage. Apple cannot read your files.")
                }

                Section {
                    Button {
                        triggerManualSync()
                    } label: {
                        HStack {
                            Label("Backup Now", systemImage: "arrow.clockwise.icloud")
                            Spacer()
                            if isSyncing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncing || iCloudStatus != .available || settings?.iCloudBackupEnabled != true)
                }

                Section("Status") {
                    LabeledContent("Uploaded", value: "\(uploadedCount) of \(allItems.count)")
                    LabeledContent("iCloud Account", value: iCloudStatusText)
                }
            } else {
                premiumRequiredSection
            }
        }
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkiCloudStatus()
        }
        .onChange(of: purchaseService.isPremium) { _, isPremium in
            if !isPremium {
                disablePremiumBackupState()
            }
        }
        .alert("Backup Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
        }
    }

    private var premiumRequiredSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Premium Required", systemImage: "lock.fill")
                    .font(.headline)
                Text("iCloud Backup is available on Premium.")
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to Premium", systemImage: "star.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Status")
                .foregroundStyle(Color.vaultTextSecondary)
            Spacer()
            Text(syncStatusText)
                .font(.caption)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    private var iCloudStatusText: String {
        switch iCloudStatus {
        case .available: "Available"
        case .noAccount: "No Account"
        case .restricted: "Restricted"
        case .couldNotDetermine: "Checking..."
        case .temporarilyUnavailable: "Temporarily Unavailable"
        @unknown default: "Unknown"
        }
    }

    private func checkiCloudStatus() async {
        let service = CloudService(encryptionService: EncryptionService())
        iCloudStatus = await service.getICloudAccountStatus()
    }

    private func triggerManualSync() {
        guard purchaseService.isPremium else {
            showPaywall = true
            return
        }
        isSyncing = true
        syncStatusText = "Syncing..."

        // Capture item data on MainActor before crossing actor boundary
        let pendingItems = allItems.filter { !$0.isUploaded }
        let payloads = pendingItems.map { item in
            CloudUploadPayload(
                itemID: item.id,
                encryptedFileRelativePath: item.encryptedFileRelativePath,
                itemType: item.type.rawValue,
                originalFilename: item.originalFilename,
                fileSize: item.fileSize,
                createdAt: item.createdAt,
                encryptedThumbnailData: item.encryptedThumbnailData
            )
        }

        Task {
            do {
                let service = CloudService(encryptionService: EncryptionService())
                for (index, payload) in payloads.enumerated() {
                    let recordName = try await service.uploadItem(payload)
                    // Update local item on MainActor
                    if index < pendingItems.count {
                        pendingItems[index].cloudRecordID = recordName
                        pendingItems[index].isUploaded = true
                    }
                }
                try? modelContext.save()
                syncStatusText = "Up to date"
            } catch {
                errorMessage = "Backup paused — \(error.localizedDescription)"
                showError = true
                syncStatusText = "Error"
            }
            isSyncing = false
        }
    }

    private func disablePremiumBackupState() {
        isSyncing = false
        syncStatusText = "Premium required"
        if let settings, settings.iCloudBackupEnabled {
            settings.iCloudBackupEnabled = false
            try? modelContext.save()
        }
    }
}
