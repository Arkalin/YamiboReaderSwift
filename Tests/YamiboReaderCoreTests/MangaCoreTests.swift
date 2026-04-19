import Foundation
import Testing
@testable import YamiboReaderCore

private struct MangaStubResponse {
    let statusCode: Int
    let body: String
}

private final class MangaStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> MangaStubResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let output = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: output.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(output.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class MangaCooldownStubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> MangaStubResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let output = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: output.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(output.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func mangaHTMLParserFindsMobileTagsAndSamePageLinks() async throws {
    let html = """
    <html>
      <body>
        <div class="header"><h2><a>中文百合漫画区</a></h2></div>
        <div class="message">
          <a href="misc.php?mod=tag&id=11">tag</a>
          <a href="forum.php?mod=viewthread&tid=100&mobile=2">第一话</a>
          <a href="thread-101-1-1.html">第二话</a>
          <img zsrc="https://img.example.com/a.jpg" />
        </div>
      </body>
    </html>
    """

    #expect(MangaHTMLParser.findTagIDsMobile(in: html) == ["11"])
    let links = MangaHTMLParser.extractSamePageLinks(from: html)
    #expect(links.count == 2)
    #expect(links.map(\.tid) == ["100", "101"])
    #expect(MangaHTMLParser.extractImageURLs(from: html).count == 1)
    #expect(MangaHTMLParser.isLikelyMangaThread(title: "作品 - 中文百合漫画区", html: html))
}

@Test func mangaHTMLParserExtractsSearchMetadataAndFloodControl() async throws {
    let html = """
    <div class="pg"><label><span title="共 3 页">3</span></label></div>
    <a href="/search.php?mod=forum&searchid=999&page=2">下一页</a>
    """

    #expect(MangaHTMLParser.extractTotalPages(from: html) == 3)
    #expect(MangaHTMLParser.extractSearchID(from: html) == "999")
    #expect(MangaHTMLParser.isFloodControlOrError("只能进行一次搜索"))
    #expect(!MangaHTMLParser.isFloodControlOrError("没有找到匹配结果"))
}

@Test func threadOpenResolverClassifiesNovelMangaAndWeb() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MangaStubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = YamiboClient(session: session, cookie: nil, userAgent: "Test-UA")
    let resolver = ThreadOpenResolver(client: client)

    let novelHTML = """
    <title>测试 - 文学区 - 百合会</title>
    <div class="message">正文</div>
    """
    let mangaHTML = """
    <title>测试 - 中文百合漫画区 - 百合会</title>
    <div class="header"><h2><a>中文百合漫画区</a></h2></div>
    <div class="message"><img src="https://img.example.com/1.jpg" /></div>
    """
    let webHTML = """
    <title>普通帖子 - 茶水间 - 百合会</title>
    <div class="message">hello</div>
    """

    let novelTarget = try await resolver.resolve(
        threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")!,
        title: "测试 - 文学区 - 百合会",
        htmlOverride: novelHTML
    )
    if case let .novel(context) = novelTarget {
        #expect(context.threadURL.absoluteString.contains("tid=1"))
    } else {
        Issue.record("Expected novel target")
    }

    let mangaTarget = try await resolver.resolve(
        threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=2&mobile=2")!,
        title: "测试 - 中文百合漫画区 - 百合会",
        htmlOverride: mangaHTML
    )
    if case let .manga(context) = mangaTarget {
        #expect(context.chapterURL.absoluteString.contains("tid=2"))
    } else {
        Issue.record("Expected manga target")
    }

    let webTarget = try await resolver.resolve(
        threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=3&mobile=2")!,
        title: "普通帖子 - 茶水间 - 百合会",
        htmlOverride: webHTML
    )
    if case .web = webTarget {
    } else {
        Issue.record("Expected web target")
    }
}

@Test func mangaDirectoryStoreInitializesUpdatesAndMergesDirectories() async throws {
    let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = MangaDirectoryStore(baseDirectory: baseDirectory)
    let initialHTML = """
    <html>
      <div class="header"><h2><a>中文百合漫画区</a></h2></div>
      <div class="message">
        <a href="misc.php?mod=tag&id=31">tag</a>
        <a href="forum.php?mod=viewthread&tid=500&mobile=2">第1话</a>
        <a href="forum.php?mod=viewthread&tid=501&mobile=2">第2话</a>
        <img src="https://img.example.com/500-1.jpg" />
      </div>
    </html>
    """

    let directory = try await store.initializeDirectory(
        currentURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=500&mobile=2")!,
        rawTitle: "【作者】作品标题 - 中文百合漫画区",
        html: initialHTML
    )
    #expect(directory.strategy == .tag)
    #expect(directory.chapters.count == 2)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MangaStubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    MangaStubURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        if url.contains("misc.php"), url.contains("mod=tag"), url.contains("id=31"), url.contains("page=1") {
            return MangaStubResponse(
                statusCode: 200,
                body: """
                <table>
                  <tr>
                    <th><a href="thread-500-1-1.html">第1话</a></th>
                    <td class="by"></td>
                    <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-02</span></em></td>
                  </tr>
                  <tr>
                    <th><a href="thread-502-1-1.html">第3话</a></th>
                    <td class="by"></td>
                    <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-03</span></em></td>
                  </tr>
                </table>
                """
            )
        }
        return MangaStubResponse(statusCode: 200, body: "")
    }
    let repository = MangaRepository(client: YamiboClient(session: session, cookie: nil, userAgent: "Test-UA"))
    let updated = try await store.updateDirectory(directory, using: repository)
    #expect(updated.directory.chapters.map(\.tid).contains("502"))

    let merged = try await store.renameAndMergeDirectory(
        updated.directory,
        newCleanName: "新标题",
        newSearchKeyword: "作者 新标题"
    )
    #expect(merged.cleanBookName == "新标题")
    #expect(merged.searchKeyword == "作者 新标题")
}

@Test func mangaChapterDisplayFormatterHandlesSpecialChapterLabelsAndLatestSelection() async throws {
    let special = MangaChapter(
        tid: "1",
        rawTitle: "番外篇",
        chapterNumber: 0,
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")!
    )
    let ending = MangaChapter(
        tid: "2",
        rawTitle: "最终话",
        chapterNumber: 999,
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=2&mobile=2")!
    )
    let ex = MangaChapter(
        tid: "3",
        rawTitle: "特别篇",
        chapterNumber: 12.345,
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=3&mobile=2")!
    )
    let normal = MangaChapter(
        tid: "4",
        rawTitle: "第12.5话",
        chapterNumber: 12.5,
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=4&mobile=2")!
    )

    #expect(MangaChapterDisplayFormatter.displayNumber(for: special) == "SP")
    #expect(MangaChapterDisplayFormatter.displayNumber(for: ending) == "终")
    #expect(MangaChapterDisplayFormatter.displayNumber(for: ex) == "Ex")
    #expect(MangaChapterDisplayFormatter.displayNumber(for: normal) == "12-5")
    #expect(MangaChapterDisplayFormatter.latestChapter(in: [special, ex, normal])?.tid == "4")
}

@Test func mangaDirectoryStoreSearchCooldownUsesTypedError() async throws {
    let baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = MangaDirectoryStore(baseDirectory: baseDirectory)
    let initialHTML = """
    <html>
      <div class="header"><h2><a>中文百合漫画区</a></h2></div>
      <div class="message">
        <img src="https://img.example.com/600-1.jpg" />
      </div>
    </html>
    """

    let directory = try await store.initializeDirectory(
        currentURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=600&mobile=2")!,
        rawTitle: "【作者】作品标题 - 中文百合漫画区",
        html: initialHTML
    )
    #expect(directory.strategy == .pendingSearch)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MangaCooldownStubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    MangaCooldownStubURLProtocol.handler = { request in
        let url = request.url!.absoluteString
        if url.contains("search.php") {
            return MangaStubResponse(
                statusCode: 200,
                body: """
                <li class="list">
                  <a href="forum.php?mod=viewthread&tid=600&mobile=2">第1话</a>
                  <h3><a href="space-uid-77.html">作者甲</a></h3>
                </li>
                """
            )
        }
        return MangaStubResponse(statusCode: 200, body: "")
    }
    let repository = MangaRepository(client: YamiboClient(session: session, cookie: nil, userAgent: "Test-UA"))

    _ = try await store.updateDirectory(directory, using: repository)

    do {
        _ = try await store.updateDirectory(directory, using: repository)
        Issue.record("Expected search cooldown error")
    } catch let error as YamiboError {
        #expect(error == .searchCooldown(seconds: 20))
    }
}
