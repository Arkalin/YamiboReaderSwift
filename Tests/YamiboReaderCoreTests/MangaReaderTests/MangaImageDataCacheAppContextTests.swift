import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Image Data Cache App Context", .serialized)
struct MangaReaderTestsImageDataCacheAppContext {
    @Test func appContextImageDataLoaderUsesSharedDiskCacheAcrossLoaderInstances() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        let counter = MangaImageDataCacheRequestCounter()
        harness.setHandler { request in
            counter.increment()
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "ImageAgent/Context")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=context")
            return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
        }

        let defaults = try #require(UserDefaults(suiteName: "manga-image-context-\(UUID().uuidString)"))
        let sessionStore = SessionStore(defaults: defaults, key: "session")
        try await sessionStore.save(
            SessionState(
                cookie: "auth=context",
                userAgent: "ImageAgent/Context",
                isLoggedIn: true
            )
        )

        let cacheRoot = try makeTemporaryAppContextImageCacheDirectory()
        let cacheStore = FileMangaImageDataCacheStore(
            databasePool: try YamiboDatabase.openPool(rootDirectory: cacheRoot.appendingPathComponent("grdb", isDirectory: true)),
            baseDirectory: cacheRoot.appendingPathComponent("image-data", isDirectory: true)
        )
        let appContext = YamiboAppContext(
            sessionStore: sessionStore,
            mangaImageDataCacheStore: cacheStore,
            session: harness.session
        )
        let imageURL = try #require(URL(string: "https://img.example.com/context.jpg"))

        let firstLoader = await appContext.makeMangaImageDataLoader()
        let first = try await firstLoader.imageData(for: imageURL, refererURL: nil)
        let secondLoader = await appContext.makeMangaImageDataLoader()
        let second = try await secondLoader.imageData(for: imageURL, refererURL: nil)

        #expect(first == Data([1, 2, 3]))
        #expect(second == Data([1, 2, 3]))
        #expect(counter.value == 1)
    }
}

private final class MangaImageDataCacheRequestCounter: @unchecked Sendable {
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

private func makeTemporaryAppContextImageCacheDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
