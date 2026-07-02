import CryptoKit
import Foundation
@preconcurrency import GRDB

public actor FileImageDataCacheStore: YamiboImageDataCaching {
    public static let defaultDiskLimitBytes = 512 * 1024 * 1024

    private let database: DatabasePool
    private nonisolated(unsafe) let fileManager: FileManager
    private let baseDirectory: URL
    private let diskLimitBytes: Int

    public init(
        databasePool: DatabasePool? = nil,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        diskLimitBytes: Int = FileImageDataCacheStore.defaultDiskLimitBytes
    ) {
        self.database = databasePool ?? Self.openDatabase()
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("image-data", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("YamiboReader", isDirectory: true)
                .appendingPathComponent("image-data", isDirectory: true)
        self.diskLimitBytes = max(0, diskLimitBytes)
    }

    public func data(for request: YamiboImageRequest) async -> Data? {
        let namespace = request.cacheNamespace.value
        let imageURLString = request.url.absoluteString

        guard let fileName = try? await database.read({ db in
            try String.fetchOne(
                db,
                sql: """
                SELECT file_name
                FROM image_data_cache_entries
                WHERE namespace = ? AND image_url = ?
                """,
                arguments: [namespace, imageURLString]
            )
        }) else {
            return nil
        }

        let fileURL = namespaceDirectory(for: namespace).appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            try? await database.write { db in
                try Self.deleteEntry(
                    namespace: namespace,
                    imageURLString: imageURLString,
                    fileManager: fileManager,
                    baseDirectory: baseDirectory,
                    in: db
                )
            }
            return nil
        }

        try? await database.write { db in
            try db.execute(
                sql: """
                UPDATE image_data_cache_entries
                SET last_accessed_at = ?
                WHERE namespace = ? AND image_url = ?
                """,
                arguments: [Date().timeIntervalSince1970, namespace, imageURLString]
            )
        }
        return data
    }

    public func save(
        _ data: Data,
        for request: YamiboImageRequest,
        retentionPolicy: YamiboImageDataCacheRetentionPolicy = .evictable
    ) async throws {
        let namespace = request.cacheNamespace.value
        let imageURLString = request.url.absoluteString

        guard !data.isEmpty,
              retentionPolicy == .protected || (diskLimitBytes > 0 && data.count <= diskLimitBytes) else {
            do {
                try await database.write { db in
                    try Self.deleteEntry(
                        namespace: namespace,
                        imageURLString: imageURLString,
                        fileManager: fileManager,
                        baseDirectory: baseDirectory,
                        in: db
                    )
                }
            } catch {
                throw persistenceError(from: error)
            }
            return
        }

        do {
            let namespaceDirectory = namespaceDirectory(for: namespace)
            try ensureDirectoryExists(namespaceDirectory)
            let fileName = fileName(for: request)
            let fileURL = namespaceDirectory.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: fileURL, options: [.atomic])

            try await database.write { db in
                if let oldFileName = try String.fetchOne(
                    db,
                    sql: """
                    SELECT file_name
                    FROM image_data_cache_entries
                    WHERE namespace = ? AND image_url = ?
                    """,
                    arguments: [namespace, imageURLString]
                ), oldFileName != fileName {
                    try? fileManager.removeItem(at: namespaceDirectory.appendingPathComponent(oldFileName, isDirectory: false))
                }

                try db.execute(
                    sql: """
                    INSERT INTO image_data_cache_entries
                        (namespace, image_url, file_name, byte_count, last_accessed_at, retention_policy)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(namespace, image_url) DO UPDATE SET
                        file_name = excluded.file_name,
                        byte_count = excluded.byte_count,
                        last_accessed_at = excluded.last_accessed_at,
                        retention_policy = excluded.retention_policy
                    """,
                    arguments: [
                        namespace,
                        imageURLString,
                        fileName,
                        data.count,
                        Date().timeIntervalSince1970,
                        retentionPolicy.rawValue,
                    ]
                )
                try Self.trimDiskIfNeeded(
                    diskLimitBytes: diskLimitBytes,
                    fileManager: fileManager,
                    baseDirectory: baseDirectory,
                    in: db
                )
            }
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func clearAll() async throws {
        do {
            try await database.write { db in
                try db.execute(sql: "DELETE FROM image_data_cache_entries")
            }
            if fileManager.fileExists(atPath: baseDirectory.path) {
                try fileManager.removeItem(at: baseDirectory)
            }
        } catch {
            throw persistenceError(from: error)
        }
    }

    public func totalDiskUsageBytes() async -> Int {
        (try? await database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(byte_count), 0) FROM image_data_cache_entries"
            ) ?? 0
        }) ?? 0
    }

    public func evictableDiskUsageBytes() async -> Int {
        (try? await database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(byte_count), 0)
                FROM image_data_cache_entries
                WHERE retention_policy = ?
                """,
                arguments: [YamiboImageDataCacheRetentionPolicy.evictable.rawValue]
            ) ?? 0
        }) ?? 0
    }

    private func ensureDirectoryExists(_ directory: URL) throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func namespaceDirectory(for namespace: String) -> URL {
        baseDirectory.appendingPathComponent(sha256Hex(namespace), isDirectory: true)
    }

    private func fileName(for request: YamiboImageRequest) -> String {
        let rawExtension = request.url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExtension = rawExtension.isEmpty ? "bin" : sanitizedFileExtension(rawExtension)
        return "image_\(sha256Hex(request.persistentCacheKey)).\(safeExtension)"
    }

    private func sanitizedFileExtension(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: #"[^A-Za-z0-9]"#, with: "", options: .regularExpression)
        return sanitized.isEmpty ? "bin" : sanitized
    }

    private func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persistenceError(from error: Error) -> YamiboError {
        if let error = error as? YamiboError {
            return error
        }
        return YamiboError.persistenceFailed(error.localizedDescription)
    }

    private static func deleteEntry(
        namespace: String,
        imageURLString: String,
        fileManager: FileManager,
        baseDirectory: URL,
        in db: Database
    ) throws {
        if let row = try Row.fetchOne(
            db,
            sql: """
            SELECT file_name
            FROM image_data_cache_entries
            WHERE namespace = ? AND image_url = ?
            """,
            arguments: [namespace, imageURLString]
        ) {
            let fileName = row["file_name"] as String
            let namespaceDirectory = baseDirectory.appendingPathComponent(sha256Hex(namespace), isDirectory: true)
            try? fileManager.removeItem(at: namespaceDirectory.appendingPathComponent(fileName, isDirectory: false))
        }
        try db.execute(
            sql: "DELETE FROM image_data_cache_entries WHERE namespace = ? AND image_url = ?",
            arguments: [namespace, imageURLString]
        )
    }

    private static func trimDiskIfNeeded(
        diskLimitBytes: Int,
        fileManager: FileManager,
        baseDirectory: URL,
        in db: Database
    ) throws {
        var totalBytes = try Int.fetchOne(
            db,
            sql: """
            SELECT COALESCE(SUM(byte_count), 0)
            FROM image_data_cache_entries
            WHERE retention_policy = ?
            """,
            arguments: [YamiboImageDataCacheRetentionPolicy.evictable.rawValue]
        ) ?? 0
        guard totalBytes > diskLimitBytes else { return }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT namespace, image_url, file_name, byte_count
            FROM image_data_cache_entries
            WHERE retention_policy = ?
            ORDER BY last_accessed_at ASC, namespace ASC, image_url ASC
            """,
            arguments: [YamiboImageDataCacheRetentionPolicy.evictable.rawValue]
        )
        for row in rows where totalBytes > diskLimitBytes {
            let namespace = row["namespace"] as String
            let imageURLString = row["image_url"] as String
            let fileName = row["file_name"] as String
            let byteCount = row["byte_count"] as Int
            let namespaceDirectory = baseDirectory.appendingPathComponent(sha256Hex(namespace), isDirectory: true)
            try? fileManager.removeItem(at: namespaceDirectory.appendingPathComponent(fileName, isDirectory: false))
            try db.execute(
                sql: "DELETE FROM image_data_cache_entries WHERE namespace = ? AND image_url = ?",
                arguments: [namespace, imageURLString]
            )
            totalBytes -= byteCount
        }
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func openDatabase() -> DatabasePool {
        do {
            return try YamiboDatabase.openSharedPool()
        } catch {
            fatalError("Failed to open FileImageDataCacheStore database: \(error)")
        }
    }
}
