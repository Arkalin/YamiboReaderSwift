import Foundation
@preconcurrency import GRDB

/// Owns the shared `yamibo.sqlite` pool: path resolution, pool configuration, and
/// aggregation of the feature schema modules that own the actual tables.
enum YamiboDatabase {
    static let databaseFileName = "yamibo.sqlite"
    static let cacheDirectoryName = "yamibo_cache"

    /// Every feature module owning tables in `yamibo.sqlite`.
    private static let schemaModules: [any DatabaseSchemaModule.Type] = [
        DiskCacheDatabaseSchema.self,
        LibraryDatabaseSchema.self,
        ReaderDatabaseSchema.self,
    ]

    static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("YamiboReader", isDirectory: true)
    }

    static func databaseURL(rootDirectory: URL? = nil, fileManager: FileManager = .default) -> URL {
        (rootDirectory ?? defaultRootDirectory(fileManager: fileManager))
            .appendingPathComponent(databaseFileName, isDirectory: false)
    }

    static func cacheDirectoryURL(rootDirectory: URL? = nil, fileManager: FileManager = .default) -> URL {
        (rootDirectory ?? defaultRootDirectory(fileManager: fileManager))
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    static func openPool(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> DatabasePool {
        let root = rootDirectory ?? defaultRootDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        var configuration = Configuration()
        // Several pools may point at the same database file (app plus tests);
        // wait for concurrent writers instead of failing with SQLITE_BUSY.
        configuration.busyMode = .timeout(5)
        let pool = try DatabasePool(
            path: databaseURL(rootDirectory: root, fileManager: fileManager).path,
            configuration: configuration
        )
        try migrate(pool)
        return pool
    }

    static func migrate(_ writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        // Pre-release app: a schema change rebuilds the local database instead of migrating it.
        migrator.eraseDatabaseOnSchemaChange = true
        for module in schemaModules {
            module.registerMigrations(in: &migrator)
        }
        try migrator.migrate(writer)
    }

    static func reset(
        writer: any DatabaseWriter,
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        try writer.write { db in
            for module in schemaModules {
                try module.erase(in: db)
            }
        }
        let cacheDirectory = cacheDirectoryURL(rootDirectory: rootDirectory, fileManager: fileManager)
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
    }
}
