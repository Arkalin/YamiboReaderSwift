import CryptoKit
import Foundation
@preconcurrency import GRDB

extension OfflineCacheStore {
    public func offlineImageData(for imageURL: URL) async -> Data? {
        try? await recoverQueueStateAfterRestart()
        let imageURLString = imageURL.absoluteString
        guard let fileName = try? await database.read({ db in
            try String.fetchOne(
                db,
                sql: "SELECT file_name FROM offline_cache_image_assets WHERE image_url = ?",
                arguments: [imageURLString]
            )
        }) else {
            return nil
        }

        let fileURL = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            try? await database.write { db in
                try Self.deleteImage(imageURLString: imageURLString, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db)
            }
            return nil
        }
        return data
    }

    public func saveOfflineImageData(_ data: Data, for imageURL: URL) async throws {
        try await recoverQueueStateAfterRestart()
        do {
            let imageURLString = imageURL.absoluteString
            let fileName = imageFileName(for: imageURL)
            if !data.isEmpty {
                try ensureImagesDirectoryExists()
                let fileURL = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
                try data.write(to: fileURL, options: [.atomic])
            }

            try await database.write { db in
                guard !data.isEmpty else {
                    try Self.deleteImage(imageURLString: imageURLString, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db)
                    return
                }

                if let oldFileName = try String.fetchOne(
                    db,
                    sql: "SELECT file_name FROM offline_cache_image_assets WHERE image_url = ?",
                    arguments: [imageURLString]
                ), oldFileName != fileName {
                    try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(oldFileName, isDirectory: false))
                }
                try db.execute(
                    sql: """
                    INSERT INTO offline_cache_image_assets (image_url, file_name, byte_count)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [imageURLString, fileName, data.count]
                )

                let memberships = try Self.allMemberships(in: db)
                for membership in memberships where membership.imageURLs.contains(imageURL) {
                    if try Self.isMembershipComplete(membership, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db) {
                        try Self.deleteWork(ownerName: membership.ownerName, tid: membership.tid, in: db)
                    }
                }
            }
            notifyOfflineCacheDidChange()
        } catch {
            throw offlineCachePersistenceError(from: error)
        }
    }

    public func diskUsageByOwner() async -> [MangaOfflineCacheOwnerUsage] {
        try? await recoverQueueStateAfterRestart()
        return (try? await database.read { db in
            var imageURLsByOwner: [String: Set<String>] = [:]
            for membership in try Self.allMemberships(in: db) {
                imageURLsByOwner[membership.ownerName, default: []].formUnion(membership.imageURLs.map(\.absoluteString))
            }
            for work in try Self.allWorks(in: db) {
                imageURLsByOwner[work.ownerName, default: []].formUnion((work.targetImageURLs + work.completedImageURLs).map(\.absoluteString))
            }

            var usage: [MangaOfflineCacheOwnerUsage] = []
            for (ownerName, imageURLs) in imageURLsByOwner {
                var byteCount = 0
                for imageURL in imageURLs {
                    byteCount += try Int.fetchOne(
                        db,
                        sql: "SELECT byte_count FROM offline_cache_image_assets WHERE image_url = ?",
                        arguments: [imageURL]
                    ) ?? 0
                }
                usage.append(MangaOfflineCacheOwnerUsage(ownerName: ownerName, byteCount: byteCount))
            }
            return usage.sorted { $0.ownerName.localizedStandardCompare($1.ownerName) == .orderedAscending }
        }) ?? []
    }

    func ensureImagesDirectoryExists() throws {
        try ensureBaseDirectoryExists()
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
    }

    func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isMembershipComplete(
        _ membership: MangaOfflineCacheMembership,
        fileManager: FileManager,
        imagesDirectory: URL,
        in db: Database
    ) throws -> Bool {
        guard membership.sourcePage.thread.tid == membership.tid else { return false }
        guard !membership.imageURLs.isEmpty else { return false }
        for imageURL in membership.imageURLs {
            guard let fileName = try String.fetchOne(
                db,
                sql: "SELECT file_name FROM offline_cache_image_assets WHERE image_url = ?",
                arguments: [imageURL.absoluteString]
            ) else {
                return false
            }
            let fileURL = imagesDirectory.appendingPathComponent(fileName, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        }
        return true
    }

    static func removeUnreferencedImages(
        candidateImageURLs: [URL],
        fileManager: FileManager,
        imagesDirectory: URL,
        in db: Database
    ) throws {
        let candidates = Set(candidateImageURLs.map(\.absoluteString))
        guard !candidates.isEmpty else { return }
        let referenced = try referencedImageURLs(in: db)
        for imageURLString in candidates where !referenced.contains(imageURLString) {
            try deleteImage(imageURLString: imageURLString, fileManager: fileManager, imagesDirectory: imagesDirectory, in: db)
        }
    }

    private func imageFileName(for imageURL: URL) -> String {
        let rawExtension = imageURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeExtension = sanitizedFileExtension(rawExtension.isEmpty ? "bin" : rawExtension)
        return "offline_image_\(sha256Hex(imageURL.absoluteString)).\(safeExtension)"
    }

    private func sanitizedFileExtension(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(of: #"[^A-Za-z0-9]"#, with: "", options: .regularExpression)
        return sanitized.isEmpty ? "bin" : sanitized
    }

    private static func referencedImageURLs(in db: Database) throws -> Set<String> {
        var referenced = Set<String>()
        for table in [
            "offline_cache_manga_entry_images",
            "offline_cache_novel_entry_images",
            "offline_cache_work_images",
            "offline_cache_completed_images"
        ] {
            referenced.formUnion(try String.fetchAll(db, sql: "SELECT image_url FROM \(table)"))
        }
        return referenced
    }

    private static func deleteImage(
        imageURLString: String,
        fileManager: FileManager,
        imagesDirectory: URL,
        in db: Database
    ) throws {
        if let fileName = try String.fetchOne(
            db,
            sql: "SELECT file_name FROM offline_cache_image_assets WHERE image_url = ?",
            arguments: [imageURLString]
        ) {
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(fileName, isDirectory: false))
        }
        try db.execute(sql: "DELETE FROM offline_cache_image_assets WHERE image_url = ?", arguments: [imageURLString])
    }
}

private func offlineCachePersistenceError(from error: Error) -> YamiboError {
    if let error = error as? YamiboError {
        return error
    }
    return YamiboError.persistenceFailed(error.localizedDescription)
}
