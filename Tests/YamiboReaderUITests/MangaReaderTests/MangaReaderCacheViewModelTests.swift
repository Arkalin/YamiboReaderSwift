import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MangaReaderCacheViewModelTests: XCTestCase {
    func testProjectsDirectoryChaptersInPanelOrderWithCachedUncachedAndCachingStates() async throws {
        let fixture = try await makeCacheFixture(chapters: [
            cacheChapter(tid: "100", number: 1),
            cacheChapter(tid: "200", number: 2),
            cacheChapter(tid: "300", number: 3)
        ])
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))

        try await fixture.store.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.store.saveMembership(cacheMembership(favorite: fixture.favorite, tid: "100", imageURLs: [cachedImage]))
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "300"))

        await fixture.model.load()

        XCTAssertEqual(fixture.model.rows.map(\.chapter.tid), ["100", "200", "300"])
        XCTAssertEqual(fixture.model.rows.map(\.state), [.cached, .uncached, .caching])
    }

    func testLoadProjectsExistingOfflineCacheQueueEntryCount() async throws {
        let fixture = try await makeCacheFixture(chapters: [
            cacheChapter(tid: "100", number: 1),
            cacheChapter(tid: "200", number: 2)
        ])
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "100"))
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "200"))

        await fixture.model.load()

        XCTAssertEqual(fixture.model.offlineCacheQueueEntryCount, 2)
    }

    func testOfflineCacheQueueUpdatesRefreshEntryCountAndRows() async throws {
        let fixture = try await makeCacheFixture(chapters: [cacheChapter(tid: "100", number: 1)])

        await fixture.model.load()
        XCTAssertEqual(fixture.model.offlineCacheQueueEntryCount, 0)
        XCTAssertEqual(fixture.model.rows.map(\.state), [.uncached])

        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "100"))

        try await waitForMangaReaderCacheCondition {
            fixture.model.offlineCacheQueueEntryCount == 1
                && fixture.model.rows.map(\.state) == [.caching]
        }

        try await fixture.store.cancelOfflineCacheWork(ownerName: fixture.favorite.title, tid: "100")

        try await waitForMangaReaderCacheCondition {
            fixture.model.offlineCacheQueueEntryCount == 0
                && fixture.model.rows.map(\.state) == [.uncached]
        }
    }

    func testFailedQueueWorkProjectsAsCaching() async throws {
        let fixture = try await makeCacheFixture(chapters: [cacheChapter(tid: "100", number: 1)])
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "100"))
        try await fixture.store.markOfflineCacheWorkFailed(ownerName: fixture.favorite.title, tid: "100", message: "Timeout")

        await fixture.model.load()

        XCTAssertEqual(fixture.model.rows.map(\.state), [.caching])
    }

    func testCacheCommandEnqueuesOnlyUncachedChaptersAndDoesNotRetryFailedWork() async throws {
        let fixture = try await makeCacheFixture(chapters: [
            cacheChapter(tid: "100", number: 1),
            cacheChapter(tid: "200", number: 2),
            cacheChapter(tid: "300", number: 3)
        ])
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        try await fixture.store.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.store.saveMembership(cacheMembership(favorite: fixture.favorite, tid: "100", imageURLs: [cachedImage]))
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "300"))
        try await fixture.store.markOfflineCacheWorkFailed(ownerName: fixture.favorite.title, tid: "300", message: "Timeout")

        await fixture.model.load()
        await fixture.model.cacheSelected(tids: ["100", "200", "300"])

        let works = await fixture.store.allOfflineCacheWorks()
        XCTAssertEqual(Set(works.map(\.tid)), ["200", "300"])
        XCTAssertEqual(works.first(where: { $0.tid == "300" })?.state, .failed)
        XCTAssertEqual(fixture.model.rows.map(\.state), [.cached, .caching, .caching])
    }

    func testDeleteCommandRemovesCachedMembershipAndCancelsUnfinishedOrFailedWork() async throws {
        let fixture = try await makeCacheFixture(chapters: [
            cacheChapter(tid: "100", number: 1),
            cacheChapter(tid: "200", number: 2),
            cacheChapter(tid: "300", number: 3)
        ])
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        try await fixture.store.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.store.saveMembership(cacheMembership(favorite: fixture.favorite, tid: "100", imageURLs: [cachedImage]))
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "200"))
        _ = try await fixture.store.enqueueOfflineCacheWork(cacheWorkRequest(favorite: fixture.favorite, tid: "300"))
        try await fixture.store.markOfflineCacheWorkFailed(ownerName: fixture.favorite.title, tid: "300", message: "Timeout")

        await fixture.model.load()
        await fixture.model.deleteSelected(tids: ["100", "200", "300"])

        let deletedMembership = await fixture.store.membership(ownerName: fixture.favorite.title, tid: "100")
        let deletedImageData = await fixture.store.offlineImageData(for: cachedImage)
        let remainingWorks = await fixture.store.allOfflineCacheWorks()
        XCTAssertNil(deletedMembership)
        XCTAssertNil(deletedImageData)
        XCTAssertTrue(remainingWorks.isEmpty)
        XCTAssertEqual(fixture.model.rows.map(\.state), [.uncached, .uncached, .uncached])
    }

    func testNonFavoriteCacheCommandPromptsInsteadOfQueueingWork() async throws {
        let fixture = try await makeCacheFixture(chapters: [cacheChapter(tid: "100", number: 1)], saveFavorite: false)

        await fixture.model.load()
        await fixture.model.cacheSelected(tids: ["100"])

        XCTAssertEqual(fixture.model.prompt, .addFavorite(title: "测试漫画"))
        let works = await fixture.store.allOfflineCacheWorks()
        XCTAssertTrue(works.isEmpty)
    }

    func testNonFavoriteDeleteCommandCanRemoveExistingOfflineCache() async throws {
        let fixture = try await makeCacheFixture(chapters: [cacheChapter(tid: "100", number: 1)], saveFavorite: false)
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/nonfavorite-100-1.jpg"))
        try await fixture.store.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.store.saveMembership(cacheMembership(favorite: fixture.favorite, tid: "100", imageURLs: [cachedImage]))

        await fixture.model.load()
        XCTAssertEqual(fixture.model.rows.map(\.state), [.cached])

        await fixture.model.deleteSelected(tids: ["100"])

        let deletedMembership = await fixture.store.membership(ownerName: fixture.favorite.title, tid: "100")
        let deletedImageData = await fixture.store.offlineImageData(for: cachedImage)
        XCTAssertNil(deletedMembership)
        XCTAssertNil(deletedImageData)
        XCTAssertEqual(fixture.model.rows.map(\.state), [.uncached])
    }
}

private struct MangaReaderCacheFixture {
    let model: MangaReaderCacheViewModel
    let favorite: Favorite
    let store: FileMangaOfflineCacheStore
}

@MainActor
private func makeCacheFixture(
    chapters: [MangaChapter],
    saveFavorite: Bool = true
) async throws -> MangaReaderCacheFixture {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "manga-reader-cache")
    let favoriteStore = try FavoriteStore(testSuiteName: suiteName, key: "favorites")
    let offlineStore = FileMangaOfflineCacheStore(
        baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    let threadURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/thread-900-1-1.html"))
    let favorite = Favorite(
        id: "favorite-900",
        title: "测试漫画",
        url: threadURL,
        type: .manga
    )
    if saveFavorite {
        try await favoriteStore.saveFavorites([favorite])
    }

    let panel = MangaDirectoryPanelPresentation(
        directoryTitle: "测试漫画",
        displayChapters: chapters,
        sortOrder: .ascending
    )
    let context = MangaLaunchContext(
        originalThreadURL: threadURL,
        chapterURL: chapters[0].url,
        displayTitle: "测试漫画",
        source: .forum,
        directoryName: "测试漫画"
    )
    return MangaReaderCacheFixture(
        model: MangaReaderCacheViewModel(
            context: context,
            panel: panel,
            favoriteStore: favoriteStore,
            offlineCacheStore: offlineStore
        ),
        favorite: favorite,
        store: offlineStore
    )
}

private func cacheChapter(tid: String, number: Double) throws -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: "第\(Int(number))话",
        chapterNumber: number,
        url: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1"))
    )
}

private func cacheMembership(
    favorite: Favorite,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: favorite.title,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1")),
        imageURLs: imageURLs
    )
}

private func cacheWorkRequest(favorite: Favorite, tid: String) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: favorite.title,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1"))
    )
}

private func waitForMangaReaderCacheCondition(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let start = ContinuousClock.now
    while await MainActor.run(body: condition) == false {
        if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
            throw YamiboError.underlying("Timed out waiting for condition")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
