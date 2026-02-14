import SwiftUI
import SwiftData
import CloudKit
import CryptoKit

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

    // Restore state
    @State private var isRestoring = false
    @State private var restoreProgress: (completed: Int, total: Int) = (0, 0)
    @State private var showRestoreConfirmation = false
    @State private var showRestoreSuccess = false
    @State private var restoredItemCount = 0
    @State private var showPINEntry = false
    @State private var restorePIN = ""
    @State private var pinError = ""

    // Key backup state
    @State private var showKeyBackupPINEntry = false
    @State private var keyBackupPIN = ""
    @State private var keyBackupPINError = ""
    @State private var keyBackupConfirmed = false

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
                    .disabled(isSyncing || isRestoring || iCloudStatus != .available || settings?.iCloudBackupEnabled != true)
                }

                restoreSection

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
        .alert("Restore from iCloud", isPresented: $showRestoreConfirmation) {
            Button("Restore", role: .destructive) {
                startRestore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will download all backed-up items from iCloud. Existing items won't be duplicated.")
        }
        .alert("Restore Complete", isPresented: $showRestoreSuccess) {
            Button("OK") {}
        } message: {
            Text("\(restoredItemCount) item\(restoredItemCount == 1 ? "" : "s") restored from iCloud.")
        }
        .sheet(isPresented: $showPINEntry) {
            restorePINEntrySheet
        }
        .sheet(isPresented: $showKeyBackupPINEntry) {
            keyBackupPINEntrySheet
        }
        .fullScreenCover(isPresented: $showPaywall) {
            VaultBoxPaywallView()
        }
    }

    // MARK: - Restore Section

    private var restoreSection: some View {
        Section {
            Button {
                showRestoreConfirmation = true
            } label: {
                HStack {
                    Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                    Spacer()
                    if isRestoring {
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring || isSyncing || iCloudStatus != .available)

            if isRestoring && restoreProgress.total > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(
                        value: Double(restoreProgress.completed),
                        total: Double(restoreProgress.total)
                    )
                    .tint(.accentColor)

                    Text("Restoring \(restoreProgress.completed) of \(restoreProgress.total) items…")
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                }
            }
        } footer: {
            Text("Download backed-up items to this device. Items already on this device will be skipped.")
        }
    }

    // MARK: - PIN Entry for Restore

    private var restorePINEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)

                Text("Enter Your Original PIN")
                    .font(.title2.bold())

                Text("Your backup is encrypted with your PIN. Enter the PIN you used when you first set up VaultBox to decrypt your items.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SecureField("PIN", text: $restorePIN)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                if !pinError.isEmpty {
                    Text(pinError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    verifyPINAndRestore()
                } label: {
                    Text("Decrypt & Restore")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(restorePIN.isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        restorePIN = ""
                        pinError = ""
                        showPINEntry = false
                    }
                }
            }
        }
    }

    // MARK: - PIN Entry for Key Backup

    private var keyBackupPINEntrySheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "key.icloud")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)

                Text("Confirm PIN for Key Backup")
                    .font(.title2.bold())

                Text("Enter your PIN to encrypt your backup key. You'll need this PIN to restore on a new device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                SecureField("PIN", text: $keyBackupPIN)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                if !keyBackupPINError.isEmpty {
                    Text(keyBackupPINError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    verifyPINAndBackupKey()
                } label: {
                    Text("Back Up Key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyBackupPIN.isEmpty)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        keyBackupPIN = ""
                        keyBackupPINError = ""
                        showKeyBackupPINEntry = false
                    }
                }
            }
        }
    }

    // MARK: - Other Views

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

    // MARK: - Actions

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
                let encryptionService = EncryptionService()
                let service = CloudService(encryptionService: encryptionService)

                // Ensure key backup exists in iCloud (skip query if we just uploaded it)
                if !keyBackupConfirmed {
                    let hasKeyBackup = await service.hasKeyBackup()
                    if !hasKeyBackup {
                        // Need PIN to create the key backup
                        isSyncing = false
                        syncStatusText = "Ready"
                        showKeyBackupPINEntry = true
                        return
                    }
                }

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

    // MARK: - Restore Flow

    private func startRestore() {
        let encryptionService = EncryptionService()

        Task {
            let hasMasterKey = await encryptionService.hasMasterKey()

            if hasMasterKey && !allItems.isEmpty {
                // Local key exists and there are already local items, so the
                // key is correct — proceed directly with restore.
                performRestore(encryptionService: encryptionService)
            } else {
                // Either no local key, or this is a fresh install (vault is
                // empty) where the setup flow created a new key that doesn't
                // match the backed-up data. Prompt for PIN so we can restore
                // the original master key from iCloud before downloading items.
                showPINEntry = true
            }
        }
    }

    private func verifyPINAndRestore() {
        let pin = restorePIN
        pinError = ""

        Task {
            do {
                let encryptionService = EncryptionService()
                let cloudService = CloudService(encryptionService: encryptionService)

                // Fetch the key backup from iCloud
                guard let keyBackup = try await cloudService.fetchKeyBackup() else {
                    pinError = CloudError.keyBackupNotFound.localizedDescription
                    return
                }

                // Try to decrypt the master key with the entered PIN
                try await encryptionService.importWrappedMasterKey(
                    keyBackup.wrappedKey,
                    pin: pin,
                    salt: keyBackup.salt
                )

                // Success — close PIN sheet and start restore
                restorePIN = ""
                showPINEntry = false
                performRestore(encryptionService: encryptionService)
            } catch let error as CryptoKit.CryptoKitError {
                pinError = "Incorrect PIN. Please try again."
                #if DEBUG
                print("[BackupSettings] PIN decryption failed: \(error)")
                #endif
            } catch {
                pinError = error.localizedDescription
                #if DEBUG
                print("[BackupSettings] Restore key import failed: \(error)")
                #endif
            }
        }
    }

    private func performRestore(encryptionService: EncryptionService) {
        isRestoring = true
        restoreProgress = (0, 0)

        Task {
            do {
                let cloudService = CloudService(encryptionService: encryptionService)
                let restoredItems = try await vaultService.restoreFromiCloud(
                    cloudService: cloudService
                ) { completed, total in
                    restoreProgress = (completed, total)
                }
                restoredItemCount = restoredItems.count

                // Queue vision analysis & search indexing — same as all other import flows
                if !restoredItems.isEmpty {
                    vaultService.queueVisionAnalysis(for: restoredItems)
                    vaultService.queueSearchIndexing(for: restoredItems)
                }

                showRestoreSuccess = true
            } catch {
                errorMessage = "Restore failed — \(error.localizedDescription)"
                showError = true
            }
            isRestoring = false
        }
    }

    // MARK: - Key Backup Flow

    private func verifyPINAndBackupKey() {
        let pin = keyBackupPIN
        keyBackupPINError = ""

        Task {
            do {
                let encryptionService = EncryptionService()

                // Verify the PIN is correct by checking against stored hash
                guard let settings else {
                    keyBackupPINError = "Settings not found."
                    return
                }
                guard let saltData = Data(base64Encoded: settings.pinSalt) else {
                    keyBackupPINError = "PIN data missing."
                    return
                }
                let computedHash = await encryptionService.hashPIN(pin, salt: saltData)
                guard computedHash == settings.pinHash else {
                    keyBackupPINError = "Incorrect PIN. Please try again."
                    return
                }

                // PIN verified — create wrapped key and upload
                let wrappingSalt = await encryptionService.generateSalt()
                let wrappedKey = try await encryptionService.exportWrappedMasterKey(
                    pin: pin,
                    salt: wrappingSalt
                )

                let cloudService = CloudService(encryptionService: encryptionService)
                try await cloudService.uploadKeyBackup(wrappedKey: wrappedKey, salt: wrappingSalt)

                // Close sheet and resume backup
                keyBackupPIN = ""
                showKeyBackupPINEntry = false
                keyBackupConfirmed = true
                triggerManualSync()
            } catch {
                keyBackupPINError = "Failed to back up key: \(error.localizedDescription)"
            }
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
