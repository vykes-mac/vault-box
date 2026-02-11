import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers

@MainActor
@Observable
class WiFiTransferViewModel: WiFiTransferDelegate {
    let vaultService: VaultService
    let authService: AuthService
    let modelContext: ModelContext
    private let hasPremiumAccess: () -> Bool
    private let encryptionService = EncryptionService()
    private let transferService = WiFiTransferService()
    private var countdownTask: Task<Void, Never>?

    var isRunning = false
    var connectedDeviceCount = 0
    var serverURL = ""
    var timeoutSecondsRemaining = 0
    var showPINReEntry = false

    init(
        vaultService: VaultService,
        authService: AuthService,
        modelContext: ModelContext,
        hasPremiumAccess: @escaping () -> Bool = { false }
    ) {
        self.vaultService = vaultService
        self.authService = authService
        self.modelContext = modelContext
        self.hasPremiumAccess = hasPremiumAccess
    }

    // MARK: - Start / Stop

    func requestStart() {
        guard hasPremiumAccess() else { return }
        showPINReEntry = true
    }

    func onPINVerified() {
        guard hasPremiumAccess() else { return }
        showPINReEntry = false
        Task {
            await transferService.setDelegate(self)
            await transferService.setOnStateChange { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.syncState()
                }
            }
            do {
                try await transferService.start()
                await syncState()
                startCountdown()
            } catch {
                isRunning = false
            }
        }
    }

    func stopServer() {
        countdownTask?.cancel()
        countdownTask = nil
        Task {
            await transferService.stop()
            isRunning = false
            connectedDeviceCount = 0
            serverURL = ""
            timeoutSecondsRemaining = 0
        }
    }

    // MARK: - State Sync

    private func syncState() async {
        let running = await transferService.isRunning
        let count = await transferService.connectedDeviceCount
        let ip = await transferService.localIPAddress

        isRunning = running
        connectedDeviceCount = count
        if let ip {
            serverURL = "http://\(ip):\(Constants.wifiTransferPort)"
        }

        if !running {
            countdownTask?.cancel()
            countdownTask = nil
            timeoutSecondsRemaining = 0
        }
    }

    // MARK: - Countdown

    private func startCountdown() {
        timeoutSecondsRemaining = Constants.wifiTransferTimeoutMinutes * 60
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.timeoutSecondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.timeoutSecondsRemaining -= 1
                if self.timeoutSecondsRemaining <= 0 {
                    self.isRunning = false
                    self.serverURL = ""
                    self.connectedDeviceCount = 0
                    break
                }
            }
        }
    }

    // MARK: - WiFiTransferDelegate

    func transferServiceDidReceiveFile(data: Data, filename: String, contentType: String) async throws {
        guard hasPremiumAccess() else { throw VaultError.premiumRequired }
        let lowerCT = contentType.lowercased()
        if lowerCT.hasPrefix("image/") {
            if let image = UIImage(data: data) {
                _ = try await vaultService.importFromCamera(image, album: nil)
            }
        } else {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            _ = try await vaultService.importDocument(at: tempURL, album: nil)
        }
    }

    func transferServiceNeedsItems() async throws -> [TransferItemPayload] {
        guard hasPremiumAccess() else { return [] }
        let descriptor = FetchDescriptor<VaultItem>(sortBy: [SortDescriptor(\VaultItem.importedAt, order: .reverse)])
        guard let items = try? modelContext.fetch(descriptor) else { return [] }
        return items.map { item in
            TransferItemPayload(
                id: item.id.uuidString,
                filename: item.originalFilename,
                type: item.type.rawValue,
                fileSize: item.fileSize,
                createdAt: item.createdAt
            )
        }
    }

    func transferServiceNeedsDecryptedFile(itemID: String) async throws -> (Data, String, String) {
        guard hasPremiumAccess() else { throw VaultError.premiumRequired }
        guard let uuid = UUID(uuidString: itemID) else {
            throw VaultError.itemNotFound
        }
        let predicate = #Predicate<VaultItem> { $0.id == uuid }
        var descriptor = FetchDescriptor<VaultItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else {
            throw VaultError.itemNotFound
        }

        let filename = item.originalFilename
        let contentType = mimeType(for: filename, itemType: item.type)
        let relativePath = item.encryptedFileRelativePath

        let vaultDir = try await encryptionService.vaultFilesDirectory()
        let fileURL = vaultDir.appendingPathComponent(relativePath)
        let decryptedData = try await encryptionService.decryptFile(at: fileURL)

        return (decryptedData, contentType, filename)
    }

    func transferServiceNeedsThumbnail(itemID: String) async throws -> Data {
        guard hasPremiumAccess() else { throw VaultError.premiumRequired }
        guard let uuid = UUID(uuidString: itemID) else {
            throw VaultError.itemNotFound
        }
        let predicate = #Predicate<VaultItem> { $0.id == uuid }
        var descriptor = FetchDescriptor<VaultItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        guard let item = try modelContext.fetch(descriptor).first else {
            throw VaultError.itemNotFound
        }
        guard let encryptedThumb = item.encryptedThumbnailData else {
            throw VaultError.thumbnailNotFound
        }
        return try await encryptionService.decryptData(encryptedThumb)
    }

    // MARK: - Helpers

    private func mimeType(for filename: String, itemType: VaultItem.ItemType) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        switch itemType {
        case .photo: return "image/jpeg"
        case .video: return "video/mp4"
        case .document: return "application/octet-stream"
        }
    }
}

extension WiFiTransferService {
    func setOnStateChange(_ callback: @escaping @Sendable () -> Void) {
        self.onStateChange = callback
    }
}
