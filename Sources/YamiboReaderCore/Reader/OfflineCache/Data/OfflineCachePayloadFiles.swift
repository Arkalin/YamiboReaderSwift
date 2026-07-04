import Foundation
@preconcurrency import GRDB

extension OfflineCacheStore {
    public func saveNovelOfflineSourcePage(
        _ sourcePage: ForumThreadPage,
        request: NovelOfflineCacheWorkRequest,
        projectionPrewarm: ReaderPageDocument?,
        updatedAt: Date = .now,
        completesMatchingWork: Bool = true,
        preservesExistingImageReferencesWhenEmpty: Bool = false
    ) async throws {
        try await recoverQueueStateAfterRestart()
        do {
            let normalized = try Self.normalizedNovelWorkRequest(request)
            let sourceData = try Self.encodeJSONData(sourcePage, context: "novel offline source page")
            let sourceFileName = novelPayloadFileName(
                prefix: "source",
                entryKey: normalized.entryKey
            )
            try ensureNovelSourcePagesDirectoryExists()
            let sourceURL = novelSourcePagesDirectory.appendingPathComponent(sourceFileName, isDirectory: false)
            try sourceData.write(to: sourceURL, options: [.atomic])
            let document = try projectionPrewarm ?? Self.projectionDocument(
                from: sourcePage,
                request: normalized
            )
            let documentJSON = try Self.encodeNovelDocument(document)
            let sourceFingerprint = sha256Hex(String(decoding: sourceData, as: UTF8.self))

            let previousFiles = try await database.write { db in
                let previousFiles = try Self.novelPayloadFileNames(entryKey: normalized.entryKey, in: db)
                let imageURLs = try Self.imageURLsForNovelSourcePageMetadata(
                    request: normalized,
                    imageURLs: normalized.targetImageURLs,
                    preservesExistingImageReferencesWhenEmpty: preservesExistingImageReferencesWhenEmpty,
                    in: db
                )
                try Self.saveNovelSourcePageMetadata(
                    request: normalized,
                    documentJSON: documentJSON,
                    sourceFileName: sourceFileName,
                    sourceFingerprint: sourceFingerprint,
                    sourceByteCount: sourceData.count,
                    imageURLs: imageURLs,
                    updatedAt: updatedAt,
                    in: db
                )
                if completesMatchingWork {
                    try Self.deleteWork(
                        readerKind: OfflineCacheReaderKind.novel.rawValue,
                        ownerName: normalized.groupKey,
                        tid: normalized.entryKey,
                        in: db
                    )
                }
                return previousFiles
            }
            removeNovelPayloadFiles(NovelPayloadFileNames(
                sourcePageFileNames: previousFiles.sourcePageFileNames.subtracting([sourceFileName])
            ))
            notifyOfflineCacheDidChange()
            if projectionPrewarm != nil {
                try? await saveNovelOfflineProjectionPrewarm(document, ownerTitle: normalized.ownerTitle)
            }
        } catch {
            throw novelPayloadPersistenceError(from: error)
        }
    }

    public func novelOfflineSourcePage(
        ownerTitle: String,
        threadURL: URL,
        view: Int,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> ForumThreadPage? {
        try? await recoverQueueStateAfterRestart()
        guard let identity = novelEntryLookup(
            ownerTitle: ownerTitle,
            threadURL: threadURL,
            view: view,
            authorID: authorID,
            contentSource: contentSource
        ) else { return nil }
        let fileName = try? await database.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT source_page_file_name
                FROM offline_cache_novel_entries
                WHERE entry_key = ?
                """,
                arguments: [identity.entryKey]
            )
        }
        guard let fileName else {
            return nil
        }
        return Self.decodeFile(
            fileName: fileName,
            directory: novelSourcePagesDirectory,
            fileManager: fileManager,
            as: ForumThreadPage.self
        )
    }

    public func novelOfflineSourcePageSnapshot(
        threadURL: URL,
        view: Int,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> NovelOfflineSourcePageSnapshot? {
        try? await recoverQueueStateAfterRestart()
        let canonicalThreadURL = ReaderCacheIdentity.canonicalThreadURL(from: threadURL)
        let normalizedAuthorID = authorID?.mangaReaderTrimmedNonEmpty
        let source = normalizedAuthorID == nil ? (contentSource ?? .fallbackUnfilteredPage) : .authorFilteredPage
        let entryKey = NovelOfflineCacheEntry.entryKey(
            threadURL: canonicalThreadURL,
            view: view,
            authorID: normalizedAuthorID,
            contentSource: source
        )
        let row = try? await database.read { db -> NovelOfflineSourcePageSnapshotRow? in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT owner_title, source_page_file_name, updated_at
                FROM offline_cache_novel_entries
                WHERE entry_key = ? AND source_page_file_name IS NOT NULL
                ORDER BY updated_at DESC
                LIMIT 1
                """,
                arguments: [entryKey]
            ),
                let fileName = row["source_page_file_name"] as String? else {
                return nil
            }
            return NovelOfflineSourcePageSnapshotRow(
                ownerTitle: (row["owner_title"] as String?)
                    ?? Self.novelDisplayOwnerTitle(ownerTitle: "", threadURL: canonicalThreadURL),
                fileName: fileName,
                updatedAt: novelPayloadOptionalDate(from: row["updated_at"] as Double?)
            )
        }
        guard let row,
              let sourcePage = Self.decodeFile(
                fileName: row.fileName,
                directory: novelSourcePagesDirectory,
                fileManager: fileManager,
                as: ForumThreadPage.self
              ) else {
            return nil
        }
        return NovelOfflineSourcePageSnapshot(
            ownerTitle: row.ownerTitle,
            sourcePage: sourcePage,
            updatedAt: row.updatedAt
        )
    }

    public func saveNovelOfflineProjectionPrewarm(_ document: ReaderPageDocument, ownerTitle: String) async throws {
        try await recoverQueueStateAfterRestart()
        let displayOwnerTitle = Self.novelDisplayOwnerTitle(ownerTitle: ownerTitle, threadURL: document.threadURL)
        let entryKey = NovelOfflineCacheEntry.entryKey(document: document)
        do {
            guard entryKey.mangaReaderTrimmedNonEmpty != nil else {
                throw YamiboError.persistenceFailed("Novel offline cache entry is empty")
            }
            let data = try Self.encodeJSONData(document, context: "novel offline projection prewarm")
            let fileName = novelPayloadFileName(
                prefix: "projection",
                entryKey: entryKey
            )
            try ensureNovelProjectionPrewarmDirectoryExists()
            let fileURL = novelProjectionPrewarmDirectory.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: fileURL, options: [.atomic])
            let previousFiles = try await database.write { db in
                let previousFiles = try Self.novelPayloadFileNames(entryKey: entryKey, in: db)
                try db.execute(
                    sql: """
                    UPDATE offline_cache_novel_entries
                    SET owner_title = ?, projection_file_name = ?, projection_schema_version = ?
                    WHERE entry_key = ?
                    """,
                    arguments: [
                        displayOwnerTitle,
                        fileName,
                        document.projectionSchemaVersion ?? NovelOfflineCacheEntry.projectionPrewarmSchemaVersion,
                        entryKey
                    ]
                )
                return previousFiles
            }
            removeNovelPayloadFiles(NovelPayloadFileNames(
                projectionFileNames: previousFiles.projectionFileNames.subtracting([fileName])
            ))
            notifyOfflineCacheDidChange()
        } catch {
            throw novelPayloadPersistenceError(from: error)
        }
    }

    public func novelOfflineProjectionPrewarm(
        ownerTitle: String,
        threadURL: URL,
        view: Int,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> ReaderPageDocument? {
        try? await recoverQueueStateAfterRestart()
        guard let identity = novelEntryLookup(
            ownerTitle: ownerTitle,
            threadURL: threadURL,
            view: view,
            authorID: authorID,
            contentSource: contentSource
        ) else { return nil }
        let fileName = try? await database.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT projection_file_name
                FROM offline_cache_novel_entries
                WHERE entry_key = ?
                """,
                arguments: [identity.entryKey]
            )
        }
        guard let fileName else {
            return nil
        }
        return Self.decodeFile(
            fileName: fileName,
            directory: novelProjectionPrewarmDirectory,
            fileManager: fileManager,
            as: ReaderPageDocument.self
        )
    }

    func novelEntryLookup(
        ownerTitle: String,
        threadURL: URL,
        view: Int,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) -> NovelEntryLookup? {
        let canonicalThreadURL = ReaderCacheIdentity.canonicalThreadURL(from: threadURL)
        let identity = ReaderCacheIdentity(
            threadURL: canonicalThreadURL,
            view: max(1, view),
            authorID: authorID,
            contentSource: contentSource
        )
        let normalizedAuthorID = authorID?.mangaReaderTrimmedNonEmpty
        let source = normalizedAuthorID == nil ? (contentSource ?? .fallbackUnfilteredPage) : .authorFilteredPage
        return NovelEntryLookup(
            ownerTitle: Self.novelDisplayOwnerTitle(ownerTitle: ownerTitle, threadURL: canonicalThreadURL),
            groupKey: NovelOfflineCacheEntry.groupKey(
                threadURL: canonicalThreadURL,
                authorID: normalizedAuthorID,
                contentSource: source
            ),
            threadURL: canonicalThreadURL,
            threadID: identity.threadID,
            entryKey: NovelOfflineCacheEntry.entryKey(
                threadURL: canonicalThreadURL,
                view: view,
                authorID: normalizedAuthorID,
                contentSource: source
            ),
            authorID: normalizedAuthorID,
            contentSource: source
        )
    }

    func novelPayloadFileName(prefix: String, entryKey: String) -> String {
        "\(prefix)_\(sha256Hex(entryKey)).json"
    }

    func removeNovelPayloadFiles(_ files: NovelPayloadFileNames) {
        for fileName in files.sourcePageFileNames {
            try? fileManager.removeItem(at: novelSourcePagesDirectory.appendingPathComponent(fileName, isDirectory: false))
        }
        for fileName in files.projectionFileNames {
            try? fileManager.removeItem(at: novelProjectionPrewarmDirectory.appendingPathComponent(fileName, isDirectory: false))
        }
    }

    static func novelPayloadFileNames(entryKey: String, in db: Database) throws -> NovelPayloadFileNames {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT source_page_file_name, projection_file_name
            FROM offline_cache_novel_entries
            WHERE entry_key = ?
            """,
            arguments: [entryKey]
        ) else {
            return NovelPayloadFileNames()
        }
        return NovelPayloadFileNames(
            sourcePageFileNames: Set((row["source_page_file_name"] as String?).map { [$0] } ?? []),
            projectionFileNames: Set((row["projection_file_name"] as String?).map { [$0] } ?? [])
        )
    }

    static func novelPayloadFileNames(ownerName: String, in db: Database) throws -> NovelPayloadFileNames {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT source_page_file_name, projection_file_name
            FROM offline_cache_novel_entries
            WHERE owner_name = ?
            """,
            arguments: [ownerName]
        )
        return NovelPayloadFileNames(
            sourcePageFileNames: Set(rows.compactMap { $0["source_page_file_name"] as String? }),
            projectionFileNames: Set(rows.compactMap { $0["projection_file_name"] as String? })
        )
    }

    private static func encodeJSONData<T: Encodable>(_ value: T, context: String) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw YamiboError.persistenceFailed("Failed to encode \(context)")
        }
    }

    private static func decodeFile<T: Decodable>(
        fileName: String,
        directory: URL,
        fileManager: FileManager,
        as _: T.Type
    ) -> T? {
        guard payloadFileExists(fileName: fileName, directory: directory, fileManager: fileManager) else {
            return nil
        }
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func payloadFileExists(
        fileName: String,
        directory: URL,
        fileManager: FileManager
    ) -> Bool {
        let value = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let url = directory.appendingPathComponent(value, isDirectory: false)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func projectionDocument(
        from sourcePage: ForumThreadPage,
        request: NovelOfflineCacheWorkRequest
    ) throws -> ReaderPageDocument {
        let authorID = request.authorID
            ?? sourcePage.posts.first?.author.uid?.mangaReaderTrimmedNonEmpty
            ?? "offline"
        return try ReaderHTMLParser.parseDocument(
            threadPage: sourcePage,
            request: ReaderPageRequest(
                threadURL: request.threadURL,
                view: request.view,
                authorID: authorID
            ),
            authorID: authorID,
            projectionSourceFingerprint: "",
            projectionSchemaVersion: 0
        )
    }

    static func syntheticSourcePage(from document: ReaderPageDocument) -> ForumThreadPage {
        let canonicalURL = ReaderCacheIdentity.canonicalThreadURL(from: document.threadURL)
        let threadID = ReaderCacheIdentity(
            threadURL: canonicalURL,
            view: document.view,
            authorID: document.resolvedAuthorID,
            contentSource: document.contentSource
        ).threadID
        let thread = ThreadIdentity(tid: threadID, canonicalURL: canonicalURL)
        let authorID = document.resolvedAuthorID?.mangaReaderTrimmedNonEmpty ?? "offline"
        let posts = document.segments.enumerated().map { index, segment in
            ForumThreadPost(
                postID: document.segmentSources.indices.contains(index)
                    ? document.segmentSources[index]?.ownerPostID ?? "\(document.view)-\(index)"
                    : "\(document.view)-\(index)",
                author: BlogReaderUser(uid: authorID, name: "楼主"),
                contentHTML: syntheticHTML(for: segment, index: index),
                contentText: ""
            )
        }
        return ForumThreadPage(
            thread: thread,
            title: document.threadURL.absoluteString,
            posts: posts,
            pageNavigation: ForumPageNavigation(currentPage: document.view, totalPages: document.maxView)
        )
    }

    private static func syntheticHTML(for segment: ReaderSegment, index: Int) -> String {
        switch segment {
        case let .text(text, chapterTitle):
            return "<strong>\((chapterTitle ?? "第\(index + 1)章").novelOfflineEscapedHTML)</strong><br>\(text.novelOfflineEscapedHTML)"
        case let .image(url, _):
            return #"<img src="\#(url.absoluteString.novelOfflineEscapedHTML)" />"#
        }
    }

    static func novelEntryKeyComponents(from key: String) -> NovelEntryKeyComponents? {
        let components = key.components(separatedBy: "_")
        guard components.count == 8,
              components[0] == "tid",
              components[2] == "source",
              components[4] == "author",
              components[6] == "view",
              let contentSource = ReaderContentSource(rawValue: components[3]),
              let view = Int(components[7]) else {
            return nil
        }
        return NovelEntryKeyComponents(
            threadID: components[1],
            contentSource: contentSource,
            authorID: components[5] == "all" ? nil : components[5],
            view: max(1, view)
        )
    }
}

struct NovelEntryLookup {
    var ownerTitle: String
    var groupKey: String
    var threadURL: URL
    var threadID: String
    var entryKey: String
    var authorID: String?
    var contentSource: ReaderContentSource
}

struct NovelEntryKeyComponents {
    var threadID: String
    var contentSource: ReaderContentSource
    var authorID: String?
    var view: Int
}

struct NovelPayloadFileNames {
    var sourcePageFileNames: Set<String> = []
    var projectionFileNames: Set<String> = []
}

private struct NovelOfflineSourcePageSnapshotRow: Sendable {
    var ownerTitle: String
    var fileName: String
    var updatedAt: Date?
}

private extension String {
    var novelOfflineEscapedHTML: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private func novelPayloadPersistenceError(from error: Error) -> YamiboError {
    if let error = error as? YamiboError {
        return error
    }
    return YamiboError.persistenceFailed(error.localizedDescription)
}

private func novelPayloadOptionalDate(from value: Double?) -> Date? {
    value.map(Date.init(timeIntervalSince1970:))
}
