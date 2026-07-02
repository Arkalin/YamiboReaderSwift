import Foundation
import Testing
@testable import YamiboReaderCore

@Test func yamiboImageDataLoaderSendsCookieUserAgentAndReferer() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    let pipeline = try makeIsolatedImageDataPipeline()
    harness.setHandler { request in
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=1")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "UnitAgent")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.yamibo.com/thread-1.html")
        #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/*") == true)
        return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
        pipeline: pipeline
    )

    let data = try await loader.imageData(
        for: imageRequest(refererURL: URL(string: "https://bbs.yamibo.com/thread-1.html")!)
    )

    #expect(data == Data([1, 2, 3]))
    #expect(harness.requests.count == 1)
}

@Test func yamiboImageDataLoaderOmitsRefererWhenNil() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    let pipeline = try makeIsolatedImageDataPipeline()
    harness.setHandler { request in
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        return MangaReaderDataTestResponse(data: Data([4]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "", userAgent: "UnitAgent"),
        pipeline: pipeline
    )

    _ = try await loader.imageData(for: imageRequest(refererURL: nil))

    #expect(harness.requests.count == 1)
}

@Test func yamiboImageDataLoaderDeduplicatesConcurrentSameRequest() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    let pipeline = try makeIsolatedImageDataPipeline()
    let counter = LockedCounter()
    harness.setHandler { _ in
        counter.increment()
        Thread.sleep(forTimeInterval: 0.05)
        return MangaReaderDataTestResponse(data: Data([7]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
        pipeline: pipeline
    )
    let request = imageRequest(refererURL: URL(string: "https://bbs.yamibo.com/thread-1.html")!)

    async let first = loader.imageData(for: request)
    async let second = loader.imageData(for: request)
    let values = try await [first, second]

    #expect(values == [Data([7]), Data([7])])
    #expect(counter.value == 1)
}

@Test func yamiboImageDataLoaderDoesNotDeduplicateDifferentRequestNamespaces() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    let pipeline = try makeIsolatedImageDataPipeline()
    let counter = LockedCounter()
    harness.setHandler { _ in
        counter.increment()
        Thread.sleep(forTimeInterval: 0.05)
        return MangaReaderDataTestResponse(data: Data([9]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
        pipeline: pipeline
    )
    let first = imageRequest(namespace: "first", refererURL: URL(string: "https://bbs.yamibo.com/thread-1.html")!)
    let second = imageRequest(namespace: "second", refererURL: URL(string: "https://bbs.yamibo.com/thread-1.html")!)

    async let firstData = loader.imageData(for: first)
    async let secondData = loader.imageData(for: second)
    _ = try await [firstData, secondData]

    #expect(counter.value == 2)
}

@Test func yamiboImageDataLoaderMapsAuthAndEmptyDataFailures() async throws {
    let authHarness = MangaReaderDataTestHarness()
    defer { authHarness.reset() }
    let authPipeline = try makeIsolatedImageDataPipeline()
    authHarness.setHandler { _ in
        MangaReaderDataTestResponse(statusCode: 403, data: Data([1]))
    }
    let authLoader = YamiboImageDataLoader(
        client: YamiboClient(session: authHarness.session),
        pipeline: authPipeline
    )
    await #expect(throws: YamiboError.notAuthenticated) {
        _ = try await authLoader.imageData(for: imageRequest())
    }

    let emptyHarness = MangaReaderDataTestHarness()
    defer { emptyHarness.reset() }
    let emptyPipeline = try makeIsolatedImageDataPipeline()
    emptyHarness.setHandler { _ in
        MangaReaderDataTestResponse(data: Data())
    }
    let emptyLoader = YamiboImageDataLoader(
        client: YamiboClient(session: emptyHarness.session),
        pipeline: emptyPipeline
    )
    await #expect(throws: YamiboError.unreadableBody) {
        _ = try await emptyLoader.imageData(for: imageRequest())
    }
}

@Test func yamiboImageDataLoaderReusesNukeDataCacheAcrossLoaderInstances() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    let pipeline = try makeIsolatedImageDataPipeline()
    let counter = LockedCounter()
    harness.setHandler { _ in
        counter.increment()
        return MangaReaderDataTestResponse(data: Data([8, 6]))
    }
    let request = imageRequest(url: "https://img.example.com/nuke-cache-\(UUID().uuidString).jpg")
    let firstLoader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
        pipeline: pipeline
    )
    let secondLoader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent"),
        pipeline: pipeline
    )

    let first = try await firstLoader.imageData(for: request)
    try await waitForCachedData(in: pipeline, request: request)
    let second = try await secondLoader.imageData(for: request)

    #expect(first == Data([8, 6]))
    #expect(second == Data([8, 6]))
    #expect(counter.value == 1)
}

@Test func yamiboNukeImageDataPipelineUsesExpectedCacheBudgetAndNoURLCacheDiskStorage() throws {
    let pipeline = try makeIsolatedImageDataPipeline()

    #expect(pipeline.dataCacheLimitBytes == YamiboNukeImageDataPipeline.defaultDataCacheLimitBytes)
    #expect(pipeline.usesURLCacheDiskStorage == false)
}

private func imageRequest(
    namespace: String = "test",
    refererURL: URL? = nil,
    url: String = "https://img.example.com/a.jpg"
) -> YamiboImageRequest {
    YamiboImageRequest(
        url: URL(string: url)!,
        refererURL: refererURL,
        cacheNamespace: YamiboImageCacheNamespace(value: namespace)
    )
}

private func makeIsolatedImageDataPipeline() throws -> YamiboNukeImageDataPipeline {
    try YamiboNukeImageDataPipeline(
        dataCacheDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("yamibo-nuke-test-\(UUID().uuidString)", isDirectory: true)
    )
}

private func waitForCachedData(
    in pipeline: YamiboNukeImageDataPipeline,
    request: YamiboImageRequest
) async throws {
    for _ in 0 ..< 20 {
        if pipeline.cachedData(for: request) != nil {
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    #expect(pipeline.cachedData(for: request) != nil)
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
