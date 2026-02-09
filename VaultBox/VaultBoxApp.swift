import SwiftUI
import SwiftData

@main
struct VaultBoxApp: App {
    let modelContainer: ModelContainer

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
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            seedSettingsIfNeeded(container: modelContainer)
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
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
