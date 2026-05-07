import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MangaPresentationRouteTests: XCTestCase {
    func testMangaFavoriteLaunchNeedsProbeBlocker() {
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

        XCTAssertTrue(favoriteLaunchNeedsMangaProbeBlocker(manga))
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
        XCTAssertEqual(appModel.selectedTab, .forum)
        XCTAssertEqual(appModel.forumNavigationRequest?.url, originalURL)
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
