import Foundation
@preconcurrency import GRDB

public actor OfflineCacheStore: OfflineCacheStoring {
    let database: DatabasePool
    nonisolated(unsafe) let fileManager: FileManager
    private let baseDirectory: URL
    let imagesDirectory: URL
    let novelSourcePagesDirectory: URL
    let novelProjectionPrewarmDirectory: URL
    private let updateNotifier = OfflineCacheUpdateNotifier()
    private var didRecoverQueueState = false
    private static let mangaReaderKind = "manga"

    public init(
        databasePool: DatabasePool? = nil,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.database = databasePool ?? Self.openDatabase()
        self.fileManager = fileManager
        let root = baseDirectory ?? Self.defaultBaseDirectory(fileManager: fileManager)
        self.baseDirectory = root
        self.imagesDirectory = root.appendingPathComponent("images", isDirectory: true)
        self.novelSourcePagesDirectory = root.appendingPathComponent("novel-source-pages", isDirectory: true)
        self.novelProjectionPrewarmDirectory = root.appendingPathComponent("novel-projections", isDirectory: true)
    }

    nonisolated public func offlineCacheUpdates() -> AsyncStream<Void> {
        updateNotifier.stream()
    }

    public func membership(ownerName: String, tid: String) async -> MangaOfflineCacheMembership? {
        try? await recoverQueueStateAfterRestart()
        guard let id = normalizedID(ownerName: ownerName, tid: tid) else { return nil }
        return try? await database.read { db in
            try Self.membership(ownerName: id.ownerName, tid: id.tid, in: db)
        }
    }

    public func memberships(forOwnerName ownerName: String) async -> [MangaOfflineCacheMembership] {
        try? await recoverQueueStateAfterRestart()
        guard let ownerName = ownerName.mangaReaderTrimmedNonEmpty else { return [] }
        return (try? await database.read { db in
            try Self.memberships(ownerName: ownerName, in: db)
        }) ?? []
    }

    public func allMemberships() async -> [MangaOfflineCacheMembership] {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            try Self.allMemberships(in: db)
        }) ?? []
    }

    public func saveMembership(_ membership: MangaOfflineCacheMembership) async throws {
        try await recoverQueueStateAfterRestart()
        do {
            try await database.write { db in
                let normalized = try Self.normalizedMembership(membership)
                try Self.save(normalized, in: db)
                if try Self.isMembershipComplete(normalized, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db) {
                    try Self.deleteWork(ownerName: normalized.ownerName, tid: normalized.tid, in: db)
                }
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func removeMembership(ownerName: String, tid: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let id = normalizedID(ownerName: ownerName, tid: tid) else { return }
        do {
            try await database.write { db in
                let removed = try Self.membership(ownerName: id.ownerName, tid: id.tid, in: db)
                let canceled = try Self.work(ownerName: id.ownerName, tid: id.tid, in: db)
                try Self.deleteMembership(ownerName: id.ownerName, tid: id.tid, in: db)
                try Self.deleteWork(ownerName: id.ownerName, tid: id.tid, in: db)
                let candidateURLs = (removed?.imageURLs ?? []) + (canceled.map { $0.targetImageURLs + $0.completedImageURLs } ?? [])
                try Self.removeUnreferencedImages(
                    candidateImageURLs: candidateURLs,
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

    public func removeMemberships(forOwnerName ownerName: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let ownerName = ownerName.mangaReaderTrimmedNonEmpty else { return }
        do {
            try await database.write { db in
                let removed = try Self.memberships(ownerName: ownerName, in: db)
                let canceled = try Self.works(ownerName: ownerName, in: db)
                try db.execute(sql: "DELETE FROM offline_cache_manga_entries WHERE owner_name = ?", arguments: [ownerName])
                try db.execute(
                    sql: "DELETE FROM offline_cache_works WHERE reader_kind = ? AND owner_name = ?",
                    arguments: [Self.mangaReaderKind, ownerName]
                )
                try Self.removeUnreferencedImages(
                    candidateImageURLs: removed.flatMap(\.imageURLs) + canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs },
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

    public func renameOwner(from oldOwnerName: String, to newOwnerName: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let oldOwnerName = oldOwnerName.mangaReaderTrimmedNonEmpty,
              let newOwnerName = newOwnerName.mangaReaderTrimmedNonEmpty,
              oldOwnerName != newOwnerName else {
            return
        }
        do {
            try await database.write { db in
                let memberships = try Self.memberships(ownerName: oldOwnerName, in: db)
                let works = try Self.works(ownerName: oldOwnerName, in: db)
                guard !memberships.isEmpty || !works.isEmpty else { return }

                try db.execute(sql: "DELETE FROM offline_cache_manga_entries WHERE owner_name = ?", arguments: [oldOwnerName])
                try db.execute(
                    sql: "DELETE FROM offline_cache_works WHERE reader_kind = ? AND owner_name = ?",
                    arguments: [Self.mangaReaderKind, oldOwnerName]
                )

                for membership in memberships {
                    try Self.save(MangaOfflineCacheMembership(
                        ownerName: newOwnerName,
                        tid: membership.tid,
                        chapterTitle: membership.chapterTitle,
                        chapterURL: Self.chapterURL(tid: membership.tid),
                        imageURLs: membership.imageURLs,
                        sourcePage: membership.sourcePage,
                        createdAt: membership.createdAt
                    ), in: db)
                }
                for work in works {
                    try Self.save(MangaOfflineCacheWork(
                        workID: work.workID,
                        ownerName: newOwnerName,
                        tid: work.tid,
                        chapterTitle: work.chapterTitle,
                        chapterURL: Self.chapterURL(tid: work.tid),
                        targetImageURLs: work.targetImageURLs,
                        completedImageURLs: work.completedImageURLs,
                        state: work.state,
                        failureMessage: work.failureMessage,
                        currentBytesPerSecond: work.currentBytesPerSecond,
                        insertionIndex: work.insertionIndex,
                        createdAt: work.createdAt,
                        updatedAt: work.updatedAt
                    ), in: db)
                }
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func offlineCacheWork(ownerName: String, tid: String) async -> MangaOfflineCacheWork? {
        try? await recoverQueueStateAfterRestart()
        guard let id = normalizedID(ownerName: ownerName, tid: tid) else { return nil }
        return try? await database.read { db in
            try Self.work(ownerName: id.ownerName, tid: id.tid, in: db)
        }
    }

    public func allOfflineCacheWorks() async -> [MangaOfflineCacheWork] {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            try Self.allWorks(in: db)
        }) ?? []
    }

    public func enqueueOfflineCacheWork(_ request: MangaOfflineCacheWorkRequest) async throws -> MangaOfflineCacheEnqueueResult {
        try await recoverQueueStateAfterRestart()
        do {
            let result: MangaOfflineCacheEnqueueResult = try await database.write { db in
                guard request.ownerName.mangaReaderTrimmedNonEmpty != nil else {
                    throw YamiboError.persistenceFailed("Offline cache owner is empty")
                }
                guard request.tid.mangaReaderTrimmedNonEmpty != nil else {
                    throw YamiboError.persistenceFailed("Chapter tid is empty")
                }
                let normalizedRequest = MangaOfflineCacheWorkRequest(
                    ownerName: request.ownerName,
                    tid: request.tid,
                    chapterTitle: request.chapterTitle,
                    chapterURL: Self.chapterURL(tid: request.tid),
                    targetImageURLs: request.targetImageURLs
                )
                if let membership = try Self.membership(ownerName: normalizedRequest.ownerName, tid: normalizedRequest.tid, in: db),
                   try Self.isMembershipComplete(membership, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db) {
                    return .alreadyCached(membership)
                }
                if let work = try Self.work(ownerName: normalizedRequest.ownerName, tid: normalizedRequest.tid, in: db) {
                    return .alreadyQueued(work)
                }
                let work = MangaOfflineCacheWork(
                    request: normalizedRequest,
                    insertionIndex: try Self.nextQueueInsertionIndex(in: db)
                )
                try Self.save(work, in: db)
                return .enqueued(work)
            }
            if result.enqueuedWork != nil {
                notifyOfflineCacheDidChange()
            }
            return result
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func updateOfflineCacheWorkProgress(
        ownerName: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL],
        currentBytesPerSecond: Int? = nil
    ) async throws {
        try await recoverQueueStateAfterRestart()
        try await updateWork(ownerName: ownerName, tid: tid) { work in
            work.updatingProgress(
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs,
                currentBytesPerSecond: currentBytesPerSecond
            )
        }
    }

    public func prepareOfflineCacheWorkForRun(
        ownerName: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL]
    ) async throws {
        try await recoverQueueStateAfterRestart()
        try await updateWork(ownerName: ownerName, tid: tid) { work in
            work.preparingForRun(targetImageURLs: targetImageURLs, completedImageURLs: completedImageURLs)
        }
    }

    public func markOfflineCacheWorkFailed(ownerName: String, tid: String, message: String?) async throws {
        try await recoverQueueStateAfterRestart()
        try await updateWork(ownerName: ownerName, tid: tid) { work in
            work.markingFailed(message: message)
        }
    }

    public func cancelOfflineCacheWork(ownerName: String, tid: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let id = normalizedID(ownerName: ownerName, tid: tid) else { return }
        do {
            try await database.write { db in
                guard let canceled = try Self.work(ownerName: id.ownerName, tid: id.tid, in: db) else { return }
                try Self.deleteWork(ownerName: id.ownerName, tid: id.tid, in: db)
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

    public func cancelOfflineCacheWorks(forOwnerName ownerName: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let ownerName = ownerName.mangaReaderTrimmedNonEmpty else { return }
        do {
            try await database.write { db in
                let canceled = try Self.works(ownerName: ownerName, in: db)
                try db.execute(
                    sql: "DELETE FROM offline_cache_works WHERE reader_kind = ? AND owner_name = ?",
                    arguments: [Self.mangaReaderKind, ownerName]
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

    public func clearOfflineCacheQueue() async throws {
        try await recoverQueueStateAfterRestart()
        try await database.write { db in
            try db.execute(sql: "DELETE FROM offline_cache_works")
            try Self.setQueueRunState(.paused, in: db)
        }
        notifyOfflineCacheDidChange()
    }

    public func offlineCacheQueueRunState() async -> MangaOfflineCacheQueueRunState {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            try Self.queueRunState(in: db)
        }) ?? .paused
    }

    public func setOfflineCacheQueueRunState(_ state: MangaOfflineCacheQueueRunState) async throws {
        didRecoverQueueState = true
        do {
            try await database.write { db in
                try Self.setQueueRunState(state, in: db)
                if state == .paused {
                    try Self.pauseRunningOfflineCacheWorks(in: db)
                }
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func offlineCacheState(ownerName: String, tid: String) async -> MangaOfflineCacheState {
        try? await recoverQueueStateAfterRestart()
        guard let id = normalizedID(ownerName: ownerName, tid: tid) else { return .uncached }
        return (try? await database.read { db in
            if let membership = try Self.membership(ownerName: id.ownerName, tid: id.tid, in: db),
               try Self.isMembershipComplete(membership, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db) {
                return .cached
            }
            if try Self.work(ownerName: id.ownerName, tid: id.tid, in: db) != nil {
                return .caching
            }
            return .uncached
        }) ?? .uncached
    }

    public func clearAll() async throws {
        do {
            try await database.write { db in
                try db.execute(sql: "DELETE FROM offline_cache_completed_images")
                try db.execute(sql: "DELETE FROM offline_cache_work_images")
                try db.execute(sql: "DELETE FROM offline_cache_works")
                try db.execute(sql: "DELETE FROM offline_cache_novel_entry_images")
                try db.execute(sql: "DELETE FROM offline_cache_novel_entries")
                try db.execute(sql: "DELETE FROM offline_cache_manga_entry_images")
                try db.execute(sql: "DELETE FROM offline_cache_manga_entries")
                try db.execute(sql: "DELETE FROM offline_cache_image_assets")
                try db.execute(sql: "DELETE FROM offline_cache_queue_state")
                try db.execute(sql: "DELETE FROM manga_offline_cache_completed_images")
                try db.execute(sql: "DELETE FROM manga_offline_cache_work_images")
                try db.execute(sql: "DELETE FROM manga_offline_cache_works")
                try db.execute(sql: "DELETE FROM manga_offline_cache_membership_images")
                try db.execute(sql: "DELETE FROM manga_offline_cache_memberships")
                try db.execute(sql: "DELETE FROM manga_offline_cache_images")
                try db.execute(sql: "DELETE FROM manga_offline_cache_queue_state")
            }
            if fileManager.fileExists(atPath: baseDirectory.path) {
                try fileManager.removeItem(at: baseDirectory)
            }
            didRecoverQueueState = true
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            let imageBytes = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(byte_count), 0) FROM offline_cache_image_assets"
            ) ?? 0
            let novelBytes = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(byte_count), 0) FROM offline_cache_novel_entries"
            ) ?? 0
            return imageBytes + novelBytes
        }) ?? 0
    }

    private func updateWork(
        ownerName: String,
        tid: String,
        transform: @Sendable (MangaOfflineCacheWork) -> MangaOfflineCacheWork
    ) async throws {
        guard let id = normalizedID(ownerName: ownerName, tid: tid) else { return }
        do {
            try await database.write { db in
                guard let work = try Self.work(ownerName: id.ownerName, tid: id.tid, in: db) else { return }
                try Self.save(transform(work), in: db)
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    func recoverQueueStateAfterRestart() async throws {
        guard !didRecoverQueueState else { return }
        didRecoverQueueState = true
        try await database.write { db in
            if try Self.queueRunState(in: db) == .running {
                try Self.setQueueRunState(.paused, in: db)
                try Self.pauseRunningOfflineCacheWorks(in: db)
            }
        }
    }

    private func normalizedID(ownerName: String, tid: String) -> MangaOfflineCacheMembershipID? {
        guard let ownerName = ownerName.mangaReaderTrimmedNonEmpty,
              let tid = tid.mangaReaderTrimmedNonEmpty else {
            return nil
        }
        return MangaOfflineCacheMembershipID(ownerName: ownerName, tid: tid)
    }

    func notifyOfflineCacheDidChange() {
        updateNotifier.notify()
    }

    func ensureBaseDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    func ensureNovelSourcePagesDirectoryExists() throws {
        try ensureBaseDirectoryExists()
        if !fileManager.fileExists(atPath: novelSourcePagesDirectory.path) {
            try fileManager.createDirectory(at: novelSourcePagesDirectory, withIntermediateDirectories: true)
        }
    }

    func ensureNovelProjectionPrewarmDirectoryExists() throws {
        try ensureBaseDirectoryExists()
        if !fileManager.fileExists(atPath: novelProjectionPrewarmDirectory.path) {
            try fileManager.createDirectory(at: novelProjectionPrewarmDirectory, withIntermediateDirectories: true)
        }
    }

    private static func normalizedMembership(_ membership: MangaOfflineCacheMembership) throws -> MangaOfflineCacheMembership {
        guard membership.ownerName.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.persistenceFailed("Offline cache owner is empty")
        }
        guard membership.tid.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.persistenceFailed("Chapter tid is empty")
        }
        return MangaOfflineCacheMembership(
            ownerName: membership.ownerName,
            tid: membership.tid,
            chapterTitle: membership.chapterTitle,
            chapterURL: chapterURL(tid: membership.tid),
            imageURLs: membership.imageURLs,
            sourcePage: membership.sourcePage,
            createdAt: membership.createdAt
        )
    }

    private static func save(_ membership: MangaOfflineCacheMembership, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO offline_cache_manga_entries (owner_name, tid, chapter_title, source_page_json, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [
                membership.ownerName,
                membership.tid,
                membership.chapterTitle,
                try encodeSourcePage(membership.sourcePage),
                offlineCacheTimeInterval(from: membership.createdAt)
            ]
        )
        try db.execute(
            sql: "DELETE FROM offline_cache_manga_entry_images WHERE owner_name = ? AND tid = ?",
            arguments: [membership.ownerName, membership.tid]
        )
        for (index, imageURL) in membership.imageURLs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO offline_cache_manga_entry_images (owner_name, tid, manual_order, image_url)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [membership.ownerName, membership.tid, index, imageURL.absoluteString]
            )
        }
    }

    private static func save(_ work: MangaOfflineCacheWork, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO offline_cache_works
            (reader_kind, work_id, owner_name, tid, chapter_title, retains_inline_images, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                mangaReaderKind,
                work.workID,
                work.ownerName,
                work.tid,
                work.chapterTitle,
                false,
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
            readerKind: mangaReaderKind,
            ownerName: work.ownerName,
            tid: work.tid,
            imageURLs: work.targetImageURLs,
            in: db
        )
        try replaceImageList(
            table: "offline_cache_completed_images",
            readerKind: mangaReaderKind,
            ownerName: work.ownerName,
            tid: work.tid,
            imageURLs: work.completedImageURLs,
            in: db
        )
    }

    static func replaceImageList(
        table: String,
        readerKind: String,
        ownerName: String,
        tid: String,
        imageURLs: [URL],
        in db: Database
    ) throws {
        try db.execute(
            sql: "DELETE FROM \(table) WHERE reader_kind = ? AND owner_name = ? AND tid = ?",
            arguments: [readerKind, ownerName, tid]
        )
        for (index, imageURL) in imageURLs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO \(table) (reader_kind, owner_name, tid, manual_order, image_url)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [readerKind, ownerName, tid, index, imageURL.absoluteString]
            )
        }
    }

    private static func membership(ownerName: String, tid: String, in db: Database) throws -> MangaOfflineCacheMembership? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT owner_name, tid, chapter_title, source_page_json, created_at
            FROM offline_cache_manga_entries
            WHERE owner_name = ? AND tid = ?
            """,
            arguments: [ownerName, tid]
        ) else {
            return nil
        }
        return try membership(from: row, in: db)
    }

    private static func memberships(ownerName: String, in db: Database) throws -> [MangaOfflineCacheMembership] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT owner_name, tid, chapter_title, source_page_json, created_at
            FROM offline_cache_manga_entries
            WHERE owner_name = ?
            ORDER BY owner_name ASC, tid ASC
            """,
            arguments: [ownerName]
        ).map { try membership(from: $0, in: db) }
    }

    static func allMemberships(in db: Database) throws -> [MangaOfflineCacheMembership] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT owner_name, tid, chapter_title, source_page_json, created_at
            FROM offline_cache_manga_entries
            ORDER BY owner_name ASC, tid ASC
            """
        ).map { try membership(from: $0, in: db) }
    }

    private static func membership(from row: Row, in db: Database) throws -> MangaOfflineCacheMembership {
        let tid = row["tid"] as String
        return MangaOfflineCacheMembership(
            ownerName: row["owner_name"],
            tid: tid,
            chapterTitle: row["chapter_title"],
            chapterURL: chapterURL(tid: tid),
            imageURLs: try imageURLs(
                table: "offline_cache_manga_entry_images",
                ownerName: row["owner_name"],
                tid: tid,
                in: db
            ),
            sourcePage: try decodeSourcePage(row["source_page_json"] as String?),
            createdAt: offlineCacheOptionalDate(from: row["created_at"] as Double?) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func work(ownerName: String, tid: String, in db: Database) throws -> MangaOfflineCacheWork? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
            FROM offline_cache_works
            WHERE reader_kind = ? AND owner_name = ? AND tid = ?
            """,
            arguments: [mangaReaderKind, ownerName, tid]
        ) else {
            return nil
        }
        return try work(from: row, in: db)
    }

    private static func works(ownerName: String, in db: Database) throws -> [MangaOfflineCacheWork] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
            FROM offline_cache_works
            WHERE reader_kind = ? AND owner_name = ?
            ORDER BY insertion_index ASC, owner_name ASC, tid ASC
            """,
            arguments: [mangaReaderKind, ownerName]
        ).map { try work(from: $0, in: db) }
    }

    static func allWorks(in db: Database) throws -> [MangaOfflineCacheWork] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
            FROM offline_cache_works
            WHERE reader_kind = ?
            ORDER BY insertion_index ASC, owner_name ASC, tid ASC
            """,
            arguments: [mangaReaderKind]
        ).map { try work(from: $0, in: db) }
    }

    private static func work(workID: String, in db: Database) throws -> MangaOfflineCacheWork? {
        guard let workID = workID.mangaReaderTrimmedNonEmpty,
              let row = try Row.fetchOne(
                db,
                sql: """
                SELECT work_id, owner_name, tid, chapter_title, state, failure_message, current_bytes_per_second, insertion_index, created_at, updated_at
                FROM offline_cache_works
                WHERE reader_kind = ? AND work_id = ?
                """,
                arguments: [mangaReaderKind, workID]
              ) else {
            return nil
        }
        return try work(from: row, in: db)
    }

    private static func work(from row: Row, in db: Database) throws -> MangaOfflineCacheWork {
        let tid = row["tid"] as String
        let state = MangaOfflineCacheWorkState(rawValue: row["state"] as String) ?? .paused
        return MangaOfflineCacheWork(
            workID: row["work_id"],
            ownerName: row["owner_name"],
            tid: tid,
            chapterTitle: row["chapter_title"],
            chapterURL: chapterURL(tid: tid),
            targetImageURLs: try imageURLs(
                table: "offline_cache_work_images",
                readerKind: mangaReaderKind,
                ownerName: row["owner_name"],
                tid: tid,
                in: db
            ),
            completedImageURLs: try imageURLs(
                table: "offline_cache_completed_images",
                readerKind: mangaReaderKind,
                ownerName: row["owner_name"],
                tid: tid,
                in: db
            ),
            state: state,
            failureMessage: row["failure_message"] as String?,
            currentBytesPerSecond: row["current_bytes_per_second"] as Int,
            insertionIndex: row["insertion_index"] as Int,
            createdAt: offlineCacheOptionalDate(from: row["created_at"] as Double?) ?? Date(timeIntervalSince1970: 0),
            updatedAt: offlineCacheOptionalDate(from: row["updated_at"] as Double?) ?? Date(timeIntervalSince1970: 0)
        )
    }

    static func imageURLs(
        table: String,
        readerKind: String? = nil,
        ownerName: String,
        tid: String,
        in db: Database
    ) throws -> [URL] {
        if let readerKind {
            return try String.fetchAll(
                db,
                sql: """
                SELECT image_url
                FROM \(table)
                WHERE reader_kind = ? AND owner_name = ? AND tid = ?
                ORDER BY manual_order ASC
                """,
                arguments: [readerKind, ownerName, tid]
            ).compactMap(URL.init(string:))
        }

        return try String.fetchAll(
            db,
            sql: """
            SELECT image_url
            FROM \(table)
            WHERE owner_name = ? AND tid = ?
            ORDER BY manual_order ASC
            """,
            arguments: [ownerName, tid]
        ).compactMap(URL.init(string:))
    }

    private static func deleteMembership(ownerName: String, tid: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM offline_cache_manga_entries WHERE owner_name = ? AND tid = ?",
            arguments: [ownerName, tid]
        )
    }

    static func deleteWork(ownerName: String, tid: String, in db: Database) throws {
        try deleteWork(readerKind: mangaReaderKind, ownerName: ownerName, tid: tid, in: db)
    }

    static func deleteWork(readerKind: String, ownerName: String, tid: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM offline_cache_works WHERE reader_kind = ? AND owner_name = ? AND tid = ?",
            arguments: [readerKind, ownerName, tid]
        )
    }

    private static func encodeSourcePage(_ sourcePage: ForumThreadPage?) throws -> String? {
        guard let sourcePage else { return nil }
        let data = try JSONEncoder().encode(sourcePage)
        return String(data: data, encoding: .utf8)
    }

    private static func decodeSourcePage(_ value: String?) throws -> ForumThreadPage? {
        guard let value,
              let data = value.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(ForumThreadPage.self, from: data)
    }

    private static func nextQueueInsertionIndex(in db: Database) throws -> Int {
        try nextQueueInsertionIndex(readerKind: mangaReaderKind, in: db)
    }

    static func nextQueueInsertionIndex(readerKind: String, in db: Database) throws -> Int {
        (try Int.fetchOne(
            db,
            sql: "SELECT MAX(insertion_index) FROM offline_cache_works WHERE reader_kind = ?",
            arguments: [readerKind]
        ) ?? 0) + 1
    }

    private static func pauseRunningOfflineCacheWorks(in db: Database) throws {
        try db.execute(
            sql: """
            UPDATE offline_cache_works
            SET state = ?, current_bytes_per_second = 0
            WHERE state = ?
            """,
            arguments: [
                MangaOfflineCacheWorkState.paused.rawValue,
                MangaOfflineCacheWorkState.running.rawValue
            ]
        )
    }

    private static func queueRunState(in db: Database) throws -> MangaOfflineCacheQueueRunState {
        guard let rawValue = try String.fetchOne(
            db,
            sql: "SELECT value FROM offline_cache_queue_state WHERE key = ?",
            arguments: ["run_state"]
        ) else {
            return .paused
        }
        return MangaOfflineCacheQueueRunState(rawValue: rawValue) ?? .paused
    }

    private static func setQueueRunState(_ state: MangaOfflineCacheQueueRunState, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO offline_cache_queue_state (key, value)
            VALUES (?, ?)
            """,
            arguments: ["run_state", state.rawValue]
        )
    }

    private static func chapterURL(tid: String) -> URL {
        YamiboRoute.chapterURL(forTID: tid) ?? URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=0")!
    }

    private static func defaultBaseDirectory(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("offline-cache", isDirectory: true)
    }

    private static func openDatabase() -> DatabasePool {
        do {
            return try YamiboDatabase.openSharedPool()
        } catch {
            fatalError("Failed to open OfflineCacheStore database: \(error)")
        }
    }
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

private final class OfflineCacheUpdateNotifier: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    func stream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    func notify() {
        let activeContinuations = lock.withLock {
            Array(continuations.values)
        }
        for continuation in activeContinuations {
            continuation.yield(())
        }
    }

    private func removeContinuation(id: UUID) {
        _ = lock.withLock {
            continuations.removeValue(forKey: id)
        }
    }
}
