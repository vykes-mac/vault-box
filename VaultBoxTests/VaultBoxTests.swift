import Testing
import SwiftData
import UIKit
@testable import VaultBox

@Suite("VaultBox Tests")
struct VaultBoxTests {
    @Test("App launches")
    func appLaunches() {
        #expect(true)
    }
}

@Suite("VaultService Tests")
struct VaultServiceTests {

    enum TestError: Error {
        case failedToCreateImageData
    }

    @MainActor
    private func makeService() async throws -> (VaultService, ModelContext, ModelContainer) {
        let schema = Schema([AppSettings.self, VaultItem.self, Album.self, BreakInAttempt.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let encryption = EncryptionService(keyStorage: InMemoryKeyStorage())
        let masterKey = await encryption.generateMasterKey()
        try await encryption.storeMasterKey(masterKey)

        let service = VaultService(
            encryptionService: encryption,
            modelContext: context,
            hasPremiumAccess: { true }
        )

        return (service, context, container)
    }

    private func makeImageData(width: CGFloat, height: CGFloat) throws -> Data {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        guard let data = image.pngData() else {
            throw TestError.failedToCreateImageData
        }
        return data
    }

    @Test("importPhotoData keeps original byte size and dimensions")
    @MainActor
    func importPhotoDataKeepsOriginalSize() async throws {
        let (service, context, _) = try await makeService()
        let imageData = try makeImageData(width: 32, height: 24)

        let item = try await service.importPhotoData(imageData, filename: "selfie.png", album: nil)

        #expect(item.type.rawValue == "photo")
        #expect(item.originalFilename == "selfie.png")
        #expect(item.fileSize == Int64(imageData.count))
        #expect(item.pixelWidth == 32)
        #expect(item.pixelHeight == 24)

        let storedItems = try context.fetch(FetchDescriptor<VaultItem>())
        #expect(storedItems.count == 1)
    }

    @Test("importPhotoData uses default filename when input is empty")
    @MainActor
    func importPhotoDataUsesDefaultFilename() async throws {
        let (service, _, _) = try await makeService()
        let imageData = try makeImageData(width: 12, height: 12)

        let item = try await service.importPhotoData(imageData, filename: "   ", album: nil)

        #expect(item.originalFilename == "Photo")
    }

    @Test("smartTags persist after save")
    @MainActor
    func smartTagsPersistAfterSave() async throws {
        let (service, context, container) = try await makeService()
        let imageData = try makeImageData(width: 20, height: 20)
        let item = try await service.importPhotoData(imageData, filename: "tag-test.png", album: nil)

        item.smartTags = ["people", "document"]
        try context.save()
        let itemID = item.id

        let descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate { $0.id == itemID }
        )
        let fetched = try context.fetch(descriptor).first
        #expect(fetched != nil)
        #expect(fetched?.smartTags.contains("people") == true)
        #expect(fetched?.smartTags.contains("document") == true)

        let freshContext = ModelContext(container)
        let reloaded = try freshContext.fetch(descriptor).first
        #expect(reloaded != nil)
        #expect(reloaded?.smartTags.contains("people") == true)
        #expect(reloaded?.smartTags.contains("document") == true)
    }
}
