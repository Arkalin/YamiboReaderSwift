import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MangaPresentationRouteTests: XCTestCase {
    func testBootstrapRestoresNovelResumeRoute() async throws {
        let (appModel, store) = try await makeAppModelWithReaderResumeRouteStore()
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=720&mobile=2"))
        let context = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .resume,
            initialView: 3
        )
        try await store.save(.novel(context))

        await appModel.bootstrap()

        XCTAssertEqual(appModel.activeReaderContext, context)
        XCTAssertNil(appModel.activeMangaRoute)
    }

    func testBootstrapRestoresMangaResumeRoute() async throws {
        let (appModel, store) = try await makeAppModelWithReaderResumeRouteStore()
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=721&mobile=2"))
        let chapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=722&mobile=2"))
        let route = MangaPresentationRoute.native(
            MangaLaunchContext(
                originalThreadURL: originalURL,
                chapterURL: chapterURL,
                displayTitle: "测试漫画",
                source: .resume,
                initialPage: 6
            )
        )
        try await store.save(.manga(route))

        await appModel.bootstrap()

        XCTAssertNil(appModel.activeReaderContext)
        XCTAssertEqual(appModel.activeMangaRoute, route)
    }

    func testPresentingReadersPersistsResumeRouteAndDismissClearsIt() async throws {
        let (appModel, store) = try await makeAppModelWithReaderResumeRouteStore()
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=723&mobile=2"))
        let readerContext = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .favorites,
            initialView: 2
        )

        appModel.presentReader(readerContext)
        try await waitForReaderResumeRoute(store, equals: .novel(readerContext))

        appModel.dismissReader()
        try await waitForReaderResumeRoute(store, equals: nil)

        let mangaContext = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: originalURL,
            displayTitle: "测试漫画",
            source: .favorites,
            initialPage: 2
        )
        appModel.presentManga(mangaContext)
        try await waitForReaderResumeRoute(store, equals: .manga(.native(mangaContext)))

        appModel.dismissManga()
        try await waitForReaderResumeRoute(store, equals: nil)
    }

    func testPresentingMangaWebPersistsResumeRouteAndOpenForumClearsIt() async throws {
        let (appModel, store) = try await makeAppModelWithReaderResumeRouteStore()
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=724&mobile=2"))
        let context = MangaWebContext(
            currentURL: originalURL,
            originalThreadURL: originalURL,
            source: .favorites,
            initialPage: 1,
            autoOpenNative: false
        )

        appModel.presentMangaWeb(context)
        try await waitForReaderResumeRoute(store, equals: .manga(.web(context)))

        appModel.dismissManga(openThreadInForum: originalURL)
        try await waitForReaderResumeRoute(store, equals: nil)
        XCTAssertNotNil(appModel.suspendedMangaRoute)
        XCTAssertEqual(appModel.selectedTab, .forum)
    }

    func testReaderResumeRouteUpdateAfterDismissDoesNotRecreateRestoreState() async throws {
        let (appModel, store) = try await makeAppModelWithReaderResumeRouteStore()
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=725&mobile=2"))
        let context = MangaWebContext(
            currentURL: originalURL,
            originalThreadURL: originalURL,
            source: .forum
        )

        appModel.presentMangaWeb(context)
        try await waitForReaderResumeRoute(store, equals: .manga(.web(context)))

        appModel.dismissManga()
        try await waitForReaderResumeRoute(store, equals: nil)

        appModel.updateReaderResumeRoute(.manga(.web(context.updating(initialPage: 3))))

        let loadedRoute = await store.load()
        XCTAssertNil(loadedRoute)
        XCTAssertNil(appModel.activeMangaRoute)
    }

    func testMangaFavoriteLaunchDoesNotNeedProbeBlocker() {
        let manga = Favorite(
            title: "测试漫画",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!,
            type: .manga
        )
        let novel = Favorite(
            title: "测试小说",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=705&mobile=2")!,
            type: .novel
        )
        let unknown = Favorite(
            title: "未知收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=706&mobile=2")!
        )

        XCTAssertFalse(favoriteLaunchNeedsMangaProbeBlocker(manga))
        XCTAssertFalse(favoriteLaunchNeedsMangaProbeBlocker(novel))
        XCTAssertFalse(favoriteLaunchNeedsMangaProbeBlocker(unknown))
    }

    func testOpeningMangaFavoriteIDBlocksFavoriteInteractions() {
        XCTAssertFalse(shouldBlockFavoriteInteractions(openingMangaFavoriteID: nil))
        XCTAssertTrue(shouldBlockFavoriteInteractions(openingMangaFavoriteID: "favorite-1"))
    }

    func testPresentMangaFromWebStoresSuspendedContextAndDismissRestoresWeb() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext())
        let webContext = MangaWebContext(
            currentURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
            originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
            source: .forum,
            autoOpenNative: false
        )
        let nativeContext = MangaLaunchContext(
            originalThreadURL: webContext.originalThreadURL,
            chapterURL: webContext.currentURL,
            displayTitle: "测试漫画",
            source: .forum,
            initialPage: 3
        )

        appModel.presentMangaFromWeb(nativeContext, preserving: webContext)

        guard case let .native(activeNative)? = appModel.activeMangaRoute else {
            return XCTFail("Expected native route")
        }
        XCTAssertEqual(activeNative.initialPage, 3)
        XCTAssertEqual(appModel.suspendedMangaWebContext?.currentURL, webContext.currentURL)

        appModel.dismissMangaRestoringWebIfNeeded()

        guard case let .web(restoredWeb)? = appModel.activeMangaRoute else {
            return XCTFail("Expected restored web route")
        }
        XCTAssertNil(appModel.suspendedMangaWebContext)
        XCTAssertTrue(restoredWeb.waitingForNativeReturn)
        XCTAssertFalse(restoredWeb.autoOpenNative)
    }

    func testPresentMangaAfterAutomaticFallbackDoesNotRestoreWebOnDismiss() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext())
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!
        let webContext = MangaWebContext(
            currentURL: originalURL,
            originalThreadURL: originalURL,
            source: .favorites,
            autoOpenNative: true
        )
        let nativeContext = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: originalURL,
            displayTitle: "测试漫画",
            source: .favorites
        )

        appModel.presentMangaWeb(webContext)
        appModel.presentManga(nativeContext)

        guard case .native? = appModel.activeMangaRoute else {
            return XCTFail("Expected native route")
        }
        XCTAssertNil(appModel.suspendedMangaWebContext)

        appModel.dismissMangaRestoringWebIfNeeded()

        XCTAssertNil(appModel.activeMangaRoute)
        XCTAssertNil(appModel.suspendedMangaWebContext)
    }

    func testDismissMangaToOriginalPostClearsSuspendedContext() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext())
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=701&mobile=2")!
        let webContext = MangaWebContext(
            currentURL: originalURL,
            originalThreadURL: originalURL,
            source: .favorites
        )
        let nativeContext = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: originalURL,
            displayTitle: "测试漫画",
            source: .favorites
        )

        appModel.presentMangaFromWeb(nativeContext, preserving: webContext)
        appModel.dismissManga(openThreadInForum: originalURL)

        XCTAssertNil(appModel.activeMangaRoute)
        XCTAssertNil(appModel.suspendedMangaWebContext)
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, originalURL)
    }

    func testSelectingFavoritesAfterMangaOpenedForumRestoresManga() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext(), initialTab: .favorites)
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!
        let context = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&page=3&mobile=2")!,
            displayTitle: "测试漫画",
            source: .favorites,
            initialPage: 5
        )

        appModel.presentManga(context)
        appModel.dismissManga(openThreadInForum: originalURL)
        appModel.selectTab(.favorites)

        guard case let .native(restoredContext)? = appModel.activeMangaRoute else {
            return XCTFail("Expected restored native manga route")
        }
        XCTAssertEqual(restoredContext, context)
        XCTAssertNil(appModel.suspendedMangaRoute)
        XCTAssertEqual(appModel.selectedTab, .favorites)
    }

    func testMangaPresentationDismissCallbackDoesNotClearSuspendedMangaRoute() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext(), initialTab: .favorites)
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!
        let context = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: originalURL,
            displayTitle: "测试漫画",
            source: .favorites,
            initialPage: 2
        )

        appModel.presentManga(context)
        appModel.dismissManga(openThreadInForum: originalURL)
        appModel.dismissManga()
        appModel.selectTab(.favorites)

        guard case let .native(restoredContext)? = appModel.activeMangaRoute else {
            return XCTFail("Expected restored native manga route")
        }
        XCTAssertEqual(restoredContext, context)
    }

    func testDismissReaderToOriginalPostSelectsForumAndCreatesNavigationRequest() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext(), initialTab: .mine)
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703&mobile=2")!
        let context = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .forum
        )

        appModel.presentReader(context)
        appModel.dismissReader(openThreadInForum: originalURL)

        XCTAssertNil(appModel.activeReaderContext)
        XCTAssertEqual(appModel.suspendedReaderContext, context)
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, originalURL)
    }

    func testSelectingFavoritesAfterReaderOpenedForumRestoresReader() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext(), initialTab: .favorites)
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703&mobile=2")!
        let context = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .favorites,
            initialView: 2
        )

        appModel.presentReader(context)
        appModel.dismissReader(openThreadInForum: originalURL)
        appModel.selectTab(.favorites)

        XCTAssertEqual(appModel.activeReaderContext, context)
        XCTAssertNil(appModel.suspendedReaderContext)
        XCTAssertEqual(appModel.selectedTab, .favorites)
    }

    func testFallbackMangaToWebDisablesAutoOpenLoop() {
        let appModel = YamiboAppModel(appContext: YamiboAppContext())
        let context = MangaWebContext(
            currentURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=702&mobile=2")!,
            originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
            source: .forum,
            initialPage: 0,
            autoOpenNative: true,
            waitingForNativeReturn: true
        )

        appModel.fallbackMangaToWeb(context)

        guard case let .web(activeWeb)? = appModel.activeMangaRoute else {
            return XCTFail("Expected web route")
        }
        XCTAssertFalse(activeWeb.autoOpenNative)
        XCTAssertFalse(activeWeb.waitingForNativeReturn)
    }
}

private func makeAppModelWithReaderResumeRouteStore() async throws -> (YamiboAppModel, ReaderResumeRouteStore) {
    let suiteName = "reader-resume-app-model-tests-\(UUID().uuidString)"
    try XCTUnwrap(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
    let store = ReaderResumeRouteStore(
        defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
        key: "reader-route"
    )
    let context = YamiboAppContext(
        sessionStore: SessionStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)), key: "session"),
        settingsStore: SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)), key: "settings"),
        readerResumeRouteStore: store,
        favoriteStore: FavoriteStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)), key: "favorites")
    )
    let appModel = await MainActor.run {
        YamiboAppModel(appContext: context)
    }
    return (appModel, store)
}

private func waitForReaderResumeRoute(
    _ store: ReaderResumeRouteStore,
    equals expected: ReaderResumeRoute?,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    for _ in 0..<20 {
        if await store.load() == expected {
            return
        }
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    let loaded = await store.load()
    XCTAssertEqual(loaded, expected, file: file, line: line)
}
