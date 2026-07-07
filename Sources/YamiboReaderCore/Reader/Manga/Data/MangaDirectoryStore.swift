import Foundation
@preconcurrency import GRDB

public actor MangaDirectoryStore: MangaDirectoryPersisting, MangaDirectoryRenaming {
    private let database: DatabasePool

    public init(databasePool: DatabasePool? = nil) {
        self.database = databasePool ?? Self.openDatabase()
    }

    public func directory(named name: String) async throws -> MangaDirectory? {
        guard let name = name.mangaReaderTrimmedNonEmpty else { return nil }
        return try await database.read { db in
            try Self.directory(named: name, in: db)
        }
    }

    public func directory(containingTID tid: String) async throws -> MangaDirectory? {
        guard let tid = tid.mangaReaderTrimmedNonEmpty else { return nil }
        return try await database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT d.clean_book_name
                FROM manga_directories d
                JOIN manga_directory_chapters c ON c.directory_name = d.clean_book_name
                WHERE c.tid = ?
                ORDER BY COALESCE(d.last_updated_at, -62135769600) DESC, d.clean_book_name ASC
                LIMIT 1
                """,
                arguments: [tid]
            ) else {
                return nil
            }
            return try Self.directory(named: row["clean_book_name"], in: db)
        }
    }

    public func saveDirectory(_ directory: MangaDirectory) async throws {
        do {
            try await database.write { db in
                try Self.save(directory, in: db)
            }
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func deleteDirectory(named name: String) async throws {
        guard let name = name.mangaReaderTrimmedNonEmpty else { return }
        try await database.write { db in
            try db.execute(sql: "DELETE FROM manga_directories WHERE clean_book_name = ?", arguments: [name])
        }
    }

    public func renameDirectory(
        from oldName: String,
        to newDirectory: MangaDirectory
    ) async throws {
        guard let oldName = oldName.mangaReaderTrimmedNonEmpty else {
            try await saveDirectory(newDirectory)
            return
        }
        try await database.write { db in
            try Self.save(newDirectory, in: db)
            try Self.renameRelatedStructuredMetadata(from: oldName, to: newDirectory.cleanBookName, in: db)
            if oldName != newDirectory.cleanBookName {
                try db.execute(sql: "DELETE FROM manga_directories WHERE clean_book_name = ?", arguments: [oldName])
            }
        }
    }

    public func clearAll() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM manga_directory_chapters")
            try db.execute(sql: "DELETE FROM manga_directories")
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        do {
            return try await database.read { db in
                let directoryBytes = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COALESCE(SUM(
                        length(CAST(clean_book_name AS BLOB)) +
                        length(CAST(strategy AS BLOB)) +
                        length(CAST(source_key AS BLOB)) +
                        COALESCE(length(CAST(search_keyword AS BLOB)), 0) +
                        16
                    ), 0)
                    FROM manga_directories
                    """
                ) ?? 0
                let chapterBytes = try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COALESCE(SUM(
                        length(CAST(directory_name AS BLOB)) +
                        length(CAST(tid AS BLOB)) +
                        length(CAST(raw_title AS BLOB)) +
                        COALESCE(length(CAST(author_uid AS BLOB)), 0) +
                        COALESCE(length(CAST(author_name AS BLOB)), 0) +
                        40
                    ), 0)
                    FROM manga_directory_chapters
                    """
                ) ?? 0
                return directoryBytes + chapterBytes
            }
        } catch {
            YamiboLog.persistence.warning("Failed to read manga directory disk usage: \(error)")
            return 0
        }
    }

    static func save(_ directory: MangaDirectory, in db: Database) throws {
        var normalized = directory
        guard let cleanBookName = directory.cleanBookName.mangaReaderTrimmedNonEmpty else {
            throw YamiboError.persistenceFailed("Directory name is empty")
        }
        normalized.cleanBookName = cleanBookName

        try db.execute(
            sql: """
            INSERT INTO manga_directories
            (clean_book_name, strategy, source_key, last_updated_at, search_keyword)
            VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [
                normalized.cleanBookName,
                normalized.strategy.rawValue,
                normalized.sourceKey,
                normalized.lastUpdatedAt.map(timeInterval(from:)),
                normalized.searchKeyword,
            ]
        )
        try db.execute(sql: "DELETE FROM manga_directory_chapters WHERE directory_name = ?", arguments: [normalized.cleanBookName])
        for (index, chapter) in normalized.chapters.enumerated() {
            guard let tid = chapter.tid.mangaReaderTrimmedNonEmpty else { continue }
            try db.execute(
                sql: """
                INSERT INTO manga_directory_chapters
                (directory_name, tid, view, raw_title, chapter_number, author_uid, author_name, group_index, publish_time, manual_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    normalized.cleanBookName,
                    tid,
                    chapter.view,
                    chapter.rawTitle,
                    chapter.chapterNumber,
                    chapter.authorUID,
                    chapter.authorName,
                    chapter.groupIndex,
                    chapter.publishTime.map(timeInterval(from:)),
                    index,
                ]
            )
        }
    }

    static func directory(named name: String, in db: Database) throws -> MangaDirectory? {
        guard let directoryRow = try Row.fetchOne(
            db,
            sql: """
            SELECT clean_book_name, strategy, source_key, last_updated_at, search_keyword
            FROM manga_directories
            WHERE clean_book_name = ?
            """,
            arguments: [name]
        ) else {
            return nil
        }
        guard let strategy = MangaDirectoryStrategy(rawValue: directoryRow["strategy"] as String) else {
            return nil
        }
        let chapters: [MangaChapter] = try Row.fetchAll(
            db,
            sql: """
            SELECT tid, view, raw_title, chapter_number, author_uid, author_name, group_index, publish_time
            FROM manga_directory_chapters
            WHERE directory_name = ?
            ORDER BY manual_order ASC, tid ASC
            """,
            arguments: [name]
        ).compactMap { row -> MangaChapter? in
            let tid = row["tid"] as String
            return MangaChapter(
                tid: tid,
                rawTitle: row["raw_title"],
                chapterNumber: row["chapter_number"],
                view: row["view"],
                authorUID: row["author_uid"] as String?,
                authorName: row["author_name"] as String?,
                groupIndex: row["group_index"],
                publishTime: optionalDate(from: row["publish_time"] as Double?)
            )
        }
        return MangaDirectory(
            cleanBookName: directoryRow["clean_book_name"],
            strategy: strategy,
            sourceKey: directoryRow["source_key"],
            chapters: chapters,
            lastUpdatedAt: optionalDate(from: directoryRow["last_updated_at"] as Double?),
            searchKeyword: directoryRow["search_keyword"] as String?
        )
    }

    static func renameRelatedStructuredMetadata(from oldName: String, to newName: String, in db: Database) throws {
        guard oldName != newName else { return }
        try renameFavoriteMangaTargets(from: oldName, to: newName, in: db)
        try renameReadingProgressMangaTargets(from: oldName, to: newName, in: db)
        try ContentCoverStore.renameMangaTitleCover(from: oldName, to: newName, in: db)
    }

    private static func renameFavoriteMangaTargets(from oldName: String, to newName: String, in db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, title, item_json
            FROM favorite_items
            WHERE target_kind = ? AND clean_book_name = ?
            """,
            arguments: [FavoriteContentTargetKind.mangaTitle.rawValue, oldName]
        )
        guard !rows.isEmpty else { return }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        for row in rows {
            let oldID = row["id"] as String
            let oldTitle = row["title"] as String
            let itemJSON = row["item_json"] as String
            guard var item = try? decoder.decode(FavoriteItem.self, from: Data(itemJSON.utf8)) else {
                YamiboLog.persistence.error("Failed to decode favorite_items.item_json while renaming directory '\(oldName)' -> '\(newName)' for id \(oldID); only clean_book_name/title columns were patched, item_json was left stale")
                try db.execute(
                    sql: """
                    UPDATE favorite_items
                    SET clean_book_name = ?,
                        title = CASE WHEN title = ? THEN ? ELSE title END
                    WHERE id = ?
                    """,
                    arguments: [newName, oldName, newName, oldID]
                )
                continue
            }

            item.target = item.target.renamedMangaTitle(to: newName)
            item.sourceGroup = .mangaTitle(mangaID: item.target.mangaID ?? newName, cleanBookName: newName)
            if item.title == oldName {
                item.title = newName
            }
            let updatedJSON = String(data: try encoder.encode(item), encoding: .utf8) ?? itemJSON
            try db.execute(
                sql: """
                UPDATE favorite_items
                SET id = ?,
                    manga_id = ?,
                    clean_book_name = ?,
                    title = ?,
                    item_json = ?
                WHERE id = ?
                """,
                arguments: [
                    item.id,
                    item.target.mangaID,
                    newName,
                    oldTitle == oldName ? newName : oldTitle,
                    updatedJSON,
                    oldID,
                ]
            )
        }
    }

    private static func renameReadingProgressMangaTargets(from oldName: String, to newName: String, in db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, manga_id, updated_at
            FROM reading_progress
            WHERE target_kind = ? AND clean_book_name = ?
            """,
            arguments: [FavoriteContentTargetKind.mangaTitle.rawValue, oldName]
        )
        for row in rows {
            let oldID = row["id"] as String
            let existingMangaID = row["manga_id"] as String?
            let mangaID = existingMangaID?.mangaReaderTrimmedNonEmpty == oldName
                ? newName
                : (existingMangaID?.mangaReaderTrimmedNonEmpty ?? newName)
            let newID = FavoriteContentTarget(mangaID: mangaID, mangaCleanBookName: newName).id
            if newID != oldID,
               let existing = try Row.fetchOne(
                   db,
                   sql: "SELECT updated_at FROM reading_progress WHERE id = ?",
                   arguments: [newID]
               ) {
                let existingUpdatedAt = existing["updated_at"] as Double
                let oldUpdatedAt = row["updated_at"] as Double
                if existingUpdatedAt >= oldUpdatedAt {
                    try db.execute(sql: "DELETE FROM reading_progress WHERE id = ?", arguments: [oldID])
                    continue
                }
                try db.execute(sql: "DELETE FROM reading_progress WHERE id = ?", arguments: [newID])
            }
            try db.execute(
                sql: """
                UPDATE reading_progress
                SET id = ?, manga_id = ?, clean_book_name = ?
                WHERE id = ?
                """,
                arguments: [newID, mangaID, newName, oldID]
            )
        }
    }

    private static func openDatabase() -> DatabasePool {
        do {
            return try YamiboDatabase.openPool()
        } catch {
            fatalError("Failed to open MangaDirectoryStore database: \(error)")
        }
    }
}

private func timeInterval(from date: Date) -> Double {
    date.timeIntervalSince1970
}

private func optionalDate(from value: Double?) -> Date? {
    value.map(Date.init(timeIntervalSince1970:))
}

private func persistenceError(from error: Error) -> YamiboError {
    if let error = error as? YamiboError {
        return error
    }
    return YamiboError.persistenceFailed(error.localizedDescription)
}
