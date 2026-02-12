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

    init() {
        do {
            let schema = Schema([
                VaultItem.self,
                Album.self,
                BreakInAttempt.self,
                AppSettings.self
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
                }
                .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
                    loadTheme()
                }
        }
        .modelContainer(modelContainer)
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
