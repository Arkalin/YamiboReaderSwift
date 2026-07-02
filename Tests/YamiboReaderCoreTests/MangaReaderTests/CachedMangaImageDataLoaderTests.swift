import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Cached Image Data Loader", .serialized)
struct MangaReaderTestsCachedImageDataLoader {
    @Test func cacheHitDoesNotCallUpstream() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/hit.jpg"))
        let cache = RecordingMangaImageDataCache(initialData: [imageURL.absoluteString: Data([1])])
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(data == Data([1]))
        #expect(await upstream.callCount == 0)
        #expect(await cache.saveCallCount == 0)
    }

    @Test func matchingOfflineMembershipReadsRetainedBytesBeforeTransparentCacheAndNetwork() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/offline.jpg"))
        let offlineStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryCachedImageLoaderDirectory())
        try await offlineStore.saveOfflineImageData(Data([7]), for: imageURL)
        try await offlineStore.saveMembership(makeCachedImageLoaderMembership(imageURLs: [imageURL]))
        let cache = RecordingMangaImageDataCache(initialData: [imageURL.absoluteString: Data([1])])
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(
            cache: cache,
            upstream: upstream,
            offlineCacheStore: offlineStore
        )

        let data = try await loader.imageData(
            for: imageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([7]))
        #expect(await cache.dataCallCount == 0)
        #expect(await upstream.callCount == 0)
    }

    @Test func missingOfflineBytesForMatchingMembershipFallsBackToTransparentCache() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/fallback-cache.jpg"))
        let offlineStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryCachedImageLoaderDirectory())
        try await offlineStore.saveMembership(makeCachedImageLoaderMembership(imageURLs: [imageURL]))
        let cache = RecordingMangaImageDataCache(initialData: [imageURL.absoluteString: Data([2])])
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(
            cache: cache,
            upstream: upstream,
            offlineCacheStore: offlineStore
        )

        let data = try await loader.imageData(
            for: imageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([2]))
        #expect(await upstream.callCount == 0)
    }

    @Test func nonMemberImageKeepsTransparentCacheThenNetworkBehaviorWithoutCreatingMembership() async throws {
        let memberImageURL = try #require(URL(string: "https://img.example.com/member.jpg"))
        let requestedImageURL = try #require(URL(string: "https://img.example.com/non-member.jpg"))
        let offlineStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryCachedImageLoaderDirectory())
        try await offlineStore.saveOfflineImageData(Data([7]), for: requestedImageURL)
        try await offlineStore.saveMembership(makeCachedImageLoaderMembership(imageURLs: [memberImageURL]))
        let cache = RecordingMangaImageDataCache(initialData: [requestedImageURL.absoluteString: Data([3])])
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(
            cache: cache,
            upstream: upstream,
            offlineCacheStore: offlineStore
        )

        let data = try await loader.imageData(
            for: requestedImageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([3]))
        #expect(await upstream.callCount == 0)
        #expect(await offlineStore.membership(ownerName: "favorite-a", tid: "missing") == nil)
    }

    @Test func matchingMembershipFallsBackToNetworkWhenOfflineAndTransparentBytesAreMissing() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/fallback-network.jpg"))
        let offlineStore = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryCachedImageLoaderDirectory())
        try await offlineStore.saveMembership(makeCachedImageLoaderMembership(imageURLs: [imageURL]))
        let cache = RecordingMangaImageDataCache()
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([4]))])
        let loader = CachedMangaImageDataLoader(
            cache: cache,
            upstream: upstream,
            offlineCacheStore: offlineStore
        )

        let data = try await loader.imageData(
            for: imageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([4]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.data(for: imageURL) == Data([4]))
    }

    @Test func missFetchesSavesAndThenHitsCache() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/miss.jpg"))
        let cache = RecordingMangaImageDataCache()
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([2, 3]))])
        let loader = CachedMangaImageDataLoader(cache: cache, upstream: upstream)

        let first = try await loader.imageData(for: imageURL, refererURL: nil)
        let second = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(first == Data([2, 3]))
        #expect(second == Data([2, 3]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
    }

    @Test func concurrentMissesForSameURLShareOneUpstreamRequest() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let cache = RecordingMangaImageDataCache()
        let upstream = RecordingMangaImageDataLoader(
            results: [.success(Data([4]))],
            delayNanoseconds: 50_000_000
        )
        let loader = CachedMangaImageDataLoader(cache: cache, upstream: upstream)

        async let first = loader.imageData(for: imageURL, refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=1"))
        async let second = loader.imageData(for: imageURL, refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=2"))

        let values = try await [first, second]

        #expect(values == [Data([4]), Data([4])])
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
    }

    @Test func upstreamFailureIsNotCached() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/fail.jpg"))
        let cache = RecordingMangaImageDataCache()
        let upstream = RecordingMangaImageDataLoader(results: [
            .failure(YamiboError.offline),
            .failure(YamiboError.offline),
        ])
        let loader = CachedMangaImageDataLoader(cache: cache, upstream: upstream)

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: imageURL, refererURL: nil)
        }
        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: imageURL, refererURL: nil)
        }

        #expect(await upstream.callCount == 2)
        #expect(await cache.saveCallCount == 0)
        #expect(await cache.data(for: imageURL) == nil)
    }

    @Test func saveFailureDoesNotPreventReturningNetworkData() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/save-fail.jpg"))
        let cache = RecordingMangaImageDataCache(failsSave: true)
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([5]))])
        let loader = CachedMangaImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(data == Data([5]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
        #expect(await cache.data(for: imageURL) == nil)
    }

    @Test func missTaskRechecksCacheBeforeCallingUpstream() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/recheck.jpg"))
        let cache = SecondReadHitMangaImageDataCache(imageURL: imageURL, data: Data([6]))
        let upstream = RecordingMangaImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(data == Data([6]))
        #expect(await upstream.callCount == 0)
        #expect(await cache.saveCallCount == 0)
    }
}

private actor RecordingMangaImageDataCache: MangaImageDataCaching {
    private var storage: [String: Data]
    private let failsSave: Bool
    private(set) var dataCallCount = 0
    private(set) var saveCallCount = 0

    init(initialData: [String: Data] = [:], failsSave: Bool = false) {
        self.storage = initialData
        self.failsSave = failsSave
    }

    func data(for imageURL: URL) async -> Data? {
        dataCallCount += 1
        return storage[imageURL.absoluteString]
    }

    func save(_ data: Data, for imageURL: URL) async throws {
        saveCallCount += 1
        if failsSave {
            throw YamiboError.persistenceFailed("save failed")
        }
        storage[imageURL.absoluteString] = data
    }

    func clearAll() async throws {
        storage = [:]
    }
}

private actor SecondReadHitMangaImageDataCache: MangaImageDataCaching {
    private let key: String
    private let output: Data
    private var dataCallCount = 0
    private(set) var saveCallCount = 0

    init(imageURL: URL, data: Data) {
        self.key = imageURL.absoluteString
        self.output = data
    }

    func data(for imageURL: URL) async -> Data? {
        dataCallCount += 1
        guard imageURL.absoluteString == key, dataCallCount >= 2 else { return nil }
        return output
    }

    func save(_ data: Data, for imageURL: URL) async throws {
        saveCallCount += 1
    }

    func clearAll() async throws {}
}

private actor RecordingMangaImageDataLoader: MangaImageDataLoading {
    private var results: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(results: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let result = results.isEmpty ? Result<Data, Error>.failure(YamiboError.unreadableBody) : results.removeFirst()
        return try result.get()
    }
}

private func makeCachedImageLoaderMembership(imageURLs: [URL]) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: "favorite-a",
        tid: "100",
        chapterTitle: "第100话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100")),
        imageURLs: imageURLs
    )
}

private func makeTemporaryCachedImageLoaderDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
