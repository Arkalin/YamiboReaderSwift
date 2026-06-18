import CryptoKit
import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Image Data Cache Store")
struct MangaReaderTestsImageDataCacheStore {
    @Test func savesAndLoadsDataAcrossStoreInstances() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/a.jpg"))
        let expected = Data([1, 2, 3])

        let writingStore = FileMangaImageDataCacheStore(baseDirectory: directory)
        try await writingStore.save(expected, for: imageURL)

        let readingStore = FileMangaImageDataCacheStore(baseDirectory: directory)
        let loaded = await readingStore.data(for: imageURL)

        #expect(loaded == expected)
    }

    @Test func fileNameUsesSHA256AndDoesNotExposeRawURL() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/path/a secret.jpg?token=private"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory)

        try await store.save(Data([1]), for: imageURL)

        let cachedFiles = try cachedImageFiles(in: directory)
        let fileName = try #require(cachedFiles.first?.lastPathComponent)
        #expect(cachedFiles.count == 1)
        #expect(fileName == "manga_image_\(sha256Hex(imageURL.absoluteString)).jpg")
        #expect(!fileName.contains("secret"))
        #expect(!fileName.contains("token"))
    }

    @Test func cacheHitUpdatesLRUForLaterTrimWithoutImmediateIndexWrite() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let firstURL = try #require(URL(string: "https://img.example.com/first.jpg"))
        let secondURL = try #require(URL(string: "https://img.example.com/second.jpg"))
        let thirdURL = try #require(URL(string: "https://img.example.com/third.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory, diskLimitBytes: 8)

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
        let directory = try makeTemporaryImageCacheDirectory()
        let oldURL = try #require(URL(string: "https://img.example.com/old.jpg"))
        let newURL = try #require(URL(string: "https://img.example.com/new.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory, diskLimitBytes: 6)

        try await store.save(Data([1, 2, 3, 4]), for: oldURL)
        try await Task.sleep(nanoseconds: 1_000_000)
        try await store.save(Data([5, 6, 7, 8]), for: newURL)

        #expect(await store.data(for: oldURL) == nil)
        #expect(await store.data(for: newURL) == Data([5, 6, 7, 8]))
        #expect(await store.totalDiskUsageBytes() == 4)
    }

    @Test func oversizedImageIsNotStored() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/large.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory, diskLimitBytes: 4)

        try await store.save(Data([1, 2, 3, 4, 5]), for: imageURL)

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
        #expect(try cachedImageFiles(in: directory).isEmpty)
    }

    @Test func emptyDataSaveDeletesExistingEntry() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/delete.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory)
        try await store.save(Data([9]), for: imageURL)

        try await store.save(Data(), for: imageURL)

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func corruptIndexClearsCacheDirectory() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let orphanURL = directory.appendingPathComponent("orphan.bin", isDirectory: false)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("index.json"), options: [.atomic])
        try Data([1]).write(to: orphanURL, options: [.atomic])

        let store = FileMangaImageDataCacheStore(baseDirectory: directory)
        let loaded = await store.data(for: try #require(URL(string: "https://img.example.com/missing.jpg")))

        #expect(loaded == nil)
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
    }

    @Test func missingIndexedFileSelfHealsToMiss() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/missing-file.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory)
        try await store.save(Data([7]), for: imageURL)

        for url in try cachedImageFiles(in: directory) {
            try FileManager.default.removeItem(at: url)
        }

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
    }

    @Test func emptyIndexedFileSelfHealsToMiss() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/empty-file.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory)
        try await store.save(Data([8]), for: imageURL)

        let fileURL = try #require(try cachedImageFiles(in: directory).first)
        try Data().write(to: fileURL, options: [.atomic])

        #expect(await store.data(for: imageURL) == nil)
        #expect(await store.totalDiskUsageBytes() == 0)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func clearAllDeletesCacheDirectory() async throws {
        let directory = try makeTemporaryImageCacheDirectory()
        let imageURL = try #require(URL(string: "https://img.example.com/clear.jpg"))
        let store = FileMangaImageDataCacheStore(baseDirectory: directory)
        try await store.save(Data([1, 2]), for: imageURL)

        try await store.clearAll()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(await store.totalDiskUsageBytes() == 0)
    }
}

private func makeTemporaryImageCacheDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
