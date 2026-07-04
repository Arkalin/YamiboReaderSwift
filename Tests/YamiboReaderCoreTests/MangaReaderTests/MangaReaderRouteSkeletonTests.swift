import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Route Contracts")
struct MangaReaderTestsRouteContracts {
    @Test func yamiboThreadRouteResolverCreatesMangaPayload() async throws {
        let resolver = YamiboThreadRouteResolver(
            client: YamiboClient(session: URLSession(configuration: .ephemeral), cookie: nil, userAgent: "Test-UA")
        )
        let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))

        let target = try await resolver.resolve(YamiboThreadRouteRequest(
            threadURL: url,
            title: "测试漫画 第1话",
            knownThreadKind: .manga
        ))

        guard case let .manga(payload) = target else {
            Issue.record("Expected manga payload")
            return
        }
        #expect(payload.thread.tid == "700")
        #expect(payload.title == "测试漫画 第1话")
    }
}
