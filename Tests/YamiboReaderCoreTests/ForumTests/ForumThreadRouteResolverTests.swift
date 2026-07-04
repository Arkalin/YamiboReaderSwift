import Foundation
import Testing
@testable import YamiboReaderCore

private final class ForumThreadRouteResolverTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Data, HTTPURLResponse)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ForumThreadRouteResolverTestError.missingHandler)
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

private enum ForumThreadRouteResolverTestError: Error {
    case missingHandler
}

@Suite(.serialized)
struct ForumThreadRouteResolverTests {

@Test func forumThreadRouteResolverUsesContainingBoardForNovelThreadsWithoutFetching() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100&mobile=2")),
        title: "小说标题",
        authorID: "705216",
        tapContext: ForumThreadTapContext(containingFid: "49")
    )

    let target = try await resolver.resolve(request)

    guard case let .novelDetail(context) = target else {
        Issue.record("Expected novel detail target, got \(target)")
        return
    }
    #expect(context.thread.tid == "100")
    #expect(context.title == "小说标题")
    #expect(context.authorID == "705216")
}

@Test func forumThreadRouteResolverUsesLightNovelSubBoardForNovelDetail() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&extra=page%3D1&mobile=2&page=25&authorid=705217")),
        title: "轻小说标题",
        authorID: "705217",
        tapContext: ForumThreadTapContext(containingFid: "55")
    )

    let target = try await resolver.resolve(request)

    guard case let .novelDetail(context) = target else {
        Issue.record("Expected novel detail target, got \(target)")
        return
    }
    #expect(context.thread.tid == "101")
    #expect(context.thread.fid == "55")
    #expect(context.title == "轻小说标题")
    #expect(context.authorID == "705217")
}

@Test func forumThreadRouteResolverUsesKnownMangaKindWhenTaxonomyMisses() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=200&mobile=2")),
        title: "漫画标题",
        threadFid: "999999",
        knownThreadKind: .manga
    )

    let target = try await resolver.resolve(request)

    guard case let .mangaDetail(context) = target else {
        Issue.record("Expected manga detail target, got \(target)")
        return
    }
    #expect(context.thread.tid == "200")
    #expect(context.thread.fid == "999999")
    #expect(context.title == "漫画标题")
}

@Test func forumThreadRouteResolverNativeThreadIntentBypassesNovelClassification() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=201&page=4&mobile=2")),
        title: "小说原帖",
        authorID: "705216",
        intent: .nativeThreadReader,
        tapContext: ForumThreadTapContext(containingFid: "49")
    )

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "201")
    #expect(context.thread.fid == "49")
    #expect(context.title == "小说原帖")
    #expect(context.initialPage == 4)
    #expect(context.authorID == "705216")
}

@Test func forumThreadRouteResolverNativeThreadIntentBypassesMangaClassification() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=202&mobile=2")),
        title: "漫画原帖",
        threadFid: "999999",
        knownThreadKind: .manga,
        intent: .nativeThreadReader
    )

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "202")
    #expect(context.thread.fid == "999999")
    #expect(context.title == "漫画原帖")
}

@Test func forumThreadRouteResolverNativeThreadIntentExtractsTargetPostFromFragment() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=203&page=5&mobile=2#pid9901")),
        title: "原帖",
        intent: .nativeThreadReader
    )

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "203")
    #expect(context.initialPage == 5)
    #expect(context.targetPostID == "9901")
}

@Test func forumThreadRouteResolverDefaultsUnknownBoardToNativeThreadReader() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=300&page=2&mobile=2")),
        title: "普通帖子",
        threadFid: "999999",
        targetPostID: "42"
    )

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "300")
    #expect(context.thread.fid == "999999")
    #expect(context.initialPage == 2)
    #expect(context.targetPostID == "42")
    #expect(context.loadsAllPosts)
}

@Test func forumThreadRouteResolverExtractsInitialPageFromRewriteThreadURL() async throws {
    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClient())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/thread-301-4-1.html")),
        title: "普通帖子",
        threadFid: "999999"
    )

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "301")
    #expect(context.initialPage == 4)
}

@Test func forumThreadRouteResolverNormalizesFindPostURLAndCarriesTargetPost() async throws {
    defer { ForumThreadRouteResolverTestURLProtocol.handler = nil }

    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClientWithHandler())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=302&pid=9001&mobile=2")),
        title: "普通帖子",
        threadFid: "999999"
    )
    ForumThreadRouteResolverTestURLProtocol.handler = { request in
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.value(named: "goto") == "findpost")
        #expect(items.value(named: "ptid") == "302")
        #expect(items.value(named: "pid") == "9001")
        return forumThreadRouteHTTPResponse(
            url: request.url!,
            body: #"""
            <html>
            <head><title>普通帖子 - 百合会</title></head>
            <body>
              <div id="post_9001">
                <div class="authi">
                  <a class="author" href="home.php?mod=space&amp;uid=42&amp;mobile=2">楼主名</a>
                  <em>发表于 2026-6-1 10:00</em>
                </div>
                <div class="message" id="postmessage_9001">目标回复</div>
              </div>
              <div class="pg"><a>1</a><a>2</a><strong>3</strong><span>/ 5 页</span></div>
            </body>
            </html>
            """#
        )
    }

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "302")
    #expect(context.initialPage == 3)
    #expect(context.targetPostID == "9001")
}

@Test func forumThreadRouteResolverNativeThreadIntentKeepsFindPostTargetWhenPageResolutionFails() async throws {
    defer { ForumThreadRouteResolverTestURLProtocol.handler = nil }

    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClientWithHandler())
    let request = ThreadRouteRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=303&pid=9002&mobile=2")),
        title: "原帖",
        intent: .nativeThreadReader
    )
    ForumThreadRouteResolverTestURLProtocol.handler = { request in
        forumThreadRouteHTTPResponse(url: request.url!, body: "forbidden", statusCode: 403)
    }

    let target = try await resolver.resolve(request)

    guard case let .threadReader(context) = target else {
        Issue.record("Expected native thread reader target, got \(target)")
        return
    }
    #expect(context.thread.tid == "303")
    #expect(context.initialPage == 1)
    #expect(context.targetPostID == "9002")
}

@Test func forumThreadRouteResolverFetchesThreadMetadataWhenBoardIsUnknown() async throws {
    defer { ForumThreadRouteResolverTestURLProtocol.handler = nil }

    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClientWithHandler())
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=400&mobile=2"))

    ForumThreadRouteResolverTestURLProtocol.handler = { request in
        #expect(request.url?.path == "/forum.php")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.value(named: "tid") == "400")
        return forumThreadRouteHTTPResponse(
            url: request.url!,
            body: #"""
            <html>
            <head><title>章节标题 - 文学区 - 百合会</title></head>
            <body>
              <div class="header"><h2><a href="forum.php?mod=forumdisplay&amp;fid=49&amp;mobile=2">文学区</a></h2></div>
              <a href="home.php?mod=space&amp;uid=88&amp;mobile=2" class="mmc">作者</a>
            </body>
            </html>
            """#
        )
    }

    let target = try await resolver.resolve(ThreadRouteRequest(threadURL: url))

    guard case let .novelDetail(context) = target else {
        Issue.record("Expected novel detail target, got \(target)")
        return
    }
    #expect(context.thread.tid == "400")
    #expect(context.thread.fid == "49")
    #expect(context.title == "章节标题 - 文学区 - 百合会")
    #expect(context.authorID == "88")
}

@Test func forumThreadRouteResolverUsesWebFallbackForAuthenticatedMetadataFailure() async throws {
    defer { ForumThreadRouteResolverTestURLProtocol.handler = nil }

    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClientWithHandler())
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=500&mobile=2"))

    ForumThreadRouteResolverTestURLProtocol.handler = { request in
        forumThreadRouteHTTPResponse(url: request.url!, body: "forbidden", statusCode: 403)
    }

    let target = try await resolver.resolve(ThreadRouteRequest(threadURL: url))

    guard case let .webFallback(fallbackURL) = target else {
        Issue.record("Expected web fallback target, got \(target)")
        return
    }
    #expect(fallbackURL == url)
}

@Test func forumThreadRouteResolverPropagatesNonFallbackMetadataFailure() async throws {
    defer { ForumThreadRouteResolverTestURLProtocol.handler = nil }

    let resolver = ForumThreadRouteResolver(client: forumThreadRouteTestClientWithHandler())
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=600&mobile=2"))

    ForumThreadRouteResolverTestURLProtocol.handler = { request in
        forumThreadRouteHTTPResponse(url: request.url!, body: "")
    }

    await #expect(throws: YamiboError.emptyHTML) {
        _ = try await resolver.resolve(ThreadRouteRequest(threadURL: url))
    }
}

}

private func forumThreadRouteTestClient() -> YamiboClient {
    YamiboClient(session: URLSession(configuration: .ephemeral), userAgent: "Test-UA")
}

private func forumThreadRouteTestClientWithHandler() -> YamiboClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ForumThreadRouteResolverTestURLProtocol.self]
    return YamiboClient(session: URLSession(configuration: configuration), userAgent: "Test-UA")
}

private func forumThreadRouteHTTPResponse(
    url: URL,
    body: String,
    statusCode: Int = 200
) -> (Data, HTTPURLResponse) {
    (
        Data(body.utf8),
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    )
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}
