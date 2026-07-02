import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Image Data Cache App Context", .serialized)
struct MangaReaderTestsImageDataCacheAppContext {
    @Test func genericImagePipelineContextUsesSharedTransparentImageDataCache() async throws {
        let fixture = try await makeAppContextImageCacheFixture()
        defer { fixture.harness.reset() }
        let counter = fixture.counter
        fixture.harness.setHandler { request in
            counter.increment()
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "ImageAgent/Context")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=context")
            return MangaReaderDataTestResponse(data: Data([1, 2, 3]))
        }
        let imageURL = try #require(URL(string: "https://img.example.com/generic-context.jpg"))

        let firstContext = await fixture.appContext.makeImagePipelineContext()
        let first = try await firstContext.dataLoader.imageData(
            for: YamiboImageRequest(url: imageURL, cacheNamespace: firstContext.cacheNamespace)
        )
        let secondContext = await fixture.appContext.makeImagePipelineContext()
        let second = try await secondContext.dataLoader.imageData(
            for: YamiboImageRequest(url: imageURL, cacheNamespace: secondContext.cacheNamespace)
        )

        #expect(first == Data([1, 2, 3]))
        #expect(second == Data([1, 2, 3]))
        #expect(fixture.counter.value == 1)
        #expect(await fixture.imageDataCacheStore.totalDiskUsageBytes() == 3)
    }

    @Test func novelInlineImageContextUsesSharedTransparentImageDataCache() async throws {
        let fixture = try await makeAppContextImageCacheFixture()
        defer { fixture.harness.reset() }
        let counter = fixture.counter
        fixture.harness.setHandler { request in
            counter.increment()
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://bbs.yamibo.com/forum.php?tid=900")
            return MangaReaderDataTestResponse(data: Data([4, 5]))
        }
        let imageURL = try #require(URL(string: "https://img.example.com/novel-context.jpg"))
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=900"))

        let firstContext = await fixture.appContext.makeNovelInlineImageLoadingContext()
        let first = try await firstContext.loader.imageData(for: imageURL, refererURL: refererURL)
        let secondContext = await fixture.appContext.makeNovelInlineImageLoadingContext()
        let second = try await secondContext.loader.imageData(for: imageURL, refererURL: refererURL)

        #expect(first == Data([4, 5]))
        #expect(second == Data([4, 5]))
        #expect(fixture.counter.value == 1)
    }

    @Test func mangaImageDataLoaderReadsOfflineBytesBeforeTransparentCacheAndNetwork() async throws {
        let fixture = try await makeAppContextImageCacheFixture()
        defer { fixture.harness.reset() }
        let counter = fixture.counter
        fixture.harness.setHandler { _ in
            counter.increment()
            return MangaReaderDataTestResponse(data: Data([9]))
        }
        let imageURL = try #require(URL(string: "https://img.example.com/offline-first.jpg"))
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100"))
        let transparentRequest = YamiboImageRequest(
            url: imageURL,
            cacheNamespace: YamiboImageCacheNamespace.ordinarySessionNamespace(
                cookie: "auth=context",
                userAgent: "ImageAgent/Context"
            )
        )
        try await fixture.imageDataCacheStore.save(Data([1]), for: transparentRequest, retentionPolicy: .evictable)
        try await fixture.appContext.mangaOfflineCacheStore.saveOfflineImageData(Data([7]), for: imageURL)
        try await fixture.appContext.mangaOfflineCacheStore.saveMembership(
            MangaOfflineCacheMembership(
                ownerName: "favorite-a",
                tid: "100",
                chapterTitle: "第100话",
                chapterURL: chapterURL,
                imageURLs: [imageURL]
            )
        )

        let loader = await fixture.appContext.makeMangaImageDataLoader()
        let data = try await loader.imageData(
            for: imageURL,
            refererURL: chapterURL,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([7]))
        #expect(fixture.counter.value == 0)
    }

    @Test func mangaImageDataLoaderFallsBackToGenericCacheAndNetworkAcrossLoaderInstances() async throws {
        let fixture = try await makeAppContextImageCacheFixture()
        defer { fixture.harness.reset() }
        let counter = fixture.counter
        fixture.harness.setHandler { request in
            counter.increment()
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "ImageAgent/Context")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=context")
            return MangaReaderDataTestResponse(data: Data([6]))
        }
        let imageURL = try #require(URL(string: "https://img.example.com/manga-context.jpg"))

        let firstLoader = await fixture.appContext.makeMangaImageDataLoader()
        let first = try await firstLoader.imageData(for: imageURL, refererURL: nil)
        let secondLoader = await fixture.appContext.makeMangaImageDataLoader()
        let second = try await secondLoader.imageData(for: imageURL, refererURL: nil)

        #expect(first == Data([6]))
        #expect(second == Data([6]))
        #expect(fixture.counter.value == 1)
    }

    @Test func profileAvatarLoaderWritesProtectedAvatarNamespaceEntries() async throws {
        let fixture = try await makeAppContextImageCacheFixture()
        defer { fixture.harness.reset() }
        let counter = fixture.counter
        fixture.harness.setHandler { request in
            counter.increment()
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "ImageAgent/Context")
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=context")
            return MangaReaderDataTestResponse(data: Data([8, 8, 8]))
        }
        let profile = YamiboProfile(
            uid: "535977",
            username: "reader",
            userGroup: "百合幼苗",
            points: 10,
            partner: 0,
            totalPoints: 10,
            avatarURL: URL(string: "https://bbs.yamibo.com/avatar-context.jpg")!
        )

        let firstLoader = fixture.appContext.makeProfileAvatarLoader()
        let first = try await firstLoader.avatarData(for: profile)
        let secondLoader = fixture.appContext.makeProfileAvatarLoader()
        let second = try await secondLoader.avatarData(for: profile)

        #expect(first == Data([8, 8, 8]))
        #expect(second == Data([8, 8, 8]))
        #expect(fixture.counter.value == 1)
        #expect(await fixture.imageDataCacheStore.totalDiskUsageBytes() == 3)
        #expect(await fixture.imageDataCacheStore.evictableDiskUsageBytes() == 0)
    }

    @Test func resetApplicationDataClearsTransparentImageDataCache() async throws {
        let fixture = try await makeAppContextImageCacheFixture()
        defer { fixture.harness.reset() }
        let ordinary = YamiboImageRequest(
            url: try #require(URL(string: "https://img.example.com/reset-ordinary.jpg")),
            cacheNamespace: YamiboImageCacheNamespace.ordinarySessionNamespace(
                cookie: "auth=context",
                userAgent: "ImageAgent/Context"
            )
        )
        let avatar = YamiboImageRequest(
            url: try #require(URL(string: "https://img.example.com/reset-avatar.jpg")),
            cacheNamespace: YamiboImageCacheNamespace.avatarSessionNamespace(
                cookie: "auth=context",
                userAgent: "ImageAgent/Context"
            )
        )
        try await fixture.imageDataCacheStore.save(Data([1, 2]), for: ordinary, retentionPolicy: .evictable)
        try await fixture.imageDataCacheStore.save(Data([3, 4]), for: avatar, retentionPolicy: .protected)

        try await fixture.appContext.resetApplicationData()

        #expect(await fixture.imageDataCacheStore.totalDiskUsageBytes() == 0)
        #expect(await fixture.imageDataCacheStore.evictableDiskUsageBytes() == 0)
    }
}

private struct AppContextImageCacheFixture {
    var harness: MangaReaderDataTestHarness
    var counter: ImageDataCacheRequestCounter
    var appContext: YamiboAppContext
    var imageDataCacheStore: FileImageDataCacheStore
}

private func makeAppContextImageCacheFixture() async throws -> AppContextImageCacheFixture {
    let harness = MangaReaderDataTestHarness()
    let counter = ImageDataCacheRequestCounter()
    let suiteName = "image-context-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let sessionStore = SessionStore(defaults: defaults, key: "session")
    try await sessionStore.save(
        SessionState(
            cookie: "auth=context",
            userAgent: "ImageAgent/Context",
            isLoggedIn: true,
            accountUID: "535977"
        )
    )

    let cacheRoot = try makeTemporaryAppContextImageCacheDirectory()
    let database = try YamiboDatabase.openPool(rootDirectory: cacheRoot.appendingPathComponent("grdb", isDirectory: true))
    let imageDataCacheStore = FileImageDataCacheStore(
        databasePool: database,
        baseDirectory: cacheRoot.appendingPathComponent("image-data", isDirectory: true)
    )
    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        imageDataCacheStore: imageDataCacheStore,
        mangaOfflineCacheStore: MangaOfflineCacheStore(
            databasePool: database,
            baseDirectory: cacheRoot.appendingPathComponent("offline-cache", isDirectory: true)
        ),
        clearsWebDataOnReset: false,
        session: harness.session
    )
    return AppContextImageCacheFixture(
        harness: harness,
        counter: counter,
        appContext: appContext,
        imageDataCacheStore: imageDataCacheStore
    )
}

private final class ImageDataCacheRequestCounter: @unchecked Sendable {
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
