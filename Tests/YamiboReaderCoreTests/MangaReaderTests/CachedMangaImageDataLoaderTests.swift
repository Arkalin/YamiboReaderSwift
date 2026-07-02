import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Cached Image Data Loader", .serialized)
struct MangaReaderTestsCachedImageDataLoader {
    @Test func cacheHitDoesNotCallUpstream() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/hit.jpg"))
        let cache = RecordingYamiboImageDataCache(initialData: initialCacheData([imageURL: Data([1])]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream)

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
        let cache = RecordingYamiboImageDataCache(initialData: initialCacheData([imageURL: Data([1])]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream, offlineCacheStore: offlineStore)

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
        let cache = RecordingYamiboImageDataCache(initialData: initialCacheData([imageURL: Data([2])]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream, offlineCacheStore: offlineStore)

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
        let cache = RecordingYamiboImageDataCache(initialData: initialCacheData([requestedImageURL: Data([3])]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream, offlineCacheStore: offlineStore)

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
        let cache = RecordingYamiboImageDataCache()
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([4]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream, offlineCacheStore: offlineStore)

        let data = try await loader.imageData(
            for: imageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([4]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.data(for: makeMangaImageRequest(for: imageURL)) == Data([4]))
    }

    @Test func missFetchesSavesAndThenHitsCache() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/miss.jpg"))
        let cache = RecordingYamiboImageDataCache()
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([2, 3]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream)

        let first = try await loader.imageData(for: imageURL, refererURL: nil)
        let second = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(first == Data([2, 3]))
        #expect(second == Data([2, 3]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
    }

    @Test func concurrentMissesForSameURLShareOneUpstreamRequest() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let cache = RecordingYamiboImageDataCache()
        let upstream = RecordingYamiboImageDataLoader(
            results: [.success(Data([4]))],
            delayNanoseconds: 50_000_000
        )
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream)

        async let first = loader.imageData(for: imageURL, refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=1"))
        async let second = loader.imageData(for: imageURL, refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=2"))

        let values = try await [first, second]

        #expect(values == [Data([4]), Data([4])])
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
    }

    @Test func upstreamFailureIsNotCached() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/fail.jpg"))
        let cache = RecordingYamiboImageDataCache()
        let upstream = RecordingYamiboImageDataLoader(results: [
            .failure(YamiboError.offline),
            .failure(YamiboError.offline),
        ])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream)

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: imageURL, refererURL: nil)
        }
        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: imageURL, refererURL: nil)
        }

        #expect(await upstream.callCount == 2)
        #expect(await cache.saveCallCount == 0)
        #expect(await cache.data(for: makeMangaImageRequest(for: imageURL)) == nil)
    }

    @Test func saveFailureDoesNotPreventReturningNetworkData() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/save-fail.jpg"))
        let cache = RecordingYamiboImageDataCache(failsSave: true)
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([5]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(data == Data([5]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
        #expect(await cache.data(for: makeMangaImageRequest(for: imageURL)) == nil)
    }

    @Test func missTaskRechecksCacheBeforeCallingUpstream() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/recheck.jpg"))
        let cache = SecondReadHitYamiboImageDataCache(request: makeMangaImageRequest(for: imageURL), data: Data([6]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = makeMangaImageLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(data == Data([6]))
        #expect(await upstream.callCount == 0)
        #expect(await cache.saveCallCount == 0)
    }
}

private let mangaImageCacheNamespace = YamiboImageCacheNamespace(value: "manga-test")

private func makeMangaImageRequest(for imageURL: URL, refererURL: URL? = nil) -> YamiboImageRequest {
    YamiboImageRequest(url: imageURL, refererURL: refererURL, cacheNamespace: mangaImageCacheNamespace)
}

private func initialCacheData(_ dataByURL: [URL: Data]) -> [String: Data] {
    Dictionary(uniqueKeysWithValues: dataByURL.map { url, data in
        (makeMangaImageRequest(for: url).persistentCacheKey, data)
    })
}

private func makeMangaImageLoader(
    cache: any YamiboImageDataCaching,
    upstream: RecordingYamiboImageDataLoader,
    offlineCacheStore: (any MangaOfflineCacheStoring)? = nil
) -> CachedMangaImageDataLoader {
    CachedMangaImageDataLoader(
        imageDataLoader: CachedYamiboImageDataLoader(cache: cache, upstream: upstream),
        cacheNamespace: mangaImageCacheNamespace,
        offlineCacheStore: offlineCacheStore
    )
}

private actor RecordingYamiboImageDataCache: YamiboImageDataCaching {
    private var storage: [String: Data]
    private let failsSave: Bool
    private(set) var dataCallCount = 0
    private(set) var saveCallCount = 0

    init(initialData: [String: Data] = [:], failsSave: Bool = false) {
        self.storage = initialData
        self.failsSave = failsSave
    }

    func data(for request: YamiboImageRequest) async -> Data? {
        dataCallCount += 1
        return storage[request.persistentCacheKey]
    }

    func save(
        _ data: Data,
        for request: YamiboImageRequest,
        retentionPolicy: YamiboImageDataCacheRetentionPolicy
    ) async throws {
        saveCallCount += 1
        if failsSave {
            throw YamiboError.persistenceFailed("save failed")
        }
        storage[request.persistentCacheKey] = data
    }

    func clearAll() async throws {
        storage = [:]
    }
}

private actor SecondReadHitYamiboImageDataCache: YamiboImageDataCaching {
    private let key: String
    private let output: Data
    private var dataCallCount = 0
    private(set) var saveCallCount = 0

    init(request: YamiboImageRequest, data: Data) {
        self.key = request.persistentCacheKey
        self.output = data
    }

    func data(for request: YamiboImageRequest) async -> Data? {
        dataCallCount += 1
        guard request.persistentCacheKey == key, dataCallCount >= 2 else { return nil }
        return output
    }

    func save(
        _ data: Data,
        for request: YamiboImageRequest,
        retentionPolicy: YamiboImageDataCacheRetentionPolicy
    ) async throws {
        saveCallCount += 1
    }

    func clearAll() async throws {}
}

private actor RecordingYamiboImageDataLoader: YamiboImageDataLoading {
    private var results: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(results: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func imageData(for request: YamiboImageRequest) async throws -> Data {
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
