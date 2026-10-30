import Foundation
import UniformTypeIdentifiers

/// Turns one shared attachment into a sealed inbox payload. Files are streamed straight from
/// the provider's temporary copy, so nothing larger than one chunk is held in memory.
enum SharedItemLoader {
    enum Outcome: Sendable, Equatable {
        case saved
        case unsupported
        case tooLarge
        case failed
    }

    /// Picks the vault item kind and the type identifier to load. Images win over movies so
    /// Live Photos import as photos, matching the in-app picker.
    static func classify(typeIdentifiers: [String]) -> (kind: ShareInboxItemMetadata.Kind, typeIdentifier: String)? {
        let types = typeIdentifiers.compactMap { identifier in
            UTType(identifier).map { (identifier, $0) }
        }
        if let match = types.first(where: { $0.1.conforms(to: .image) }) {
            return (.photo, match.0)
        }
        if let match = types.first(where: { $0.1.conforms(to: .movie) }) {
            return (.video, match.0)
        }
        if let match = types.first(where: { $0.1.conforms(to: .data) && !$0.1.conforms(to: .url) }) {
            return (.document, match.0)
        }
        return nil
    }

    /// Main-actor bound because `NSItemProvider` isn't Sendable; the sealing itself runs on
    /// the provider's background completion queue.
    @MainActor
    static func enqueue(
        _ provider: NSItemProvider,
        isDecoy: Bool,
        recipientPublicKey: Data,
        root: URL
    ) async -> Outcome {
        guard let (kind, typeIdentifier) = classify(typeIdentifiers: provider.registeredTypeIdentifiers) else {
            return .unsupported
        }
        let suggestedName = provider.suggestedName

        let fileOutcome: Outcome = await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                // The provider deletes `url` once this handler returns, so seal it here.
                guard let url else {
                    continuation.resume(returning: .failed)
                    return
                }
                let filename = resolvedFilename(suggestedName: suggestedName, fileURL: url, kind: kind)
                let outcome = seal(
                    .file(url),
                    byteCount: fileSize(of: url),
                    kind: kind,
                    filename: filename,
                    isDecoy: isDecoy,
                    recipientPublicKey: recipientPublicKey,
                    root: root
                )
                continuation.resume(returning: outcome)
            }
        }
        guard fileOutcome == .failed, kind == .photo else { return fileOutcome }

        // Some apps (screenshots, Markup) only hand over in-memory image data.
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                guard let data else {
                    continuation.resume(returning: .failed)
                    return
                }
                let ext = UTType(typeIdentifier)?.preferredFilenameExtension ?? "jpg"
                let filename = ShareInbox.sanitizedFilename(
                    suggestedName.map { ($0 as NSString).pathExtension.isEmpty ? "\($0).\(ext)" : $0 },
                    fallback: "Photo.\(ext)"
                )
                let outcome = seal(
                    .data(data),
                    byteCount: Int64(data.count),
                    kind: kind,
                    filename: filename,
                    isDecoy: isDecoy,
                    recipientPublicKey: recipientPublicKey,
                    root: root
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    private static func seal(
        _ source: ShareInboxPayload.Source,
        byteCount: Int64?,
        kind: ShareInboxItemMetadata.Kind,
        filename: String,
        isDecoy: Bool,
        recipientPublicKey: Data,
        root: URL
    ) -> Outcome {
        if let byteCount, let limit = sizeLimit(for: kind), byteCount > limit {
            return .tooLarge
        }
        let metadata = ShareInboxItemMetadata(
            kind: kind,
            filename: filename,
            isDecoy: isDecoy,
            sharedAt: Date()
        )
        do {
            try ShareInbox.enqueue(source, metadata: metadata, recipientPublicKey: recipientPublicKey, root: root)
            return .saved
        } catch {
            return .failed
        }
    }

    private static func sizeLimit(for kind: ShareInboxItemMetadata.Kind) -> Int64? {
        switch kind {
        case .photo: nil
        case .video: ShareInbox.maxVideoBytes
        case .document: ShareInbox.maxDocumentBytes
        }
    }

    private static func fileSize(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    /// Providers often give a bare title ("IMG_1234") and a temp file that carries the real
    /// extension; keep the extension so documents still open in the right viewer.
    private static func resolvedFilename(
        suggestedName: String?,
        fileURL: URL,
        kind: ShareInboxItemMetadata.Kind
    ) -> String {
        let fallback: String = switch kind {
        case .photo: "Photo"
        case .video: "Video"
        case .document: "Document"
        }
        let ext = fileURL.pathExtension
        guard let suggestedName, !suggestedName.isEmpty else {
            return ShareInbox.sanitizedFilename(fileURL.lastPathComponent, fallback: fallback)
        }
        let name = (suggestedName as NSString).pathExtension.isEmpty && !ext.isEmpty
            ? "\(suggestedName).\(ext)"
            : suggestedName
        return ShareInbox.sanitizedFilename(name, fallback: fallback)
    }
}
