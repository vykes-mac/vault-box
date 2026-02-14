import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

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
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
            seedSettingsIfNeeded(container: modelContainer)
            registerBackgroundTasks()
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

    // MARK: - Background Indexing

    private func registerBackgroundTasks() {
        let container = self.modelContainer
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Constants.bgTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            VaultBoxApp.handleBackgroundIndexing(task: bgTask, container: container)
        }
    }

    /// Schedules a background processing task for search indexing.
    /// Call after imports or on app launch when there are unindexed items.
    static func scheduleBackgroundIndexing() {
        let request = BGProcessingTaskRequest(identifier: Constants.bgTaskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("[VaultBoxApp] Failed to schedule background indexing: \(error)")
            #endif
        }
    }

    /// Sendable wrapper for BGProcessingTask to cross task boundaries in Swift 6.
    private struct SendableBGTask: @unchecked Sendable {
        let task: BGProcessingTask
    }

    private nonisolated static func handleBackgroundIndexing(task: BGProcessingTask, container: ModelContainer) {
        let sendableTask = SendableBGTask(task: task)

        let indexingTask = Task.detached {
            do {
                let context = ModelContext(container)
                let encryptionService = EncryptionService()
                let searchIndexService = try await SearchIndexService.open()
                let embeddingService = EmbeddingService()
                let ingestionService = IngestionService(
                    encryptionService: encryptionService,
                    searchIndexService: searchIndexService,
                    embeddingService: embeddingService
                )

                let descriptor = FetchDescriptor<VaultItem>(
                    predicate: #Predicate<VaultItem> { !$0.isIndexed && !$0.indexingFailed }
                )
                let unindexed = (try? context.fetch(descriptor)) ?? []

                guard !unindexed.isEmpty else {
                    sendableTask.task.setTaskCompleted(success: true)
                    return
                }

                let inputs = unindexed.compactMap { item -> IngestionInput? in
                    guard item.type != .video else { return nil }
                    return IngestionInput(
                        itemID: item.id,
                        encryptedFileRelativePath: item.encryptedFileRelativePath,
                        itemType: item.type.rawValue,
                        originalFilename: item.originalFilename
                    )
                }

                // Pre-load embedding model once for the batch
                try? await embeddingService.loadModel()

                // Process items individually to avoid @Sendable closure issues
                // with mutable result collection. indexItem reuses the already-loaded model.
                for input in inputs {
                    guard !Task.isCancelled else { break }
                    let result = await ingestionService.indexItem(input)

                    let targetID = result.itemID
                    let itemDescriptor = FetchDescriptor<VaultItem>(
                        predicate: #Predicate { $0.id == targetID }
                    )
                    guard let item = try? context.fetch(itemDescriptor).first else { continue }
                    item.isIndexed = result.success
                    item.indexingFailed = !result.success
                    item.chunkCount = result.chunkCount
                    item.totalPages = result.totalPages
                    if let preview = result.extractedTextPreview {
                        item.extractedTextPreview = preview
                    }
                    try? context.save()
                }

                await embeddingService.unloadModel()
                await searchIndexService.close()
                sendableTask.task.setTaskCompleted(success: true)
            } catch {
                sendableTask.task.setTaskCompleted(success: false)
            }
        }

        // Handle system requesting early termination
        task.expirationHandler = {
            indexingTask.cancel()
        }
    }
}
