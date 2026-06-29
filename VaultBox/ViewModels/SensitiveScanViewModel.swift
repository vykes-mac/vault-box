import SwiftUI
import Photos

@MainActor
@Observable
class SensitiveScanViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case importing
        case finished(imported: Int)
        case denied
        case error(String)
    }

    let vaultService: VaultService
    private let scanService = SensitiveContentScanService()
    private let imageManager = PHCachingImageManager()

    /// Cap on how many recent photos a single scan inspects.
    private let scanLimit = 400

    var phase: Phase = .idle
    var candidates: [SensitiveScanCandidate] = []
    var selectedIDs: Set<String> = []
    var scannedCount = 0
    var totalCount = 0
    private var thumbnails: [String: UIImage] = [:]

    init(vaultService: VaultService) {
        self.vaultService = vaultService
    }

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return Double(scannedCount) / Double(totalCount)
    }

    var allSelected: Bool {
        !candidates.isEmpty && selectedIDs.count == candidates.count
    }

    // MARK: - Scanning

    func startScan() {
        phase = .scanning
        scannedCount = 0
        totalCount = 0
        candidates = []
        selectedIDs = []

        Task {
            let granted = await requestPhotoAccess()
            guard granted else {
                phase = .denied
                return
            }

            do {
                let found = try await scanService.scan(maxAssets: scanLimit) { scanned, total in
                    Task { @MainActor in
                        self.scannedCount = scanned
                        self.totalCount = total
                    }
                }
                candidates = found
                selectedIDs = Set(found.map(\.id)) // pre-select all
                phase = .results
            } catch SensitiveContentScanService.ScanError.notAuthorized {
                phase = .denied
            } catch {
                phase = .error("Scan failed. Please try again.")
            }
        }
    }

    private func requestPhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    // MARK: - Selection

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func toggleSelectAll() {
        if allSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(candidates.map(\.id))
        }
    }

    // MARK: - Import

    func moveSelectedToVault(deleteOriginals: Bool, onComplete: @escaping () -> Void) {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        phase = .importing

        Task {
            do {
                let result = try await vaultService.importFromCameraRoll(localIdentifiers: ids, album: nil)
                if deleteOriginals, !result.assetIdentifiers.isEmpty {
                    try? await vaultService.deleteFromCameraRoll(localIdentifiers: result.assetIdentifiers)
                }
                phase = .finished(imported: result.items.count)
                onComplete()
            } catch {
                phase = .error("Couldn't move items to the vault. \( (error as? LocalizedError)?.errorDescription ?? "")")
            }
        }
    }

    // MARK: - Thumbnails

    func thumbnail(for id: String) -> UIImage? {
        thumbnails[id]
    }

    func loadThumbnail(for id: String, size: CGFloat) {
        guard thumbnails[id] == nil else { return }
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = fetch.firstObject else { return }

        let scale = UIScreen.main.scale
        let target = CGSize(width: size * scale, height: size * scale)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        imageManager.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            guard let image else { return }
            Task { @MainActor in
                self?.thumbnails[id] = image
            }
        }
    }
}
