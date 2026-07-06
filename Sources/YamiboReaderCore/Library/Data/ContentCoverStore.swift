import Foundation
@preconcurrency import GRDB

public enum ContentCoverTargetType: String, Codable, Hashable, Sendable, CaseIterable {
    /// Forum thread content, keyed by tid. Whether the thread reads as a novel
    /// or a normal thread is presentation, not content identity, so both share
    /// this type.
    case thread = "Thread"
    /// Manga directory content, keyed by the directory's `cleanBookName`.
    case mangaTitle = "MangaTitle"
}

public struct ContentCoverKey: Codable, Hashable, Sendable {
    public var targetType: ContentCoverTargetType
    public var targetID: String

    public init(targetType: ContentCoverTargetType, targetID: String) {
        self.targetType = targetType
        self.targetID = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func thread(tid: String) -> ContentCoverKey {
        ContentCoverKey(targetType: .thread, targetID: tid)
    }

    public static func mangaTitle(cleanBookName: String) -> ContentCoverKey {
        ContentCoverKey(targetType: .mangaTitle, targetID: cleanBookName)
    }

    /// Canonical cover key for a favorite target. Normal and novel threads
    /// share the `.thread` key: how a thread reads is presentation, not
    /// content identity.
    public init?(target: FavoriteContentTarget) {
        switch target.kind {
        case .normalThread, .novelThread:
            guard let threadID = target.threadID else { return nil }
            self = .thread(tid: threadID)
        case .mangaTitle:
            guard let cleanBookName = target.mangaCleanBookName else { return nil }
            self = .mangaTitle(cleanBookName: cleanBookName)
        }
    }
}

public struct ContentCover: Codable, Hashable, Sendable {
    public var key: ContentCoverKey
    public var automaticCoverURL: URL?
    public var manualCoverURL: URL?
    public var dynamicEnabled: Bool
    public var updatedAt: Date

    public init(
        key: ContentCoverKey,
        automaticCoverURL: URL? = nil,
        manualCoverURL: URL? = nil,
        dynamicEnabled: Bool = true,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.automaticCoverURL = automaticCoverURL
        self.manualCoverURL = manualCoverURL
        self.dynamicEnabled = dynamicEnabled
        self.updatedAt = updatedAt
    }

    public var resolvedURL: URL? {
        if dynamicEnabled {
            automaticCoverURL ?? manualCoverURL
        } else {
            manualCoverURL ?? automaticCoverURL
        }
    }
}

public actor ContentCoverStore {
    private let database: DatabasePool

    public init(databasePool: DatabasePool? = nil) {
        self.database = databasePool ?? Self.openDatabase()
    }

    /// Isolated-storage convenience mirroring `FavoriteLibraryStore`: standard
    /// defaults use the shared database, any other suite gets its own pool in
    /// a temporary directory (tests and previews).
    public init(defaults: UserDefaults, key: String = "yamibo.contentCovers") {
        self.database = Self.openDatabase(defaults: defaults, key: key)
    }

    public func cover(for key: ContentCoverKey) async -> ContentCover? {
        guard !key.targetID.isEmpty else { return nil }
        return try? await database.read { db in
            try Self.fetchCover(for: key, in: db)
        }
    }

    @discardableResult
    public func setAutomaticCover(_ url: URL, for key: ContentCoverKey, date: Date = .now) async throws -> Bool {
        guard let normalizedURL = Self.normalizedCoverURL(from: url.absoluteString),
              !key.targetID.isEmpty else {
            return false
        }
        try await database.write { db in
            var cover = try Self.fetchCover(for: key, in: db) ?? ContentCover(key: key)
            cover.automaticCoverURL = normalizedURL
            cover.updatedAt = date
            try Self.upsert(cover, in: db)
        }
        return true
    }

    @discardableResult
    public func setManualCover(_ url: URL, for key: ContentCoverKey, date: Date = .now) async throws -> Bool {
        guard let normalizedURL = Self.normalizedCoverURL(from: url.absoluteString),
              !key.targetID.isEmpty else {
            return false
        }
        try await database.write { db in
            var cover = try Self.fetchCover(for: key, in: db) ?? ContentCover(key: key)
            cover.manualCoverURL = normalizedURL
            cover.dynamicEnabled = false
            cover.updatedAt = date
            try Self.upsert(cover, in: db)
        }
        return true
    }

    /// Reverts the target to automatic covers: drops the manual URL and turns
    /// dynamic mode back on.
    @discardableResult
    public func clearManualCover(for key: ContentCoverKey, date: Date = .now) async throws -> Bool {
        guard !key.targetID.isEmpty else { return false }
        return try await database.write { db in
            guard var cover = try Self.fetchCover(for: key, in: db), cover.manualCoverURL != nil else {
                return false
            }
            cover.manualCoverURL = nil
            cover.dynamicEnabled = true
            cover.updatedAt = date
            try Self.upsert(cover, in: db)
            return true
        }
    }

    public func setDynamicEnabled(_ enabled: Bool, for key: ContentCoverKey, date: Date = .now) async throws {
        guard !key.targetID.isEmpty else { return }
        try await database.write { db in
            var cover = try Self.fetchCover(for: key, in: db) ?? ContentCover(key: key)
            cover.dynamicEnabled = enabled
            cover.updatedAt = date
            try Self.upsert(cover, in: db)
        }
    }

    public func clearAll() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM content_cover")
        }
    }

    public static func normalizedCoverURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let lowercased = value.lowercased()
        guard !lowercased.hasPrefix("data:"),
              !lowercased.hasPrefix("blob:"),
              !lowercased.contains("none.gif"),
              !lowercased.contains("static/image/"),
              !lowercased.contains("/smiley/"),
              !lowercased.contains("/face/") else {
            return nil
        }

        if lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://") {
            return URL(string: value)
        }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        return YamiboDomain.url(forSitePath: value)
    }

    /// Moves a manga-title cover row to a renamed directory inside the caller's
    /// transaction, so directory renames keep their cover atomically.
    static func renameMangaTitleCover(from oldName: String, to newName: String, in db: Database) throws {
        let oldKey = ContentCoverKey.mangaTitle(cleanBookName: oldName)
        let newKey = ContentCoverKey.mangaTitle(cleanBookName: newName)
        guard !oldKey.targetID.isEmpty, !newKey.targetID.isEmpty, oldKey != newKey else { return }
        guard var cover = try fetchCover(for: oldKey, in: db) else { return }
        // The renamed directory may already have a row; the moved row wins only
        // if the destination is empty.
        if try fetchCover(for: newKey, in: db) == nil {
            cover.key = newKey
            try upsert(cover, in: db)
        }
        try db.execute(
            sql: "DELETE FROM content_cover WHERE target_type = ? AND target_id = ?",
            arguments: [oldKey.targetType.rawValue, oldKey.targetID]
        )
    }

    private static func fetchCover(for key: ContentCoverKey, in db: Database) throws -> ContentCover? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT automatic_url, manual_url, dynamic_enabled, updated_at
            FROM content_cover
            WHERE target_type = ? AND target_id = ?
            """,
            arguments: [key.targetType.rawValue, key.targetID]
        ) else {
            return nil
        }
        return ContentCover(
            key: key,
            automaticCoverURL: (row["automatic_url"] as String?).flatMap(URL.init(string:)),
            manualCoverURL: (row["manual_url"] as String?).flatMap(URL.init(string:)),
            dynamicEnabled: row["dynamic_enabled"],
            updatedAt: Date(timeIntervalSince1970: row["updated_at"])
        )
    }

    private static func upsert(_ cover: ContentCover, in db: Database) throws {
        try db.execute(
            sql: """
            INSERT OR REPLACE INTO content_cover
            (target_type, target_id, automatic_url, manual_url, dynamic_enabled, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                cover.key.targetType.rawValue,
                cover.key.targetID,
                cover.automaticCoverURL?.absoluteString,
                cover.manualCoverURL?.absoluteString,
                cover.dynamicEnabled,
                cover.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    private static func openDatabase() -> DatabasePool {
        do {
            return try YamiboDatabase.openPool()
        } catch {
            fatalError("Failed to open ContentCoverStore database: \(error)")
        }
    }

    private static func openDatabase(defaults: UserDefaults, key: String) -> DatabasePool {
        do {
            if defaults === UserDefaults.standard {
                return try YamiboDatabase.openPool()
            }
            let idKey = "\(key).grdbDatabaseID"
            let databaseID: String
            if let existing = defaults.string(forKey: idKey), !existing.isEmpty {
                databaseID = existing
            } else {
                databaseID = UUID().uuidString
                defaults.set(databaseID, forKey: idKey)
            }
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("YamiboReaderContentCovers", isDirectory: true)
                .appendingPathComponent(databaseID, isDirectory: true)
            return try YamiboDatabase.openPool(rootDirectory: root)
        } catch {
            fatalError("Failed to open ContentCoverStore database: \(error)")
        }
    }
}
