import Foundation
import Testing
@testable import YamiboReaderCore

@Test func yamiboImageDataLoaderSendsCookieUserAgentAndReferer() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    harness.setHandler { request in
        #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=1")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "UnitAgent")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.yamibo.com/thread-1.html")
        #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/*") == true)
        return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent")
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
    harness.setHandler { request in
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        return MangaReaderDataTestResponse(data: Data([4]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "", userAgent: "UnitAgent")
    )

    _ = try await loader.imageData(for: imageRequest(refererURL: nil))

    #expect(harness.requests.count == 1)
}

@Test func yamiboImageDataLoaderDeduplicatesConcurrentSameRequest() async throws {
    let harness = MangaReaderDataTestHarness()
    defer { harness.reset() }
    let counter = LockedCounter()
    harness.setHandler { _ in
        counter.increment()
        Thread.sleep(forTimeInterval: 0.05)
        return MangaReaderDataTestResponse(data: Data([7]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent")
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
    let counter = LockedCounter()
    harness.setHandler { _ in
        counter.increment()
        Thread.sleep(forTimeInterval: 0.05)
        return MangaReaderDataTestResponse(data: Data([9]))
    }
    let loader = YamiboImageDataLoader(
        client: YamiboClient(session: harness.session, cookie: "auth=1", userAgent: "UnitAgent")
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
    authHarness.setHandler { _ in
        MangaReaderDataTestResponse(statusCode: 403, data: Data([1]))
    }
    let authLoader = YamiboImageDataLoader(client: YamiboClient(session: authHarness.session))
    await #expect(throws: YamiboError.notAuthenticated) {
        _ = try await authLoader.imageData(for: imageRequest())
    }

    let emptyHarness = MangaReaderDataTestHarness()
    defer { emptyHarness.reset() }
    emptyHarness.setHandler { _ in
        MangaReaderDataTestResponse(data: Data())
    }
    let emptyLoader = YamiboImageDataLoader(client: YamiboClient(session: emptyHarness.session))
    await #expect(throws: YamiboError.unreadableBody) {
        _ = try await emptyLoader.imageData(for: imageRequest())
    }
}

private func imageRequest(
    namespace: String = "test",
    refererURL: URL? = nil
) -> YamiboImageRequest {
    YamiboImageRequest(
        url: URL(string: "https://img.example.com/a.jpg")!,
        refererURL: refererURL,
        cacheNamespace: YamiboImageCacheNamespace(value: namespace)
    )
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
