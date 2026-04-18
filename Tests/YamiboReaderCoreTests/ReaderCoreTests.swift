import Foundation
import Testing
@testable import YamiboReaderCore

private struct StubURLProtocolResponse {
    let statusCode: Int
    let body: String
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: StubURLProtocolResponse?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func readerModeDetectorMatchesNovelThreadPages() async throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=563621&mobile=2"))
    #expect(ReaderModeDetector.canOpenReader(url: url, title: "文學區 - 测试帖子"))
    #expect(!ReaderModeDetector.canOpenReader(url: url, title: "绘图区 - 测试帖子"))
    #expect(!ReaderModeDetector.canOpenReader(url: URL(string: "https://bbs.yamibo.com/home.php"), title: "文學區"))
}

@Test func threadRoutePreservesAuthorIDFromExistingURL() async throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&page=1&authorid=77&mobile=2"))
    let built = YamiboRoute.thread(url: url, page: 2, authorID: nil).url.absoluteString
    #expect(built.contains("authorid=77"))
    #expect(built.contains("page=2"))
}

@Test func readerHTMLParserExtractsTextImagesAndAuthor() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">
          第一章 相遇<br>这里是正文。<img src="images/cover.jpg" />
        </div>
        <div class="message">
          第二章<br>第二段内容
        </div>
        <a href="forum.php?mod=viewthread&tid=1&page=4&authorid=99">4</a>
      </body>
    </html>
    """#

    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")),
        view: 2
    )
    let document = try ReaderHTMLParser.parseDocument(html: html, request: request)

    #expect(document.maxView == 4)
    #expect(document.resolvedAuthorID == "99")
    #expect(document.segments.count == 3)
    #expect(document.segments[0] == .text("第一章 相遇\n这里是正文。", chapterTitle: "第一章 相遇"))
    #expect(document.segments[1] == .image(try #require(URL(string: "https://bbs.yamibo.com/images/cover.jpg")), chapterTitle: "第一章 相遇"))
    #expect(document.segments[2] == .text("第二章\n第二段内容", chapterTitle: "第二章"))
}

@Test func readerHTMLParserExtractsMaxViewFromSameThreadLinksOnly() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">正文里提到第 315 页和 9494 次浏览</div>
        <a href="forum.php?mod=viewthread&tid=557752&page=2&mobile=2">2</a>
        <a href="forum.php?mod=viewthread&tid=557752&page=4&mobile=2">4</a>
        <a href="forum.php?mod=viewthread&tid=999999&page=88&mobile=2">88</a>
      </body>
    </html>
    """#
    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=557752&mobile=2")),
        view: 1
    )

    #expect(ReaderHTMLParser.extractMaxView(from: html, request: request) == 4)
}

@Test func readerHTMLParserExtractsPageTitle() async throws {
    let html = "<html><head><title>测试标题 - 轻小说/译文区 - 百合会</title></head><body></body></html>"
    #expect(ReaderHTMLParser.extractPageTitle(from: html) == "测试标题 - 轻小说/译文区 - 百合会")
}

@Test func readerHTMLParserExtractsOnlyAuthorIDFromThreadLink() async throws {
    let html = #"""
    <html>
      <body>
        <a class="nav-more-item" href="forum.php?mod=viewthread&tid=557752&page=1&authorid=595655&mobile=2">只看楼主</a>
      </body>
    </html>
    """#
    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=557752&mobile=2")),
        view: 1
    )

    #expect(ReaderHTMLParser.extractOnlyAuthorID(from: html, request: request) == "595655")
}

@Test func chapterTitleNormalizerPreservesNonEmptyFirstLines() async throws {
    #expect(ReaderChapterTitleNormalizer.normalize("第1话 恋爱的开始") == "第1话 恋爱的开始")
    #expect(ReaderChapterTitleNormalizer.normalize("後記") == "後記")
    #expect(ReaderChapterTitleNormalizer.normalize("感谢翻译，收藏一波") == "感谢翻译，收藏一波")
    #expect(ReaderChapterTitleNormalizer.normalize("本帖最后由 xxx 于 2025-1-1 编辑") == "本帖最后由 xxx 于 2025-1-1 编辑")
}

@Test func readerTextTransformerConvertsTraditionalAndSimplified() async throws {
    #expect(ReaderTextTransformer.transform("戀上朋友的妹妹了 後記", mode: .simplified) == "恋上朋友的妹妹了 后记")
    #expect(ReaderTextTransformer.transform("恋上朋友的妹妹了 后记", mode: .traditional) == "戀上朋友的妹妹了 後記")
}

@Test func parseDocumentCarriesContentSourceAndChapterStats() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">第1话 恋爱的开始<br>正文</div>
        <div class="message">感谢翻译，收藏一波<br>评论</div>
      </body>
    </html>
    """#
    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=11&mobile=2")),
        view: 1
    )
    let document = try ReaderHTMLParser.parseDocument(html: html, request: request, contentSource: .authorFilteredPage)

    #expect(document.contentSource == .authorFilteredPage)
    #expect(document.retainedChapterCount == 2)
    #expect(document.filteredChapterCandidateCount == 0)
    let chapterTitles = document.segments.compactMap { segment -> String? in
        switch segment {
        case let .text(_, chapterTitle), let .image(_, chapterTitle):
            chapterTitle
        }
    }
    #expect(chapterTitles == ["第1话 恋爱的开始", "感谢翻译，收藏一波"])
}

@Test func repositoryTreatsLoginFavoritesPageAsNotAuthenticated() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let repository = YamiboRepository(
        client: YamiboClient(session: session, cookie: "sid=1", userAgent: "Test-UA")
    )

    StubURLProtocol.response = StubURLProtocolResponse(
        statusCode: 200,
        body: """
        <html>
          <head><title>登录 - 百合会 - 手机版 - Powered by Discuz!</title></head>
          <body class="pg_logging">
            <form id="member_login" action="member.php?mod=logging&action=login"></form>
          </body>
        </html>
        """
    )

    await #expect(throws: YamiboError.notAuthenticated) {
        _ = try await repository.fetchFavorites()
    }
}

@Test func readerPaginatorProducesChaptersForBothModes() async throws {
    let document = ReaderPageDocument(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2")),
        view: 1,
        maxView: 2,
        segments: [
            .text(String(repeating: "第一章内容。", count: 80), chapterTitle: "第一章"),
            .text(String(repeating: "第二章内容。", count: 80), chapterTitle: "第二章")
        ]
    )

    let paged = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(readingMode: .paged),
        layout: ReaderContainerLayout(width: 320, height: 568)
    )
    #expect(paged.pages.count >= 2)
    #expect(paged.chapters.count == 2)
    #expect(paged.chapters.first?.title == "第一章")
    #expect(paged.chapters.last?.title == "第二章")
    #expect((paged.chapters.last?.startIndex ?? 0) > 0)

    let vertical = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(readingMode: .vertical),
        layout: ReaderContainerLayout(width: 320, height: 568)
    )
    #expect(vertical.pages.count >= 2)
    #expect(vertical.chapters.first?.title == "第一章")
    #expect(vertical.chapters.last?.title == "第二章")
}

@Test func readerCacheStorePersistsAndDeletesPages() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ReaderCacheStore(baseDirectory: directory)
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2"))
    let document = ReaderPageDocument(
        threadURL: threadURL,
        view: 3,
        maxView: 5,
        resolvedAuthorID: "12",
        segments: [.text("正文", chapterTitle: "测试章")]
    )

    try await store.save(document)
    let loaded = await store.loadDocument(for: ReaderPageRequest(threadURL: threadURL, view: 3, authorID: "12"))
    #expect(loaded == document)
    #expect(await store.cachedViews(for: threadURL) == [3])

    try await store.deleteViews([3], for: threadURL)
    let deleted = await store.loadDocument(for: ReaderPageRequest(threadURL: threadURL, view: 3, authorID: "12"))
    #expect(deleted == nil)
}
