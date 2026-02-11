import SwiftUI
import SwiftData
import UIKit

enum AppRootRoute: Equatable {
    case setupPIN
    case lock
    case main
}

func determineAppRootRoute(isSetupComplete: Bool, isUnlocked: Bool) -> AppRootRoute {
    if isUnlocked {
        return .main
    }
    if !isSetupComplete {
        return .setupPIN
    }
    return .lock
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var authService: AuthService?
    @State private var vaultService: VaultService?
    @State private var breakInService: BreakInService?
    @State private var panicGestureService: PanicGestureService?
    @State private var showImporter = false
    @State private var showPrivacyShield = false

    var body: some View {
        ZStack {
            Group {
                if let authService, let vaultService {
                    switch determineAppRootRoute(
                        isSetupComplete: authService.isSetupComplete,
                        isUnlocked: authService.isUnlocked
                    ) {
                    case .setupPIN:
                        PINSetupView(authService: authService)
                    case .lock:
                        LockScreenView(authService: authService)
                    case .main:
                        mainTabView(authService: authService, vaultService: vaultService)
                    }
                } else {
                    ProgressView()
                        .onAppear { initializeServices() }
                }
            }

            if showPrivacyShield {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
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
        TabView {
            // swiftlint:disable:previous closure_body_length
            VaultGridView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label("Vault", systemImage: "lock.shield")
                }

            AlbumGridView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label("Albums", systemImage: "rectangle.stack")
                }

            CameraView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }

            SettingsView(authService: authService, vaultService: vaultService)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .onAppear {
            setupPanicGesture(authService: authService)
        }
        .sheet(isPresented: $showImporter) {
            ImportView(
                vaultService: vaultService,
                album: nil,
                onDismiss: { showImporter = false }
            )
        }
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
           settings.panicGestureEnabled {
            service.startMonitoring()
        }
    }

    private func handleDidEnterBackground() {
        showPrivacyShield = true
        guard let authService else { return }
        guard authService.isSetupComplete else { return }
        authService.recordBackgroundEntry()
    }

    private func handleWillResignActive() {
        showPrivacyShield = true
    }

    private func handleDidBecomeActive() {
        if let authService, authService.isSetupComplete, authService.isUnlocked, authService.shouldAutoLock() {
            authService.lock()
        }

        Task { @MainActor in
            // Keep content obscured until route changes (lock/main) are committed.
            await Task.yield()
            if scenePhase == .active {
                showPrivacyShield = false
            }
        }
    }

    // MARK: - Service Initialization

    private func initializeServices() {
        let encryptionService = EncryptionService()
        let auth = AuthService(encryptionService: encryptionService, modelContext: modelContext)
        let vault = VaultService(encryptionService: encryptionService, modelContext: modelContext)
        let breakIn = BreakInService(modelContext: modelContext)
        authService = auth
        vaultService = vault
        breakInService = breakIn
    }
}
