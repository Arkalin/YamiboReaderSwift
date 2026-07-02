import CryptoKit
import Foundation
@preconcurrency import GRDB

public actor FileMangaImageDataCacheStore: MangaImageDataCaching {
    public static let defaultDiskLimitBytes = 512 * 1024 * 1024

    private let database: DatabasePool
    private nonisolated(unsafe) let fileManager: FileManager
    private let baseDirectory: URL
    private let diskLimitBytes: Int

    public init(
        databasePool: DatabasePool? = nil,
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        diskLimitBytes: Int = FileMangaImageDataCacheStore.defaultDiskLimitBytes
    ) {
        self.database = databasePool ?? Self.openDatabase()
        self.fileManager = fileManager
        let root = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YamiboReader", isDirectory: true)
            .appendingPathComponent("manga-reader", isDirectory: true)
            .appendingPathComponent("image-data", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("YamiboReader", isDirectory: true)
                .appendingPathComponent("manga-reader", isDirectory: true)
                .appendingPathComponent("image-data", isDirectory: true)
        self.baseDirectory = root
        self.diskLimitBytes = max(0, diskLimitBytes)
    }

    public func data(for imageURL: URL) async -> Data? {
        let imageURLString = cacheKey(for: imageURL)
        guard let fileName = try? await database.read({ db in
            try String.fetchOne(
                db,
                sql: "SELECT file_name FROM manga_image_data_cache_entries WHERE image_url = ?",
                arguments: [imageURLString]
            )
        }) else {
            return nil
        }

        let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            try? await database.write { db in
                try Self.deleteEntry(
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
                sql: "UPDATE manga_image_data_cache_entries SET last_accessed_at = ? WHERE image_url = ?",
                arguments: [Date().timeIntervalSince1970, imageURLString]
            )
        }
        return data
    }

    public func save(_ data: Data, for imageURL: URL) async throws {
        let imageURLString = cacheKey(for: imageURL)

        guard !data.isEmpty, diskLimitBytes > 0, data.count <= diskLimitBytes else {
            do {
                try await database.write { db in
                    try Self.deleteEntry(
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
            try ensureDirectoryExists()
            let fileName = fileName(for: imageURL)
            let fileURL = baseDirectory.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: fileURL, options: [.atomic])

            try await database.write { db in
                if let oldFileName = try String.fetchOne(
                    db,
                    sql: "SELECT file_name FROM manga_image_data_cache_entries WHERE image_url = ?",
                    arguments: [imageURLString]
                ), oldFileName != fileName {
                    try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(oldFileName, isDirectory: false))
                }

                try db.execute(
                    sql: """
                    INSERT INTO manga_image_data_cache_entries (image_url, file_name, byte_count, last_accessed_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(image_url) DO UPDATE SET
                        file_name = excluded.file_name,
                        byte_count = excluded.byte_count,
                        last_accessed_at = excluded.last_accessed_at
                    """,
                    arguments: [imageURLString, fileName, data.count, Date().timeIntervalSince1970]
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
                try db.execute(sql: "DELETE FROM manga_image_data_cache_entries")
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
                sql: "SELECT COALESCE(SUM(byte_count), 0) FROM manga_image_data_cache_entries"
            ) ?? 0
        }) ?? 0
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func cacheKey(for imageURL: URL) -> String {
        imageURL.absoluteString
    }

    private func fileName(for imageURL: URL) -> String {
        let rawExtension = imageURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExtension = rawExtension.isEmpty ? "bin" : sanitizedFileExtension(rawExtension)
        return "manga_image_\(sha256Hex(cacheKey(for: imageURL))).\(safeExtension)"
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
        imageURLString: String,
        fileManager: FileManager,
        baseDirectory: URL,
        in db: Database
    ) throws {
        if let fileName = try String.fetchOne(
            db,
            sql: "SELECT file_name FROM manga_image_data_cache_entries WHERE image_url = ?",
            arguments: [imageURLString]
        ) {
            try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(fileName, isDirectory: false))
        }
        try db.execute(
            sql: "DELETE FROM manga_image_data_cache_entries WHERE image_url = ?",
            arguments: [imageURLString]
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
            sql: "SELECT COALESCE(SUM(byte_count), 0) FROM manga_image_data_cache_entries"
        ) ?? 0
        guard totalBytes > diskLimitBytes else { return }

        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT image_url, file_name, byte_count
            FROM manga_image_data_cache_entries
            ORDER BY last_accessed_at ASC, image_url ASC
            """
        )
        for row in rows where totalBytes > diskLimitBytes {
            let imageURLString = row["image_url"] as String
            let fileName = row["file_name"] as String
            let byteCount = row["byte_count"] as Int
            try? fileManager.removeItem(at: baseDirectory.appendingPathComponent(fileName, isDirectory: false))
            try db.execute(
                sql: "DELETE FROM manga_image_data_cache_entries WHERE image_url = ?",
                arguments: [imageURLString]
            )
            totalBytes -= byteCount
        }
    }

    private static func openDatabase() -> DatabasePool {
        do {
            return try YamiboDatabase.openSharedPool()
        } catch {
            fatalError("Failed to open FileMangaImageDataCacheStore database: \(error)")
        }
    }
}
