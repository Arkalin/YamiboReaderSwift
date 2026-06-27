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

        let loader = YamiboNovelInlineImageDataLoader(client: imageClient(session: harness.session))
        let data = try await loader.imageData(
            for: URL(string: "https://img.example.com/novel.jpg")!,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=900")!
        )

        #expect(data == Data([1, 2, 3]))
    }

    @Test func deduplicatesConcurrentRequestsByImageURLAndRefererURL() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = NovelInlineImageRequestCounter()
        harness.setHandler { _ in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return MangaReaderDataTestResponse(data: Data([9]))
        }

        let loader = YamiboNovelInlineImageDataLoader(client: imageClient(session: harness.session))
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

    @Test func doesNotDeduplicateDifferentRefererURLs() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = NovelInlineImageRequestCounter()
        harness.setHandler { _ in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return MangaReaderDataTestResponse(data: Data([9]))
        }

        let loader = YamiboNovelInlineImageDataLoader(client: imageClient(session: harness.session))
        let imageURL = URL(string: "https://img.example.com/shared.jpg")!
        async let first = loader.imageData(
            for: imageURL,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=1")!
        )
        async let second = loader.imageData(
            for: imageURL,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=2")!
        )

        _ = try await [first, second]

        #expect(counter.value == 2)
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
        let loader = YamiboNovelInlineImageDataLoader(client: imageClient(session: harness.session))

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(
                for: URL(string: "https://img.example.com/a.jpg")!,
                refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=900")!
            )
        }
    }

    @Test func appContextCacheNamespaceDoesNotExposeRawSessionValues() async throws {
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

        #expect(!loadingContext.cacheNamespace.value.contains("secret-cookie"))
        #expect(!loadingContext.cacheNamespace.value.contains("NovelImageAgent"))
        #expect(!loadingContext.cacheNamespace.value.isEmpty)
    }

    private func imageClient(session: URLSession) -> YamiboClient {
        YamiboClient(
            session: session,
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
        let loader = YamiboNovelInlineImageDataLoader(client: imageClient(session: harness.session))

        await #expect(throws: expected) {
            _ = try await loader.imageData(
                for: URL(string: "https://img.example.com/a.jpg")!,
                refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=900")!
            )
        }
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
