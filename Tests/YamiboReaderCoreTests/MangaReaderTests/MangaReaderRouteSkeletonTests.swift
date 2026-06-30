import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Route Contracts")
struct MangaReaderTestsRouteContracts {
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
