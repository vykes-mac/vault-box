import Testing
import Foundation
import CryptoKit
@testable import VaultBox

// MARK: - SealedCapture

@Suite("SealedCapture Tests")
struct SealedCaptureTests {
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()

    private func randomData(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    @Test("Photo roundtrip returns identical bytes and kind")
    func photoRoundtrip() throws {
        let original = randomData(50_000)
        let sealed = try SealedCapture.seal(original, kind: .photo, to: privateKey.publicKey)
        let opened = try SealedCapture.open(sealed, with: privateKey)

        #expect(opened.kind == .photo)
        #expect(opened.plaintext == original)
        #expect(sealed.range(of: original.prefix(64)) == nil)
    }

    @Test("Multi-chunk and chunk-aligned payloads roundtrip", arguments: [0, 1, SealedCapture.chunkSize, SealedCapture.chunkSize * 2 + 7])
    func chunkBoundaries(size: Int) throws {
        let original = randomData(size)
        let sealed = try SealedCapture.seal(original, kind: .video, to: privateKey.publicKey)
        let opened = try SealedCapture.open(sealed, with: privateKey)

        #expect(opened.kind == .video)
        #expect(opened.plaintext == original)
    }

    @Test("Streaming file seal and open roundtrip")
    func fileRoundtrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = randomData(SealedCapture.chunkSize + 1234)
        let source = dir.appendingPathComponent("in.mov")
        let sealed = dir.appendingPathComponent("out.\(SealedCapture.fileExtension)")
        let opened = dir.appendingPathComponent("opened.mov")
        try original.write(to: source)

        try SealedCapture.sealFile(at: source, kind: .video, to: privateKey.publicKey, destination: sealed)
        #expect(try SealedCapture.kind(ofFileAt: sealed) == .video)

        let kind = try SealedCapture.openFile(at: sealed, with: privateKey, destination: opened)
        #expect(kind == .video)
        #expect(try Data(contentsOf: opened) == original)
        // In-memory and streaming paths produce the same format.
        #expect(try SealedCapture.open(Data(contentsOf: sealed), with: privateKey).plaintext == original)
    }

    @Test("Wrong private key cannot open a capture")
    func wrongKeyFails() throws {
        let sealed = try SealedCapture.seal(randomData(100), kind: .photo, to: privateKey.publicKey)
        #expect(throws: (any Error).self) {
            try SealedCapture.open(sealed, with: Curve25519.KeyAgreement.PrivateKey())
        }
    }

    @Test("Dropping trailing chunks is detected")
    func truncationDetected() throws {
        let sealed = try SealedCapture.seal(randomData(SealedCapture.chunkSize * 2), kind: .video, to: privateKey.publicKey)
        // Cut at the end of the first chunk: what remains is a structurally valid prefix.
        let headerLength = 4 + 2 + 2 + 32
        let firstChunkEnd = headerLength + 4 + SealedCapture.chunkSize + 16
        #expect(throws: (any Error).self) {
            try SealedCapture.open(sealed.prefix(firstChunkEnd), with: privateKey)
        }
    }

    @Test("Flipping the kind byte breaks authentication")
    func kindIsAuthenticated() throws {
        var sealed = try SealedCapture.seal(randomData(100), kind: .photo, to: privateKey.publicKey)
        sealed[5] = SealedCapture.Kind.video.rawValue
        #expect(throws: (any Error).self) {
            try SealedCapture.open(sealed, with: privateKey)
        }
    }

    @Test("Garbage is rejected as a bad header")
    func garbageRejected() {
        #expect(throws: SealedCapture.FormatError.badHeader) {
            try SealedCapture.open(Data("not a capture".utf8), with: privateKey)
        }
    }
}

// MARK: - QuickCaptureIngestor

@MainActor
private final class RecordingImporter: QuickCaptureImporting {
    var photos: [Data] = []
    var videos: [Data] = []
    var limit = Int.max
    var failNextWith: (any Error)?

    func importQuickCapturePhoto(_ data: Data) async throws {
        try check()
        photos.append(data)
    }

    func importQuickCaptureVideo(at url: URL) async throws {
        try check()
        videos.append(try Data(contentsOf: url))
    }

    private func check() throws {
        if let error = failNextWith {
            failNextWith = nil
            throw error
        }
        guard photos.count + videos.count < limit else { throw VaultError.freeLimitReached }
    }
}

private struct StubContentSource: QuickCaptureContentSource {
    let directories: [URL]
    let invalidated = InvalidationLog()

    func sessionDirectories() async -> [URL] { directories }
    func invalidate(_ directory: URL) async { await invalidated.append(directory) }
}

private actor InvalidationLog {
    var urls: [URL] = []
    func append(_ url: URL) { urls.append(url) }
}

@Suite("QuickCaptureIngestor Tests")
@MainActor
struct QuickCaptureIngestorTests {
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("QuickCaptureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func makeSession() throws -> URL {
        let dir = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func writeSealed(_ data: Data, kind: SealedCapture.Kind, in dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent("\(name).\(SealedCapture.fileExtension)")
        try SealedCapture.seal(data, kind: kind, to: privateKey.publicKey).write(to: url)
        return url
    }

    private func makeIngestor(_ importer: RecordingImporter) -> QuickCaptureIngestor {
        QuickCaptureIngestor(
            privateKey: privateKey,
            importer: importer,
            scratchDirectory: root.appendingPathComponent("scratch")
        )
    }

    @Test("Imports photos and videos in capture order and drains the session")
    func importsAndDrains() async throws {
        let session = try makeSession()
        try writeSealed(Data("second".utf8), kind: .photo, in: session, name: "2000-b")
        try writeSealed(Data("first".utf8), kind: .photo, in: session, name: "1000-a")
        try writeSealed(Data("movie".utf8), kind: .video, in: session, name: "3000-c")

        let importer = RecordingImporter()
        let result = await makeIngestor(importer).ingest([session])

        #expect(result.report == QuickCaptureIngestReport(imported: 3, discarded: 0, deferred: 0))
        #expect(importer.photos == [Data("first".utf8), Data("second".utf8)])
        #expect(importer.videos == [Data("movie".utf8)])
        #expect(result.drained == [session])
        #expect(QuickCaptureIngestor.captureFiles(in: session).isEmpty)
        // Decrypted video scratch copies are cleaned up.
        let scratch = root.appendingPathComponent("scratch")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).isEmpty)
    }

    @Test("Free limit stops ingestion and keeps the remaining captures sealed")
    func freeLimitDefers() async throws {
        let session = try makeSession()
        try writeSealed(Data("a".utf8), kind: .photo, in: session, name: "1")
        let second = try writeSealed(Data("b".utf8), kind: .photo, in: session, name: "2")
        let third = try writeSealed(Data("c".utf8), kind: .photo, in: session, name: "3")

        let importer = RecordingImporter()
        importer.limit = 1
        let result = await makeIngestor(importer).ingest([session])

        #expect(result.report == QuickCaptureIngestReport(imported: 1, discarded: 0, deferred: 2))
        #expect(result.drained.isEmpty)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: third.path))
    }

    @Test("Captures sealed to another key are discarded, not retried forever")
    func foreignKeyDiscarded() async throws {
        let session = try makeSession()
        let foreign = session.appendingPathComponent("1.\(SealedCapture.fileExtension)")
        try SealedCapture.seal(Data("x".utf8), kind: .photo, to: Curve25519.KeyAgreement.PrivateKey().publicKey)
            .write(to: foreign)

        let importer = RecordingImporter()
        let result = await makeIngestor(importer).ingest([session])

        #expect(result.report == QuickCaptureIngestReport(imported: 0, discarded: 1, deferred: 0))
        #expect(importer.photos.isEmpty)
        #expect(result.drained == [session])
    }

    @Test("A transient import failure leaves the sealed file for the next unlock")
    func transientFailureRetries() async throws {
        let session = try makeSession()
        let file = try writeSealed(Data("a".utf8), kind: .photo, in: session, name: "1")

        let importer = RecordingImporter()
        importer.failNextWith = VaultError.importFailed
        let first = await makeIngestor(importer).ingest([session])
        #expect(first.report == QuickCaptureIngestReport(imported: 0, discarded: 0, deferred: 1))
        #expect(FileManager.default.fileExists(atPath: file.path))

        let second = await makeIngestor(importer).ingest([session])
        #expect(second.report == QuickCaptureIngestReport(imported: 1, discarded: 0, deferred: 0))
        #expect(second.drained == [session])
    }

    @Test("Unsealed leftover recordings are imported and removed")
    func leftoverRecordingImported() async throws {
        let session = try makeSession()
        let recording = session.appendingPathComponent("recording", isDirectory: true)
        try FileManager.default.createDirectory(at: recording, withIntermediateDirectories: true)
        let leftover = recording.appendingPathComponent("1.mov")
        try Data("raw".utf8).write(to: leftover)

        let importer = RecordingImporter()
        let result = await makeIngestor(importer).ingest([session])

        #expect(result.report.imported == 1)
        #expect(importer.videos == [Data("raw".utf8)])
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
    }

    @Test("Service creates one stable key, imports, and invalidates drained sessions")
    func serviceSync() async throws {
        let session = try makeSession()
        let storage = InMemoryKeyStorage()
        let source = StubContentSource(directories: [session])
        let service = QuickCaptureService(
            keyStorage: storage,
            contentSource: source,
            scratchDirectory: root.appendingPathComponent("scratch")
        )

        let key = try service.loadOrCreatePrivateKey()
        #expect(try service.loadOrCreatePrivateKey().rawRepresentation == key.rawRepresentation)

        let url = session.appendingPathComponent("1.\(SealedCapture.fileExtension)")
        try SealedCapture.seal(Data("p".utf8), kind: .photo, to: key.publicKey).write(to: url)

        let importer = RecordingImporter()
        let report = await service.sync(into: importer)

        #expect(report == QuickCaptureIngestReport(imported: 1, discarded: 0, deferred: 0))
        #expect(await source.invalidated.urls == [session])
    }
}
