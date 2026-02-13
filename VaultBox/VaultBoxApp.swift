import SwiftUI
import SwiftData
import UserNotifications

private final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = NotificationPresentationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct VaultBoxApp: App {
    let modelContainer: ModelContainer
    @State private var purchaseService = PurchaseService()
    @State private var privacyShield = AppPrivacyShield()
    @State private var themeColorScheme: ColorScheme?
    @State private var pendingShareURL: URL?
    @State private var showSharedPhotoViewer = false

    init() {
        do {
            let schema = Schema([
                VaultItem.self,
                Album.self,
                BreakInAttempt.self,
                AppSettings.self,
                SharedItem.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
            seedSettingsIfNeeded(container: modelContainer)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(purchaseService)
                .environment(privacyShield)
                .preferredColorScheme(themeColorScheme)
                .onAppear {
                    purchaseService.configure()
                    loadTheme()
                    cleanupExpiredShares()
                }
                .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
                    loadTheme()
                }
                .onOpenURL { url in
                    pendingShareURL = url
                    showSharedPhotoViewer = true
                }
                .fullScreenCover(isPresented: $showSharedPhotoViewer) {
                    if let url = pendingShareURL,
                       let parsed = SharingService.parseShareURL(url) {
                        SharedPhotoViewer(
                            shareID: parsed.shareID,
                            keyBase64URL: parsed.keyBase64URL,
                            sharingService: SharingService()
                        )
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    private func cleanupExpiredShares() {
        Task {
            let sharingService = SharingService()
            await sharingService.cleanupExpiredShares()

            // Also clean up local SharedItem records that have expired
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<SharedItem>()
            if let items = try? context.fetch(descriptor) {
                for item in items where item.isExpired && !item.isRevoked {
                    // Mark as expired locally; CloudKit cleanup handled by cleanupExpiredShares above
                }
            }
        }
    }

    private func loadTheme() {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? context.fetch(descriptor).first else { return }
        switch settings.themeMode {
        case "light":
            themeColorScheme = .light
        case "dark":
            themeColorScheme = .dark
        default:
            themeColorScheme = nil
        }
    }

    private func seedSettingsIfNeeded(container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AppSettings>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
    }
}
