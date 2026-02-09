import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var authService: AuthService?
    @State private var vaultService: VaultService?
    @State private var breakInService: BreakInService?
    @State private var panicGestureService: PanicGestureService?
    @State private var showImporter = false

    private var isSetupComplete: Bool {
        guard authService != nil else { return false }
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContext.fetch(descriptor).first else { return false }
        return settings.isSetupComplete
    }

    var body: some View {
        Group {
            if let authService, let vaultService {
                if !isSetupComplete {
                    PINSetupView(authService: authService)
                } else if !authService.isUnlocked {
                    LockScreenView(authService: authService)
                } else {
                    mainTabView(authService: authService, vaultService: vaultService)
                }
            } else {
                ProgressView()
                    .onAppear { initializeServices() }
            }
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
