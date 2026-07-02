import Foundation
@preconcurrency import GRDB

public actor ReaderCacheStore {
    private let database: DatabasePool
    private nonisolated(unsafe) let fileManager: FileManager
    private let baseDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let memoryCache = NSCache<NSString, CacheBox>()

    public init(
        databasePool: DatabasePool? = nil,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("reader-cache", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("reader-cache", isDirectory: true)
        self.database = databasePool ?? Self.openDatabase(
            baseDirectory: root,
            usesDefaultBaseDirectory: baseDirectory == nil,
            fileManager: fileManager
        )
        self.baseDirectory = root
        self.fileManager = fileManager
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    public func loadDocument(
        for request: ReaderPageRequest,
        contentSource: ReaderContentSource? = nil
    ) async -> ReaderPageDocument? {
        let identity = ReaderCacheIdentity(request: request, contentSource: contentSource)
        guard let metadata = try? await metadata(for: identity) else {
            memoryCache.removeObject(forKey: identity.cacheKey as NSString)
            return nil
        }

        let fileURL = baseDirectory.appendingPathComponent(metadata.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            try? await deleteEntry(identity: identity)
            memoryCache.removeObject(forKey: identity.cacheKey as NSString)
            return nil
        }

        if let cached = memoryCache.object(forKey: identity.cacheKey as NSString)?.document {
            return cached
        }

        guard let document = try? loadDocumentFromDisk(fileName: metadata.fileName) else {
            try? await deleteEntry(identity: identity)
            memoryCache.removeObject(forKey: identity.cacheKey as NSString)
            return nil
        }

        memoryCache.setObject(CacheBox(document: document), forKey: identity.cacheKey as NSString)
        return document
    }

    public func save(_ document: ReaderPageDocument) async throws {
        try ensureDirectoryExists()

        let identity = ReaderCacheIdentity(document: document)
        let fileName = fileName(for: identity)
        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])

        try await database.write { db in
            if let oldFileName = try String.fetchOne(
                db,
                sql: """
                SELECT file_name
                FROM reader_cache_entries
                WHERE thread_key = ? AND variant_key = ? AND view = ?
                """,
                arguments: [identity.threadKey, identity.variantKey, identity.view]
            ), oldFileName != fileName {
                try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(oldFileName, isDirectory: false))
            }
            try db.execute(
                sql: """
                INSERT INTO reader_cache_entries
                (thread_key, thread_id, variant_key, view, file_name, fetched_at, byte_count)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(thread_key, variant_key, view) DO UPDATE SET
                    thread_id = excluded.thread_id,
                    file_name = excluded.file_name,
                    fetched_at = excluded.fetched_at,
                    byte_count = excluded.byte_count
                """,
                arguments: [
                    identity.threadKey,
                    identity.threadID,
                    identity.variantKey,
                    identity.view,
                    fileName,
                    document.fetchedAt.timeIntervalSince1970,
                    data.count
                ]
            )
        }

        memoryCache.setObject(CacheBox(document: document), forKey: identity.cacheKey as NSString)
    }

    public func cachedViews(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async -> Set<Int> {
        let identity = ReaderCacheIdentity(threadURL: threadURL, view: 1, authorID: authorID, contentSource: contentSource)
        return (try? await database.read { db in
            Set(try Int.fetchAll(
                db,
                sql: """
                SELECT view
                FROM reader_cache_entries
                WHERE thread_key = ? AND variant_key = ?
                ORDER BY view ASC
                """,
                arguments: [identity.threadKey, identity.variantKey]
            ))
        }) ?? []
    }

    public func deleteViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async throws {
        let identity = ReaderCacheIdentity(threadURL: threadURL, view: 1, authorID: authorID, contentSource: contentSource)
        try await database.write { db in
            for view in views {
                if let fileName = try String.fetchOne(
                    db,
                    sql: """
                    SELECT file_name
                    FROM reader_cache_entries
                    WHERE thread_key = ? AND variant_key = ? AND view = ?
                    """,
                    arguments: [identity.threadKey, identity.variantKey, view]
                ) {
                    try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(fileName, isDirectory: false))
                }
                try db.execute(
                    sql: """
                    DELETE FROM reader_cache_entries
                    WHERE thread_key = ? AND variant_key = ? AND view = ?
                    """,
                    arguments: [identity.threadKey, identity.variantKey, view]
                )
            }
        }
        for view in views {
            memoryCache.removeObject(forKey: ReaderCacheIdentity(
                threadURL: threadURL,
                view: view,
                authorID: authorID,
                contentSource: contentSource
            ).cacheKey as NSString)
        }
    }

    public func deleteAll(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource? = nil
    ) async throws {
        let views = await cachedViews(for: threadURL, authorID: authorID, contentSource: contentSource)
        try await deleteViews(views, for: threadURL, authorID: authorID, contentSource: contentSource)
    }

    public func totalDiskUsageBytes() async -> Int {
        (try? await database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(byte_count), 0) FROM reader_cache_entries"
            ) ?? 0
        }) ?? 0
    }

    public func clearAll() async throws {
        try await database.write { db in
            try db.execute(sql: "DELETE FROM reader_cache_entries")
        }
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.removeItem(at: baseDirectory)
        }
        memoryCache.removeAllObjects()
    }

    private func loadDocumentFromDisk(fileName: String) throws -> ReaderPageDocument {
        let url = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        let data = try Data(contentsOf: url)
        return try decoder.decode(ReaderPageDocument.self, from: data)
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func fileName(for identity: ReaderCacheIdentity) -> String {
        "reader_\(stableIdentifier(for: identity.threadKey))_\(stableIdentifier(for: identity.variantKey))_\(identity.view).json"
    }

    private func stableIdentifier(for value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16)
    }

    private func metadata(for identity: ReaderCacheIdentity) async throws -> ReaderCacheEntry? {
        try await database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT file_name, byte_count, fetched_at
                FROM reader_cache_entries
                WHERE thread_key = ? AND variant_key = ? AND view = ?
                """,
                arguments: [identity.threadKey, identity.variantKey, identity.view]
            ) else {
                return nil
            }
            return ReaderCacheEntry(
                fileName: row["file_name"],
                byteCount: row["byte_count"],
                fetchedAt: Date(timeIntervalSince1970: row["fetched_at"])
            )
        }
    }

    private func deleteEntry(identity: ReaderCacheIdentity) async throws {
        try await database.write { db in
            if let fileName = try String.fetchOne(
                db,
                sql: """
                SELECT file_name
                FROM reader_cache_entries
                WHERE thread_key = ? AND variant_key = ? AND view = ?
                """,
                arguments: [identity.threadKey, identity.variantKey, identity.view]
            ) {
                try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(fileName, isDirectory: false))
            }
            try db.execute(
                sql: """
                DELETE FROM reader_cache_entries
                WHERE thread_key = ? AND variant_key = ? AND view = ?
                """,
                arguments: [identity.threadKey, identity.variantKey, identity.view]
            )
        }
    }

    private static func openDatabase(
        baseDirectory: URL,
        usesDefaultBaseDirectory: Bool,
        fileManager: FileManager
    ) -> DatabasePool {
        let rootDirectory = usesDefaultBaseDirectory
            ? YamiboDatabase.defaultRootDirectory(fileManager: fileManager)
            : metadataRootDirectory(for: baseDirectory)
        do {
            return try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory, fileManager: fileManager)
        } catch {
            fatalError("Failed to open ReaderCacheStore database: \(error)")
        }
    }

    private static func metadataRootDirectory(for baseDirectory: URL) -> URL {
        let name = baseDirectory.lastPathComponent.isEmpty ? "reader-cache" : baseDirectory.lastPathComponent
        return baseDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("\(name)-grdb", isDirectory: true)
    }
}

private final class CacheBox: NSObject {
    let document: ReaderPageDocument

    init(document: ReaderPageDocument) {
        self.document = document
    }
}

private struct ReaderCacheEntry: Sendable {
    var fileName: String
    var byteCount: Int
    var fetchedAt: Date
}
