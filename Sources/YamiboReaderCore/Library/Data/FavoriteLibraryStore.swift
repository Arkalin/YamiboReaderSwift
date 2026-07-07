import Foundation
@preconcurrency import GRDB

public actor FavoriteLibraryStore {
    public static let didChangeNotification = Notification.Name("yamibo.favoriteLibraryStore.didChange")
    public static let changeIDUserInfoKey = "changeID"
    nonisolated(unsafe) private static var databasePoolCache: [String: DatabasePool] = [:]
    private static let databasePoolCacheLock = NSLock()

    public nonisolated let changeID = UUID().uuidString

    private let defaults: UserDefaults
    private let key: String
    private let database: DatabasePool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "yamibo.favoriteLibrary.localFirst"
    ) {
        self.defaults = defaults
        self.key = key
        self.database = Self.openDatabase(defaults: defaults, key: key)
    }

    init(
        defaults: UserDefaults = .standard,
        key: String = "yamibo.favoriteLibrary.localFirst",
        databasePool: DatabasePool
    ) {
        self.defaults = defaults
        self.key = key
        self.database = databasePool
    }

    public func load() async -> FavoriteLibraryDocument {
        do {
            return try await database.read { db in
                try Self.loadDocument(in: db)
            }
        } catch {
            return FavoriteLibraryDocument()
        }
    }

    public func hasStoredDocument() async -> Bool {
        (try? await database.read { db in
            let itemCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM favorite_items") ?? 0
            let collectionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM favorite_collections") ?? 0
            let tagCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM favorite_tags") ?? 0
            let nonDefaultCategoryCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM favorite_categories WHERE id <> ?",
                arguments: [FavoriteCategory.defaultID]
            ) ?? 0
            return itemCount + collectionCount + tagCount + nonDefaultCategoryCount > 0
        }) ?? false
    }

    public func save(_ document: FavoriteLibraryDocument) async throws {
        do {
            let normalized = FavoriteLibraryDocument(
                categories: document.categories,
                collections: document.collections,
                items: document.items,
                tags: document.tags
            )
            try await database.write { db in
                try Self.save(normalized, in: db)
            }
            postChangeNotification()
        } catch {
            throw YamiboError.persistenceFailed(error.localizedDescription)
        }
    }

    public func clearAll() async throws {
        try await database.write { db in
            // Favorites-scoped wipe: covers are content metadata and survive
            // clearing the library (only the app-level reset erases them).
            try LibraryDatabaseSchema.deleteAllRows(in: db)
            try LibraryDatabaseSchema.insertDefaultFavoriteCategory(in: db)
        }
        postChangeNotification()
    }

    private static func openDatabase(defaults: UserDefaults, key: String) -> DatabasePool {
        do {
            if defaults === UserDefaults.standard {
                return try cachedDatabasePool(rootDirectory: YamiboDatabase.defaultRootDirectory())
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
                .appendingPathComponent("YamiboReaderLocalFavoriteLibrary", isDirectory: true)
                .appendingPathComponent(databaseID, isDirectory: true)
            return try cachedDatabasePool(rootDirectory: root)
        } catch {
            fatalError("Failed to open FavoriteLibraryStore database: \(error)")
        }
    }

    private static func cachedDatabasePool(rootDirectory: URL) throws -> DatabasePool {
        let key = rootDirectory.standardizedFileURL.path
        databasePoolCacheLock.lock()
        defer { databasePoolCacheLock.unlock() }
        if let pool = databasePoolCache[key] {
            return pool
        }

        let pool = try YamiboDatabase.openPool(rootDirectory: rootDirectory)
        databasePoolCache[key] = pool
        return pool
    }

    private static func loadDocument(in db: Database) throws -> FavoriteLibraryDocument {
        let decoder = JSONDecoder()
        let categories = try Row.fetchAll(
            db,
            sql: """
            SELECT id, name, manual_order, is_default
            FROM favorite_categories
            ORDER BY is_default DESC, manual_order ASC, id ASC
            """
        ).map { row in
            FavoriteCategory(
                id: row["id"],
                name: row["name"],
                manualOrder: row["manual_order"],
                isDefault: row["is_default"]
            )
        }

        let collections = try Row.fetchAll(
            db,
            sql: """
            SELECT id, category_id, name, color, manual_order
            FROM favorite_collections
            ORDER BY category_id ASC, manual_order ASC, id ASC
            """
        ).map { row in
            LocalFavoriteCollection(
                id: row["id"],
                categoryID: row["category_id"],
                name: row["name"],
                color: FavoriteCollectionColor(rawValue: row["color"] as String) ?? .gray,
                manualOrder: row["manual_order"]
            )
        }

        let tags = try Row.fetchAll(
            db,
            sql: """
            SELECT id, name, color, manual_order, created_at, updated_at
            FROM favorite_tags
            ORDER BY manual_order ASC, id ASC
            """
        ).map { row in
            FavoriteTag(
                id: row["id"],
                name: row["name"],
                color: FavoriteTagColor(rawValue: row["color"] as String) ?? .gray,
                manualOrder: row["manual_order"],
                createdAt: Self.date(from: row["created_at"]),
                updatedAt: Self.date(from: row["updated_at"])
            )
        }

        let locations = try favoriteLocationsByItem(in: db)
        let tagIDs = try tagIDsByItem(in: db)
        let remoteMappings = try remoteMappingsByItem(in: db)
        let items = try Row.fetchAll(
            db,
            sql: """
            SELECT id, item_json
            FROM favorite_items
            ORDER BY id ASC
            """
        ).compactMap { row -> FavoriteItem? in
            guard let data = (row["item_json"] as String).data(using: .utf8),
                  var item = try? decoder.decode(FavoriteItem.self, from: data) else {
                return nil
            }
            item.locations = locations[item.id] ?? item.locations
            item.tagIDs = tagIDs[item.id] ?? []
            item.remoteMapping = remoteMappings[item.id]
            return item
        }

        return FavoriteLibraryDocument(
            categories: categories,
            collections: collections,
            items: items,
            tags: tags
        )
    }

    private static func favoriteLocationsByItem(in db: Database) throws -> [String: [FavoriteLocation]] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT item_id, category_id, collection_id
            FROM favorite_locations
            ORDER BY item_id ASC, manual_order ASC, location_id ASC
            """
        )
        return Dictionary(grouping: rows, by: { $0["item_id"] as String }).mapValues { rows in
            rows.map { row in
                let categoryID = row["category_id"] as String
                if let collectionID = row["collection_id"] as String? {
                    return .collection(categoryID: categoryID, collectionID: collectionID)
                }
                return .category(categoryID)
            }
        }
    }

    private static func tagIDsByItem(in db: Database) throws -> [String: [String]] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT item_id, tag_id
            FROM favorite_item_tags
            ORDER BY item_id ASC, manual_order ASC, tag_id ASC
            """
        )
        return Dictionary(grouping: rows, by: { $0["item_id"] as String }).mapValues { rows in
            rows.map { $0["tag_id"] as String }
        }
    }

    private static func remoteMappingsByItem(in db: Database) throws -> [String: FavoriteRemoteMapping] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT item_id, yamibo_favorite_id, yamibo_remote_order, last_seen_at
            FROM favorite_remote_mappings
            """
        )
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            (
                row["item_id"] as String,
                FavoriteRemoteMapping(
                    yamiboFavoriteID: row["yamibo_favorite_id"] as String?,
                    yamiboRemoteOrder: row["yamibo_remote_order"] as Int?,
                    lastSeenAt: Self.optionalDate(from: row["last_seen_at"] as Double?)
                )
            )
        })
    }

    private static func save(_ document: FavoriteLibraryDocument, in db: Database) throws {
        let encoder = JSONEncoder()
        try LibraryDatabaseSchema.deleteAllRows(in: db)
        for category in document.categories {
            try db.execute(
                sql: """
                INSERT INTO favorite_categories (id, name, manual_order, is_default)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [category.id, category.name, category.manualOrder, category.isDefault]
            )
        }
        if !document.categories.contains(where: { $0.id == FavoriteCategory.defaultID }) {
            try LibraryDatabaseSchema.insertDefaultFavoriteCategory(in: db)
        }

        for collection in document.collections {
            try db.execute(
                sql: """
                INSERT INTO favorite_collections (id, category_id, name, color, manual_order)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [collection.id, collection.categoryID, collection.name, collection.color.rawValue, collection.manualOrder]
            )
        }

        for tag in document.tags {
            try db.execute(
                sql: """
                INSERT INTO favorite_tags (id, name, color, manual_order, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [tag.id, tag.name, tag.color.rawValue, tag.manualOrder, Self.timeInterval(from: tag.createdAt), Self.timeInterval(from: tag.updatedAt)]
            )
        }

        for item in document.items where !item.locations.isEmpty {
            let itemJSON = String(data: try encoder.encode(item), encoding: .utf8) ?? "{}"
            let targetColumns = Self.targetColumns(for: item.target)
            try db.execute(
                sql: """
                INSERT INTO favorite_items
                (id, target_kind, thread_id, manga_id, clean_book_name, title, item_json, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id,
                    item.target.kind.rawValue,
                    targetColumns.threadID,
                    targetColumns.mangaID,
                    targetColumns.cleanBookName,
                    item.title,
                    itemJSON,
                    Self.timeInterval(from: item.createdAt),
                    Self.timeInterval(from: item.updatedAt),
                ]
            )
            for (index, location) in item.locations.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO favorite_locations (item_id, location_id, category_id, collection_id, manual_order)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [item.id, location.id, location.categoryID, location.collectionID, index]
                )
            }
            for (index, tagID) in item.tagIDs.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO favorite_item_tags (item_id, tag_id, manual_order)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [item.id, tagID, index]
                )
            }
            if let mapping = item.remoteMapping {
                try db.execute(
                    sql: """
                    INSERT INTO favorite_remote_mappings
                    (item_id, yamibo_favorite_id, yamibo_remote_order, last_seen_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [
                        item.id,
                        mapping.yamiboFavoriteID,
                        mapping.yamiboRemoteOrder,
                        mapping.lastSeenAt.map(Self.timeInterval(from:)),
                    ]
                )
            }
        }
    }

    private static func targetColumns(for target: FavoriteContentTarget) -> (threadID: String?, mangaID: String?, cleanBookName: String?) {
        switch target {
        case let .normalThread(threadID), let .novelThread(threadID):
            return (threadID, nil, nil)
        case let .mangaTitle(mangaID, cleanBookName):
            return (nil, mangaID, cleanBookName)
        }
    }

    private static func timeInterval(from date: Date) -> Double {
        date.timeIntervalSince1970
    }

    private static func date(from value: Double) -> Date {
        Date(timeIntervalSince1970: value)
    }

    private static func optionalDate(from value: Double?) -> Date? {
        value.map(Date.init(timeIntervalSince1970:))
    }

    private nonisolated func postChangeNotification() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.changeIDUserInfoKey: changeID]
        )
    }
}
