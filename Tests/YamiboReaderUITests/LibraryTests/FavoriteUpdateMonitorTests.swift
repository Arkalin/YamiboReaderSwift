import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@MainActor
final class FavoriteUpdateMonitorTests: XCTestCase {
    func testUpdateCheckBuildsBaselineDetectsEventsAndHonorsFidFilter() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-updates")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let favoriteUpdateStore = FavoriteUpdateStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "favorite-updates"
        )
        let target = FavoriteItemTarget(kind: .normalThread, threadID: "960")
        var document = FavoriteLibraryDocument()
        let category = document.createCategory(name: "更新检测")
        document.upsertItem(try FavoriteItem(
            target: target,
            title: "更新主题",
            sourceGroup: .forumBoard(id: "50", label: "测试板块"),
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)

        var pagesByThreadID = [
            "960": [
                try makeThreadPage(threadID: "960", postID: "p1", title: "更新主题", replyCount: 1, pageCount: 1),
                try makeThreadPage(threadID: "960", postID: "p2", title: "更新主题", replyCount: 3, pageCount: 2),
                try makeThreadPage(threadID: "960", postID: "p3", title: "更新主题", replyCount: 4, pageCount: 2)
            ]
        ]
        var fetchedThreadIDs: [String] = []
        let monitor = try makeUpdateMonitor(
            updateStore: favoriteUpdateStore,
            libraryStore: localFavoriteLibraryStore,
            pageFetcher: { item in
                let threadID = try XCTUnwrap(item.target.threadID)
                fetchedThreadIDs.append(threadID)
                var pages = pagesByThreadID[threadID] ?? []
                let page = try XCTUnwrap(pages.first)
                if pages.count > 1 {
                    pages.removeFirst()
                    pagesByThreadID[threadID] = pages
                }
                return page
            }
        )
        await monitor.load()

        _ = await monitor.startCheck()
        try await waitForStatus(.completed, in: monitor)
        XCTAssertEqual(monitor.events.count, 0)
        XCTAssertEqual(monitor.fidFilters.map(\.fid), ["50"])
        XCTAssertEqual(monitor.categoryFilters.map(\.categoryID), [category.id])

        _ = await monitor.startCheck()
        try await waitForStatus(.completed, in: monitor)
        XCTAssertEqual(monitor.events.count, 1)
        XCTAssertEqual(monitor.events.first?.title, "更新主题")
        XCTAssertEqual(monitor.events.first?.fid, "50")
        XCTAssertEqual(monitor.events.first?.summary, .newReplies(count: 2))

        await monitor.setFidFilter("50", enabled: false)
        let fetchCountBeforeDisabledRun = fetchedThreadIDs.count
        _ = await monitor.startCheck()
        try await waitForStatus(.completed, in: monitor)
        XCTAssertEqual(fetchedThreadIDs.count, fetchCountBeforeDisabledRun)
        XCTAssertEqual(monitor.snapshot?.totalCount, 0)
    }

    func testUpdateCheckReportsFetchFailureAsFailedNotSkipped() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-updates-failure")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let favoriteUpdateStore = FavoriteUpdateStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "favorite-updates"
        )
        let target = FavoriteItemTarget(kind: .normalThread, threadID: "961")
        var document = FavoriteLibraryDocument()
        let category = document.createCategory(name: "更新检测失败")
        document.upsertItem(try FavoriteItem(
            target: target,
            title: "失败主题",
            sourceGroup: .forumBoard(id: "51", label: "测试板块"),
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)

        let monitor = try makeUpdateMonitor(
            updateStore: favoriteUpdateStore,
            libraryStore: localFavoriteLibraryStore,
            pageFetcher: { _ in throw YamiboError.offline }
        )
        await monitor.load()

        _ = await monitor.startCheck()
        try await waitForStatus(.completed, in: monitor)

        XCTAssertEqual(monitor.snapshot?.failedCount, 1)
        XCTAssertEqual(monitor.snapshot?.skippedCount, 0)
    }

    /// Regression guard for the `.mangaTitle` dead-case cleanup. Two facts
    /// pinned here: the mode label now mirrors `FavoriteItemTargetKind`
    /// faithfully (`init(kind:)` is total — no more ternary stamping
    /// `.normalThread` on everything non-novel), and manga-thread favorites
    /// remain EXCLUDED from update checking by `candidates(in:)`, which is
    /// why `.mangaThread` is documented as unreached at runtime.
    func testUpdateCheckExcludesMangaThreadFavoritesAndModeMappingStaysFaithful() async throws {
        XCTAssertEqual(FavoriteUpdateTargetMode(kind: .normalThread), .normalThread)
        XCTAssertEqual(FavoriteUpdateTargetMode(kind: .novelThread), .novelThread)
        XCTAssertEqual(FavoriteUpdateTargetMode(kind: .mangaThread), .mangaThread)

        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-updates-manga-mode")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let favoriteUpdateStore = FavoriteUpdateStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "favorite-updates"
        )
        let target = FavoriteItemTarget(kind: .mangaThread, threadID: "962")
        var document = FavoriteLibraryDocument()
        let category = document.createCategory(name: "漫画更新检测")
        document.upsertItem(try FavoriteItem(
            target: target,
            title: "漫画主题",
            sourceGroup: .forumBoard(id: "30", label: "漫画板块"),
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)

        let page = try makeThreadPage(threadID: "962", postID: "p1", title: "漫画主题", replyCount: 1, pageCount: 1)
        let monitor = try makeUpdateMonitor(
            updateStore: favoriteUpdateStore,
            libraryStore: localFavoriteLibraryStore,
            pageFetcher: { _ in page }
        )
        await monitor.load()

        _ = await monitor.startCheck()
        try await waitForStatus(.completed, in: monitor)

        let state = await favoriteUpdateStore.loadState()
        XCTAssertTrue(state.trackedTargets.isEmpty)
        XCTAssertEqual(monitor.snapshot?.totalCount, 0)
    }

    private func waitForStatus(
        _ status: FavoriteUpdateRunStatus,
        in monitor: FavoriteUpdateMonitor
    ) async throws {
        for _ in 0..<100 {
            if monitor.snapshot?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for favorite update status \(status)")
    }

    private func makeThreadPage(
        threadID: String,
        postID: String,
        title: String,
        replyCount: Int,
        pageCount: Int
    ) throws -> ForumThreadPage {
        ForumThreadPage(
            thread: ThreadIdentity(tid: threadID, fid: "50"),
            title: title,
            posts: [
                ForumThreadPost(
                    postID: postID,
                    author: BlogReaderUser(uid: "u1", name: "作者"),
                    contentHTML: "<p>正文</p>",
                    contentText: "正文"
                )
            ],
            pageNavigation: ForumPageNavigation(currentPage: 1, totalPages: pageCount),
            totalReplies: replyCount,
            forumID: "50",
            forumName: "测试板块"
        )
    }
}

/// Builds a `FavoriteUpdateMonitor` backed by isolated per-test stores.
@MainActor
private func makeUpdateMonitor(
    updateStore: FavoriteUpdateStore,
    libraryStore: FavoriteLibraryStore,
    pageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)? = nil
) throws -> FavoriteUpdateMonitor {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "favorite-update-monitor-deps")
    let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
    let sessionStore = SessionStore(defaults: defaults, key: "session")
    let urlSession = YamiboNetworkConfiguration.makeSession()
    let forumCacheStore = ForumCacheStore(
        baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    return FavoriteUpdateMonitor(
        updateStore: updateStore,
        libraryStore: libraryStore,
        makeForumThreadReaderRepository: {
            let sessionState = await sessionStore.load()
            let client = YamiboClient(
                session: urlSession,
                cookie: sessionState.cookie,
                userAgent: sessionState.userAgent
            )
            return ForumThreadReaderRepository(client: client, cacheStore: forumCacheStore)
        },
        pageFetcher: pageFetcher
    )
}
