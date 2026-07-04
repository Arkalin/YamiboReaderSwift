import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("Novel Inline Image Data Loader", .serialized)
struct NovelInlineImageDataLoaderTests {
    @Test func sendsAuthenticatedImageRequestHeaders() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "NovelImageAgent/1")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=novel")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.yamibo.com/forum.php?tid=900")
            #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
            return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
        }

        let loader = YamiboNovelInlineImageDataLoader(imageDataLoader: imageDataLoader(harness: harness))
        let data = try await loader.imageData(
            for: URL(string: "https://img.example.com/novel.jpg")!,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=900")!
        )

        #expect(data == Data([1, 2, 3]))
    }

    @Test func deduplicatesConcurrentRequestsByImageURL() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = NovelInlineImageRequestCounter()
        harness.setHandler { _ in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return MangaReaderDataTestResponse(data: Data([9]))
        }

        let loader = YamiboNovelInlineImageDataLoader(imageDataLoader: imageDataLoader(harness: harness))
        let imageURL = URL(string: "https://img.example.com/shared.jpg")!
        let refererURL = URL(string: "https://bbs.yamibo.com/forum.php?tid=1")!
        async let first = loader.imageData(
            for: imageURL,
            refererURL: refererURL
        )
        async let second = loader.imageData(
            for: imageURL,
            refererURL: refererURL
        )

        let values = try await [first, second]

        #expect(values == [Data([9]), Data([9])])
        #expect(counter.value == 1)
    }

    @Test func deduplicatesConcurrentRequestsWithDifferentRefererURLs() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = NovelInlineImageRequestCounter()
        harness.setHandler { _ in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return MangaReaderDataTestResponse(data: Data([9]))
        }

        let loader = YamiboNovelInlineImageDataLoader(imageDataLoader: imageDataLoader(harness: harness))
        let imageURL = URL(string: "https://img.example.com/shared.jpg")!
        async let first = loader.imageData(
            for: imageURL,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=1")!
        )
        async let second = loader.imageData(
            for: imageURL,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=2")!
        )

        let values = try await [first, second]

        #expect(values == [Data([9]), Data([9])])
        #expect(counter.value == 1)
    }

    @Test func mapsHTTPAndBodyErrors() async throws {
        try await expectImageError(statusCode: 401, data: Data([1]), expected: YamiboError.notAuthenticated)
        try await expectImageError(statusCode: 403, data: Data([1]), expected: YamiboError.notAuthenticated)
        try await expectImageError(statusCode: 500, data: Data([1]), expected: YamiboError.invalidResponse(statusCode: 500))
        try await expectImageError(statusCode: 200, data: Data(), expected: YamiboError.unreadableBody)
    }

    @Test func mapsOfflineURLError() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            throw URLError(.notConnectedToInternet)
        }
        let loader = YamiboNovelInlineImageDataLoader(imageDataLoader: imageDataLoader(harness: harness))

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(
                for: URL(string: "https://img.example.com/a.jpg")!,
                refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=900")!
            )
        }
    }

    @Test func cachedLoaderUsesOfflineImageProviderBeforeUpstream() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/provider-hit.jpg"))
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=910&page=2"))
        let offlineProvider = RecordingNovelOfflineImageProvider(result: Data([4, 2]))
        let upstream = RecordingNovelInlineImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedNovelInlineImageDataLoader(
            imageDataLoader: upstream,
            offlineCacheStore: offlineProvider,
            threadID: "910"
        )

        let data = try await loader.imageData(for: imageURL, refererURL: refererURL)

        #expect(data == Data([4, 2]))
        #expect(await offlineProvider.requestedImageURLs == [imageURL])
        #expect(await offlineProvider.requestedThreadIDs == ["910"])
        #expect(await upstream.callCount == 0)
    }

    @Test func cachedLoaderDelegatesWhenOfflineImageProviderMisses() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/provider-miss.jpg"))
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=911&page=2"))
        let offlineProvider = RecordingNovelOfflineImageProvider(result: nil)
        let upstream = RecordingNovelInlineImageDataLoader(results: [.success(Data([6]))])
        let loader = CachedNovelInlineImageDataLoader(
            imageDataLoader: upstream,
            offlineCacheStore: offlineProvider,
            threadID: "911"
        )

        let data = try await loader.imageData(for: imageURL, refererURL: refererURL)

        #expect(data == Data([6]))
        #expect(await offlineProvider.requestedImageURLs == [imageURL])
        #expect(await offlineProvider.requestedThreadIDs == ["911"])
        #expect(await upstream.requestedRequests == [
            YamiboImageRequest(url: imageURL, refererURL: refererURL)
        ])
    }

    @Test func cachedLoaderReadsRetainedOfflineImageBeforeUpstream() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/novel-offline.jpg"))
        let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=900&page=1"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: makeTemporaryNovelInlineImageLoaderDirectory())
        try await offlineStore.saveNovelOfflineCacheEntry(
            makeNovelInlineImageOfflineEntry(threadID: "900", imageURLs: [imageURL])
        )
        try await offlineStore.saveOfflineImageData(Data([7, 8]), for: imageURL)
        let upstream = RecordingNovelInlineImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedNovelInlineImageDataLoader(
            imageDataLoader: upstream,
            offlineCacheStore: offlineStore,
            threadID: "900"
        )

        let data = try await loader.imageData(for: imageURL, refererURL: threadURL)

        #expect(data == Data([7, 8]))
        #expect(await upstream.callCount == 0)
    }

    @Test func cachedLoaderDelegatesWhenRetainedOfflineImageBytesAreMissing() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/novel-missing.jpg"))
        let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&page=1"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: makeTemporaryNovelInlineImageLoaderDirectory())
        try await offlineStore.saveNovelOfflineCacheEntry(
            makeNovelInlineImageOfflineEntry(threadID: "901", imageURLs: [imageURL])
        )
        let upstream = RecordingNovelInlineImageDataLoader(results: [.success(Data([3]))])
        let loader = CachedNovelInlineImageDataLoader(
            imageDataLoader: upstream,
            offlineCacheStore: offlineStore,
            threadID: "901"
        )

        let data = try await loader.imageData(for: imageURL, refererURL: threadURL)

        #expect(data == Data([3]))
        #expect(await upstream.callCount == 1)
        #expect(await upstream.requestedRequests == [YamiboImageRequest(url: imageURL, refererURL: threadURL)])
    }

    @Test func cachedLoaderDoesNotUseRetainedOfflineImageForDifferentThread() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/novel-other-thread.jpg"))
        let cachedThreadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=902&page=1"))
        let requestedThreadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=903&page=1"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: makeTemporaryNovelInlineImageLoaderDirectory())
        try await offlineStore.saveNovelOfflineCacheEntry(
            makeNovelInlineImageOfflineEntry(threadID: "902", imageURLs: [imageURL])
        )
        try await offlineStore.saveOfflineImageData(Data([7]), for: imageURL)
        let upstream = RecordingNovelInlineImageDataLoader(results: [.success(Data([4]))])
        let loader = CachedNovelInlineImageDataLoader(
            imageDataLoader: upstream,
            offlineCacheStore: offlineStore,
            threadID: "903"
        )

        let data = try await loader.imageData(for: imageURL, refererURL: requestedThreadURL)

        #expect(data == Data([4]))
        #expect(await upstream.callCount == 1)
    }

    @Test func cachedLoaderSurfacesUpstreamFailureWhenRetainedOfflineImageBytesAreMissing() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/novel-queued.jpg"))
        let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=904&page=1"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: makeTemporaryNovelInlineImageLoaderDirectory())
        try await offlineStore.saveNovelOfflineCacheEntry(
            makeNovelInlineImageOfflineEntry(threadID: "904", imageURLs: [imageURL])
        )
        let upstream = RecordingNovelInlineImageDataLoader(results: [.failure(YamiboError.offline)])
        let loader = CachedNovelInlineImageDataLoader(
            imageDataLoader: upstream,
            offlineCacheStore: offlineStore,
            threadID: "904"
        )

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: imageURL, refererURL: threadURL)
        }

        #expect(await upstream.callCount == 1)
    }

    @Test func appContextInlineImageContextProvidesProjectLoader() async throws {
        let suiteName = "NovelInlineImageDataLoaderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let sessionStore = SessionStore(defaults: defaults, key: "session")
        try await sessionStore.save(SessionState(
            cookie: "EeqY_2132_auth=secret-cookie",
            userAgent: "NovelImageAgent/1",
            isLoggedIn: true
        ))
        let context = YamiboAppContext(sessionStore: sessionStore)

        let loadingContext = await context.makeNovelInlineImageLoadingContext()

        _ = loadingContext.loader
    }

    private func imageDataLoader(harness: MangaReaderDataTestHarness) -> YamiboImageDataLoader {
        harness.imageDataLoader(
            cookie: "auth=novel",
            userAgent: "NovelImageAgent/1"
        )
    }

    private func expectImageError(statusCode: Int, data: Data, expected: YamiboError) async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            MangaReaderDataTestResponse(statusCode: statusCode, data: data)
        }
        let loader = YamiboNovelInlineImageDataLoader(imageDataLoader: imageDataLoader(harness: harness))

        await #expect(throws: expected) {
            _ = try await loader.imageData(
                for: URL(string: "https://img.example.com/a.jpg")!,
                refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=900")!
            )
        }
    }
}

private actor RecordingNovelOfflineImageProvider: NovelOfflineImageDataProviding {
    private let result: Data?
    private(set) var requestedImageURLs: [URL] = []
    private(set) var requestedThreadIDs: [String] = []

    init(result: Data?) {
        self.result = result
    }

    func novelOfflineImageData(for imageURL: URL, threadID: String) async -> Data? {
        requestedImageURLs.append(imageURL)
        requestedThreadIDs.append(threadID)
        return result
    }
}

private actor RecordingNovelInlineImageDataLoader: NovelInlineImageDataLoading {
    private var results: [Result<Data, Error>]
    private(set) var requestedRequests: [YamiboImageRequest] = []
    private(set) var callCount = 0

    init(results: [Result<Data, Error>]) {
        self.results = results
    }

    func imageData(for imageURL: URL, refererURL: URL) async throws -> Data {
        callCount += 1
        requestedRequests.append(YamiboImageRequest(url: imageURL, refererURL: refererURL))
        let result = results.isEmpty ? Result<Data, Error>.failure(YamiboError.unreadableBody) : results.removeFirst()
        return try result.get()
    }
}

private final class NovelInlineImageRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private func makeNovelInlineImageOfflineEntry(threadID: String, imageURLs: [URL]) -> NovelOfflineCacheEntry {
    NovelOfflineCacheEntry(
        ownerTitle: "测试小说",
        document: NovelReaderProjection(
            threadID: threadID,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-900",
            contentSource: .authorFilteredPage,
            segments: imageURLs.map { .image($0, chapterTitle: nil) }
        ),
        imageURLs: imageURLs
    )
}

private func makeTemporaryNovelInlineImageLoaderDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
