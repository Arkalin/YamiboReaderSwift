import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("CommonTests: Cached Yamibo Image Data Loader", .serialized)
struct CommonTestsCachedYamiboImageDataLoader {
    @Test func cacheHitDoesNotCallUpstream() async throws {
        let request = try imageRequest(url: "https://img.example.com/hit.jpg")
        let cache = RecordingImageDataCache(initialData: [request.persistentCacheKey: Data([1])])
        let upstream = RecordingImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: request)

        #expect(data == Data([1]))
        #expect(await upstream.callCount == 0)
        #expect(await cache.saveCallCount == 0)
    }

    @Test func missFetchesSavesAndThenHitsCache() async throws {
        let request = try imageRequest(url: "https://img.example.com/miss.jpg")
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(results: [.success(Data([2, 3]))])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let first = try await loader.imageData(for: request)
        let second = try await loader.imageData(for: request)

        #expect(first == Data([2, 3]))
        #expect(second == Data([2, 3]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
        #expect(await cache.retentionPolicies == [.evictable])
    }

    @Test func protectedLoaderSavesWithProtectedRetentionPolicy() async throws {
        let request = try imageRequest(url: "https://img.example.com/avatar.jpg", namespace: "avatar")
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(results: [.success(Data([4]))])
        let loader = CachedYamiboImageDataLoader(
            cache: cache,
            upstream: upstream,
            retentionPolicy: .protected
        )

        _ = try await loader.imageData(for: request)

        #expect(await cache.retentionPolicies == [.protected])
    }

    @Test func saveFailureDoesNotPreventReturningNetworkData() async throws {
        let request = try imageRequest(url: "https://img.example.com/save-fail.jpg")
        let cache = RecordingImageDataCache(failsSave: true)
        let upstream = RecordingImageDataLoader(results: [.success(Data([5]))])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: request)

        #expect(data == Data([5]))
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
        #expect(await cache.data(for: request) == nil)
    }

    @Test func upstreamFailureIsNotCached() async throws {
        let request = try imageRequest(url: "https://img.example.com/fail.jpg")
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(results: [
            .failure(YamiboError.offline),
            .failure(YamiboError.offline),
        ])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: request)
        }
        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: request)
        }

        #expect(await upstream.callCount == 2)
        #expect(await cache.saveCallCount == 0)
        #expect(await cache.data(for: request) == nil)
    }

    @Test func emptySuccessfulDataIsReturnedButNotCached() async throws {
        let request = try imageRequest(url: "https://img.example.com/empty.jpg")
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(results: [.success(Data())])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: request)

        #expect(data == Data())
        #expect(await cache.saveCallCount == 0)
    }

    @Test func concurrentMissesForSamePersistentKeyShareOneUpstreamRequestEvenWithDifferentReferers() async throws {
        let imageURL = "https://img.example.com/shared.jpg"
        let first = try imageRequest(
            url: imageURL,
            refererURL: "https://bbs.yamibo.com/forum.php?tid=1"
        )
        let second = try imageRequest(
            url: imageURL,
            refererURL: "https://bbs.yamibo.com/forum.php?tid=2"
        )
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(
            results: [.success(Data([6]))],
            delayNanoseconds: 50_000_000
        )
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        async let firstData = loader.imageData(for: first)
        async let secondData = loader.imageData(for: second)

        let values = try await [firstData, secondData]

        #expect(values == [Data([6]), Data([6])])
        #expect(await upstream.callCount == 1)
        #expect(await cache.saveCallCount == 1)
        #expect(await upstream.requests.map(\.refererURL?.absoluteString) == [first.refererURL?.absoluteString])
    }

    @Test func sameURLInDifferentNamespacesDoesNotSharePersistentCache() async throws {
        let first = try imageRequest(url: "https://img.example.com/shared.jpg", namespace: "first")
        let second = try imageRequest(url: "https://img.example.com/shared.jpg", namespace: "second")
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(results: [
            .success(Data([1])),
            .success(Data([2])),
        ])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let firstData = try await loader.imageData(for: first)
        let secondData = try await loader.imageData(for: second)

        #expect(firstData == Data([1]))
        #expect(secondData == Data([2]))
        #expect(await upstream.callCount == 2)
    }

    @Test func refererDoesNotParticipateInPersistentCacheIdentity() async throws {
        let first = try imageRequest(
            url: "https://img.example.com/referer.jpg",
            refererURL: "https://bbs.yamibo.com/forum.php?tid=1"
        )
        let second = try imageRequest(
            url: "https://img.example.com/referer.jpg",
            refererURL: "https://bbs.yamibo.com/forum.php?tid=2"
        )
        let cache = RecordingImageDataCache()
        let upstream = RecordingImageDataLoader(results: [.success(Data([7])), .success(Data([9]))])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let firstData = try await loader.imageData(for: first)
        let secondData = try await loader.imageData(for: second)

        #expect(firstData == Data([7]))
        #expect(secondData == Data([7]))
        #expect(await upstream.callCount == 1)
    }

    @Test func missTaskRechecksCacheBeforeCallingUpstream() async throws {
        let request = try imageRequest(url: "https://img.example.com/recheck.jpg")
        let cache = SecondReadHitImageDataCache(request: request, data: Data([8]))
        let upstream = RecordingImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedYamiboImageDataLoader(cache: cache, upstream: upstream)

        let data = try await loader.imageData(for: request)

        #expect(data == Data([8]))
        #expect(await upstream.callCount == 0)
        #expect(await cache.saveCallCount == 0)
    }

    @Test func sessionNamespaceHelpersDoNotExposeRawValuesAndSeparateAvatars() {
        let ordinary = YamiboImageCacheNamespace.ordinarySessionNamespace(
            cookie: "auth=secret-cookie",
            userAgent: "Agent/1"
        )
        let avatar = YamiboImageCacheNamespace.avatarSessionNamespace(
            cookie: "auth=secret-cookie",
            userAgent: "Agent/1"
        )

        #expect(!ordinary.value.contains("secret-cookie"))
        #expect(!ordinary.value.contains("Agent/1"))
        #expect(!avatar.value.contains("secret-cookie"))
        #expect(!avatar.value.contains("Agent/1"))
        #expect(avatar.value.hasPrefix("avatar:"))
        #expect(ordinary.value != avatar.value)
    }
}

private actor RecordingImageDataCache: YamiboImageDataCaching {
    private var storage: [String: Data]
    private let failsSave: Bool
    private(set) var dataCallCount = 0
    private(set) var saveCallCount = 0
    private(set) var retentionPolicies: [YamiboImageDataCacheRetentionPolicy] = []

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
        retentionPolicies.append(retentionPolicy)
        if failsSave {
            throw YamiboError.persistenceFailed("save failed")
        }
        storage[request.persistentCacheKey] = data
    }

    func clearAll() async throws {
        storage = [:]
    }
}

private actor SecondReadHitImageDataCache: YamiboImageDataCaching {
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

private actor RecordingImageDataLoader: YamiboImageDataLoading {
    private var results: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0
    private(set) var requests: [YamiboImageRequest] = []

    init(results: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func imageData(for request: YamiboImageRequest) async throws -> Data {
        callCount += 1
        requests.append(request)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        let result = results.isEmpty ? Result<Data, Error>.failure(YamiboError.unreadableBody) : results.removeFirst()
        return try result.get()
    }
}

private func imageRequest(
    url: String,
    namespace: String = "ordinary",
    refererURL: String? = nil
) throws -> YamiboImageRequest {
    YamiboImageRequest(
        url: try #require(URL(string: url)),
        refererURL: try refererURL.map { try #require(URL(string: $0)) },
        cacheNamespace: YamiboImageCacheNamespace(value: namespace)
    )
}
