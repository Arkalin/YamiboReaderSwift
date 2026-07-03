import Foundation
@preconcurrency import GRDB

extension OfflineCacheStore {
    public func offlineCacheQueueWorks() async -> [OfflineCacheQueueWorkProjection] {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            try Self.allRawWorks(in: db).map(Self.queueWorkProjection(from:))
        }) ?? []
    }

    public func enqueueNovelOfflineCacheWork(_ request: NovelOfflineCacheWorkRequest) async throws -> NovelOfflineCacheEnqueueResult {
        try await enqueueNovelOfflineCacheWork(request, skipsExistingCachedEntry: true)
    }

    public func enqueueNovelOfflineCacheUpdateWork(_ request: NovelOfflineCacheWorkRequest) async throws -> NovelOfflineCacheEnqueueResult {
        try await enqueueNovelOfflineCacheWork(request, skipsExistingCachedEntry: false)
    }

    private func enqueueNovelOfflineCacheWork(
        _ request: NovelOfflineCacheWorkRequest,
        skipsExistingCachedEntry: Bool
    ) async throws -> NovelOfflineCacheEnqueueResult {
        try await recoverQueueStateAfterRestart()
        do {
            let result: NovelOfflineCacheEnqueueResult = try await database.write { db in
                let normalizedRequest = try Self.normalizedNovelWorkRequest(request)
                let entryID = OfflineCacheEntryID(
                    readerKind: .novel,
                    ownerKey: normalizedRequest.ownerTitle,
                    entryKey: normalizedRequest.entryKey
                )
                if skipsExistingCachedEntry,
                   let entry = try Self.novelEntry(ownerName: entryID.ownerKey, entryKey: entryID.entryKey, in: db) {
                    return .alreadyCached(entry)
                }
                if let work = try Self.rawWork(
                    readerKind: .novel,
                    ownerKey: entryID.ownerKey,
                    entryKey: entryID.entryKey,
                    in: db
                ) {
                    return .alreadyQueued(Self.queueWorkProjection(from: work))
                }
                let work = OfflineCacheRawWork(
                    readerKind: .novel,
                    workID: UUID().uuidString,
                    ownerKey: normalizedRequest.ownerTitle,
                    entryKey: normalizedRequest.entryKey,
                    title: normalizedRequest.title.isEmpty
                        ? L10n.string("reader.page_number_spaced", normalizedRequest.view)
                        : normalizedRequest.title,
                    targetImageURLs: normalizedRequest.targetImageURLs,
                    completedImageURLs: [],
                    state: .queued,
                    failureMessage: nil,
                    currentBytesPerSecond: 0,
                    insertionIndex: try Self.nextQueueInsertionIndex(readerKind: OfflineCacheReaderKind.novel.rawValue, in: db),
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try Self.save(work, in: db)
                return .enqueued(Self.queueWorkProjection(from: work))
            }
            if result.enqueuedWork != nil {
                notifyOfflineCacheDidChange()
            }
            return result
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func retryFailedOfflineCacheWorks() async throws {
        try await recoverQueueStateAfterRestart()
        do {
            try await database.write { db in
                try db.execute(
                    sql: """
                    UPDATE offline_cache_works
                    SET state = ?, failure_message = NULL, current_bytes_per_second = 0, updated_at = ?
                    WHERE state = ?
                    """,
                    arguments: [
                        OfflineCacheWorkState.queued.rawValue,
                        offlineCacheTimeInterval(from: Date()),
                        OfflineCacheWorkState.failed.rawValue
                    ]
                )
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func markOfflineCacheWorkFailed(id: OfflineCacheWorkID, message: String?) async throws {
        try await recoverQueueStateAfterRestart()
        do {
            try await database.write { db in
                guard var work = try Self.rawWork(workID: id.rawValue, readerKind: id.readerKind, in: db) else {
                    return
                }
                work.state = .failed
                work.failureMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
                if work.failureMessage?.isEmpty == true {
                    work.failureMessage = nil
                }
                work.currentBytesPerSecond = 0
                work.updatedAt = Date()
                try Self.save(work, in: db)
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func cancelOfflineCacheWork(id: OfflineCacheWorkID) async throws {
        try await recoverQueueStateAfterRestart()
        do {
            try await database.write { db in
                guard let canceled = try Self.rawWork(workID: id.rawValue, readerKind: id.readerKind, in: db) else {
                    return
                }
                try Self.deleteWork(
                    readerKind: canceled.readerKind.rawValue,
                    ownerName: canceled.ownerKey,
                    tid: canceled.entryKey,
                    in: db
                )
                try Self.removeUnreferencedImages(
                    candidateImageURLs: canceled.targetImageURLs + canceled.completedImageURLs,
                    fileManager: fileManager,
                    imagesDirectory: imagesDirectory,
                    in: db
                )
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func cancelOfflineCacheGroup(_ id: OfflineCacheGroupID) async throws {
        switch id.readerKind {
        case .manga:
            try await cancelOfflineCacheWorks(forOwnerName: id.ownerKey)
        case .novel:
            try await cancelOfflineCacheWorks(readerKind: id.readerKind, ownerKey: id.ownerKey)
        }
    }

    private func cancelOfflineCacheWorks(readerKind: OfflineCacheReaderKind, ownerKey: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let ownerKey = ownerKey.mangaReaderTrimmedNonEmpty else { return }
        do {
            try await database.write { db in
                let canceled = try Self.rawWorks(readerKind: readerKind, ownerKey: ownerKey, in: db)
                try db.execute(
                    sql: "DELETE FROM offline_cache_works WHERE reader_kind = ? AND owner_name = ?",
                    arguments: [readerKind.rawValue, ownerKey]
                )
                try Self.removeUnreferencedImages(
                    candidateImageURLs: canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs },
                    fileManager: fileManager,
                    imagesDirectory: imagesDirectory,
                    in: db
                )
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    static func save(_ work: OfflineCacheRawWork, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO offline_cache_works
            (reader_kind, work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                work.readerKind.rawValue,
                work.workID,
                work.ownerKey,
                work.entryKey,
                work.title,
                work.state.rawValue,
                work.failureMessage,
                work.currentBytesPerSecond,
                work.insertionIndex,
                offlineCacheTimeInterval(from: work.createdAt),
                offlineCacheTimeInterval(from: work.updatedAt)
            ]
        )
        try replaceImageList(
            table: "offline_cache_work_images",
            readerKind: work.readerKind.rawValue,
            ownerName: work.ownerKey,
            tid: work.entryKey,
            imageURLs: work.targetImageURLs,
            in: db
        )
        try replaceImageList(
            table: "offline_cache_completed_images",
            readerKind: work.readerKind.rawValue,
            ownerName: work.ownerKey,
            tid: work.entryKey,
            imageURLs: work.completedImageURLs,
            in: db
        )
    }

    static func rawWork(
        workID: String,
        readerKind: OfflineCacheReaderKind,
        in db: Database
    ) throws -> OfflineCacheRawWork? {
        guard let workID = workID.mangaReaderTrimmedNonEmpty,
              let row = try Row.fetchOne(
                db,
                sql: """
                SELECT reader_kind, work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
                FROM offline_cache_works
                WHERE reader_kind = ? AND work_id = ?
                """,
                arguments: [readerKind.rawValue, workID]
              ) else {
            return nil
        }
        return try rawWork(from: row, in: db)
    }

    static func rawWork(
        readerKind: OfflineCacheReaderKind,
        ownerKey: String,
        entryKey: String,
        in db: Database
    ) throws -> OfflineCacheRawWork? {
        guard let ownerKey = ownerKey.mangaReaderTrimmedNonEmpty,
              let entryKey = entryKey.mangaReaderTrimmedNonEmpty,
              let row = try Row.fetchOne(
                db,
                sql: """
                SELECT reader_kind, work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
                FROM offline_cache_works
                WHERE reader_kind = ? AND owner_name = ? AND tid = ?
                """,
                arguments: [readerKind.rawValue, ownerKey, entryKey]
              ) else {
            return nil
        }
        return try rawWork(from: row, in: db)
    }

    static func rawWorks(
        readerKind: OfflineCacheReaderKind,
        ownerKey: String,
        in db: Database
    ) throws -> [OfflineCacheRawWork] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT reader_kind, work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
            FROM offline_cache_works
            WHERE reader_kind = ? AND owner_name = ?
            ORDER BY insertion_index ASC, owner_name ASC, tid ASC
            """,
            arguments: [readerKind.rawValue, ownerKey]
        ).compactMap { try rawWork(from: $0, in: db) }
    }

    static func allRawWorks(in db: Database) throws -> [OfflineCacheRawWork] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT reader_kind, work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
            FROM offline_cache_works
            ORDER BY insertion_index ASC, reader_kind ASC, owner_name ASC, tid ASC
            """
        ).compactMap { try rawWork(from: $0, in: db) }
    }

    static func queueWorkProjection(from work: OfflineCacheRawWork) -> OfflineCacheQueueWorkProjection {
        let groupID = OfflineCacheGroupID(readerKind: work.readerKind, ownerKey: work.ownerKey)
        let entryID = OfflineCacheEntryID(readerKind: work.readerKind, ownerKey: work.ownerKey, entryKey: work.entryKey)
        return OfflineCacheQueueWorkProjection(
            id: OfflineCacheWorkID(readerKind: work.readerKind, rawValue: work.workID),
            groupID: groupID,
            entryID: entryID,
            ownerTitle: work.ownerKey,
            title: offlineCacheEntryTitle(chapterTitle: work.title, entryKey: work.entryKey),
            progress: OfflineCacheProgress(
                completedUnitCount: work.completedImageURLs.count,
                targetUnitCount: work.targetImageURLs.count
            ),
            state: work.state,
            failureMessage: work.failureMessage,
            currentBytesPerSecond: work.currentBytesPerSecond,
            insertionIndex: work.insertionIndex
        )
    }

    static func offlineCacheEntryTitle(chapterTitle: String, entryKey: String) -> String {
        chapterTitle.mangaReaderTrimmedNonEmpty ?? entryKey
    }

    private static func rawWork(from row: Row, in db: Database) throws -> OfflineCacheRawWork? {
        guard let readerKind = OfflineCacheReaderKind(rawValue: row["reader_kind"] as String) else {
            return nil
        }
        let ownerKey = row["owner_name"] as String
        let entryKey = row["tid"] as String
        return OfflineCacheRawWork(
            readerKind: readerKind,
            workID: row["work_id"],
            ownerKey: ownerKey,
            entryKey: entryKey,
            title: row["chapter_title"],
            targetImageURLs: try imageURLs(
                table: "offline_cache_work_images",
                readerKind: readerKind.rawValue,
                ownerName: ownerKey,
                tid: entryKey,
                in: db
            ),
            completedImageURLs: try imageURLs(
                table: "offline_cache_completed_images",
                readerKind: readerKind.rawValue,
                ownerName: ownerKey,
                tid: entryKey,
                in: db
            ),
            state: OfflineCacheWorkState(rawValue: row["state"] as String) ?? .paused,
            failureMessage: row["failure_message"] as String?,
            currentBytesPerSecond: row["current_bytes_per_second"] as Int,
            insertionIndex: row["insertion_index"] as Int,
            createdAt: offlineCacheOptionalDate(from: row["created_at"] as Double?) ?? Date(timeIntervalSince1970: 0),
            updatedAt: offlineCacheOptionalDate(from: row["updated_at"] as Double?) ?? Date(timeIntervalSince1970: 0)
        )
    }
}

struct OfflineCacheRawWork {
    var readerKind: OfflineCacheReaderKind
    var workID: String
    var ownerKey: String
    var entryKey: String
    var title: String
    var targetImageURLs: [URL]
    var completedImageURLs: [URL]
    var state: OfflineCacheWorkState
    var failureMessage: String?
    var currentBytesPerSecond: Int
    var insertionIndex: Int
    var createdAt: Date
    var updatedAt: Date
}

private func offlineCacheTimeInterval(from date: Date) -> Double {
    date.timeIntervalSince1970
}

private func offlineCacheOptionalDate(from value: Double?) -> Date? {
    value.map(Date.init(timeIntervalSince1970:))
}

private func offlineCachePersistenceError(from error: Error) -> YamiboError {
    if let error = error as? YamiboError {
        return error
    }
    return YamiboError.persistenceFailed(error.localizedDescription)
}
