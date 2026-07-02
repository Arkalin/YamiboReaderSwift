import Foundation
@preconcurrency import GRDB

public enum YamiboDatabase {
    public static let databaseFileName = "yamibo.sqlite"
    public static let cacheDirectoryName = "yamibo_cache"

    public static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("YamiboReader", isDirectory: true)
    }

    public static func databaseURL(rootDirectory: URL? = nil, fileManager: FileManager = .default) -> URL {
        (rootDirectory ?? defaultRootDirectory(fileManager: fileManager))
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    public static func cacheDirectoryURL(rootDirectory: URL? = nil, fileManager: FileManager = .default) -> URL {
        (rootDirectory ?? defaultRootDirectory(fileManager: fileManager))
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    public static func openPool(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default,
        configuration: Configuration = Configuration()
    ) throws -> DatabasePool {
        let root = rootDirectory ?? defaultRootDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let pool = try DatabasePool(path: databaseURL(rootDirectory: root, fileManager: fileManager).path, configuration: configuration)
        try migrate(pool)
        return pool
    }

    public static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        registerMigrations(in: &migrator)
        try migrator.migrate(writer)
    }

    public static func reset(
        writer: any DatabaseWriter,
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM cache_entries")
            try db.execute(sql: "DELETE FROM favorite_categories WHERE id <> ?", arguments: [FavoriteCategory.defaultID])
        }
        try seedDefaultFavoriteCategory(in: writer)
        let cacheDirectory = cacheDirectoryURL(rootDirectory: rootDirectory, fileManager: fileManager)
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
    }

    private static func registerMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("create_cache_entries") { db in
            try db.create(table: "cache_entries") { table in
                table.column("namespace", .text).notNull()
                table.column("cache_key", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("last_accessed_at", .double).notNull()
                table.primaryKey(["namespace", "cache_key"], onConflict: .replace)
            }
            try db.create(index: "cache_entries_namespace_last_accessed_idx", on: "cache_entries", columns: ["namespace", "last_accessed_at"])
            try db.create(index: "cache_entries_namespace_cache_key_idx", on: "cache_entries", columns: ["namespace", "cache_key"])
        }

        migrator.registerMigration("create_favorite_category_seed") { db in
            try db.create(table: "favorite_categories") { table in
                table.column("id", .text).primaryKey(onConflict: .replace)
                table.column("name", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("is_default", .boolean).notNull()
            }
            try insertDefaultFavoriteCategory(in: db)
        }
    }

    private static func seedDefaultFavoriteCategory(in writer: any DatabaseWriter) throws {
        try writer.write { db in
            try insertDefaultFavoriteCategory(in: db)
        }
    }

    private static func insertDefaultFavoriteCategory(in db: Database) throws {
        let category = FavoriteCategory.defaultCategory
        try db.execute(
            sql: """
            INSERT OR IGNORE INTO favorite_categories (id, name, manual_order, is_default)
            VALUES (?, ?, ?, ?)
            """,
            arguments: [
                category.id,
                category.name,
                category.manualOrder,
                category.isDefault,
            ]
        )
    }
}
