import Foundation
@preconcurrency import GRDB

extension OfflineCacheStore {
    private static let novelEntryColumnList = """
    owner_name, entry_key, title, thread_url, view, author_id, content_source, document_json,
    source_page_file_name, source_page_schema_version, source_page_fingerprint,
    projection_file_name, projection_schema_version, byte_count, created_at, updated_at
    """

    public func removeOfflineCacheGroup(_ id: OfflineCacheGroupID) async throws {
        switch id.readerKind {
        case .manga:
            try await removeMemberships(forOwnerName: id.ownerKey)
        case .novel:
            try await removeNovelOfflineCacheEntries(ownerName: id.ownerKey)
        }
    }

    public func removeOfflineCacheEntry(_ id: OfflineCacheEntryID) async throws {
        switch id.readerKind {
        case .manga:
            try await removeMembership(ownerName: id.ownerKey, tid: id.entryKey)
        case .novel:
            try await removeNovelOfflineCacheEntry(ownerName: id.ownerKey, entryKey: id.entryKey)
        }
    }

    public func saveNovelOfflineCacheEntry(_ entry: NovelOfflineCacheEntry) async throws {
        let request = NovelOfflineCacheWorkRequest(
            ownerTitle: entry.ownerTitle,
            title: entry.title,
            threadURL: entry.document.threadURL,
            view: entry.document.view,
            authorID: entry.document.resolvedAuthorID,
            contentSource: entry.document.contentSource,
            targetImageURLs: entry.imageURLs,
            retainsInlineImages: !entry.imageURLs.isEmpty
        )
        try await saveNovelOfflineSourcePage(
            Self.syntheticSourcePage(from: entry.document),
            request: request,
            projectionPrewarm: entry.document,
            updatedAt: entry.updatedAt
        )
    }

    public func novelOfflineCacheEntry(id: OfflineCacheEntryID) async -> NovelOfflineCacheEntry? {
        try? await recoverQueueStateAfterRestart()
        guard id.readerKind == .novel else { return nil }
        return try? await database.read { db in
            try Self.novelEntry(ownerName: id.ownerKey, entryKey: id.entryKey, in: db)
        }
    }

    public func allNovelOfflineCacheEntries() async -> [NovelOfflineCacheEntry] {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            try Self.allNovelEntries(in: db)
        }) ?? []
    }

    public func novelOfflineCacheViewsSnapshot(
        ownerTitle: String,
        threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> NovelOfflineCacheViewsSnapshot {
        try? await recoverQueueStateAfterRestart()
        guard let lookup = novelEntryLookup(
            ownerTitle: ownerTitle,
            threadURL: threadURL,
            view: 1,
            authorID: authorID,
            contentSource: contentSource
        ) else { return NovelOfflineCacheViewsSnapshot() }
        return (try? await database.read { db in
            let cachedRows: [Row]
            if let authorID = lookup.authorID {
                cachedRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT view, source_page_file_name, updated_at
                    FROM offline_cache_novel_entries
                    WHERE owner_name = ? AND thread_url = ? AND author_id = ? AND content_source = ?
                    ORDER BY view ASC
                    """,
                    arguments: [
                        lookup.ownerTitle,
                        lookup.threadURL.absoluteString,
                        authorID,
                        lookup.contentSource.rawValue
                    ]
                )
            } else {
                cachedRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT view, source_page_file_name, updated_at
                    FROM offline_cache_novel_entries
                    WHERE owner_name = ? AND thread_url = ? AND author_id IS NULL AND content_source = ?
                    ORDER BY view ASC
                    """,
                    arguments: [
                        lookup.ownerTitle,
                        lookup.threadURL.absoluteString,
                        lookup.contentSource.rawValue
                    ]
                )
            }
            var cachedViews: Set<Int> = []
            var updateTimes: [Int: Date] = [:]
            for row in cachedRows {
                let view = row["view"] as Int
                guard let fileName = row["source_page_file_name"] as String?,
                      Self.payloadFileExists(
                        fileName: fileName,
                        directory: novelSourcePagesDirectory,
                        fileManager: fileManager
                      ) else {
                    continue
                }
                cachedViews.insert(view)
                if let updatedAt = offlineCacheOptionalDate(from: row["updated_at"] as Double?) {
                    updateTimes[view] = updatedAt
                }
            }

            let works = try Self.rawWorks(readerKind: .novel, ownerKey: lookup.ownerTitle, in: db)
            let cachingViews = Set(works.compactMap { work -> Int? in
                guard let parsed = Self.novelEntryKeyComponents(from: work.entryKey),
                      parsed.threadID == lookup.threadID,
                      parsed.authorID == lookup.authorID,
                      parsed.contentSource == lookup.contentSource else {
                    return nil
                }
                return parsed.view
            })
            return NovelOfflineCacheViewsSnapshot(
                cachedViews: cachedViews,
                cachingViews: cachingViews,
                updateTimesByView: updateTimes
            )
        }) ?? NovelOfflineCacheViewsSnapshot()
    }

    public func removeNovelOfflineCacheViews(
        _ views: Set<Int>,
        ownerTitle: String,
        threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        for view in views {
            guard let lookup = novelEntryLookup(
                ownerTitle: ownerTitle,
                threadURL: threadURL,
                view: view,
                authorID: authorID,
                contentSource: contentSource
            ) else { continue }
            try await removeNovelOfflineCacheEntry(ownerName: lookup.ownerTitle, entryKey: lookup.entryKey)
        }
    }

    private func removeNovelOfflineCacheEntry(ownerName: String, entryKey: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let ownerName = ownerName.mangaReaderTrimmedNonEmpty,
              let entryKey = entryKey.mangaReaderTrimmedNonEmpty else { return }
        do {
            let files = try await database.write { db -> NovelPayloadFileNames in
                let removed = try Self.novelEntry(ownerName: ownerName, entryKey: entryKey, in: db)
                let canceled = try Self.rawWork(readerKind: .novel, ownerKey: ownerName, entryKey: entryKey, in: db)
                let files = try Self.novelPayloadFileNames(ownerName: ownerName, entryKey: entryKey, in: db)
                try Self.deleteNovelEntry(ownerName: ownerName, entryKey: entryKey, in: db)
                try Self.deleteWork(
                    readerKind: OfflineCacheReaderKind.novel.rawValue,
                    ownerName: ownerName,
                    tid: entryKey,
                    in: db
                )
                try Self.removeUnreferencedImages(
                    candidateImageURLs: (removed?.imageURLs ?? []) + (canceled.map { $0.targetImageURLs + $0.completedImageURLs } ?? []),
                    fileManager: fileManager,
                    imagesDirectory: imagesDirectory,
                    in: db
                )
                return files
            }
            removeNovelPayloadFiles(files)
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    private func removeNovelOfflineCacheEntries(ownerName: String) async throws {
        try await recoverQueueStateAfterRestart()
        guard let ownerName = ownerName.mangaReaderTrimmedNonEmpty else { return }
        do {
            let files = try await database.write { db -> NovelPayloadFileNames in
                let removed = try Self.novelEntries(ownerName: ownerName, in: db)
                let canceled = try Self.rawWorks(readerKind: .novel, ownerKey: ownerName, in: db)
                let files = try Self.novelPayloadFileNames(ownerName: ownerName, in: db)
                try db.execute(sql: "DELETE FROM offline_cache_novel_entries WHERE owner_name = ?", arguments: [ownerName])
                try db.execute(
                    sql: "DELETE FROM offline_cache_works WHERE reader_kind = ? AND owner_name = ?",
                    arguments: [OfflineCacheReaderKind.novel.rawValue, ownerName]
                )
                try Self.removeUnreferencedImages(
                    candidateImageURLs: removed.flatMap(\.imageURLs) + canceled.flatMap { $0.targetImageURLs + $0.completedImageURLs },
                    fileManager: fileManager,
                    imagesDirectory: imagesDirectory,
                    in: db
                )
                return files
            }
            removeNovelPayloadFiles(files)
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    static func normalizedNovelWorkRequest(
        _ request: NovelOfflineCacheWorkRequest
    ) throws -> NovelOfflineCacheWorkRequest {
        guard request.ownerTitle.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.persistenceFailed("Offline cache owner is empty")
        }
        guard request.entryKey.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.persistenceFailed("Novel offline cache entry is empty")
        }
        return NovelOfflineCacheWorkRequest(
            ownerTitle: request.ownerTitle,
            title: request.title,
            threadURL: request.threadURL,
            view: request.view,
            authorID: request.authorID,
            contentSource: request.contentSource,
            targetImageURLs: request.targetImageURLs,
            retainsInlineImages: request.retainsInlineImages
        )
    }

    static func novelEntry(ownerName: String, entryKey: String, in db: Database) throws -> NovelOfflineCacheEntry? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT \(novelEntryColumnList)
            FROM offline_cache_novel_entries
            WHERE owner_name = ? AND entry_key = ?
            """,
            arguments: [ownerName, entryKey]
        ) else {
            return nil
        }
        return try novelEntry(from: row, in: db)
    }

    static func novelEntries(ownerName: String, in db: Database) throws -> [NovelOfflineCacheEntry] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT \(novelEntryColumnList)
            FROM offline_cache_novel_entries
            WHERE owner_name = ?
            ORDER BY owner_name ASC, view ASC, entry_key ASC
            """,
            arguments: [ownerName]
        ).map { try novelEntry(from: $0, in: db) }
    }

    static func allNovelEntries(in db: Database) throws -> [NovelOfflineCacheEntry] {
        try Row.fetchAll(
            db,
            sql: """
            SELECT \(novelEntryColumnList)
            FROM offline_cache_novel_entries
            ORDER BY owner_name ASC, view ASC, entry_key ASC
            """
        ).map { try novelEntry(from: $0, in: db) }
    }

    static func novelEntryByteCount(ownerName: String, entryKey: String, in db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT byte_count FROM offline_cache_novel_entries WHERE owner_name = ? AND entry_key = ?",
            arguments: [ownerName, entryKey]
        ) ?? 0
    }

    private static func normalizedNovelEntry(_ entry: NovelOfflineCacheEntry) throws -> NovelOfflineCacheEntry {
        guard entry.ownerTitle.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.persistenceFailed("Offline cache owner is empty")
        }
        guard entry.id.entryKey.mangaReaderTrimmedNonEmpty != nil else {
            throw YamiboError.persistenceFailed("Novel offline cache entry is empty")
        }
        return NovelOfflineCacheEntry(
            ownerTitle: entry.ownerTitle,
            title: entry.title,
            document: entry.document,
            imageURLs: entry.imageURLs,
            updatedAt: entry.updatedAt
        )
    }

    private static func save(_ entry: NovelOfflineCacheEntry, in db: Database) throws {
        let documentJSON = try encodeNovelDocument(entry.document)
        let entryKey = entry.id.entryKey
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO offline_cache_novel_entries
            (
                owner_name, entry_key, title, thread_url, view, author_id, content_source, document_json,
                source_page_file_name, source_page_schema_version, source_page_fingerprint,
                projection_file_name, projection_schema_version, byte_count, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, NULL, ?, COALESCE((SELECT created_at FROM offline_cache_novel_entries WHERE owner_name = ? AND entry_key = ?), ?), ?)
            """,
            arguments: [
                entry.ownerTitle,
                entryKey,
                entry.title,
                entry.document.threadURL.absoluteString,
                entry.document.view,
                entry.document.resolvedAuthorID,
                entry.document.contentSource.rawValue,
                documentJSON,
                documentJSON.utf8.count,
                entry.ownerTitle,
                entryKey,
                offlineCacheTimeInterval(from: entry.updatedAt),
                offlineCacheTimeInterval(from: entry.updatedAt)
            ]
        )
        try db.execute(
            sql: "DELETE FROM offline_cache_novel_entry_images WHERE owner_name = ? AND entry_key = ?",
            arguments: [entry.ownerTitle, entryKey]
        )
        for (index, imageURL) in entry.imageURLs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO offline_cache_novel_entry_images (owner_name, entry_key, manual_order, image_url)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [entry.ownerTitle, entryKey, index, imageURL.absoluteString]
            )
        }
    }

    static func saveNovelSourcePageMetadata(
        request: NovelOfflineCacheWorkRequest,
        documentJSON: String,
        sourceFileName: String,
        sourceFingerprint: String,
        sourceByteCount: Int,
        imageURLs: [URL],
        updatedAt: Date,
        in db: Database
    ) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO offline_cache_novel_entries
            (
                owner_name, entry_key, title, thread_url, view, author_id, content_source, document_json,
                source_page_file_name, source_page_schema_version, source_page_fingerprint,
                projection_file_name, projection_schema_version, byte_count, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE((SELECT projection_file_name FROM offline_cache_novel_entries WHERE owner_name = ? AND entry_key = ?), NULL), COALESCE((SELECT projection_schema_version FROM offline_cache_novel_entries WHERE owner_name = ? AND entry_key = ?), NULL), ?, COALESCE((SELECT created_at FROM offline_cache_novel_entries WHERE owner_name = ? AND entry_key = ?), ?), ?)
            """,
            arguments: [
                request.ownerTitle,
                request.entryKey,
                request.title.isEmpty ? L10n.string("reader.page_number_spaced", request.view) : request.title,
                request.threadURL.absoluteString,
                request.view,
                request.authorID,
                request.contentSource.rawValue,
                documentJSON,
                sourceFileName,
                NovelOfflineCacheEntry.sourcePageSchemaVersion,
                sourceFingerprint,
                request.ownerTitle,
                request.entryKey,
                request.ownerTitle,
                request.entryKey,
                sourceByteCount,
                request.ownerTitle,
                request.entryKey,
                offlineCacheTimeInterval(from: updatedAt),
                offlineCacheTimeInterval(from: updatedAt)
            ]
        )
        try db.execute(
            sql: "DELETE FROM offline_cache_novel_entry_images WHERE owner_name = ? AND entry_key = ?",
            arguments: [request.ownerTitle, request.entryKey]
        )
        for (index, imageURL) in imageURLs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO offline_cache_novel_entry_images (owner_name, entry_key, manual_order, image_url)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [request.ownerTitle, request.entryKey, index, imageURL.absoluteString]
            )
        }
    }

    static func imageURLsForNovelSourcePageMetadata(
        request: NovelOfflineCacheWorkRequest,
        imageURLs: [URL],
        preservesExistingImageReferencesWhenEmpty: Bool,
        in db: Database
    ) throws -> [URL] {
        guard preservesExistingImageReferencesWhenEmpty, imageURLs.isEmpty else {
            return imageURLs
        }
        return try novelImageURLs(ownerName: request.ownerTitle, entryKey: request.entryKey, in: db)
    }

    private static func novelEntry(from row: Row, in db: Database) throws -> NovelOfflineCacheEntry {
        NovelOfflineCacheEntry(
            ownerTitle: row["owner_name"],
            title: row["title"],
            document: try decodeNovelDocument(row["document_json"] as String),
            imageURLs: try novelImageURLs(ownerName: row["owner_name"], entryKey: row["entry_key"], in: db),
            updatedAt: offlineCacheOptionalDate(from: row["updated_at"] as Double?) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func novelImageURLs(ownerName: String, entryKey: String, in db: Database) throws -> [URL] {
        try String.fetchAll(
            db,
            sql: """
            SELECT image_url
            FROM offline_cache_novel_entry_images
            WHERE owner_name = ? AND entry_key = ?
            ORDER BY manual_order ASC
            """,
            arguments: [ownerName, entryKey]
        ).compactMap(URL.init(string:))
    }

    private static func deleteNovelEntry(ownerName: String, entryKey: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM offline_cache_novel_entries WHERE owner_name = ? AND entry_key = ?",
            arguments: [ownerName, entryKey]
        )
    }

    static func encodeNovelDocument(_ document: ReaderPageDocument) throws -> String {
        let data = try JSONEncoder().encode(document)
        guard let value = String(data: data, encoding: .utf8) else {
            throw YamiboError.persistenceFailed("Failed to encode novel offline cache document")
        }
        return value
    }

    private static func decodeNovelDocument(_ value: String) throws -> ReaderPageDocument {
        guard let data = value.data(using: .utf8) else {
            throw YamiboError.persistenceFailed("Failed to decode novel offline cache document")
        }
        return try JSONDecoder().decode(ReaderPageDocument.self, from: data)
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
