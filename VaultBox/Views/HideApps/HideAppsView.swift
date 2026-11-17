import SwiftUI
@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

/// Picks apps to hide and turns hiding on and off.
///
/// One screen serves every entry point: Settings pushes it, while the security setup and
/// the first-run checklist present it in a sheet with a Done button (`onDone`).
///
/// Flow for a new user: allow Screen Time access, Apple's picker opens on its own, and the
/// first apps picked are hidden straight away. Asking for one more "turn it on" tap after
/// they just chose what to hide would be a step that only exists to be missed.
struct HideAppsView: View {
    let entryPoint: HideAppsEntryPoint
    var onDone: (() -> Void)?

    @Environment(HideAppsService.self) private var hideApps
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AnalyticsService.self) private var analytics

    @State private var isPickerPresented = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var isRequestingAccess = false
    @State private var accessError: String?
    @State private var pickIssue: HideAppsSelectionIssue?
    @State private var showPaywall = false
    @State private var revealError: String?

    /// Lapsed or free users can still bring hidden apps back, never just change them.
    private var isLocked: Bool {
        purchaseService.isPremiumRequired(for: .hideApps)
    }

    var body: some View {
        List {
            headerSection

            if hideApps.isAuthorized {
                hidingSection
                if hideApps.isHiding {
                    showForAWhileSection
                }
                appsSection
            } else {
                accessSection
            }

            howItWorksSection
        }
        .navigationTitle("Hide Apps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        .familyActivityPicker(isPresented: $isPickerPresented, selection: $draftSelection)
        .onChange(of: isPickerPresented) { _, isPresented in
            if !isPresented { commitPick() }
        }
        .sheet(isPresented: $showPaywall) {
            VaultBoxPaywallView(placement: .featureGate)
        }
        .alert(
            "Couldn't Show Apps",
            isPresented: Binding(
                get: { revealError != nil },
                set: { if !$0 { revealError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { revealError = nil }
        } message: {
            Text(revealError ?? "")
        }
        .task(id: hideApps.activeReveal?.until) {
            // Keep the screen honest when a reveal runs out while it is open.
            guard let until = hideApps.activeReveal?.until else { return }
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 1))
            guard !Task.isCancelled else { return }
            hideApps.refresh()
        }
        .task {
            hideApps.refresh()
            analytics.record(.hideAppsViewed(entryPoint: entryPoint))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.vaultAccent.opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.vaultAccent)
                }

                Text("Make apps disappear")
                    .font(.title3.bold())
                    .foregroundStyle(Color.vaultTextPrimary)

                Text("Hidden apps vanish from your Home Screen, App Library and search. Only VaultBox can bring them back.")
                    .font(.subheadline)
                    .foregroundStyle(Color.vaultTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Access

    private var accessSection: some View {
        Section {
            Button {
                requestAccess()
            } label: {
                HStack {
                    Label("Allow Screen Time Access", systemImage: "hourglass")
                        .foregroundStyle(Color.vaultAccent)
                    Spacer()
                    if isRequestingAccess {
                        ProgressView()
                    } else if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    }
                }
            }
            .disabled(isRequestingAccess)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("VaultBox hides apps with Apple's Screen Time. iOS asks you to confirm with Face ID or your passcode. VaultBox never sees which apps you use or for how long.")
                if let accessError {
                    Text(accessError)
                        .foregroundStyle(Color.vaultDestructive)
                }
            }
        }
    }

    // MARK: - Hiding

    private var hidingSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { hideApps.isHiding },
                set: { setHiding($0) }
            )) {
                Label("Hide Apps", systemImage: "eye.slash")
            }
            .disabled(hideApps.selectedAppCount == 0 && !hideApps.isHiding)
        } footer: {
            Text(hidingFooter)
        }
    }

    private var hidingFooter: String {
        if isLocked && hideApps.isHiding {
            return String(localized: "Your apps stay hidden. Renew Premium to change which ones.")
        }
        if hideApps.isHiding {
            return String(localized: "Hidden from your Home Screen, App Library and search.")
        }
        if hideApps.selectedAppCount == 0 {
            return String(localized: "Choose the apps to hide first.")
        }
        return String(localized: "Your apps are visible. Turn this on to hide them again.")
    }

    // MARK: - Show for a While

    private var showForAWhileSection: some View {
        Section {
            if let reveal = hideApps.activeReveal {
                HStack {
                    Label(HideAppsCopy.visibleUntil(reveal.until), systemImage: "eye")
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    Button("Hide Now") {
                        hideApps.hideNow()
                        Haptics.itemSelected()
                        analytics.record(
                            .hideAppsApplied(entryPoint: entryPoint, appCount: hideApps.hiddenAppCount)
                        )
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                }
            }

            ForEach(HideAppsRevealDuration.allCases) { duration in
                Button {
                    show(nil, for: duration)
                } label: {
                    Label(duration.showAllTitle, systemImage: "timer")
                        .foregroundStyle(Color.vaultAccent)
                }
            }
        } header: {
            Text("Show Them for a While")
        } footer: {
            Text("They hide again on their own, even if VaultBox is closed. To show just one app, tap it below.")
        }
    }

    // MARK: - Apps

    private var appsSection: some View {
        Section {
            ForEach(Array(hideApps.selection.applicationTokens), id: \.self) { token in
                appRow(token)
            }

            Button {
                openPicker()
            } label: {
                HStack {
                    Label(
                        hideApps.selectedAppCount == 0
                            ? String(localized: "Choose Apps")
                            : String(localized: "Edit Apps"),
                        systemImage: hideApps.selectedAppCount == 0 ? "plus.circle" : "pencil"
                    )
                    .foregroundStyle(Color.vaultAccent)
                    Spacer()
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.vaultPremium)
                    }
                }
            }
        } header: {
            Text("Apps to Hide")
        } footer: {
            if let issue = pickIssue ?? hideApps.selectionIssue {
                Text(issue.message)
            }
        }
    }

    @ViewBuilder
    private func appRow(_ token: ApplicationToken) -> some View {
        if hideApps.isHiding {
            Menu {
                if hideApps.isTemporarilyVisible(token) {
                    Text(HideAppsCopy.visibleUntil(hideApps.activeReveal?.until ?? .now))
                }
                ForEach(HideAppsRevealDuration.allCases) { duration in
                    Button {
                        show([token], for: duration)
                    } label: {
                        Label(duration.showOneTitle, systemImage: "timer")
                    }
                }
            } label: {
                HStack {
                    Label(token)
                        .foregroundStyle(Color.vaultTextPrimary)
                    Spacer()
                    Text(hideApps.isTemporarilyVisible(token) ? "Showing" : "Hidden")
                        .font(.caption)
                        .foregroundStyle(
                            hideApps.isTemporarilyVisible(token)
                                ? Color.vaultAccent
                                : Color.vaultTextSecondary
                        )
                }
            }
        } else {
            Label(token)
        }
    }

    // MARK: - How It Works

    private var howItWorksSection: some View {
        Section("How It Works") {
            infoRow(
                icon: "hand.tap",
                text: String(localized: "To use a hidden app, show it for a while from here or from the eye button above your vault.")
            )
            infoRow(
                icon: "arrow.uturn.backward",
                text: String(localized: "Your apps come back if you delete VaultBox or turn off its Screen Time access in Settings.")
            )
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.vaultTextSecondary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    // MARK: - Actions

    private func requestAccess() {
        guard !isLocked else {
            showPaywall = true
            return
        }
        isRequestingAccess = true
        accessError = nil
        Task {
            accessError = await hideApps.requestAuthorization()
            analytics.record(
                .hideAppsAuthorized(entryPoint: entryPoint, granted: hideApps.isAuthorized)
            )
            isRequestingAccess = false
            // Straight on to choosing apps: it's the only next step there is.
            if hideApps.isAuthorized && hideApps.selectedAppCount == 0 {
                openPicker()
            }
        }
    }

    private func openPicker() {
        guard !isLocked else {
            showPaywall = true
            return
        }
        pickIssue = nil
        draftSelection = hideApps.selection
        isPickerPresented = true
    }

    /// Runs when Apple's picker closes. Cancelling leaves the draft unchanged, so an
    /// unchanged draft means there is nothing to save.
    private func commitPick() {
        guard draftSelection != hideApps.selection else { return }
        let wasHiding = hideApps.isHiding
        pickIssue = hideApps.updateSelection(draftSelection)
        if hideApps.isHiding {
            Haptics.itemSelected()
            analytics.record(
                .hideAppsApplied(entryPoint: entryPoint, appCount: hideApps.hiddenAppCount)
            )
        } else if wasHiding {
            analytics.record(.hideAppsRevealed(entryPoint: entryPoint))
        }
    }

    private func show(_ tokens: Set<ApplicationToken>?, for duration: HideAppsRevealDuration) {
        if let error = hideApps.showTemporarily(tokens, for: duration) {
            revealError = error
            return
        }
        Haptics.itemSelected()
        analytics.record(
            .hideAppsShownTemporarily(
                entryPoint: entryPoint,
                minutes: duration.rawValue,
                scope: tokens == nil ? .all : .one
            )
        )
    }

    private func setHiding(_ hide: Bool) {
        if hide {
            guard !isLocked else {
                showPaywall = true
                return
            }
            hideApps.hide()
            Haptics.itemSelected()
            analytics.record(
                .hideAppsApplied(entryPoint: entryPoint, appCount: hideApps.hiddenAppCount)
            )
        } else {
            hideApps.showAll()
            analytics.record(.hideAppsRevealed(entryPoint: entryPoint))
        }
    }
}
