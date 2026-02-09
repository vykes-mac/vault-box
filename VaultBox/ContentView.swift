import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var authService: AuthService?
    @State private var vaultService: VaultService?
    @State private var showImporter = false

    private var isSetupComplete: Bool {
        guard let auth = authService else { return false }
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
            VaultGridView(vaultService: vaultService)
                .tabItem {
                    Label("Vault", systemImage: "lock.shield")
                }

            AlbumGridView(vaultService: vaultService)
                .tabItem {
                    Label("Albums", systemImage: "rectangle.stack")
                }

            // Camera tab — placeholder until F30
            cameraPlaceholder
                .tabItem {
                    Label("Camera", systemImage: "camera")
                }

            // Settings tab — placeholder until F20
            settingsPlaceholder
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .sheet(isPresented: $showImporter) {
            ImportView(
                vaultService: vaultService,
                album: nil,
                onDismiss: { showImporter = false }
            )
        }
    }

    private var cameraPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera")
                .font(.system(size: 60))
                .foregroundStyle(Color.vaultTextSecondary)
            Text("Camera")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.vaultTextPrimary)
            Text("Direct-to-vault capture coming soon")
                .font(.body)
                .foregroundStyle(Color.vaultTextSecondary)
        }
    }

    private var settingsPlaceholder: some View {
        NavigationStack {
            List {
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                }
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Service Initialization

    private func initializeServices() {
        let encryptionService = EncryptionService()
        let auth = AuthService(encryptionService: encryptionService, modelContext: modelContext)
        let vault = VaultService(encryptionService: encryptionService, modelContext: modelContext)
        authService = auth
        vaultService = vault
    }
}
