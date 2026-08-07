import SwiftData
import SwiftUI
import UIKit

enum MainTab: Hashable {
    case vault
    case albums
    case camera
    case smartSearch
    case settings
}

struct VaultBoxMainTabView: View {
    let authService: AuthService
    let vaultService: VaultService
    let searchEngine: SearchEngine?
    let indexingProgress: IndexingProgress
    let panicGestureService: PanicGestureService?
    let reminderNavigationTrigger: Int
    let targetReminderID: UUID?
    let onAppear: () -> Void

    @Binding var selection: MainTab
    @Binding var showImporter: Bool

    var body: some View {
        TabView(selection: $selection) {
            VaultGridView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label(
                        String(localized: "tab.vault", defaultValue: "Vault"),
                        systemImage: "lock.shield"
                    )
                }
                .tag(MainTab.vault)

            AlbumGridView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label(
                        String(localized: "tab.albums", defaultValue: "Albums"),
                        systemImage: "rectangle.stack"
                    )
                }
                .tag(MainTab.albums)

            CameraView(vaultService: vaultService, isDecoyMode: authService.isDecoyMode)
                .tabItem {
                    Label(
                        String(localized: "tab.camera", defaultValue: "Camera"),
                        systemImage: "camera"
                    )
                }
                .tag(MainTab.camera)

            AskVaultView(
                vaultService: vaultService,
                searchEngine: searchEngine,
                indexingProgress: indexingProgress,
                isDecoyMode: authService.isDecoyMode
            )
            .tabItem {
                Label(
                    String(localized: "tab.search", defaultValue: "Search"),
                    systemImage: "sparkles"
                )
            }
            .tag(MainTab.smartSearch)

            SettingsView(
                authService: authService,
                vaultService: vaultService,
                panicGestureService: panicGestureService,
                reminderNavigationTrigger: reminderNavigationTrigger,
                targetReminderID: targetReminderID
            )
            .tabItem {
                Label(
                    String(localized: "tab.settings", defaultValue: "Settings"),
                    systemImage: "gearshape"
                )
            }
            .tag(MainTab.settings)
        }
        .onAppear(perform: onAppear)
        .fullScreenCover(isPresented: $showImporter) {
            ImportView(
                vaultService: vaultService,
                album: nil,
                isDecoyMode: authService.isDecoyMode,
                onDismiss: { showImporter = false }
            )
        }
    }
}

@MainActor
func makePanicGestureService(
    existingService: PanicGestureService?,
    authService: AuthService,
    modelContext: ModelContext,
    isPremium: Bool
) -> PanicGestureService {
    if let existingService {
        return existingService
    }

    let service = PanicGestureService()
    service.onPanicTriggered = {
        authService.lock()

        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first,
           let action = PanicAction(rawValue: settings.panicAction),
           let url = action.appURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                UIApplication.shared.open(url)
            }
        }
    }

    let descriptor = FetchDescriptor<AppSettings>()
    if let settings = try? modelContext.fetch(descriptor).first,
       settings.panicGestureEnabled,
       isPremium {
        service.startMonitoring()
    }

    return service
}

/// Applies entitlement changes to premium-only services and settings.
///
/// Returns `true` when premium lapsed so the caller can present its UI notice. The
/// disguised icon is intentionally preserved: reverting it would expose the vault and
/// trigger an unavoidable system alert naming VaultBox.
@MainActor
@discardableResult
func applyPremiumStatusChange(
    isPremium: Bool,
    modelContext: ModelContext,
    panicGestureService: PanicGestureService?,
    authService: AuthService?
) -> Bool {
    let descriptor = FetchDescriptor<AppSettings>()
    guard let settings = try? modelContext.fetch(descriptor).first else {
        if isPremium {
            panicGestureService?.startMonitoring()
        } else {
            panicGestureService?.stopMonitoring()
        }
        return false
    }

    if isPremium {
        if settings.panicGestureEnabled {
            panicGestureService?.startMonitoring()
        } else {
            panicGestureService?.stopMonitoring()
        }
        return false
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
    return true
}

@MainActor
func makeVaultSearchEngine(
    encryptionService: EncryptionService,
    vaultService: VaultService,
    indexingProgress: IndexingProgress
) async -> SearchEngine? {
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

        vaultService.configureSearchIndex(
            ingestionService: ingestion,
            indexingProgress: indexingProgress
        )
        vaultService.indexUnindexedItems()
        return engine
    } catch {
        #if DEBUG
        print("[ContentView] Failed to initialize search services: \(error)")
        #endif
        return nil
    }
}
