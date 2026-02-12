import SwiftUI
import SwiftData

private enum SettingsDestination: String {
    case breakInLog
    case appIconPicker
    case backupSettings
    case wifiTransfer
}

struct SettingsView: View {
    let authService: AuthService
    let vaultService: VaultService

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    @State private var viewModel: SettingsViewModel?
    @State private var showPaywall = false
    @State private var showChangePIN = false
    @State private var showDecoySetup = false
    @State private var showDecoyInfo = false
    @State private var showBreakInLog = false
    @State private var showAppIconPicker = false
    @State private var showBackupSettings = false
    @State private var showWiFiTransfer = false
    @State private var showClearBreakInConfirm = false
    @State private var showRestoreAlert = false
    @State private var restoreMessage = ""
    @State private var showBreakInPermissionSetup = false
    @SceneStorage("settingsActiveDestination") private var activeDestinationRawValue = ""

    @Query private var settingsQuery: [AppSettings]

    private var settings: AppSettings? { settingsQuery.first }
    private var hasConfiguredAlternateIcons: Bool {
        AppIconService().availableIcons().count > 1
    }

    var body: some View {
        NavigationStack {
            List {
                if !authService.isDecoyMode {
                    securitySection
                    appearanceSection
                    backupSection
                    transferSection
                    privacySection
                }
                storageSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear {
                if viewModel == nil {
                    viewModel = SettingsViewModel(authService: authService, vaultService: vaultService)
                }
                restoreLastDestinationIfNeeded()
            }
            .fullScreenCover(isPresented: $showPaywall) {
                VaultBoxPaywallView()
            }
            .sheet(isPresented: $showChangePIN) {
                NavigationStack {
                    SecuritySettingsView(authService: authService, mode: .changePIN)
                }
                .presentationBackground(Color.vaultBackground)
            }
            .sheet(isPresented: $showDecoySetup) {
                NavigationStack {
                    SecuritySettingsView(authService: authService, mode: .decoySetup)
                }
                .presentationBackground(Color.vaultBackground)
            }
            .sheet(isPresented: $showDecoyInfo) {
                NavigationStack {
                    DecoyVaultInfoView()
                }
                .presentationBackground(Color.vaultBackground)
            }
            .sheet(isPresented: $showBreakInPermissionSetup) {
                BreakInPermissionSetupView(
                    includeLocation: purchaseService.isPremium,
                    title: "Complete Break-in Setup",
                    subtitle: "Choose which break-in protections to enable. We only show each permission prompt after you tap that step.",
                    continueButtonTitle: "Done",
                    onContinue: { showBreakInPermissionSetup = false }
                )
            }
            .navigationDestination(isPresented: $showBreakInLog) {
                BreakInLogView()
            }
            .navigationDestination(isPresented: $showAppIconPicker) {
                AppIconPickerView()
            }
            .navigationDestination(isPresented: $showBackupSettings) {
                BackupSettingsView(vaultService: vaultService)
            }
            .navigationDestination(isPresented: $showWiFiTransfer) {
                WiFiTransferView(vaultService: vaultService, authService: authService)
            }
            .onChange(of: showBreakInLog) { _, isPresented in
                updatePersistedDestination(isPresented: isPresented, destination: .breakInLog)
            }
            .onChange(of: showAppIconPicker) { _, isPresented in
                updatePersistedDestination(isPresented: isPresented, destination: .appIconPicker)
            }
            .onChange(of: showBackupSettings) { _, isPresented in
                updatePersistedDestination(isPresented: isPresented, destination: .backupSettings)
            }
            .onChange(of: showWiFiTransfer) { _, isPresented in
                updatePersistedDestination(isPresented: isPresented, destination: .wifiTransfer)
            }
            .alert("Clear Break-in Log?", isPresented: $showClearBreakInConfirm) {
                Button("Clear All", role: .destructive) {
                    viewModel?.clearBreakInLog(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all break-in attempt records.")
            }
            .alert("Restore Purchases", isPresented: $showRestoreAlert) {
                Button("OK") {}
            } message: {
                Text(restoreMessage)
            }
        }
    }

    private func restoreLastDestinationIfNeeded() {
        guard let destination = SettingsDestination(rawValue: activeDestinationRawValue) else { return }
        switch destination {
        case .breakInLog:
            showBreakInLog = true
        case .appIconPicker:
            showAppIconPicker = true
        case .backupSettings:
            showBackupSettings = true
        case .wifiTransfer:
            showWiFiTransfer = true
        }
    }

    private func updatePersistedDestination(isPresented: Bool, destination: SettingsDestination) {
        if isPresented {
            activeDestinationRawValue = destination.rawValue
            return
        }

        if !showBreakInLog && !showAppIconPicker && !showBackupSettings && !showWiFiTransfer {
            activeDestinationRawValue = ""
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section("Security") {
            Button {
                showChangePIN = true
            } label: {
                Label("Change PIN", systemImage: "lock.rotation")
                    .foregroundStyle(Color.vaultTextPrimary)
            }

            if let settings {
                Toggle(isOn: Binding(
                    get: { settings.biometricsEnabled },
                    set: { viewModel?.toggleBiometrics(enabled: $0, modelContext: modelContext) }
                )) {
                    Label(
                        authService.isBiometricsAvailable() ? "Face ID" : "Touch ID",
                        systemImage: "faceid"
                    )
                }
                .disabled(!authService.isBiometricsAvailable())

                Picker(selection: Binding(
                    get: { settings.autoLockSeconds },
                    set: { viewModel?.setAutoLock(seconds: $0, modelContext: modelContext) }
                )) {
                    ForEach(Constants.autoLockOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                } label: {
                    Label("Auto-Lock", systemImage: "clock.arrow.circlepath")
                }
            }

            // Decoy Vault (premium)
            Button {
                if purchaseService.isPremiumRequired(for: .decoyVault) {
                    showPaywall = true
                } else {
                    showDecoySetup = true
                }
            } label: {
                HStack {
                    Label("Decoy Vault", systemImage: "eye.slash")
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    if purchaseService.isPremiumRequired(for: .decoyVault) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    } else if settings?.decoyPINHash != nil {
                        Text("Configured")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                    }
                }
            }

            Button {
                showDecoyInfo = true
            } label: {
                HStack {
                    Label("What is Decoy Vault?", systemImage: "info.circle")
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.vaultTextSecondary)
                }
            }

            // Panic Gesture (premium)
            if let settings {
                HStack {
                    Label("Panic Gesture", systemImage: "hand.raised")
                    Spacer()
                    if purchaseService.isPremiumRequired(for: .panicGesture) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { settings.panicGestureEnabled },
                            set: { viewModel?.togglePanicGesture(enabled: $0, modelContext: modelContext) }
                        ))
                        .labelsHidden()
                    }
                }
                .onTapGesture {
                    if purchaseService.isPremiumRequired(for: .panicGesture) {
                        showPaywall = true
                    }
                }
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Appearance") {
            Button {
                if !hasConfiguredAlternateIcons {
                    return
                }
                if purchaseService.isPremiumRequired(for: .fakeAppIcon) {
                    showPaywall = true
                } else {
                    showAppIconPicker = true
                }
            } label: {
                HStack {
                    Label("App Icon", systemImage: "app.badge")
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    if !hasConfiguredAlternateIcons {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                    } else if purchaseService.isPremiumRequired(for: .fakeAppIcon) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                    }
                }
            }
            .disabled(!hasConfiguredAlternateIcons)

            if let settings {
                Picker(selection: Binding(
                    get: { settings.themeMode },
                    set: { viewModel?.setThemeMode($0, modelContext: modelContext) }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
            }
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        Section("Backup") {
            Button {
                if purchaseService.isPremiumRequired(for: .iCloudBackup) {
                    showPaywall = true
                } else {
                    showBackupSettings = true
                }
            } label: {
                HStack {
                    Label("iCloud Backup", systemImage: "icloud")
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    if purchaseService.isPremiumRequired(for: .iCloudBackup) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    } else if settings?.iCloudBackupEnabled == true {
                        Text("On")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Transfer Section

    private var transferSection: some View {
        Section("Transfer") {
            Button {
                if purchaseService.isPremiumRequired(for: .wifiTransfer) {
                    showPaywall = true
                } else {
                    showWiFiTransfer = true
                }
            } label: {
                HStack {
                    Label("Wi-Fi Transfer", systemImage: "wifi")
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    if purchaseService.isPremiumRequired(for: .wifiTransfer) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.vaultTextSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section("Privacy") {
            if let settings {
                Toggle(isOn: Binding(
                    get: { settings.breakInAlertsEnabled },
                    set: { handleBreakInAlertsToggleChange($0) }
                )) {
                    Label("Break-in Alerts", systemImage: "exclamationmark.shield")
                }
            }

            Button {
                showBreakInLog = true
            } label: {
                Label("View Break-in Log", systemImage: "list.bullet.rectangle")
                    .foregroundStyle(Color.vaultTextPrimary)
            }

            Button {
                showClearBreakInConfirm = true
            } label: {
                Label("Clear Break-in Log", systemImage: "trash")
                    .foregroundStyle(Color.vaultDestructive)
            }
        }
    }

    private func handleBreakInAlertsToggleChange(_ enabled: Bool) {
        guard let viewModel else { return }
        _ = viewModel.toggleBreakInAlerts(enabled: enabled, modelContext: modelContext)
        guard enabled else { return }
        showBreakInPermissionSetup = true
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        Section("Storage") {
            LabeledContent("Items", value: viewModel?.itemCountText(purchaseService: purchaseService) ?? "—")
            LabeledContent("Storage Used", value: viewModel?.storageUsedText() ?? "—")

            if !purchaseService.isPremium {
                Button {
                    showPaywall = true
                } label: {
                    Label("Upgrade to Premium", systemImage: "star.fill")
                        .foregroundStyle(Color.vaultPremium)
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            Link(destination: URL(string: "https://apps.apple.com/app/id0000000000")!) {
                Label("Rate VaultBox", systemImage: "star")
                    .foregroundStyle(Color.vaultTextPrimary)
            }

            Link(destination: URL(string: "https://vaultbox.pacsix.com/privacy/")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundStyle(Color.vaultTextPrimary)
            }

            Link(destination: URL(string: "https://vaultbox.pacsix.com/terms/")!) {
                Label("Terms of Service", systemImage: "doc.text")
                    .foregroundStyle(Color.vaultTextPrimary)
            }

            Button {
                Task {
                    do {
                        let restored = try await purchaseService.restorePurchases()
                        restoreMessage = restored
                            ? "Your premium subscription has been restored."
                            : "No active subscription found."
                        showRestoreAlert = true
                    } catch {
                        restoreMessage = "Couldn't restore purchases. Please try again."
                        showRestoreAlert = true
                    }
                }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
                    .foregroundStyle(Color.vaultTextPrimary)
            }

            LabeledContent("Version", value: appVersion)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct DecoyVaultInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Decoy Vault lets you unlock VaultBox with a second PIN that shows a separate, harmless set of items.")
                    Text("How it works")
                        .font(.headline)
                    Text("1. Set a separate decoy PIN in Security settings.")
                    Text("2. Enter that decoy PIN on the lock screen.")
                    Text("3. VaultBox opens a filtered view that only shows decoy items.")
                }
                .foregroundStyle(Color.vaultTextPrimary)

                Group {
                    Text("Important details")
                        .font(.headline)
                    Text("• There is no visible 'decoy mode' badge.")
                    Text("• Real vault items stay hidden while decoy mode is active.")
                    Text("• To make decoy mode look normal, add a few non-sensitive photos/videos while unlocked with the decoy PIN.")
                    Text("• Use a decoy PIN that is different from your real PIN.")
                }
                .foregroundStyle(Color.vaultTextPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Constants.standardPadding)
        }
        .background(Color.vaultBackground.ignoresSafeArea())
        .navigationTitle("Decoy Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .toolbarBackground(Color.vaultBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
