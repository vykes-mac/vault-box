import SwiftUI
import SwiftData
import UIKit

enum AppRootRoute: Equatable {
    case onboarding
    case setupPIN
    case lock
    case main
}

private enum MainTab: Int {
    case vault = 0
    case albums = 1
    case camera = 2
    case settings = 3
}

@MainActor
@Observable
final class AppPrivacyShield {
    var isVisible = true
}

func determineAppRootRoute(hasCompletedOnboarding: Bool, isSetupComplete: Bool, isUnlocked: Bool) -> AppRootRoute {
    if isUnlocked {
        return .main
    }
    if !hasCompletedOnboarding && !isSetupComplete {
        return .onboarding
    }
    if !isSetupComplete {
        return .setupPIN
    }
    return .lock
}

struct PostSetupOverlayDecision: Equatable {
    let showSecuritySetup: Bool
    let deferPaywallUntilSecuritySetupCompletes: Bool

    static let none = PostSetupOverlayDecision(
        showSecuritySetup: false,
        deferPaywallUntilSecuritySetupCompletes: false
    )
}

func determinePostSetupOverlayDecision(oldRoute: AppRootRoute?, newRoute: AppRootRoute?) -> PostSetupOverlayDecision {
    guard newRoute == .main else { return .none }
    guard oldRoute == .onboarding || oldRoute == .setupPIN else { return .none }

    return PostSetupOverlayDecision(
        showSecuritySetup: true,
        deferPaywallUntilSecuritySetupCompletes: true
    )
}

func resolveDeferredPostSetupPaywall(shouldDefer: Bool) -> (showPaywall: Bool, shouldDefer: Bool) {
    guard shouldDefer else { return (false, false) }
    return (true, false)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(AppPrivacyShield.self) private var privacyShield

    @State private var authService: AuthService?
    @State private var vaultService: VaultService?
    @State private var breakInService: BreakInService?
    @State private var panicGestureService: PanicGestureService?
    @State private var showImporter = false
    @State private var showPostOnboardingSecuritySetup = false
    @State private var showPostSetupPaywall = false
    @State private var deferPostSetupPaywallUntilSecuritySetupCompletes = false
    @State private var awaitingLockRouteAfterForeground = false
    @State private var privacyShieldRevealToken = 0
    @SceneStorage("mainTabSelection") private var selectedMainTabRawValue = MainTab.vault.rawValue

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

    var body: some View {
        ZStack {
            Group {
                if let authService, let vaultService, let currentRoute {
                    switch currentRoute {
                    case .onboarding:
                        OnboardingView(authService: authService)
                    case .setupPIN:
                        PINSetupView(authService: authService)
                    case .lock:
                        LockScreenView(
                            authService: authService,
                            onPresented: handleLockScreenPresented
                        )
                    case .main:
                        mainTabView(authService: authService, vaultService: vaultService)
                    }
                } else {
                    ProgressView()
                        .onAppear { initializeServices() }
                }
            }

            if privacyShield.isVisible {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .zIndex(1)
            }
        }
        .onChange(of: currentRoute) { oldRoute, newRoute in
            let decision = determinePostSetupOverlayDecision(oldRoute: oldRoute, newRoute: newRoute)
            if decision.showSecuritySetup {
                deferPostSetupPaywallUntilSecuritySetupCompletes = decision.deferPaywallUntilSecuritySetupCompletes
                showPostOnboardingSecuritySetup = true
            }
            attemptPrivacyShieldReveal()
        }
        .onChange(of: purchaseService.hasResolvedCustomerInfo) { _, hasResolved in
            guard hasResolved else { return }
            handlePremiumStatusChange(isPremium: purchaseService.isPremium)
        }
        .onChange(of: purchaseService.isPremium) { _, isPremium in
            guard purchaseService.hasResolvedCustomerInfo else { return }
            handlePremiumStatusChange(isPremium: isPremium)
        }
        .fullScreenCover(
            isPresented: $showPostOnboardingSecuritySetup,
            onDismiss: handlePostOnboardingSecuritySetupDismissed
        ) {
            if let authService {
                PostOnboardingSecuritySetupView(
                    authService: authService,
                    includeLocation: purchaseService.isPremium,
                    onContinue: {
                        showPostOnboardingSecuritySetup = false
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showPostSetupPaywall) {
            VaultBoxPaywallView()
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

    // MARK: - Tab View

    private func mainTabView(authService: AuthService, vaultService: VaultService) -> some View {
        TabView(selection: selectedMainTabBinding) {
            // swiftlint:disable:previous closure_body_length
            VaultGridView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label("Vault", systemImage: "lock.shield")
                }
                .tag(MainTab.vault)

            AlbumGridView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label("Albums", systemImage: "rectangle.stack")
                }
                .tag(MainTab.albums)

            CameraView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }
                .tag(MainTab.camera)

            SettingsView(authService: authService, vaultService: vaultService)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(MainTab.settings)
        }
        .onAppear {
            setupPanicGesture(authService: authService)
        }
        .fullScreenCover(isPresented: $showImporter) {
            ImportView(
                vaultService: vaultService,
                album: nil,
                isDecoyMode: authService.isDecoyMode,
                onDismiss: { showImporter = false }
            )
        }
    }

    private var selectedMainTabBinding: Binding<MainTab> {
        Binding(
            get: { MainTab(rawValue: selectedMainTabRawValue) ?? .vault },
            set: { selectedMainTabRawValue = $0.rawValue }
        )
    }

    private func setupPanicGesture(authService: AuthService) {
        guard panicGestureService == nil else { return }
        let service = PanicGestureService()
        service.onPanicTriggered = {
            authService.lock()
        }
        panicGestureService = service

        // Check if panic gesture is enabled
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first,
           settings.panicGestureEnabled,
           purchaseService.isPremium {
            service.startMonitoring()
        }
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
        authService.recordBackgroundEntry()
    }

    private func handleWillResignActive() {
        privacyShieldRevealToken &+= 1
        privacyShield.isVisible = true
    }

    private func handleDidBecomeActive() {
        privacyShieldRevealToken &+= 1

        var shouldAwaitLockRoute = false
        if let authService, authService.isSetupComplete, authService.isUnlocked, authService.shouldAutoLock() {
            shouldAwaitLockRoute = true
            authService.lock()
        }
        awaitingLockRouteAfterForeground = shouldAwaitLockRoute

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
        showPostSetupPaywall = paywallDecision.showPaywall
        deferPostSetupPaywallUntilSecuritySetupCompletes = paywallDecision.shouldDefer
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
    }
}
