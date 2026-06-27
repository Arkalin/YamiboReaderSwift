import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@Suite("MangaReaderTests: UI Route Skeleton")
struct MangaReaderTestsUIRouteSkeleton {
    @MainActor
    @Test func openMangaRoutesDirectlyToNativeSkeleton() async throws {
        let appModel = try makeAppModel()
        let context = try makeLaunchContext(tid: "700")

        await appModel.openManga(
            context,
            currentHTML: "<html></html>",
            currentTitle: "Ignored"
        )

        #expect(appModel.activeMangaRoute == .native(context))
        #expect(appModel.suspendedMangaWebContext == nil)
    }

    @MainActor
    @Test func mangaSkeletonViewsAreConstructible() throws {
        #if os(iOS)
        let appModel = try makeAppModel()
        let nativeContext = try makeLaunchContext(tid: "700")
        let webContext = MangaWebContext(
            currentURL: nativeContext.chapterURL,
            originalThreadURL: nativeContext.originalThreadURL,
            source: .forum
        )

        _ = MangaReaderView(context: nativeContext, appModel: appModel)
        _ = MangaWebFallbackView(context: webContext, appModel: appModel)
        #else
        #expect(true)
        #endif
    }
}

@MainActor
private func makeAppModel() throws -> YamiboAppModel {
    YamiboAppModel(appContext: try makeAppContext())
}

private func makeAppContext() throws -> YamiboAppContext {
    let suiteName = "manga-route-skeleton-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return YamiboAppContext(
        sessionStore: SessionStore(defaults: defaults, key: "session"),
        settingsStore: SettingsStore(defaults: defaults, key: "settings"),
        readerResumeRouteStore: ReaderResumeRouteStore(defaults: defaults, key: "reader-route"),
        favoriteStore: FavoriteStore(defaults: defaults, key: "favorites")
    )
}

private func makeLaunchContext(tid: String) throws -> MangaLaunchContext {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    return MangaLaunchContext(
        originalThreadURL: url,
        chapterURL: url,
        displayTitle: "测试漫画",
        source: .forum
    )
}
