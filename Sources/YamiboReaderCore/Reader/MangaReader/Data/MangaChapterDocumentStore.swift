import Foundation
@preconcurrency import GRDB

public actor MangaChapterDocumentStore: MangaChapterDocumentPersisting, MangaChapterDocumentStorageReporting {
    private let database: DatabasePool

    public init(databasePool: DatabasePool? = nil) {
        self.database = databasePool ?? Self.openDatabase()
    }

    public func document(for chapterURL: URL) async -> MangaChapterDocument? {
        guard let tid = MangaTitleCleaner.extractTid(from: chapterURL.absoluteString)?.mangaReaderTrimmedNonEmpty else {
            return nil
        }
        return await document(forTID: tid)
    }

    public func document(forTID tid: String) async -> MangaChapterDocument? {
        guard let tid = tid.mangaReaderTrimmedNonEmpty else { return nil }
        return try? await database.read { db in
            try Self.document(tid: tid, in: db)
        }
    }

    public func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws {
        var normalized = document
        let tid = document.tid.mangaReaderTrimmedNonEmpty
            ?? MangaTitleCleaner.extractTid(from: chapterURL.absoluteString)?.mangaReaderTrimmedNonEmpty
        guard let tid else {
            throw YamiboError.persistenceFailed("Manga chapter document tid is empty")
        }
        normalized.tid = tid
        normalized.chapterURL = YamiboRoute.chapterURL(forTID: tid) ?? YamiboRoute.normalizedChapterURL(chapterURL)
        try await save(normalized)
    }

    public func save(_ document: MangaChapterDocument) async throws {
        do {
            try await database.write { db in
                try Self.save(document, in: db)
            }
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func clearAll() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM manga_chapter_document_images")
            try db.execute(sql: "DELETE FROM manga_chapter_documents")
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        do {
            return try await database.read { db in
                let documentBytes = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COALESCE(SUM(
                        length(CAST(tid AS BLOB)) +
                        length(CAST(owner_post_id AS BLOB)) +
                        length(CAST(chapter_title AS BLOB))
                    ), 0)
                    FROM manga_chapter_documents
                    """
                ) ?? 0
                let imageBytes = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COALESCE(SUM(
                        length(CAST(tid AS BLOB)) +
                        length(CAST(image_url AS BLOB)) +
                        8
                    ), 0)
                    FROM manga_chapter_document_images
                    """
                ) ?? 0
                return documentBytes + imageBytes
            }
        } catch {
            return 0
        }
    }

    static func save(_ document: MangaChapterDocument, in db: Database) throws {
        guard let tid = document.tid.mangaReaderTrimmedNonEmpty,
              document.chapterTitle.mangaReaderTrimmedNonEmpty != nil,
              !document.imageURLs.isEmpty else {
            throw YamiboError.persistenceFailed("Invalid manga chapter document")
        }
        try db.execute(
            sql: """
            INSERT INTO manga_chapter_documents (tid, owner_post_id, chapter_title)
            VALUES (?, ?, ?)
            """,
            arguments: [tid, document.ownerPostID, document.chapterTitle]
        )
        try db.execute(sql: "DELETE FROM manga_chapter_document_images WHERE tid = ?", arguments: [tid])
        for (index, imageURL) in document.imageURLs.enumerated() {
            try db.execute(
                sql: """
                INSERT INTO manga_chapter_document_images (tid, manual_order, image_url)
                VALUES (?, ?, ?)
                """,
                arguments: [tid, index, imageURL.absoluteString]
            )
        }
    }

    static func document(tid: String, in db: Database) throws -> MangaChapterDocument? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT tid, owner_post_id, chapter_title FROM manga_chapter_documents WHERE tid = ?",
            arguments: [tid]
        ) else {
            return nil
        }
        let imageURLs = try String.fetchAll(
            db,
            sql: """
            SELECT image_url
            FROM manga_chapter_document_images
            WHERE tid = ?
            ORDER BY manual_order ASC
            """,
            arguments: [tid]
        ).compactMap(URL.init(string:))
        guard !imageURLs.isEmpty else { return nil }
        let tid = row["tid"] as String
        return MangaChapterDocument(
            tid: tid,
            ownerPostID: row["owner_post_id"],
            chapterTitle: row["chapter_title"],
            chapterURL: YamiboRoute.chapterURL(forTID: tid) ?? URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=0")!,
            imageURLs: imageURLs
        )
    }

    private static func openDatabase() -> DatabasePool {
        do {
            return try YamiboDatabase.openSharedPool()
        } catch {
            fatalError("Failed to open MangaChapterDocumentStore database: \(error)")
        }
    }
}

private func persistenceError(from error: Error) -> YamiboError {
    if let error = error as? YamiboError {
        return error
    }
    return YamiboError.persistenceFailed(error.localizedDescription)
}
