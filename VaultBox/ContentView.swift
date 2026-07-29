import SwiftUI
import SwiftData
import UIKit

private struct ParsedShare: Identifiable {
    let id = UUID()
    let shareID: String
    let keyBase64URL: String
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AppPrivacyShield.self) private var privacyShield
    @Environment(AnalyticsService.self) private var analytics

    @State private var authService: AuthService?
    @State private var vaultService: VaultService?
    @State private var breakInService: BreakInService?
    @State private var panicGestureService: PanicGestureService?
    @State private var searchEngine: SearchEngine?
    @State private var indexingProgress = IndexingProgress()
    @State private var showImporter = false
    @State private var showPostOnboardingSecuritySetup = false
    @State private var showPostSetupPaywall = false
    @State private var deferPostSetupPaywallUntilSecuritySetupCompletes = false
    @State private var isPostSetupPaywallWaitingForConfiguration = false
    /// Set when a hard-gated user was let through anyway (App Store unreachable), so the
    /// paywall doesn't immediately re-present and trap them in a loop.
    @State private var hasWaivedHardPaywallThisSession = false
    @State private var awaitingLockRouteAfterForeground = false
    @State private var privacyShieldRevealToken = 0
    @State private var pendingShareURL: URL?
    @State private var activeShare: ParsedShare?
    @State private var isDismissingForLock = false
    @State private var selectedMainTab: MainTab = .vault
    @State private var hasPendingDocumentReminderNavigation = false
    @State private var pendingDocumentReminderID: UUID?
    @State private var documentReminderNavigationTrigger = 0

    private var hasCompletedOnboarding: Bool {
        let descriptor = FetchDescriptor<AppSettings>()
        return (try? modelContext.fetch(descriptor).first?.hasCompletedOnboarding) ?? false
    }

    private var currentRoute: AppRootRoute? {
        guard let authService else { return nil }
        return determineAppRootRoute(
            hasCompletedOnboarding: hasCompletedOnboarding,
            isSetupComplete: authService.isSetupComplete,
            isUnlocked: authService.isUnlocked
        )
    }

    private var isHardPaywallRequired: Bool {
        guard purchaseService.hasResolvedPaywallConfiguration else { return false }
        return PaywallGate.isRequired(
            isHardPaywallEnabled: purchaseService.isHardPaywallEnabled
        )
    }

    var body: some View {
        ZStack {
            Group {
                if let authService, let vaultService, let currentRoute {
                    if shouldRenderMainShell(for: currentRoute) {
                        VaultBoxMainTabView(
                            authService: authService,
                            vaultService: vaultService,
                            searchEngine: searchEngine,
                            indexingProgress: indexingProgress,
                            panicGestureService: panicGestureService,
                            reminderNavigationTrigger: documentReminderNavigationTrigger,
                            targetReminderID: pendingDocumentReminderID,
                            onAppear: { setupPanicGesture(authService: authService) },
                            selection: $selectedMainTab,
                            showImporter: $showImporter
                        )
                            .overlay {
                                if currentRoute == .lock {
                                    LockedAppOverlay(
                                        authService: authService,
                                        onPresented: handleLockScreenPresented
                                    )
                                }
                            }
                    } else if currentRoute == .onboarding {
                        OnboardingView(authService: authService)
                    } else {
                        PINSetupView(authService: authService)
                    }
                } else {
                    ProgressView()
                        .onAppear { initializeServices() }
                }
            }

            if privacyShield.isVisible {
                AppPrivacyShieldView()
                    .zIndex(1)
            }
        }
        .onChange(of: currentRoute) { oldRoute, newRoute in
            let decision = determinePostSetupOverlayDecision(oldRoute: oldRoute, newRoute: newRoute)
            if decision.showSecuritySetup {
                deferPostSetupPaywallUntilSecuritySetupCompletes = decision.deferPaywallUntilSecuritySetupCompletes
                showPostOnboardingSecuritySetup = true
            }
            if shouldDismissMainShellPresentations(oldRoute: oldRoute, newRoute: newRoute) {
                dismissActivePresentationsForLock()
            }
            // Present pending share link after authentication completes
            if newRoute == .main {
                presentPendingShareIfNeeded()
                routeToPendingDocumentReminderIfNeeded()
                presentHardPaywallIfNeeded()
            }
            attemptPrivacyShieldReveal()
        }
        .onChange(of: pendingShareURL) { _, newURL in
            // If a new URL arrives while already authenticated, present immediately
            if newURL != nil, currentRoute == .main {
                presentPendingShareIfNeeded()
            }
        }
        .onChange(of: purchaseService.hasResolvedCustomerInfo) { _, hasResolved in
            guard hasResolved else { return }
            handlePremiumStatusChange(isPremium: purchaseService.isPremium)
            presentHardPaywallIfNeeded()
        }
        .onChange(of: purchaseService.hasResolvedPaywallConfiguration) { _, hasResolved in
            guard hasResolved else { return }
            if isPostSetupPaywallWaitingForConfiguration {
                isPostSetupPaywallWaitingForConfiguration = false
                showPostSetupPaywall = true
            }
            presentHardPaywallIfNeeded()
        }
        .onChange(of: purchaseService.isHardPaywallEnabled) { _, isEnabled in
            if !isEnabled {
                hasWaivedHardPaywallThisSession = true
            }
            presentHardPaywallIfNeeded()
        }
        .onChange(of: purchaseService.isPremium) { _, isPremium in
            guard purchaseService.hasResolvedCustomerInfo else { return }
            handlePremiumStatusChange(isPremium: isPremium)
            if isPremium {
                PaywallGate.markSatisfied()
                showPostSetupPaywall = false
            } else {
                presentHardPaywallIfNeeded()
            }
        }
        .fullScreenCover(
            isPresented: $showPostOnboardingSecuritySetup,
            onDismiss: handlePostOnboardingSecuritySetupDismissed
        ) {
            if let authService {
                PostOnboardingSecuritySetupView(
                    authService: authService,
                    includeLocation: purchaseService.isPremium,
                    onContinue: { snapshot in
                        analytics.record(.securitySetupCompleted(
                            cameraGranted: snapshot?.cameraState == .enabled,
                            notificationsGranted: snapshot?.notificationState == .enabled
                        ))
                        showPostOnboardingSecuritySetup = false
                    }
                )
                .task { analytics.record(.securitySetupViewed) }
            }
        }
        .fullScreenCover(isPresented: $showPostSetupPaywall) {
            VaultBoxPaywallView(
                isHard: isHardPaywallRequired,
                onStoreUnavailableContinue: {
                    guard isHardPaywallRequired, !purchaseService.isPremium else { return }
                    hasWaivedHardPaywallThisSession = true
                }
            )
                .interactiveDismissDisabled(isHardPaywallRequired)
        }
        .fullScreenCover(item: $activeShare, onDismiss: {
            // Only clear the pending URL when the user explicitly dismissed
            // the viewer (not when the lock cycle killed it).
            if isDismissingForLock {
                isDismissingForLock = false
            } else {
                pendingShareURL = nil
            }
        }) { share in
            SharedContentViewer(
                shareID: share.shareID,
                keyBase64URL: share.keyBase64URL,
                sharingService: SharingService()
            )
        }
        .onOpenURL { url in
            pendingShareURL = url
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            guard let url = userActivity.webpageURL else { return }
            pendingShareURL = url
        }
        .onReceive(NotificationCenter.default.publisher(for: .universalLinkReceived)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                pendingShareURL = url
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentReminderNotificationReceived)) { notification in
            let rawID = notification.userInfo?["reminderID"] as? String
            pendingDocumentReminderID = rawID.flatMap(UUID.init(uuidString:))
            hasPendingDocumentReminderNavigation = true
            routeToPendingDocumentReminderIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                handleDidEnterBackground()
            case .inactive:
                handleWillResignActive()
            case .active:
                handleDidBecomeActive()
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            handleWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            handleDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            handleDidBecomeActive()
        }
    }

    private func setupPanicGesture(authService: AuthService) {
        panicGestureService = makePanicGestureService(
            existingService: panicGestureService,
            authService: authService,
            modelContext: modelContext,
            isPremium: purchaseService.isPremium
        )
    }

    private func handlePremiumStatusChange(isPremium: Bool) {
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else {
            if isPremium {
                panicGestureService?.startMonitoring()
            } else {
                panicGestureService?.stopMonitoring()
            }
            return
        }

        if isPremium {
            if settings.panicGestureEnabled {
                panicGestureService?.startMonitoring()
            } else {
                panicGestureService?.stopMonitoring()
            }
            return
        }

        panicGestureService?.stopMonitoring()
        var hasSettingsChanges = false

        if settings.panicGestureEnabled {
            settings.panicGestureEnabled = false
            hasSettingsChanges = true
        }

        if settings.iCloudBackupEnabled {
            settings.iCloudBackupEnabled = false
            hasSettingsChanges = true
        }

        if authService?.isDecoyMode == true {
            authService?.lock()
        }

        if hasSettingsChanges {
            try? modelContext.save()
        }

        Task { @MainActor in
            let iconService = AppIconService()
            if iconService.getCurrentIcon() != nil {
                try? await iconService.setIcon(nil)
            }
        }
    }

    private func handleDidEnterBackground() {
        privacyShieldRevealToken &+= 1
        privacyShield.isVisible = true
        guard let authService else { return }
        guard authService.isSetupComplete else { return }

        if shouldLockImmediatelyForDisguise(iconName: UIApplication.shared.alternateIconName) {
            authService.lock()
            return
        }

        authService.recordBackgroundEntry()
    }

    private func handleWillResignActive() {
        guard !privacyShield.shouldSuppressForIconChange() else { return }
        privacyShieldRevealToken &+= 1
        privacyShield.isVisible = true
    }

    private func handleDidBecomeActive() {
        if privacyShield.finishIconChangeOnActive() {
            privacyShield.isVisible = false
        }
        privacyShieldRevealToken &+= 1

        var shouldAwaitLockRoute = false
        if let authService, authService.isSetupComplete, authService.isUnlocked, authService.shouldAutoLock() {
            shouldAwaitLockRoute = true
            authService.lock()
        }
        awaitingLockRouteAfterForeground = shouldAwaitLockRoute

        if !shouldAwaitLockRoute {
            Task {
                await vaultService?.repairConfirmedDocumentReminders()
            }
        }
        attemptPrivacyShieldReveal(token: privacyShieldRevealToken)
    }

    private func attemptPrivacyShieldReveal(token: Int? = nil) {
        guard scenePhase == .active else { return }
        guard !awaitingLockRouteAfterForeground else { return }

        let expectedToken = token ?? privacyShieldRevealToken
        Task { @MainActor in
            // Wait for the route change transaction to settle before revealing content.
            await Task.yield()
            await Task.yield()

            guard expectedToken == privacyShieldRevealToken else { return }
            guard scenePhase == .active else { return }
            guard !awaitingLockRouteAfterForeground else { return }

            awaitingLockRouteAfterForeground = false
            privacyShield.isVisible = false
        }
    }

    private func handleLockScreenPresented() {
        guard awaitingLockRouteAfterForeground else { return }
        awaitingLockRouteAfterForeground = false
        attemptPrivacyShieldReveal(token: privacyShieldRevealToken)
    }

    private func handlePostOnboardingSecuritySetupDismissed() {
        let paywallDecision = resolveDeferredPostSetupPaywall(
            shouldDefer: deferPostSetupPaywallUntilSecuritySetupCompletes
        )
        deferPostSetupPaywallUntilSecuritySetupCompletes = paywallDecision.shouldDefer

        guard paywallDecision.showPaywall else {
            showPostSetupPaywall = false
            return
        }

        if purchaseService.hasResolvedPaywallConfiguration {
            showPostSetupPaywall = true
        } else {
            isPostSetupPaywallWaitingForConfiguration = true
        }
    }

    /// Re-presents the hard paywall for a gated, non-subscribed user — including on a
    /// cold launch after they force-quit rather than choose a plan.
    private func presentHardPaywallIfNeeded() {
        guard !showPostSetupPaywall else { return }
        guard shouldPresentHardPaywall(
            route: currentRoute,
            isGateRequired: isHardPaywallRequired,
            isPremium: purchaseService.isPremium,
            hasResolvedCustomerInfo: purchaseService.hasResolvedCustomerInfo,
            hasResolvedPaywallConfiguration: purchaseService.hasResolvedPaywallConfiguration,
            hasWaivedThisSession: hasWaivedHardPaywallThisSession
        ) else { return }
        showPostSetupPaywall = true
    }

    private func presentPendingShareIfNeeded() {
        guard let url = pendingShareURL,
              let parsed = SharingService.parseShareURL(url) else { return }
        activeShare = ParsedShare(
            shareID: parsed.shareID,
            keyBase64URL: parsed.keyBase64URL
        )
    }

    private func routeToPendingDocumentReminderIfNeeded() {
        guard hasPendingDocumentReminderNavigation, currentRoute == .main else { return }
        selectedMainTab = .settings
        documentReminderNavigationTrigger &+= 1
        hasPendingDocumentReminderNavigation = false
    }

    private func dismissActivePresentationsForLock() {
        showImporter = false
        showPostOnboardingSecuritySetup = false
        showPostSetupPaywall = false
        isPostSetupPaywallWaitingForConfiguration = false

        // Mark that any share viewer dismiss is caused by the lock cycle,
        // so pendingShareURL survives and can be re-presented after unlock.
        if activeShare != nil {
            isDismissingForLock = true
            activeShare = nil
        }

        let candidateScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windowScene = candidateScenes.first {
            $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive
        }
        guard let rootViewController = windowScene?.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return
        }

        rootViewController.dismiss(animated: false)
    }

    // MARK: - Service Initialization

    private func initializeServices() {
        let encryptionService = EncryptionService()
        let purchaseService = self.purchaseService
        let breakIn = BreakInService(
            modelContext: modelContext,
            hasPremiumAccess: { purchaseService.isPremium }
        )
        let auth = AuthService(
            encryptionService: encryptionService,
            modelContext: modelContext,
            hasPremiumAccess: { purchaseService.isPremium },
            onBreakInThresholdReached: { attemptedPIN, _ in
                _ = await breakIn.captureIntruder(attemptedPIN: attemptedPIN)
            }
        )
        let vault = VaultService(
            encryptionService: encryptionService,
            modelContext: modelContext,
            hasPremiumAccess: { purchaseService.isPremium }
        )
        authService = auth
        vaultService = vault
        breakInService = breakIn

        Task {
            await vault.repairConfirmedDocumentReminders()
        }

        // Initialize Ask My Vault search services
        initializeSearchServices(encryptionService: encryptionService, vault: vault)
    }

    private func initializeSearchServices(encryptionService: EncryptionService, vault: VaultService) {
        Task { @MainActor in
            do {
                let searchIndexService = try await SearchIndexService.open()
                let embeddingService = EmbeddingService()
                let ingestion = IngestionService(
                    encryptionService: encryptionService,
                    searchIndexService: searchIndexService,
                    embeddingService: embeddingService
                )
                let engine = SearchEngine(
                    searchIndexService: searchIndexService,
                    embeddingService: embeddingService
                )

                vault.configureSearchIndex(ingestionService: ingestion, indexingProgress: self.indexingProgress)
                self.searchEngine = engine

                // Index any items that haven't been indexed yet
                vault.indexUnindexedItems()
            } catch {
                #if DEBUG
                print("[ContentView] Failed to initialize search services: \(error)")
                #endif
            }
        }
    }
}
