import Foundation
import Testing
@testable import YamiboReaderCore
import YamiboReaderUI

@Suite("MangaReaderTests: Route Skeleton")
struct MangaReaderTestsRouteSkeleton {
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

    @Test func threadOpenResolverStillCreatesMangaLaunchContext() async throws {
        let resolver = ThreadOpenResolver(
            client: YamiboClient(session: URLSession(configuration: .ephemeral), cookie: nil, userAgent: "Test-UA")
        )
        let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))
        let html = """
        <title>测试漫画 第1话 - 中文百合漫画区 - 百合会</title>
        <div class="header"><h2><a>中文百合漫画区</a></h2></div>
        <div class="message"><img src="https://img.example.com/700-0.jpg" /></div>
        """

        let target = try await resolver.resolve(
            threadURL: url,
            title: "测试漫画 第1话",
            htmlOverride: html
        )

        guard case let .manga(context) = target else {
            Issue.record("Expected manga launch context")
            return
        }
        #expect(context.originalThreadURL == url)
        #expect(context.chapterURL == url)
        #expect(context.source == .forum)
    }
}

@MainActor
private func makeAppModel() throws -> YamiboAppModel {
    YamiboAppModel(appContext: try makeAppContext())
}

private func makeAppContext() throws -> YamiboAppContext {
    YamiboAppContext()
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
