import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Image Data Loader", .serialized)
struct MangaReaderTestsImageDataLoader {
    @Test func sendsImageRequestHeaders() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "ImageAgent/1")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=1")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.yamibo.com/forum.php?tid=700")
            #expect(request.value(forHTTPHeaderField: "Accept")?.contains("image/") == true)
            return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
        }

        let loader = YamiboMangaImageDataLoader(client: imageClient(session: harness.session))
        let data = try await loader.imageData(
            for: URL(string: "https://img.example.com/a.jpg")!,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=700")!
        )

        #expect(data == Data([1, 2, 3]))
    }

    @Test func omitsRefererWhenNil() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "Referer") == nil)
            return MangaReaderDataTestResponse(data: Data([4]))
        }

        let loader = YamiboMangaImageDataLoader(client: imageClient(session: harness.session))
        _ = try await loader.imageData(for: URL(string: "https://img.example.com/a.jpg")!, refererURL: nil)
    }

    @Test func deduplicatesConcurrentRequestsByImageURL() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = ThreadSafeCounter()
        harness.setHandler { _ in
            counter.increment()
            Thread.sleep(forTimeInterval: 0.05)
            return MangaReaderDataTestResponse(data: Data([9]))
        }

        let loader = YamiboMangaImageDataLoader(client: imageClient(session: harness.session))
        let imageURL = URL(string: "https://img.example.com/shared.jpg")!
        async let first = loader.imageData(for: imageURL, refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=1")!)
        async let second = loader.imageData(for: imageURL, refererURL: URL(string: "https://bbs.yamibo.com/forum.php?tid=2")!)

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

    @Test func mapsURLErrors() async throws {
        try await expectImageURLError(.notConnectedToInternet, expected: YamiboError.offline)

        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            throw URLError(.cannotFindHost)
        }
        let loader = YamiboMangaImageDataLoader(client: imageClient(session: harness.session))

        await #expect(throws: YamiboError.self) {
            _ = try await loader.imageData(for: URL(string: "https://img.example.com/a.jpg")!, refererURL: nil)
        }
    }

    private func expectImageError(statusCode: Int, data: Data, expected: YamiboError) async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            MangaReaderDataTestResponse(statusCode: statusCode, data: data)
        }
        let loader = YamiboMangaImageDataLoader(client: imageClient(session: harness.session))

        await #expect(throws: expected) {
            _ = try await loader.imageData(for: URL(string: "https://img.example.com/a.jpg")!, refererURL: nil)
        }
    }

    private func expectImageURLError(_ code: URLError.Code, expected: YamiboError) async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            throw URLError(code)
        }
        let loader = YamiboMangaImageDataLoader(client: imageClient(session: harness.session))

        await #expect(throws: expected) {
            _ = try await loader.imageData(for: URL(string: "https://img.example.com/a.jpg")!, refererURL: nil)
        }
    }

    private func imageClient(session: URLSession) -> YamiboClient {
        YamiboClient(
            session: session,
            cookie: "auth=1",
            userAgent: "ImageAgent/1"
        )
    }
}

private final class ThreadSafeCounter: @unchecked Sendable {
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
