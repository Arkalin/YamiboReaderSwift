import Foundation
@preconcurrency import GRDB

/// Schema for the local favorite library owned by `FavoriteLibraryStore`.
enum LibraryDatabaseSchema: DatabaseSchemaModule {
    static func registerMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("library.v1") { db in
            try db.create(table: "favorite_categories") { table in
                table.column("id", .text).primaryKey(onConflict: .replace)
                table.column("name", .text).notNull()
                table.column("manual_order", .integer).notNull()
                table.column("is_default", .boolean).notNull()
            }
            try insertDefaultFavoriteCategory(in: db)

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
            }
        }

        migrator.registerMigration("library.v2.content-cover") { db in
            // Covers are content metadata, deliberately not referencing
            // favorite_items: they outlive un-favoriting and directory deletion.
            try db.create(table: "content_cover") { table in
                table.column("target_type", .text).notNull()
                table.column("target_id", .text).notNull()
                table.column("automatic_url", .text)
                table.column("manual_url", .text)
                table.column("dynamic_enabled", .boolean).notNull()
                // User override that suppresses both cover URLs in favor of
                // the text placeholder cover.
                table.column("text_cover_forced", .boolean).notNull().defaults(to: false)
                table.column("updated_at", .double).notNull()
                table.primaryKey(["target_type", "target_id"], onConflict: .replace)
            }
        }

        migrator.registerMigration("library.v3.sync-runs") { db in
            // Yamibo sync run snapshots: runtime task state, so it lives in
            // GRDB rather than app settings (which sync over WebDAV).
            try db.create(table: "favorite_sync_runs") { table in
                table.column("run_id", .text).primaryKey(onConflict: .replace)
                table.column("status", .text).notNull()
                table.column("snapshot_json", .text).notNull()
                table.column("started_at", .double).notNull()
                table.column("updated_at", .double).notNull()
            }
            try db.create(index: "favorite_sync_runs_updated_idx", on: "favorite_sync_runs", columns: ["updated_at"])
        }
    }

    static func erase(in db: Database) throws {
        try deleteAllRows(in: db)
        try db.execute(sql: "DELETE FROM content_cover")
        try db.execute(sql: "DELETE FROM favorite_sync_runs")
        try insertDefaultFavoriteCategory(in: db)
    }

    /// Deletes every favorite-library row, including the default category.
    /// Covers are intentionally excluded: document saves call this to replace
    /// all favorite rows, and covers must survive those rewrites.
    static func deleteAllRows(in db: Database) throws {
        try db.execute(sql: "DELETE FROM favorite_remote_mappings")
        try db.execute(sql: "DELETE FROM favorite_item_tags")
        try db.execute(sql: "DELETE FROM favorite_locations")
        try db.execute(sql: "DELETE FROM favorite_items")
        try db.execute(sql: "DELETE FROM favorite_tags")
        try db.execute(sql: "DELETE FROM favorite_collections")
        try db.execute(sql: "DELETE FROM favorite_categories")
    }

    static func insertDefaultFavoriteCategory(in db: Database) throws {
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
