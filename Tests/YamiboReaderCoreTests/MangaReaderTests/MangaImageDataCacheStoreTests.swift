import CryptoKit
import Foundation
@preconcurrency import GRDB
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Image Data Cache Store")
struct MangaReaderTestsImageDataCacheStore {
    @Test func savesAndLoadsDataAcrossStoreInstances() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/a.jpg"))
        let expected = Data([1, 2, 3])

        let writingStore = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await writingStore.save(expected, for: imageURL)

        let row = try await metadataRow(for: imageURL, in: fixture.database)
        let readingStore = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        let loaded = await readingStore.data(for: imageURL)

        #expect(row?.fileName == "manga_image_\(sha256Hex(imageURL.absoluteString)).jpg")
        #expect(row?.byteCount == expected.count)
        #expect(loaded == expected)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("index.json").path))
    }

    @Test func fileNameUsesSHA256AndDoesNotExposeRawURL() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/path/a secret.jpg?token=private"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)

        try await store.save(Data([1]), for: imageURL)

        let cachedFiles = try cachedImageFiles(in: fixture.directory)
        let fileName = try #require(cachedFiles.first?.lastPathComponent)
        #expect(cachedFiles.count == 1)
        #expect(fileName == "manga_image_\(sha256Hex(imageURL.absoluteString)).jpg")
        #expect(!fileName.contains("secret"))
        #expect(!fileName.contains("token"))
    }

    @Test func cacheHitUpdatesLRUForLaterTrim() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let firstURL = try #require(URL(string: "https://img.example.com/first.jpg"))
        let secondURL = try #require(URL(string: "https://img.example.com/second.jpg"))
        let thirdURL = try #require(URL(string: "https://img.example.com/third.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory, diskLimitBytes: 8)

        try await store.save(Data([1, 1, 1, 1]), for: firstURL)
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([2, 2, 2, 2]), for: secondURL)
        try await Task.sleep(nanoseconds: 1_000_000)
        #expect(await store.data(for: firstURL) == Data([1, 1, 1, 1]))
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([3, 3, 3, 3]), for: thirdURL)

        #expect(await store.data(for: firstURL) == Data([1, 1, 1, 1]))
        #expect(await store.data(for: secondURL) == nil)
        #expect(await store.data(for: thirdURL) == Data([3, 3, 3, 3]))
    }

    @Test func evictsLeastRecentlyUsedImagesWhenOverDiskLimit() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let oldURL = try #require(URL(string: "https://img.example.com/old.jpg"))
        let newURL = try #require(URL(string: "https://img.example.com/new.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory, diskLimitBytes: 6)

        try await store.save(Data([1, 2, 3, 4]), for: oldURL)
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([5, 6, 7, 8]), for: newURL)

        #expect(await store.data(for: oldURL) == nil)
        #expect(await store.data(for: newURL) == Data([5, 6, 7, 8]))
        #expect(await store.totalDiskUsageBytes() == 4)
    }

    @Test func oversizedImageIsNotStored() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/large.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory, diskLimitBytes: 4)

        try await store.save(Data([1, 2, 3, 4, 5]), for: imageURL)

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
        #expect(try cachedImageFiles(in: fixture.directory).isEmpty)
    }

    @Test func emptyDataSaveDeletesExistingEntry() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/delete.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([9]), for: imageURL)

        try await store.save(Data(), for: imageURL)

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func legacyIndexAndFilesAreIgnoredAndPreserved() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let legacyIndexURL = fixture.directory.appendingPathComponent("index.json", isDirectory: false)
        let legacyImageURL = fixture.directory.appendingPathComponent("legacy-image.bin", isDirectory: false)
        let legacyIndexData = Data(#"{"version":1,"images":{"https://img.example.com/legacy.jpg":{"fileName":"legacy-image.bin","byteCount":1,"lastAccessedAt":"2026-01-01T00:00:00Z"}}}"#.utf8)
        try legacyIndexData.write(to: legacyIndexURL, options: [.atomic])
        try Data([1]).write(to: legacyImageURL, options: [.atomic])

        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        let legacyLoaded = await store.data(for: try #require(URL(string: "https://img.example.com/legacy.jpg")))
        try await store.save(Data([2]), for: try #require(URL(string: "https://img.example.com/new.jpg")))

        #expect(legacyLoaded == nil)
        #expect(try Data(contentsOf: legacyIndexURL) == legacyIndexData)
        #expect(FileManager.default.fileExists(atPath: legacyImageURL.path))
    }

    @Test func missingIndexedFileSelfHealsToMiss() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/missing-file.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([7]), for: imageURL)

        for url in try cachedImageFiles(in: fixture.directory) {
            try FileManager.default.removeItem(at: url)
        }

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func emptyIndexedFileSelfHealsToMiss() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/empty-file.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([8]), for: imageURL)

        let fileURL = try #require(try cachedImageFiles(in: fixture.directory).first)
        try Data().write(to: fileURL, options: [.atomic])

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func clearAllDeletesCacheDirectory() async throws {
        let fixture = try makeTemporaryImageCacheFixture()
        let imageURL = try #require(URL(string: "https://img.example.com/clear.jpg"))
        let store = FileMangaImageDataCacheStore(databasePool: fixture.database, baseDirectory: fixture.directory)
        try await store.save(Data([1, 2]), for: imageURL)

        try await store.clearAll()

        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(await store.totalDiskUsageBytes() == 0)
    }
}

private struct MangaImageCacheFixture {
    var database: DatabasePool
    var directory: URL
}

private func makeTemporaryImageCacheFixture() throws -> MangaImageCacheFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    return MangaImageCacheFixture(
        database: try YamiboDatabase.openPool(rootDirectory: root.appendingPathComponent("grdb", isDirectory: true)),
        directory: root.appendingPathComponent("image-data", isDirectory: true)
    )
}

private func cachedImageFiles(in directory: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default
        .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent != "index.json" }
}

private func sha256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private struct MangaImageCacheMetadata: Sendable {
    var fileName: String
    var byteCount: Int
}

private func metadataRow(for imageURL: URL, in database: DatabasePool) async throws -> MangaImageCacheMetadata? {
    try await database.read { db in
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT file_name, byte_count FROM manga_image_data_cache_entries WHERE image_url = ?",
            arguments: [imageURL.absoluteString]
        ) else {
            return nil
        }
        return MangaImageCacheMetadata(fileName: row["file_name"], byteCount: row["byte_count"])
    }
}
