import Foundation
import SQLite3

// MARK: - Data Types

struct TextChunk: Sendable {
    let chunkIndex: Int
    let pageNumber: Int?
    let textContent: String
    let wordCount: Int
}

struct FTSResult: Sendable {
    let chunkID: Int64
    let itemID: UUID
    let textContent: String
    let pageNumber: Int?
    let rank: Double
}

struct EmbeddingRecord: Sendable {
    let chunkID: Int64
    let itemID: UUID
    let vector: [Float]
}

// MARK: - SearchIndexService

actor SearchIndexService {
    private var db: OpaquePointer?

    private init(db: OpaquePointer) {
        self.db = db
    }

    /// Creates and opens the search index database, applying schema if needed.
    static func open() async throws -> SearchIndexService {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let vaultDataURL = docsURL.appendingPathComponent(Constants.vaultDataDirectory)
        try FileManager.default.createDirectory(at: vaultDataURL, withIntermediateDirectories: true)

        let dbURL = vaultDataURL.appendingPathComponent(Constants.searchIndexDatabaseName)
        let dbPath = dbURL.path

        var dbHandle: OpaquePointer?
        guard sqlite3_open(dbPath, &dbHandle) == SQLITE_OK, let dbHandle else {
            let msg = dbHandle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let dbHandle { sqlite3_close(dbHandle) }
            throw SearchIndexError.openFailed(msg)
        }

        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: dbPath
        )

        let service = SearchIndexService(db: dbHandle)
        try await service.setupPragmas()
        try await service.createTablesIfNeeded()
        return service
    }

    private func setupPragmas() throws {
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
    }

    func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    private func createTablesIfNeeded() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS text_chunks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                item_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                page_number INTEGER,
                text_content TEXT NOT NULL,
                word_count INTEGER NOT NULL,
                created_at REAL NOT NULL DEFAULT (julianday('now')),
                UNIQUE(item_id, chunk_index)
            )
        """)

        try exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS text_chunks_fts USING fts5(
                text_content,
                content='text_chunks',
                content_rowid='id'
            )
        """)

        try exec("""
            CREATE TRIGGER IF NOT EXISTS text_chunks_ai AFTER INSERT ON text_chunks BEGIN
                INSERT INTO text_chunks_fts(rowid, text_content) VALUES (new.id, new.text_content);
            END
        """)

        try exec("""
            CREATE TRIGGER IF NOT EXISTS text_chunks_ad AFTER DELETE ON text_chunks BEGIN
                INSERT INTO text_chunks_fts(text_chunks_fts, rowid, text_content) VALUES('delete', old.id, old.text_content);
            END
        """)

        try exec("""
            CREATE TRIGGER IF NOT EXISTS text_chunks_au AFTER UPDATE ON text_chunks BEGIN
                INSERT INTO text_chunks_fts(text_chunks_fts, rowid, text_content) VALUES('delete', old.id, old.text_content);
                INSERT INTO text_chunks_fts(rowid, text_content) VALUES (new.id, new.text_content);
            END
        """)

        try exec("""
            CREATE TABLE IF NOT EXISTS embeddings (
                chunk_id INTEGER PRIMARY KEY REFERENCES text_chunks(id) ON DELETE CASCADE,
                vector BLOB NOT NULL
            )
        """)

        try exec("CREATE INDEX IF NOT EXISTS idx_text_chunks_item_id ON text_chunks(item_id)")
    }

    // MARK: - Write Operations

    func insertChunks(_ chunks: [TextChunk], for itemID: UUID) throws -> [Int64] {
        guard let db else { throw SearchIndexError.notOpen }

        let sql = """
            INSERT INTO text_chunks (item_id, chunk_index, page_number, text_content, word_count)
            VALUES (?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        var rowIDs: [Int64] = []
        let itemIDString = itemID.uuidString

        for chunk in chunks {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            bindText(stmt, index: 1, value: itemIDString)
            sqlite3_bind_int(stmt, 2, Int32(chunk.chunkIndex))
            if let page = chunk.pageNumber {
                sqlite3_bind_int(stmt, 3, Int32(page))
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            bindText(stmt, index: 4, value: chunk.textContent)
            sqlite3_bind_int(stmt, 5, Int32(chunk.wordCount))

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw SearchIndexError.insertFailed(errorMessage)
            }
            rowIDs.append(sqlite3_last_insert_rowid(db))
        }

        return rowIDs
    }

    func insertEmbedding(chunkID: Int64, vector: [Float]) throws {
        guard let db else { throw SearchIndexError.notOpen }

        let sql = "INSERT OR REPLACE INTO embeddings (chunk_id, vector) VALUES (?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chunkID)

        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let rc = data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 2, rawBuffer.baseAddress, Int32(rawBuffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard rc == SQLITE_OK else {
            throw SearchIndexError.insertFailed(errorMessage)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchIndexError.insertFailed(errorMessage)
        }
    }

    func deleteChunks(for itemID: UUID) throws {
        guard db != nil else { throw SearchIndexError.notOpen }
        let itemIDString = itemID.uuidString

        // Delete embeddings first (foreign key), then chunks
        let deleteEmbeddings = """
            DELETE FROM embeddings WHERE chunk_id IN (
                SELECT id FROM text_chunks WHERE item_id = ?
            )
        """
        try execBound(deleteEmbeddings, binding: { stmt in
            self.bindText(stmt, index: 1, value: itemIDString)
        })

        let deleteChunks = "DELETE FROM text_chunks WHERE item_id = ?"
        try execBound(deleteChunks, binding: { stmt in
            self.bindText(stmt, index: 1, value: itemIDString)
        })
    }

    func deleteAllData() throws {
        try exec("DELETE FROM embeddings")
        try exec("DELETE FROM text_chunks")
    }

    // MARK: - FTS Search

    func ftsSearch(query: String, limit: Int = 20) throws -> [FTSResult] {
        guard let db else { throw SearchIndexError.notOpen }

        let sanitized = sanitizeFTSQuery(query)
        guard !sanitized.isEmpty else { return [] }

        let sql = """
            SELECT tc.id, tc.item_id, tc.text_content, tc.page_number, rank
            FROM text_chunks_fts
            JOIN text_chunks tc ON tc.id = text_chunks_fts.rowid
            WHERE text_chunks_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, index: 1, value: sanitized)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [FTSResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkID = sqlite3_column_int64(stmt, 0)
            let itemIDStr = String(cString: sqlite3_column_text(stmt, 1))
            let textContent = String(cString: sqlite3_column_text(stmt, 2))
            let pageNumber: Int? = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int(stmt, 3))
            let rank = sqlite3_column_double(stmt, 4)

            guard let itemID = UUID(uuidString: itemIDStr) else { continue }

            results.append(FTSResult(
                chunkID: chunkID,
                itemID: itemID,
                textContent: textContent,
                pageNumber: pageNumber,
                rank: rank
            ))
        }

        return results
    }

    // MARK: - Vector Search

    func loadAllEmbeddings() throws -> [EmbeddingRecord] {
        guard let db else { throw SearchIndexError.notOpen }

        let sql = """
            SELECT e.chunk_id, tc.item_id, e.vector
            FROM embeddings e
            JOIN text_chunks tc ON tc.id = e.chunk_id
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        var records: [EmbeddingRecord] = []
        let expectedBytes = Constants.embeddingDimension * MemoryLayout<Float>.size

        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkID = sqlite3_column_int64(stmt, 0)
            let itemIDStr = String(cString: sqlite3_column_text(stmt, 1))
            let blobPtr = sqlite3_column_blob(stmt, 2)
            let blobSize = Int(sqlite3_column_bytes(stmt, 2))

            guard let itemID = UUID(uuidString: itemIDStr),
                  let blobPtr,
                  blobSize == expectedBytes else { continue }

            let vector = Array(UnsafeBufferPointer(
                start: blobPtr.assumingMemoryBound(to: Float.self),
                count: Constants.embeddingDimension
            ))

            records.append(EmbeddingRecord(chunkID: chunkID, itemID: itemID, vector: vector))
        }

        return records
    }

    func chunkDetail(for chunkID: Int64) throws -> (text: String, itemID: UUID, pageNumber: Int?)? {
        guard let db else { throw SearchIndexError.notOpen }

        let sql = "SELECT text_content, item_id, page_number FROM text_chunks WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, chunkID)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let text = String(cString: sqlite3_column_text(stmt, 0))
        let itemIDStr = String(cString: sqlite3_column_text(stmt, 1))
        let pageNumber: Int? = sqlite3_column_type(stmt, 2) == SQLITE_NULL
            ? nil : Int(sqlite3_column_int(stmt, 2))

        guard let itemID = UUID(uuidString: itemIDStr) else { return nil }
        return (text, itemID, pageNumber)
    }

    // MARK: - Helpers

    private var errorMessage: String {
        db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "database not open"
    }

    private func exec(_ sql: String) throws {
        guard let db else { throw SearchIndexError.notOpen }
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.flatMap { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw SearchIndexError.execFailed(msg)
        }
    }

    private func execBound(_ sql: String, binding: (OpaquePointer?) -> Void) throws {
        guard let db else { throw SearchIndexError.notOpen }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SearchIndexError.prepareFailed(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }
        binding(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SearchIndexError.execFailed(errorMessage)
        }
    }

    @discardableResult
    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) -> Int32 {
        // SQLITE_TRANSIENT = -1, tells SQLite to make its own copy
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        return sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func sanitizeFTSQuery(_ query: String) -> String {
        let words = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }
        // Use implicit AND by joining words with spaces; add * for prefix matching
        return words.map { "\($0)*" }.joined(separator: " ")
    }
}

// MARK: - Errors

enum SearchIndexError: Error, LocalizedError {
    case notOpen
    case openFailed(String)
    case prepareFailed(String)
    case insertFailed(String)
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .notOpen: return "Search index database is not open"
        case .openFailed(let msg): return "Failed to open search index: \(msg)"
        case .prepareFailed(let msg): return "Failed to prepare statement: \(msg)"
        case .insertFailed(let msg): return "Failed to insert data: \(msg)"
        case .execFailed(let msg): return "SQL execution failed: \(msg)"
        }
    }
}
