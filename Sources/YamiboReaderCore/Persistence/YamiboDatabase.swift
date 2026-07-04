import Foundation
@preconcurrency import GRDB

public enum YamiboDatabase {
    public static let databaseFileName = "yamibo.sqlite"
    public static let cacheDirectoryName = "yamibo_cache"
    nonisolated(unsafe) private static var sharedPoolCache: [String: DatabasePool] = [:]
    private static let sharedPoolCacheLock = NSLock()

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

    public static func openSharedPool(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> DatabasePool {
        let root = rootDirectory ?? defaultRootDirectory(fileManager: fileManager)
        let key = root.standardizedFileURL.path
        sharedPoolCacheLock.lock()
        defer { sharedPoolCacheLock.unlock() }
        if let pool = sharedPoolCache[key] {
            return pool
        }

        let pool = try openPool(rootDirectory: root, fileManager: fileManager)
        sharedPoolCache[key] = pool
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
            try db.execute(sql: "DELETE FROM offline_cache_completed_images")
            try db.execute(sql: "DELETE FROM offline_cache_work_images")
            try db.execute(sql: "DELETE FROM offline_cache_works")
            try db.execute(sql: "DELETE FROM offline_cache_novel_entry_images")
            try db.execute(sql: "DELETE FROM offline_cache_novel_entries")
            try db.execute(sql: "DELETE FROM offline_cache_manga_entry_images")
            try db.execute(sql: "DELETE FROM offline_cache_manga_entries")
            try db.execute(sql: "DELETE FROM offline_cache_image_assets")
            try db.execute(sql: "DELETE FROM offline_cache_queue_state")
            try db.execute(sql: "DELETE FROM manga_directory_chapters")
            try db.execute(sql: "DELETE FROM manga_directories")
            try db.execute(sql: "DELETE FROM reading_progress")
            try db.execute(sql: "DELETE FROM favorite_remote_mappings")
            try db.execute(sql: "DELETE FROM favorite_item_tags")
            try db.execute(sql: "DELETE FROM favorite_locations")
            try db.execute(sql: "DELETE FROM favorite_items")
            try db.execute(sql: "DELETE FROM favorite_tags")
            try db.execute(sql: "DELETE FROM favorite_collections")
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

        migrator.registerMigration("create_favorite_library") { db in
            try db.create(table: "favorite_collections") { table in
                table.column("id", .text).primaryKey(onConflict: .replace)
                table.column("category_id", .text).notNull().references("favorite_categories", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("color", .text).notNull()
                table.column("manual_order", .integer).notNull()
            }
            try db.create(index: "favorite_collections_category_order_idx", on: "favorite_collections", columns: ["category_id", "manual_order"])

            try db.create(table: "favorite_tags") { table in
                table.column("id", .text).primaryKey(onConflict: .replace)
                table.column("name", .text).notNull()
                table.column("color", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(index: "favorite_tags_manual_order_idx", on: "favorite_tags", columns: ["manual_order"])

            try db.create(table: "favorite_items") { table in
                table.column("id", .text).primaryKey(onConflict: .replace)
                table.column("target_kind", .text).notNull()
                table.column("thread_id", .text)
                table.column("manga_id", .text)
                table.column("clean_book_name", .text)
                table.column("title", .text).notNull()
                table.column("item_json", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(index: "favorite_items_target_kind_idx", on: "favorite_items", columns: ["target_kind"])
            try db.create(index: "favorite_items_thread_id_idx", on: "favorite_items", columns: ["thread_id"])

            try db.create(table: "favorite_locations") { table in
                table.column("item_id", .text).notNull().references("favorite_items", onDelete: .cascade)
                table.column("location_id", .text).notNull()
                table.column("category_id", .text).notNull().references("favorite_categories", onDelete: .cascade)
                table.column("collection_id", .text).references("favorite_collections", onDelete: .cascade)
                table.column("manual_order", .integer).notNull()
                table.primaryKey(["item_id", "location_id"], onConflict: .replace)
            }
            try db.create(index: "favorite_locations_category_idx", on: "favorite_locations", columns: ["category_id"])
            try db.create(index: "favorite_locations_collection_idx", on: "favorite_locations", columns: ["collection_id"])

            try db.create(table: "favorite_item_tags") { table in
                table.column("item_id", .text).notNull().references("favorite_items", onDelete: .cascade)
                table.column("tag_id", .text).notNull().references("favorite_tags", onDelete: .cascade)
                table.column("manual_order", .integer).notNull()
                table.primaryKey(["item_id", "tag_id"], onConflict: .replace)
            }
            try db.create(index: "favorite_item_tags_tag_idx", on: "favorite_item_tags", columns: ["tag_id"])

            try db.create(table: "favorite_remote_mappings") { table in
                table.column("item_id", .text).primaryKey(onConflict: .replace).references("favorite_items", onDelete: .cascade)
                table.column("yamibo_favorite_id", .text)
                table.column("yamibo_remote_order", .integer)
                table.column("last_seen_at", .double)
                table.column("is_marked_remote_missing", .boolean).notNull()
            }

            try db.create(table: "favorite_remote_sync_metadata") { table in
                table.column("key", .text).primaryKey(onConflict: .replace)
                table.column("value", .text)
                table.column("updated_at", .double)
            }
        }

        migrator.registerMigration("create_reading_progress") { db in
            try db.create(table: "reading_progress") { table in
                table.column("id", .text).primaryKey(onConflict: .replace)
                table.column("target_kind", .text).notNull()
                table.column("thread_id", .text)
                table.column("manga_id", .text)
                table.column("clean_book_name", .text)
                table.column("kind", .text).notNull()
                table.column("updated_at", .double).notNull()
                table.column("last_read_at", .double)
                table.column("novel_last_view", .integer)
                table.column("novel_last_chapter", .text)
                table.column("novel_author_id", .text)
                table.column("novel_resume_point_json", .text)
                table.column("novel_max_view", .integer)
                table.column("novel_document_surface_progress_percent", .integer)
                table.column("novel_thread_cover_url", .text)
                table.column("manga_chapter_thread_id", .text)
                table.column("manga_last_chapter", .text)
                table.column("manga_page_index", .integer)
                table.column("manga_page_count", .integer)
            }
            try db.create(index: "reading_progress_kind_updated_idx", on: "reading_progress", columns: ["kind", "updated_at"])
            try db.create(index: "reading_progress_thread_idx", on: "reading_progress", columns: ["thread_id"])
            try db.create(index: "reading_progress_manga_title_idx", on: "reading_progress", columns: ["manga_id", "clean_book_name"])
            try db.create(index: "reading_progress_manga_chapter_idx", on: "reading_progress", columns: ["manga_chapter_thread_id"])
        }

        migrator.registerMigration("create_manga_directory_and_documents") { db in
            try db.create(table: "manga_directories") { table in
                table.column("clean_book_name", .text).primaryKey(onConflict: .replace)
                table.column("strategy", .text).notNull()
                table.column("source_key", .text).notNull()
                table.column("last_updated_at", .double)
                table.column("search_keyword", .text)
            }

            try db.create(table: "manga_directory_chapters") { table in
                table.column("directory_name", .text).notNull().references("manga_directories", onDelete: .cascade)
                table.column("tid", .text).notNull()
                table.column("view", .integer).notNull()
                table.column("raw_title", .text).notNull()
                table.column("chapter_number", .double).notNull()
                table.column("author_uid", .text)
                table.column("author_name", .text)
                table.column("group_index", .integer).notNull()
                table.column("publish_time", .double)
                table.column("manual_order", .integer).notNull()
                table.primaryKey(["directory_name", "tid"], onConflict: .replace)
            }
            try db.create(index: "manga_directory_chapters_tid_idx", on: "manga_directory_chapters", columns: ["tid"])
            try db.create(index: "manga_directory_chapters_directory_order_idx", on: "manga_directory_chapters", columns: ["directory_name", "manual_order"])
        }

        // Keep the historical migration identifier without creating or migrating the old manga-only cache tables.
        migrator.registerMigration("create_manga_offline_cache_metadata") { _ in }

        migrator.registerMigration("create_offline_cache_store") { db in
            try db.create(table: "offline_cache_manga_entries") { table in
                table.column("owner_name", .text).notNull()
                table.column("tid", .text).notNull()
                table.column("chapter_title", .text).notNull()
                table.column("source_page_file_name", .text)
                table.column("source_page_schema_version", .integer)
                table.column("source_page_fingerprint", .text)
                table.column("byte_count", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.primaryKey(["owner_name", "tid"], onConflict: .replace)
            }
            try db.create(index: "offline_cache_manga_entries_owner_idx", on: "offline_cache_manga_entries", columns: ["owner_name"])

            try db.create(table: "offline_cache_novel_entries") { table in
                table.column("owner_name", .text).notNull()
                table.column("owner_title", .text).notNull()
                table.column("entry_key", .text).notNull()
                table.column("title", .text).notNull()
                table.column("thread_id", .text).notNull()
                table.column("view", .integer).notNull()
                table.column("author_id", .text)
                table.column("content_source", .text).notNull()
                table.column("document_json", .text).notNull()
                table.column("source_page_file_name", .text)
                table.column("source_page_schema_version", .integer)
                table.column("source_page_fingerprint", .text)
                table.column("byte_count", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.primaryKey(["entry_key"], onConflict: .replace)
            }
            try db.create(index: "offline_cache_novel_entries_owner_idx", on: "offline_cache_novel_entries", columns: ["owner_name"])

            try db.create(table: "offline_cache_novel_entry_images") { table in
                table.column("entry_key", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("image_url", .text).notNull()
                table.primaryKey(["entry_key", "manual_order"], onConflict: .replace)
                table.foreignKey(["entry_key"], references: "offline_cache_novel_entries", columns: ["entry_key"], onDelete: .cascade)
            }
            try db.create(index: "offline_cache_novel_entry_images_url_idx", on: "offline_cache_novel_entry_images", columns: ["image_url"])

            try db.create(table: "offline_cache_manga_entry_images") { table in
                table.column("owner_name", .text).notNull()
                table.column("tid", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("image_url", .text).notNull()
                table.primaryKey(["owner_name", "tid", "manual_order"], onConflict: .replace)
                table.foreignKey(["owner_name", "tid"], references: "offline_cache_manga_entries", columns: ["owner_name", "tid"], onDelete: .cascade)
            }
            try db.create(index: "offline_cache_manga_entry_images_url_idx", on: "offline_cache_manga_entry_images", columns: ["image_url"])

            try db.create(table: "offline_cache_works") { table in
                table.column("reader_kind", .text).notNull()
                table.column("work_id", .text).notNull()
                table.column("owner_name", .text).notNull()
                table.column("owner_title", .text).notNull()
                table.column("tid", .text).notNull()
                table.column("chapter_title", .text).notNull()
                table.column("state", .text).notNull()
                table.column("failure_message", .text)
                table.column("current_bytes_per_second", .integer).notNull()
                table.column("insertion_index", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.column("updated_at", .double).notNull()
                table.primaryKey(["reader_kind", "owner_name", "tid"], onConflict: .replace)
            }
            try db.create(index: "offline_cache_works_work_id_idx", on: "offline_cache_works", columns: ["work_id"], unique: true)
            try db.create(index: "offline_cache_works_owner_idx", on: "offline_cache_works", columns: ["reader_kind", "owner_name"])
            try db.create(index: "offline_cache_works_insertion_idx", on: "offline_cache_works", columns: ["insertion_index"])

            try db.create(table: "offline_cache_work_images") { table in
                table.column("reader_kind", .text).notNull()
                table.column("owner_name", .text).notNull()
                table.column("tid", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("image_url", .text).notNull()
                table.primaryKey(["reader_kind", "owner_name", "tid", "manual_order"], onConflict: .replace)
                table.foreignKey(["reader_kind", "owner_name", "tid"], references: "offline_cache_works", columns: ["reader_kind", "owner_name", "tid"], onDelete: .cascade)
            }
            try db.create(index: "offline_cache_work_images_url_idx", on: "offline_cache_work_images", columns: ["image_url"])

            try db.create(table: "offline_cache_completed_images") { table in
                table.column("reader_kind", .text).notNull()
                table.column("owner_name", .text).notNull()
                table.column("tid", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("image_url", .text).notNull()
                table.primaryKey(["reader_kind", "owner_name", "tid", "manual_order"], onConflict: .replace)
                table.foreignKey(["reader_kind", "owner_name", "tid"], references: "offline_cache_works", columns: ["reader_kind", "owner_name", "tid"], onDelete: .cascade)
            }
            try db.create(index: "offline_cache_completed_images_url_idx", on: "offline_cache_completed_images", columns: ["image_url"])

            try db.create(table: "offline_cache_image_assets") { table in
                table.column("image_url", .text).primaryKey(onConflict: .replace)
                table.column("file_name", .text).notNull()
                table.column("byte_count", .integer).notNull()
            }

            try db.create(table: "offline_cache_queue_state") { table in
                table.column("key", .text).primaryKey(onConflict: .replace)
                table.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("create_offline_cache_novel_entries") { db in
            if try !db.tableExists("offline_cache_novel_entries") {
                try db.create(table: "offline_cache_novel_entries") { table in
                    table.column("owner_name", .text).notNull()
                    table.column("owner_title", .text).notNull()
                    table.column("entry_key", .text).notNull()
                    table.column("title", .text).notNull()
                    table.column("thread_id", .text).notNull()
                    table.column("view", .integer).notNull()
                    table.column("author_id", .text)
                    table.column("content_source", .text).notNull()
                    table.column("document_json", .text).notNull()
                    table.column("source_page_file_name", .text)
                    table.column("source_page_schema_version", .integer)
                    table.column("source_page_fingerprint", .text)
                    table.column("byte_count", .integer).notNull()
                    table.column("created_at", .double).notNull()
                    table.column("updated_at", .double).notNull()
                    table.primaryKey(["entry_key"], onConflict: .replace)
                }
                try db.create(index: "offline_cache_novel_entries_owner_idx", on: "offline_cache_novel_entries", columns: ["owner_name"])
            }

            if try !db.tableExists("offline_cache_novel_entry_images") {
                try db.create(table: "offline_cache_novel_entry_images") { table in
                    table.column("entry_key", .text).notNull()
                    table.column("manual_order", .integer).notNull()
                    table.column("image_url", .text).notNull()
                    table.primaryKey(["entry_key", "manual_order"], onConflict: .replace)
                    table.foreignKey(["entry_key"], references: "offline_cache_novel_entries", columns: ["entry_key"], onDelete: .cascade)
                }
                try db.create(index: "offline_cache_novel_entry_images_url_idx", on: "offline_cache_novel_entry_images", columns: ["image_url"])
            }
        }

        migrator.registerMigration("drop_image_data_cache_entries") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS image_data_cache_entries")
        }

        migrator.registerMigration("add_offline_cache_novel_source_files") { db in
            guard try db.tableExists("offline_cache_novel_entries") else { return }
            let columns = Set(try db.columns(in: "offline_cache_novel_entries").map(\.name))
            if !columns.contains("source_page_file_name") {
                try db.execute(sql: "ALTER TABLE offline_cache_novel_entries ADD COLUMN source_page_file_name TEXT")
            }
            if !columns.contains("source_page_schema_version") {
                try db.execute(sql: "ALTER TABLE offline_cache_novel_entries ADD COLUMN source_page_schema_version INTEGER")
            }
            if !columns.contains("source_page_fingerprint") {
                try db.execute(sql: "ALTER TABLE offline_cache_novel_entries ADD COLUMN source_page_fingerprint TEXT")
            }
        }

        migrator.registerMigration("add_offline_cache_manga_source_files") { db in
            guard try db.tableExists("offline_cache_manga_entries") else { return }
            let columns = Set(try db.columns(in: "offline_cache_manga_entries").map(\.name))
            if !columns.contains("source_page_file_name") {
                try db.execute(sql: "ALTER TABLE offline_cache_manga_entries ADD COLUMN source_page_file_name TEXT")
            }
            if !columns.contains("source_page_schema_version") {
                try db.execute(sql: "ALTER TABLE offline_cache_manga_entries ADD COLUMN source_page_schema_version INTEGER")
            }
            if !columns.contains("source_page_fingerprint") {
                try db.execute(sql: "ALTER TABLE offline_cache_manga_entries ADD COLUMN source_page_fingerprint TEXT")
            }
            if !columns.contains("byte_count") {
                try db.execute(sql: "ALTER TABLE offline_cache_manga_entries ADD COLUMN byte_count INTEGER NOT NULL DEFAULT 0")
            }
        }

        migrator.registerMigration("add_offline_cache_work_retain_inline_images") { db in
            guard try db.tableExists("offline_cache_works") else { return }
            let columns = Set(try db.columns(in: "offline_cache_works").map(\.name))
            if !columns.contains("retains_inline_images") {
                try db.execute(sql: "ALTER TABLE offline_cache_works ADD COLUMN retains_inline_images BOOLEAN NOT NULL DEFAULT 0")
            }
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
