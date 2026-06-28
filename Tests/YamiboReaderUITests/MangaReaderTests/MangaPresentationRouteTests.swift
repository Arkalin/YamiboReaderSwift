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

    func testBootstrapIfNeededRestoresNovelRouteFromDownloadedWebDAVProgress() async throws {
        let suiteName = "reader-resume-webdav-novel-\(UUID().uuidString)"
        let fixture = try makeAppModelWebDAVFixture(suiteName: suiteName)
        let host = "reader-restore-novel.example.com"
        let threadURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=730&mobile=2"))
        let staleResumePoint = ReaderResumePoint(
            view: 1,
            displayedTextOffset: 12,
            chapterOrdinal: 0,
            chapterTitle: "第一章",
            segmentProgress: 0.1,
            readingModeHint: .paged
        )
        let staleContext = ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "本地小说",
            source: .resume,
            initialView: 1,
            initialResumePoint: staleResumePoint
        )
        let remoteResumePoint = ReaderResumePoint(
            view: 5,
            displayedTextOffset: 256,
            chapterOrdinal: 4,
            chapterTitle: "第五章",
            segmentProgress: 0.6,
            authorID: "42",
            readingModeHint: .vertical
        )
        let remoteFavorite = Favorite(
            title: "远端小说",
            url: threadURL,
            lastView: 5,
            lastChapter: "第五章",
            authorID: "42",
            novelResumePoint: remoteResumePoint,
            novelMaxView: 9,
            type: .novel
        )
        let payload = WebDAVSyncPayload(
            updatedAt: Date(timeIntervalSince1970: 2_000),
            accountUID: "100",
            library: FavoriteLibrarySnapshot(favorites: [remoteFavorite], collections: [])
        )
        let encodedPayload = try JSONEncoder().encode(payload)

        try await fixture.resumeRouteStore.save(.novel(staleContext))
        try await fixture.sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))
        try await fixture.webDAVSettingsStore.save(WebDAVSyncSettings(
            baseURLString: "https://\(host)",
            username: "admin",
            password: "secret",
            isAutoSyncEnabled: true,
            lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
            localUpdatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        AppModelWebDAVTestURLProtocol.setHandler(for: host) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (
                encodedPayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }
        defer { AppModelWebDAVTestURLProtocol.removeHandler(for: host) }

        let appContext = YamiboAppContext(
            sessionStore: fixture.sessionStore,
            settingsStore: fixture.settingsStore,
            webDAVSyncSettingsStore: fixture.webDAVSettingsStore,
            readerResumeRouteStore: fixture.resumeRouteStore,
            favoriteStore: fixture.favoriteStore,
            session: fixture.session
        )
        let appModel = YamiboAppModel(appContext: appContext)

        await appModel.bootstrapIfNeeded()

        let expectedContext = ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "远端小说",
            source: .resume,
            initialView: 5,
            authorID: "42",
            initialResumePoint: remoteResumePoint
        )
        XCTAssertEqual(appModel.activeReaderContext, expectedContext)
        let restoredRoute = await fixture.resumeRouteStore.load()
        XCTAssertEqual(restoredRoute, .novel(expectedContext))
    }

    func testBootstrapIfNeededRestoresMangaRouteFromDownloadedWebDAVProgress() async throws {
        let suiteName = "reader-resume-webdav-manga-\(UUID().uuidString)"
        let fixture = try makeAppModelWebDAVFixture(suiteName: suiteName)
        let host = "reader-restore-manga.example.com"
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=731&mobile=2"))
        let staleChapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=732&mobile=2"))
        let remoteChapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=733&mobile=2"))
        let staleContext = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: staleChapterURL,
            displayTitle: "本地漫画",
            source: .resume,
            initialPage: 0,
            directoryName: "本地目录"
        )
        let remoteFavorite = Favorite(
            title: "远端漫画",
            url: originalURL,
            mangaPageIndex: 7,
            lastChapter: "第七页",
            type: .manga,
            lastMangaURL: remoteChapterURL
        )
        let payload = WebDAVSyncPayload(
            updatedAt: Date(timeIntervalSince1970: 2_000),
            accountUID: "100",
            library: FavoriteLibrarySnapshot(favorites: [remoteFavorite], collections: [])
        )
        let encodedPayload = try JSONEncoder().encode(payload)

        try await fixture.resumeRouteStore.save(.manga(.native(staleContext)))
        try await fixture.sessionStore.save(SessionState(cookie: "sid=local", isLoggedIn: true, accountUID: "100"))
        try await fixture.webDAVSettingsStore.save(WebDAVSyncSettings(
            baseURLString: "https://\(host)",
            username: "admin",
            password: "secret",
            isAutoSyncEnabled: true,
            lastRemoteUpdatedAt: Date(timeIntervalSince1970: 1_000),
            localUpdatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        AppModelWebDAVTestURLProtocol.setHandler(for: host) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            return (
                encodedPayload,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }
        defer { AppModelWebDAVTestURLProtocol.removeHandler(for: host) }

        let appContext = YamiboAppContext(
            sessionStore: fixture.sessionStore,
            settingsStore: fixture.settingsStore,
            webDAVSyncSettingsStore: fixture.webDAVSettingsStore,
            readerResumeRouteStore: fixture.resumeRouteStore,
            favoriteStore: fixture.favoriteStore,
            session: fixture.session
        )
        let appModel = YamiboAppModel(appContext: appContext)

        await appModel.bootstrapIfNeeded()

        let expectedContext = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: remoteChapterURL,
            displayTitle: "远端漫画",
            source: .resume,
            initialPage: 7,
            directoryName: "本地目录",
            offlineCacheFavoriteID: remoteFavorite.id
        )
        XCTAssertEqual(appModel.activeMangaRoute, .native(expectedContext))
        let restoredRoute = await fixture.resumeRouteStore.load()
        XCTAssertEqual(restoredRoute, .manga(.native(expectedContext)))
    }

    func testBootstrapIfNeededKeepsLocalResumeRouteWhenWebDAVDoesNotDownloadProgress() async throws {
        let suiteName = "reader-resume-webdav-skip-\(UUID().uuidString)"
        let fixture = try makeAppModelWebDAVFixture(suiteName: suiteName)
        let threadURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=734&mobile=2"))
        let localResumePoint = ReaderResumePoint(
            view: 6,
            displayedTextOffset: 512,
            chapterOrdinal: 5,
            chapterTitle: "第六章",
            segmentProgress: 0.8,
            readingModeHint: .vertical
        )
        let localContext = ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "本地小说",
            source: .resume,
            initialView: 6,
            initialResumePoint: localResumePoint
        )
        let staleFavorite = Favorite(
            title: "旧收藏进度",
            url: threadURL,
            lastView: 2,
            lastChapter: "第二章",
            type: .novel
        )
        try await fixture.resumeRouteStore.save(.novel(localContext))
        try await fixture.favoriteStore.saveFavorites([staleFavorite])

        let appContext = YamiboAppContext(
            sessionStore: fixture.sessionStore,
            settingsStore: fixture.settingsStore,
            webDAVSyncSettingsStore: fixture.webDAVSettingsStore,
            readerResumeRouteStore: fixture.resumeRouteStore,
            favoriteStore: fixture.favoriteStore,
            session: fixture.session
        )
        let appModel = YamiboAppModel(appContext: appContext)

        await appModel.bootstrapIfNeeded()

        XCTAssertEqual(appModel.activeReaderContext, localContext)
        let restoredRoute = await fixture.resumeRouteStore.load()
        XCTAssertEqual(restoredRoute, .novel(localContext))
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
        let appModel = makeIsolatedAppModel()
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
        let appModel = makeIsolatedAppModel()
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
        let appModel = makeIsolatedAppModel()
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
        let appModel = makeIsolatedAppModel(initialTab: .favorites)
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
        let appModel = makeIsolatedAppModel(initialTab: .favorites)
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
        let appModel = makeIsolatedAppModel(initialTab: .mine)
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

    func testOpenForumURLExitsActiveReaderAndCreatesNavigationRequest() {
        let appModel = makeIsolatedAppModel(initialTab: .mine)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703&mobile=2")!
        let clipboardURL = URL(string: "https://bbs.yamibo.com/thread-900-1-1.html")!
        let context = ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "测试小说",
            source: .forum
        )

        appModel.presentReader(context)
        appModel.openForumURL(clipboardURL)

        XCTAssertNil(appModel.activeReaderContext)
        XCTAssertEqual(appModel.suspendedReaderContext, context)
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, clipboardURL)
    }

    func testConfirmClipboardForumLinkPromptExitsActiveReaderAndCreatesNavigationRequest() {
        let appModel = makeIsolatedAppModel(initialTab: .mine)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703&mobile=2")!
        let clipboardURL = URL(string: "https://bbs.yamibo.com/thread-902-1-1.html")!
        let context = ReaderLaunchContext(
            threadURL: threadURL,
            threadTitle: "测试小说",
            source: .forum
        )

        appModel.presentReader(context)
        appModel.presentClipboardForumLinkPrompt(url: clipboardURL)
        let prompt = appModel.clipboardForumLinkPrompt!
        appModel.confirmClipboardForumLinkPrompt(prompt)

        XCTAssertNil(appModel.clipboardForumLinkPrompt)
        XCTAssertNil(appModel.activeReaderContext)
        XCTAssertEqual(appModel.suspendedReaderContext, context)
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, clipboardURL)
    }

    func testOpenForumURLExitsActiveMangaAndCreatesNavigationRequest() {
        let appModel = makeIsolatedAppModel(initialTab: .mine)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!
        let clipboardURL = URL(string: "https://bbs.yamibo.com/thread-901-1-1.html")!
        let context = MangaLaunchContext(
            originalThreadURL: threadURL,
            chapterURL: threadURL,
            displayTitle: "测试漫画",
            source: .forum,
            initialPage: 2
        )

        appModel.presentManga(context)
        appModel.openForumURL(clipboardURL)

        XCTAssertNil(appModel.activeMangaRoute)
        XCTAssertEqual(appModel.suspendedMangaRoute, .native(context))
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, clipboardURL)
    }

    func testConfirmClipboardForumLinkPromptExitsActiveMangaAndCreatesNavigationRequest() {
        let appModel = makeIsolatedAppModel(initialTab: .mine)
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!
        let clipboardURL = URL(string: "https://bbs.yamibo.com/thread-903-1-1.html")!
        let context = MangaLaunchContext(
            originalThreadURL: threadURL,
            chapterURL: threadURL,
            displayTitle: "测试漫画",
            source: .forum,
            initialPage: 2
        )

        appModel.presentManga(context)
        appModel.presentClipboardForumLinkPrompt(url: clipboardURL)
        let prompt = appModel.clipboardForumLinkPrompt!
        appModel.confirmClipboardForumLinkPrompt(prompt)

        XCTAssertNil(appModel.clipboardForumLinkPrompt)
        XCTAssertNil(appModel.activeMangaRoute)
        XCTAssertEqual(appModel.suspendedMangaRoute, .native(context))
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, clipboardURL)
    }

    func testDismissReaderToOriginalPostSuspendsProvidedLatestContext() {
        let appModel = makeIsolatedAppModel(initialTab: .mine)
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703&mobile=2")!
        let staleContext = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .favorites,
            initialView: 2
        )
        let latestResumePoint = ReaderResumePoint(
            view: 4,
            displayedTextOffset: 128,
            chapterOrdinal: 3,
            chapterTitle: "第四章",
            segmentProgress: 0.42,
            readingModeHint: .vertical
        )
        let latestContext = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .resume,
            initialView: 4,
            initialResumePoint: latestResumePoint
        )

        appModel.presentReader(staleContext)
        appModel.dismissReader(openThreadInForum: originalURL, suspendedContext: latestContext)

        XCTAssertNil(appModel.activeReaderContext)
        XCTAssertEqual(appModel.suspendedReaderContext, latestContext)
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, originalURL)
    }

    func testSelectingFavoritesAfterReaderOpenedForumRestoresLatestSuspendedReader() {
        let appModel = makeIsolatedAppModel(initialTab: .favorites)
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703&mobile=2")!
        let staleContext = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .favorites,
            initialView: 2
        )
        let latestResumePoint = ReaderResumePoint(
            view: 5,
            displayedTextOffset: 256,
            chapterOrdinal: 4,
            chapterTitle: "第五章",
            segmentProgress: 0.67,
            readingModeHint: .paged
        )
        let latestContext = ReaderLaunchContext(
            threadURL: originalURL,
            threadTitle: "测试小说",
            source: .resume,
            initialView: 5,
            initialResumePoint: latestResumePoint
        )

        appModel.presentReader(staleContext)
        appModel.dismissReader(openThreadInForum: originalURL, suspendedContext: latestContext)
        appModel.selectTab(.favorites)

        XCTAssertEqual(appModel.activeReaderContext, latestContext)
        XCTAssertNil(appModel.suspendedReaderContext)
        XCTAssertEqual(appModel.selectedTab, .favorites)
    }

    func testFallbackMangaToWebDisablesAutoOpenLoop() {
        let appModel = makeIsolatedAppModel()
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
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "reader-resume-app-model-tests")
    let store = try ReaderResumeRouteStore(testSuiteName: defaultsSuiteName, key: "reader-route")
    let context = YamiboAppContext(
        sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
        settingsStore: try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings"),
        readerResumeRouteStore: store,
        favoriteStore: try FavoriteStore(testSuiteName: defaultsSuiteName, key: "favorites")
    )
    let appModel = await MainActor.run {
        YamiboAppModel(appContext: context)
    }
    return (appModel, store)
}

@MainActor
private func makeIsolatedAppModel(initialTab: AppTab = .forum) -> YamiboAppModel {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "manga-presentation-route")
    let context = YamiboAppContext(
        sessionStore: try! SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
        settingsStore: try! SettingsStore(testSuiteName: defaultsSuiteName, key: "settings"),
        readerResumeRouteStore: try! ReaderResumeRouteStore(testSuiteName: defaultsSuiteName, key: "reader-route"),
        favoriteStore: try! FavoriteStore(testSuiteName: defaultsSuiteName, key: "favorites")
    )
    return YamiboAppModel(appContext: context, initialTab: initialTab)
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

private struct AppModelWebDAVFixture: Sendable {
    let sessionStore: SessionStore
    let settingsStore: SettingsStore
    let webDAVSettingsStore: WebDAVSyncSettingsStore
    let resumeRouteStore: ReaderResumeRouteStore
    let favoriteStore: FavoriteStore
    let session: URLSession
}

private func makeAppModelWebDAVFixture(suiteName: String) throws -> AppModelWebDAVFixture {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: suiteName)
    return AppModelWebDAVFixture(
        sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
        settingsStore: try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings"),
        webDAVSettingsStore: try WebDAVSyncSettingsStore(testSuiteName: defaultsSuiteName, key: "webdav"),
        resumeRouteStore: try ReaderResumeRouteStore(testSuiteName: defaultsSuiteName, key: "reader-route"),
        favoriteStore: try FavoriteStore(testSuiteName: defaultsSuiteName, key: "favorites"),
        session: makeAppModelWebDAVTestSession()
    )
}

private final class AppModelWebDAVTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Data, HTTPURLResponse)

    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    private static let lock = NSLock()

    static func setHandler(for host: String, _ handler: @escaping Handler) {
        lock.withLock {
            handlers[host] = handler
        }
    }

    static func removeHandler(for host: String) {
        _ = lock.withLock {
            handlers.removeValue(forKey: host)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let host = request.url?.host,
            let handler = Self.lock.withLock({ Self.handlers[host] })
        else {
            client?.urlProtocol(self, didFailWithError: AppModelWebDAVTestError.missingHandler)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum AppModelWebDAVTestError: Error {
    case missingHandler
}

private func makeAppModelWebDAVTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AppModelWebDAVTestURLProtocol.self]
    return URLSession(configuration: configuration)
}
