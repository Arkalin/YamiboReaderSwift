import Foundation
import Testing
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@Suite("MangaReaderTests: UI Route Contracts")
struct MangaReaderTestsUIRouteContracts {
    @MainActor
    @Test func presentMangaReaderRoutesDirectlyToNativeReader() throws {
        let appModel = try makeAppModel()
        let context = try makeLaunchContext(tid: "700")

        appModel.presentMangaReader(context)

        #expect(appModel.activeMangaContext == context)
    }

    @MainActor
    @Test func mangaReaderViewIsConstructible() throws {
        #if os(iOS)
        let appContext = try makeAppContext()
        let appModel = YamiboAppModel(appContext: appContext)
        let nativeContext = try makeLaunchContext(tid: "700")

        _ = MangaReaderView(
            context: nativeContext,
            dependencies: appContext.mangaReaderDependencies,
            appModel: appModel
        )
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
    )
}

private func makeLaunchContext(tid: String) throws -> MangaLaunchContext {
    MangaLaunchContext(
        originalThreadID: tid,
        chapterTID: tid,
        displayTitle: "测试漫画",
        source: .forum
    )
}
