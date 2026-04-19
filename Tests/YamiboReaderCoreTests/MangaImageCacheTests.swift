import Foundation
import XCTest
@testable import YamiboReaderCore

final class MangaImageCacheTests: XCTestCase {
    func testMangaImageCacheStorePersistsToDiskAndServesMemoryHits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageURL = URL(string: "https://img.example.com/a.jpg")!
        let expected = Data([0x01, 0x02, 0x03, 0x04])

        let writingStore = MangaImageCacheStore(
            baseDirectory: directory,
            memoryLimitBytes: 1024,
            diskLimitBytes: 1024 * 1024
        )
        try await writingStore.save(expected, for: imageURL)

        let readingStore = MangaImageCacheStore(
            baseDirectory: directory,
            memoryLimitBytes: 1024,
            diskLimitBytes: 1024 * 1024
        )
        let firstRead = await readingStore.loadData(for: imageURL)
        XCTAssertEqual(firstRead, expected)

        let cachedFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "index.json" }
        for fileURL in cachedFiles {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let secondRead = await readingStore.loadData(for: imageURL)
        XCTAssertEqual(secondRead, expected)
    }

    func testMangaImageCacheStoreEvictsLeastRecentlyUsedImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = MangaImageCacheStore(
            baseDirectory: directory,
            memoryLimitBytes: 1024,
            diskLimitBytes: 6
        )

        try await store.save(Data([0x01, 0x02, 0x03, 0x04]), for: URL(string: "https://img.example.com/old.jpg")!)
        try await store.save(Data([0x05, 0x06, 0x07, 0x08]), for: URL(string: "https://img.example.com/new.jpg")!)

        let evicted = await store.loadData(for: URL(string: "https://img.example.com/old.jpg")!)
        let retained = await store.loadData(for: URL(string: "https://img.example.com/new.jpg")!)
        XCTAssertNil(evicted)
        XCTAssertEqual(retained, Data([0x05, 0x06, 0x07, 0x08]))
    }

    func testMangaImageCacheStoreClearsCorruptedIndex() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("index.json"), options: [.atomic])
        try Data([0x01]).write(to: directory.appendingPathComponent("orphan.bin"), options: [.atomic])

        let store = MangaImageCacheStore(
            baseDirectory: directory,
            memoryLimitBytes: 1024,
            diskLimitBytes: 1024 * 1024
        )
        let result = await store.loadData(for: URL(string: "https://img.example.com/missing.jpg")!)
        XCTAssertNil(result)

        let remainingFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertFalse(remainingFiles.contains { $0.lastPathComponent == "orphan.bin" })
    }

    func testMangaImageRepositoryDeduplicatesConcurrentRequestsAndCachesResponses() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaImageRepositoryTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = SessionStore(key: "\(UUID().uuidString).session")
        try await sessionStore.save(
            SessionState(cookie: "foo=bar", userAgent: "Test-Agent", isLoggedIn: true)
        )

        let requestCount = RequestCounter()
        MangaImageRepositoryTestURLProtocol.handler = { request in
            Task {
                await requestCount.increment()
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "foo=bar")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Test-Agent")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700")
            return (
                Data([0x0A, 0x0B, 0x0C]),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!
            )
        }

        let repository = MangaImageRepository(
            session: session,
            sessionStore: sessionStore,
            cacheStore: MangaImageCacheStore(baseDirectory: directory)
        )
        let request = MangaImageRequest(
            imageURL: URL(string: "https://img.example.com/cached.jpg")!,
            refererURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700")!
        )

        async let first = repository.imageData(for: request)
        async let second = repository.imageData(for: request)
        let results = try await [first, second]
        XCTAssertEqual(results[0], Data([0x0A, 0x0B, 0x0C]))
        XCTAssertEqual(results[1], Data([0x0A, 0x0B, 0x0C]))
        try await Task.sleep(nanoseconds: 100_000_000)
        let firstRequestCount = await requestCount.value()
        XCTAssertEqual(firstRequestCount, 1)

        let cached = try await repository.imageData(for: request)
        XCTAssertEqual(cached, Data([0x0A, 0x0B, 0x0C]))
        try await Task.sleep(nanoseconds: 100_000_000)
        let secondRequestCount = await requestCount.value()
        XCTAssertEqual(secondRequestCount, 1)
    }

    func testMangaImageRepositoryPrefetchIgnoresSingleFailures() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaImageRepositoryTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let sessionStore = SessionStore(key: "\(UUID().uuidString).session")

        MangaImageRepositoryTestURLProtocol.handler = { request in
            let statusCode = request.url?.lastPathComponent == "bad.jpg" ? 500 : 200
            let body = request.url?.lastPathComponent == "bad.jpg" ? Data() : Data([0x11, 0x22])
            return (
                body,
                HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!
            )
        }

        let cacheStore = MangaImageCacheStore(baseDirectory: directory)
        let repository = MangaImageRepository(
            session: session,
            sessionStore: sessionStore,
            cacheStore: cacheStore
        )

        await repository.prefetch([
            MangaImageRequest(
                imageURL: URL(string: "https://img.example.com/good.jpg")!,
                refererURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700")!
            ),
            MangaImageRequest(
                imageURL: URL(string: "https://img.example.com/bad.jpg")!,
                refererURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700")!
            ),
        ])

        let goodData = await cacheStore.loadData(for: URL(string: "https://img.example.com/good.jpg")!)
        let badData = await cacheStore.loadData(for: URL(string: "https://img.example.com/bad.jpg")!)
        XCTAssertEqual(goodData, Data([0x11, 0x22]))
        XCTAssertNil(badData)
    }
}

private final class MangaImageRepositoryTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor RequestCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
