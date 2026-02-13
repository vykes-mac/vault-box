import Foundation
import CloudKit
import CryptoKit
import os

actor FeatureBoardService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VaultBox", category: "FeatureBoardService")

    private enum Keys {
        static let title = "title"
        static let details = "details"
        static let normalizedTitle = "normalizedTitle"
        static let status = "status"
        static let upVotes = "upVotes"
        static let downVotes = "downVotes"
        static let score = "score"
        static let createdAt = "createdAt"
        static let createdByHash = "createdByHash"
        static let featureRef = "featureRef"
        static let featureID = "featureID"
        static let voterHash = "voterHash"
        static let value = "value"
        static let updatedAt = "updatedAt"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private var cachedUserHash: String?

    init(containerIdentifier: String = "iCloud.com.vaultbox.app") {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.publicCloudDatabase
    }

    func getICloudAccountStatus() async -> CKAccountStatus {
        do {
            return try await container.accountStatus()
        } catch {
            return .couldNotDetermine
        }
    }

    func listFeatures(limit: Int = 100) async throws -> [FeatureRequestDTO] {
        let predicate = NSPredicate(format: "%K == %@", Keys.status, FeatureStatus.open.rawValue)
        let query = CKQuery(recordType: Constants.featureRequestRecordType, predicate: predicate)
        query.sortDescriptors = [
            NSSortDescriptor(key: Keys.score, ascending: false),
            NSSortDescriptor(key: Keys.upVotes, ascending: false),
            NSSortDescriptor(key: Keys.createdAt, ascending: false)
        ]

        let cappedLimit = max(1, min(limit, 200))

        let results: [(CKRecord.ID, Result<CKRecord, any Error>)]
        do {
            (results, _) = try await database.records(matching: query, resultsLimit: cappedLimit)
        } catch {
            if isRecordTypeNotFound(error) { return [] }
            throw error
        }

        var features: [FeatureRequestDTO] = []
        features.reserveCapacity(results.count)

        for result in results {
            if case .success(let record) = result.1,
               let feature = featureDTO(from: record) {
                features.append(feature)
            }
        }

        return features
    }

    func submitFeature(title: String, details: String) async throws -> FeatureRequestDTO {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            throw FeatureBoardError.emptyTitle
        }

        let normalized = normalizeTitle(trimmedTitle)

        // Fast path: return an existing open feature if one is already visible.
        if let existing = try await findOpenFeature(normalizedTitle: normalized),
           let dto = featureDTO(from: existing) {
            return dto
        }

        // Derive a deterministic record ID from the normalized title so that
        // two concurrent creates for the same title target the same record.
        // The second save will produce a serverRecordChanged conflict instead
        // of silently creating a duplicate.
        let deterministicName = "feature_\(sha256Hex(normalized))"

        let createdByHash = try await currentUserHash()
        let recordID = CKRecord.ID(recordName: deterministicName)
        let record = CKRecord(recordType: Constants.featureRequestRecordType, recordID: recordID)
        record[Keys.title] = trimmedTitle as CKRecordValue
        record[Keys.details] = trimmedDetails as CKRecordValue
        record[Keys.normalizedTitle] = normalized as CKRecordValue
        record[Keys.status] = FeatureStatus.open.rawValue as CKRecordValue
        record[Keys.upVotes] = Int64(0) as CKRecordValue
        record[Keys.downVotes] = Int64(0) as CKRecordValue
        record[Keys.score] = Int64(0) as CKRecordValue
        record[Keys.createdAt] = Date() as CKRecordValue
        record[Keys.createdByHash] = createdByHash as CKRecordValue

        do {
            let saved = try await database.save(record)
            guard let dto = featureDTO(from: saved) else {
                throw FeatureBoardError.invalidRecord
            }
            return dto
        } catch {
            // Handle the conflict raised when a concurrent create already
            // persisted a record with the same deterministic ID.
            guard isServerRecordChanged(error) else { throw error }

            // Try to extract the winning record directly from the error,
            // which avoids an extra round-trip.
            if let serverRecord = serverRecordFromConflict(error),
               let dto = featureDTO(from: serverRecord),
               dto.status == .open {
                return dto
            }

            // Fallback: fetch the existing record by its deterministic ID,
            // then by query if the direct fetch also fails.
            if let existing = try await fetchFeatureByIDOrQuery(
                recordName: deterministicName,
                normalizedTitle: normalized
            ), let dto = featureDTO(from: existing),
               dto.status == .open {
                return dto
            }

            throw error
        }
    }

    func setVote(featureID: String, vote: FeatureVoteValue) async throws {
        let normalizedFeatureID = featureID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFeatureID.isEmpty else {
            throw FeatureBoardError.invalidFeatureID
        }

        try await performVoteWithRetry(featureID: normalizedFeatureID, vote: vote, retryOnConflict: true)
    }

    func removeVote(featureID: String) async throws {
        let normalizedFeatureID = featureID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFeatureID.isEmpty else {
            throw FeatureBoardError.invalidFeatureID
        }

        try await performRemoveVoteWithRetry(featureID: normalizedFeatureID, retryOnConflict: true)
    }

    private static let voteBatchSize = 200

    func myVotes(featureIDs: [String]) async throws -> [String: FeatureVoteValue] {
        guard !featureIDs.isEmpty else { return [:] }

        let featureIDSet = Set(featureIDs)
        let userHash = try await currentUserHash()
        let predicate = NSPredicate(format: "%K == %@", Keys.voterHash, userHash)
        let query = CKQuery(recordType: Constants.featureVoteRecordType, predicate: predicate)

        var allResults: [(CKRecord.ID, Result<CKRecord, any Error>)] = []
        var cursor: CKQueryOperation.Cursor?

        // First batch
        do {
            let (batch, nextCursor) = try await database.records(
                matching: query,
                resultsLimit: Self.voteBatchSize
            )
            allResults.append(contentsOf: batch)
            cursor = nextCursor
        } catch {
            if isRecordTypeNotFound(error) { return [:] }
            throw error
        }

        // Continue fetching while a cursor is returned
        while let activeCursor = cursor {
            let (batch, nextCursor) = try await database.records(
                continuingMatchFrom: activeCursor,
                resultsLimit: Self.voteBatchSize
            )
            allResults.append(contentsOf: batch)
            cursor = nextCursor
        }

        var votes: [String: FeatureVoteValue] = [:]
        votes.reserveCapacity(featureIDs.count)

        for result in allResults {
            guard case .success(let record) = result.1,
                  let featureID = record[Keys.featureID] as? String,
                  featureIDSet.contains(featureID),
                  let vote = voteValue(from: record[Keys.value]) else {
                continue
            }
            votes[featureID] = vote
        }

        return votes
    }
}

private extension FeatureBoardService {

    // MARK: - Atomic Vote Operations

    func performVoteWithRetry(featureID: String, vote: FeatureVoteValue, retryOnConflict: Bool) async throws {
        let userHash = try await currentUserHash()
        let featureRecordID = CKRecord.ID(recordName: featureID)
        let featureRecord: CKRecord
        do {
            featureRecord = try await database.record(for: featureRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            throw FeatureBoardError.invalidFeatureID
        } catch {
            throw error
        }

        let voteRecordID = CKRecord.ID(recordName: voteRecordName(featureID: featureID, userHash: userHash))
        let existingVoteRecord = try await voteRecordIfExists(recordID: voteRecordID)
        let previousVote = voteValue(from: existingVoteRecord?[Keys.value])

        guard previousVote != vote else { return }

        var upVotes = numericValue(from: featureRecord[Keys.upVotes])
        var downVotes = numericValue(from: featureRecord[Keys.downVotes])

        applyVoteTransition(previousVote: previousVote, newVote: vote, upVotes: &upVotes, downVotes: &downVotes)

        featureRecord[Keys.upVotes] = Int64(upVotes) as CKRecordValue
        featureRecord[Keys.downVotes] = Int64(downVotes) as CKRecordValue
        featureRecord[Keys.score] = Int64(upVotes - downVotes) as CKRecordValue

        let voteRecord = existingVoteRecord ?? CKRecord(recordType: Constants.featureVoteRecordType, recordID: voteRecordID)
        voteRecord[Keys.featureRef] = CKRecord.Reference(recordID: featureRecordID, action: .none)
        voteRecord[Keys.featureID] = featureID as CKRecordValue
        voteRecord[Keys.voterHash] = userHash as CKRecordValue
        voteRecord[Keys.value] = Int64(vote.rawValue) as CKRecordValue
        voteRecord[Keys.updatedAt] = Date() as CKRecordValue

        do {
            let (saveResults, _) = try await database.modifyRecords(
                saving: [featureRecord, voteRecord],
                deleting: []
            )
            for (_, result) in saveResults {
                _ = try result.get()
            }
        } catch {
            if retryOnConflict, isServerRecordChanged(error) {
                try await performVoteWithRetry(featureID: featureID, vote: vote, retryOnConflict: false)
            } else {
                throw error
            }
        }
    }

    func performRemoveVoteWithRetry(featureID: String, retryOnConflict: Bool) async throws {
        let userHash = try await currentUserHash()
        let voteRecordID = CKRecord.ID(recordName: voteRecordName(featureID: featureID, userHash: userHash))

        guard let existingVoteRecord = try await voteRecordIfExists(recordID: voteRecordID),
              let previousVote = voteValue(from: existingVoteRecord[Keys.value]) else {
            return
        }

        let featureRecordID = CKRecord.ID(recordName: featureID)
        let featureRecord: CKRecord
        do {
            featureRecord = try await database.record(for: featureRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Feature was deleted — clean up the orphaned vote record so it
            // doesn't resurface if the same deterministic feature ID is reused.
            do {
                try await database.deleteRecord(withID: voteRecordID)
            } catch {
                Self.logger.warning("Failed to delete orphaned vote record \(voteRecordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return
        } catch {
            throw error
        }

        var upVotes = numericValue(from: featureRecord[Keys.upVotes])
        var downVotes = numericValue(from: featureRecord[Keys.downVotes])

        switch previousVote {
        case .up:
            upVotes -= 1
        case .down:
            downVotes -= 1
        }

        upVotes = max(0, upVotes)
        downVotes = max(0, downVotes)

        featureRecord[Keys.upVotes] = Int64(upVotes) as CKRecordValue
        featureRecord[Keys.downVotes] = Int64(downVotes) as CKRecordValue
        featureRecord[Keys.score] = Int64(upVotes - downVotes) as CKRecordValue

        do {
            let (saveResults, deleteResults) = try await database.modifyRecords(
                saving: [featureRecord],
                deleting: [voteRecordID]
            )
            for (_, result) in saveResults {
                _ = try result.get()
            }
            for (_, result) in deleteResults {
                try result.get()
            }
        } catch {
            if retryOnConflict, isServerRecordChanged(error) {
                try await performRemoveVoteWithRetry(featureID: featureID, retryOnConflict: false)
            } else {
                throw error
            }
        }
    }

    // MARK: - Query Helpers

    func findOpenFeature(normalizedTitle: String) async throws -> CKRecord? {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Keys.status,
            FeatureStatus.open.rawValue,
            Keys.normalizedTitle,
            normalizedTitle
        )
        let query = CKQuery(recordType: Constants.featureRequestRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Keys.createdAt, ascending: false)]

        let results: [(CKRecord.ID, Result<CKRecord, any Error>)]
        do {
            (results, _) = try await database.records(matching: query, resultsLimit: 1)
        } catch {
            // Record type doesn't exist yet -- no duplicates possible, safe to proceed with save.
            if isRecordTypeNotFound(error) { return nil }
            throw error
        }

        for result in results {
            if case .success(let record) = result.1 {
                return record
            }
        }
        return nil
    }

    func voteRecordIfExists(recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch {
            if isUnknownItem(error) {
                return nil
            }
            throw error
        }
    }

    func currentUserHash() async throws -> String {
        if let cachedUserHash {
            return cachedUserHash
        }

        let recordID = try await container.userRecordID()
        let hashed = sha256Hex(recordID.recordName)
        cachedUserHash = hashed
        return hashed
    }

    func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func featureDTO(from record: CKRecord) -> FeatureRequestDTO? {
        guard let title = record[Keys.title] as? String else { return nil }

        let details = (record[Keys.details] as? String) ?? ""
        let statusString = (record[Keys.status] as? String) ?? FeatureStatus.open.rawValue
        let status = FeatureStatus(rawValue: statusString) ?? .open
        let upVotes = numericValue(from: record[Keys.upVotes])
        let downVotes = numericValue(from: record[Keys.downVotes])
        let score = numericValue(from: record[Keys.score])
        let createdAt = (record[Keys.createdAt] as? Date) ?? .distantPast

        return FeatureRequestDTO(
            id: record.recordID.recordName,
            title: title,
            details: details,
            status: status,
            upVotes: upVotes,
            downVotes: downVotes,
            score: score,
            createdAt: createdAt
        )
    }

    func voteRecordName(featureID: String, userHash: String) -> String {
        "vote_\(featureID)_\(userHash)"
    }

    func voteValue(from value: Any?) -> FeatureVoteValue? {
        let numeric = numericValue(from: value)
        return FeatureVoteValue(rawValue: numeric)
    }

    func numericValue(from value: Any?) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        if let int64Value = value as? Int64 {
            return Int(int64Value)
        }
        return 0
    }

    func applyVoteTransition(
        previousVote: FeatureVoteValue?,
        newVote: FeatureVoteValue,
        upVotes: inout Int,
        downVotes: inout Int
    ) {
        switch (previousVote, newVote) {
        case (nil, .up):
            upVotes += 1
        case (nil, .down):
            downVotes += 1
        case (.up, .down):
            upVotes -= 1
            downVotes += 1
        case (.down, .up):
            downVotes -= 1
            upVotes += 1
        case (.up, .up), (.down, .down):
            break
        }

        upVotes = max(0, upVotes)
        downVotes = max(0, downVotes)
    }

    func isUnknownItem(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem
    }

    func isRecordTypeNotFound(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        // CloudKit returns .unknownItem when the record type doesn't exist in the schema yet.
        // It can also surface as .serverRejectedRequest with "Did not find record type" message.
        if ckError.code == .unknownItem { return true }
        // ⚠️ Brittle: matching on the localized error string is fragile and may break
        // if Apple changes the SDK wording in a future CloudKit release.
        if ckError.code == .serverRejectedRequest,
           let message = ckError.userInfo[NSLocalizedDescriptionKey] as? String,
           message.contains("Did not find record type") {
            Self.logger.warning("isRecordTypeNotFound matched .serverRejectedRequest via localized string — ckError: \(ckError), matched message: \(message, privacy: .public)")
            return true
        }
        return false
    }

    /// Extracts the server's version of the record from a `.serverRecordChanged`
    /// conflict error, if present.
    func serverRecordFromConflict(_ error: Error) -> CKRecord? {
        if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
            return ckError.serverRecord
        }
        if let ckError = error as? CKError, ckError.code == .partialFailure,
           let partialErrors = ckError.partialErrorsByItemID {
            for (_, partialError) in partialErrors {
                if let inner = partialError as? CKError,
                   inner.code == .serverRecordChanged,
                   let record = inner.serverRecord {
                    return record
                }
            }
        }
        return nil
    }

    /// Attempts a direct fetch by record ID first; falls back to a query by
    /// normalized title when the direct fetch fails.
    func fetchFeatureByIDOrQuery(recordName: String, normalizedTitle: String) async throws -> CKRecord? {
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            return try await database.record(for: recordID)
        } catch {
            return try await findOpenFeature(normalizedTitle: normalizedTitle)
        }
    }

    func isServerRecordChanged(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            if ckError.code == .serverRecordChanged { return true }
            if ckError.code == .partialFailure,
               let partialErrors = ckError.partialErrorsByItemID {
                return partialErrors.values.contains { partialError in
                    (partialError as? CKError)?.code == .serverRecordChanged
                }
            }
        }
        return false
    }

    func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum FeatureBoardError: LocalizedError {
    case emptyTitle
    case invalidFeatureID
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Enter a feature title."
        case .invalidFeatureID:
            return "This feature could not be found."
        case .invalidRecord:
            return "Cloud data is missing required fields."
        }
    }
}
