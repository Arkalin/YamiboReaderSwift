import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@Suite("MangaReaderTests: UI Route Contracts")
struct MangaReaderTestsUIRouteContracts {
    @MainActor
    @Test func openMangaRoutesDirectlyToNativeReader() async throws {
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
    @Test func mangaReaderAndWebFallbackViewsAreConstructible() throws {
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
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "manga-route-contracts")
    return YamiboAppContext(
        sessionStore: try SessionStore(testSuiteName: defaultsSuiteName, key: "session"),
        settingsStore: try SettingsStore(testSuiteName: defaultsSuiteName, key: "settings"),
        readerResumeRouteStore: try ReaderResumeRouteStore(testSuiteName: defaultsSuiteName, key: "reader-route"),
        favoriteStore: try FavoriteStore(testSuiteName: defaultsSuiteName, key: "favorites")
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
