import CryptoKit
import Foundation
@preconcurrency import GRDB
import Testing
@testable import YamiboReaderCore

@Suite("CommonTests: Image Data Cache Store")
struct CommonTestsImageDataCacheStore {
    @Test func savesAndLoadsDataAcrossStoreInstances() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let request = try imageCacheRequest(url: "https://img.example.com/a.jpg", namespace: "ordinary")
        let expected = Data([1, 2, 3])

        let writingStore = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await writingStore.save(expected, for: request, retentionPolicy: .evictable)

        let row = try await metadataRow(for: request, in: fixture.database)
        let readingStore = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        let loaded = await readingStore.data(for: request)

        #expect(row?.namespace == "ordinary")
        #expect(row?.imageURL == request.url.absoluteString)
        #expect(row?.fileName == "image_\(sha256Hex(request.persistentCacheKey)).jpg")
        #expect(row?.byteCount == expected.count)
        #expect(row?.retentionPolicy == .evictable)
        #expect(loaded == expected)
    }

    @Test func sameURLInDifferentNamespacesCreatesIsolatedEntries() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let first = try imageCacheRequest(url: "https://img.example.com/shared.jpg", namespace: "first")
        let second = try imageCacheRequest(url: "https://img.example.com/shared.jpg", namespace: "second")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)

        try await store.save(Data([1]), for: first, retentionPolicy: .evictable)
        try await store.save(Data([2]), for: second, retentionPolicy: .evictable)

        #expect(await store.data(for: first) == Data([1]))
        #expect(await store.data(for: second) == Data([2]))
        #expect(try namespaceDirectories(in: fixture.directory).count == 2)
    }

    @Test func fileLayoutHashesNamespaceDirectoryAndPersistentKeyFileName() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let request = try imageCacheRequest(
            url: "https://img.example.com/path/a secret.jpg?token=private",
            namespace: "cookie=private-user-agent"
        )
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)

        try await store.save(Data([1]), for: request, retentionPolicy: .evictable)

        let namespaceDirectory = fixture.directory.appendingPathComponent(sha256Hex(request.cacheNamespace.value), isDirectory: true)
        let cachedFiles = try cachedImageFiles(in: namespaceDirectory)
        let fileName = try #require(cachedFiles.first?.lastPathComponent)

        #expect(cachedFiles.count == 1)
        #expect(fileName == "image_\(sha256Hex(request.persistentCacheKey)).jpg")
        #expect(!namespaceDirectory.lastPathComponent.contains("private"))
        #expect(!fileName.contains("secret"))
        #expect(!fileName.contains("token"))
    }

    @Test func cacheHitUpdatesLRUForLaterEvictableTrim() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let first = try imageCacheRequest(url: "https://img.example.com/first.jpg")
        let second = try imageCacheRequest(url: "https://img.example.com/second.jpg")
        let third = try imageCacheRequest(url: "https://img.example.com/third.jpg")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory, diskLimitBytes: 8)

        try await store.save(Data([1, 1, 1, 1]), for: first, retentionPolicy: .evictable)
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([2, 2, 2, 2]), for: second, retentionPolicy: .evictable)
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(await store.data(for: first) == Data([1, 1, 1, 1]))
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([3, 3, 3, 3]), for: third, retentionPolicy: .evictable)

        #expect(await store.data(for: first) == Data([1, 1, 1, 1]))
        #expect(await store.data(for: second) == nil)
        #expect(await store.data(for: third) == Data([3, 3, 3, 3]))
    }

    @Test func lruTrimmingSkipsProtectedEntriesAndLimitsOnlyEvictableUsage() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let protected = try imageCacheRequest(url: "https://img.example.com/avatar.jpg", namespace: "avatar")
        let oldEvictable = try imageCacheRequest(url: "https://img.example.com/old.jpg")
        let newEvictable = try imageCacheRequest(url: "https://img.example.com/new.jpg")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory, diskLimitBytes: 6)

        try await store.save(Data([9, 9, 9, 9, 9, 9, 9, 9]), for: protected, retentionPolicy: .protected)
        try await store.save(Data([1, 2, 3, 4]), for: oldEvictable, retentionPolicy: .evictable)
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([5, 6, 7, 8]), for: newEvictable, retentionPolicy: .evictable)

        #expect(await store.data(for: protected) == Data([9, 9, 9, 9, 9, 9, 9, 9]))
        #expect(await store.data(for: oldEvictable) == nil)
        #expect(await store.data(for: newEvictable) == Data([5, 6, 7, 8]))
        #expect(await store.evictableDiskUsageBytes() == 4)
        #expect(await store.totalDiskUsageBytes() == 12)
    }

    @Test func oversizedEvictableDataIsNotStoredButOversizedProtectedDataIsStored() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let evictable = try imageCacheRequest(url: "https://img.example.com/large.jpg")
        let protected = try imageCacheRequest(url: "https://img.example.com/protected-large.jpg", namespace: "avatar")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory, diskLimitBytes: 4)

        try await store.save(Data([1, 2, 3, 4, 5]), for: evictable, retentionPolicy: .evictable)
        try await store.save(Data([6, 7, 8, 9, 10]), for: protected, retentionPolicy: .protected)

        #expect(await store.data(for: evictable) == nil)
        #expect(await store.data(for: protected) == Data([6, 7, 8, 9, 10]))
        #expect(await store.evictableDiskUsageBytes() == 0)
        #expect(await store.totalDiskUsageBytes() == 5)
    }

    @Test func emptyDataSaveDeletesExistingEntry() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let request = try imageCacheRequest(url: "https://img.example.com/delete.jpg")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([9]), for: request, retentionPolicy: .evictable)

        try await store.save(Data(), for: request, retentionPolicy: .evictable)

        #expect(await store.data(for: request) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func missingIndexedFileSelfHealsToMiss() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let request = try imageCacheRequest(url: "https://img.example.com/missing-file.jpg")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([7]), for: request, retentionPolicy: .evictable)

        for url in try cachedImageFiles(in: fixture.directory, recursive: true) {
            try FileManager.default.removeItem(at: url)
        }

        #expect(await store.data(for: request) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func emptyIndexedFileSelfHealsToMiss() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let request = try imageCacheRequest(url: "https://img.example.com/empty-file.jpg")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([8]), for: request, retentionPolicy: .evictable)

        let fileURL = try #require(try cachedImageFiles(in: fixture.directory, recursive: true).first)
        try Data().write(to: fileURL, options: [.atomic])

        #expect(await store.data(for: request) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func clearAllDeletesEvictableAndProtectedCacheDirectory() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let evictable = try imageCacheRequest(url: "https://img.example.com/clear.jpg")
        let protected = try imageCacheRequest(url: "https://img.example.com/avatar-clear.jpg", namespace: "avatar")
        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([1, 2]), for: evictable, retentionPolicy: .evictable)
        try await store.save(Data([3, 4]), for: protected, retentionPolicy: .protected)

        try await store.clearAll()

        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(await store.totalDiskUsageBytes() == 0)
        #expect(await store.evictableDiskUsageBytes() == 0)
    }

    @Test func oldMangaOnlyTableIsIgnored() async throws {
        let fixture = try makeTemporaryImageDataCacheFixture()
        let request = try imageCacheRequest(url: "https://img.example.com/legacy.jpg")
        try await fixture.database.write { db in
            try db.execute(
                sql: """
                INSERT INTO manga_image_data_cache_entries (image_url, file_name, byte_count, last_accessed_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [request.url.absoluteString, "legacy.bin", 1, Date().timeIntervalSince1970]
            )
        }

        let store = FileImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)

        #expect(await store.data(for: request) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }
}

private struct ImageDataCacheFixture {
    var database: DatabasePool
    var directory: URL
}

private func makeTemporaryImageDataCacheFixture() throws -> ImageDataCacheFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    return ImageDataCacheFixture(
        database: try YamiboDatabase.openPool(rootDirectory: root.appendingPathComponent("grdb", isDirectory: true)),
        directory: root.appendingPathComponent("image-data", isDirectory: true)
    )
}

private func imageCacheRequest(
    url: String,
    namespace: String = "ordinary"
) throws -> YamiboImageRequest {
    YamiboImageRequest(
        url: try #require(URL(string: url)),
        cacheNamespace: YamiboImageCacheNamespace(value: namespace)
    )
}

private func namespaceDirectories(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter(\.hasDirectoryPath)
}

private func cachedImageFiles(in directory: URL, recursive: Bool = false) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    if !recursive {
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { !$0.hasDirectoryPath }
    }

    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
        return []
    }
    return enumerator
        .compactMap { $0 as? URL }
        .filter { !$0.hasDirectoryPath }
}

private func sha256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private struct ImageDataCacheMetadata: Sendable {
    var namespace: String
    var imageURL: String
    var fileName: String
    var byteCount: Int
    var retentionPolicy: YamiboImageDataCacheRetentionPolicy
}

private func metadataRow(
    for request: YamiboImageRequest,
    in database: DatabasePool
) async throws -> ImageDataCacheMetadata? {
    try await database.read { db in
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT namespace, image_url, file_name, byte_count, retention_policy
            FROM image_data_cache_entries
            WHERE namespace = ? AND image_url = ?
            """,
            arguments: [request.cacheNamespace.value, request.url.absoluteString]
        ) else {
            return nil
        }
        let retentionPolicy = YamiboImageDataCacheRetentionPolicy(rawValue: row["retention_policy"] as String)
        return ImageDataCacheMetadata(
            namespace: row["namespace"],
            imageURL: row["image_url"],
            fileName: row["file_name"],
            byteCount: row["byte_count"],
            retentionPolicy: try #require(retentionPolicy)
        )
    }
}
