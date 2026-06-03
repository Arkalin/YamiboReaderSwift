import Foundation
import Testing
import XCTest
@testable import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#endif

private struct StubURLProtocolResponse {
    let statusCode: Int
    let body: String
}

private enum StubURLProtocolOutput {
    case response(StubURLProtocolResponse)
    case error(URLError)
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> StubURLProtocolOutput)? = defaultHandler()
    nonisolated(unsafe) static var tid28UnfilteredCachePolicy: URLRequest.CachePolicy?

    static func defaultHandler() -> (URLRequest) -> StubURLProtocolOutput {
        { request in
        let absolute = request.url?.absoluteString ?? ""

        if absolute.contains("mod=space"),
           absolute.contains("do=favorite") {
            return .response(
                StubURLProtocolResponse(
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
            )
        }

        if absolute.contains("mod=faq") {
            let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            if cookie.contains("missing-token=1") {
                return .response(
                    StubURLProtocolResponse(
                        statusCode: 200,
                        body: "<html><body>no token</body></html>"
                    )
                )
            }
            return .response(
                StubURLProtocolResponse(
                    statusCode: 200,
                    body: #"<html><body><input name="formhash" value="abc12345" /></body></html>"#
                )
            )
        }

        if absolute.contains("ac=favorite"),
           absolute.contains("op=delete") {
            let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            if cookie.contains("favorite-delete-success=1")
                || body.contains("favorite%5B%5D=55")
                || body.contains("favorite[]=55") {
                return .response(
                    StubURLProtocolResponse(
                        statusCode: 200,
                        body: "<html><body>操作成功</body></html>"
                    )
                )
            }
            return .response(
                StubURLProtocolResponse(
                    statusCode: 200,
                    body: "<html><body>操作失败</body></html>"
                )
            )
        }

        if absolute.contains("tid=22") {
            return .error(URLError(.notConnectedToInternet))
        }

        if absolute.contains("tid=23") {
            let body: String
            if absolute.contains("authorid=42") {
                body = "<html><body><div class=\"message\">只看楼主新缓存</div></body></html>"
            } else {
                body = "<html><body><div class=\"message\">全部回复新缓存</div></body></html>"
            }
            return .response(StubURLProtocolResponse(statusCode: 200, body: body))
        }

        if absolute.contains("tid=24") {
            if absolute.contains("page=2") {
                return .error(URLError(.networkConnectionLost))
            }
            let page = absolute.contains("page=3") ? "3" : "1"
            let body = "<html><body><div class=\"message\">只看楼主缓存页\(page)</div></body></html>"
            return .response(StubURLProtocolResponse(statusCode: 200, body: body))
        }

        if absolute.contains("tid=25") {
            return .response(
                StubURLProtocolResponse(
                    statusCode: 200,
                    body: """
                    <html><body>
                      <div id="pid41257246">
                        <div class="message">新解析章节<br>新正文</div>
                      </div>
                    </body></html>
                    """
                )
            )
        }

        if absolute.contains("action=viewratings"),
           absolute.contains("tid=26"),
           absolute.contains("pid=2601") {
            return .response(
                StubURLProtocolResponse(
                    statusCode: 200,
                    body: """
                    <html><body>
                      <ul class="post_box cl">
                        <li class="flex-box mli">
                          <div><span class="z">积分</span></div>
                          <div><span class="z">用户名</span></div>
                          <div><span class="y">时间</span></div>
                        </li>
                        <li class="flex-box mli">
                          <div><span class="z">积分 +2 点</span></div>
                          <div><span class="z">读者甲</span></div>
                          <div><span class="y">2026-5-6 00:10</span></div>
                        </li>
                        <li class="flex-box mli"><div><span class="z">好萌好萌好萌</span></div></li>
                        <li class="flex-box mli">
                          <div><span class="z">积分 +5 点</span></div>
                          <div><span class="z">读者乙</span></div>
                          <div><span class="y">2024-11-23 11:15</span></div>
                        </li>
                        <li class="flex-box mli"><div><span class="z">完整评分理由</span></div></li>
                      </ul>
                    </body></html>
                    """
                )
            )
        }

        if absolute.contains("tid=26") {
            let body = absolute.contains("authorid=42")
                ? """
                <html><body>
                  <div id="pid2601">
                    <div class="message">episode 16<br>正文</div>
                    <div id="ratelog_2601">
                      <ul class="post_box cl">
                        <li class="flex-box mli p0">
                          <div>参与人数</div><div>积分</div><div>理由</div>
                        </li>
                        <li class="flex-box mli p0">
                          <div><a>读者甲</a></div><div> + 2</div><div>有效评分理由</div>
                        </li>
                        <li class="flex-box mli p0">
                          <div><a href="forum.php?mod=misc&amp;action=viewratings&amp;tid=26&amp;pid=2601&amp;mobile=2" title="查看全部评分">查看全部评分</a></div>
                        </li>
                      </ul>
                    </div>
                  </div>
                </body></html>
                """
                : """
                <html><body>
                  <div id="pid9999"><div class="message">普通第 2 页没有目标楼层</div></div>
                </body></html>
                """
            return .response(StubURLProtocolResponse(statusCode: 200, body: body))
        }

        if absolute.contains("tid=27") {
            let body = absolute.contains("authorid=42")
                ? """
                <html><body>
                  <div class="plc cl" id="pid2701">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第一章<br>正文</div>
                  </div>
                  <div class="plc cl" id="pid2703">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第二章<br>正文</div>
                  </div>
                </body></html>
                """
                : """
                <html><body>
                  <div class="plc cl" id="pid2701">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第一章<br>正文</div>
                  </div>
                  <div class="plc cl" id="pid2702">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=77&mobile=2">读者甲</a></li></ul>
                    <div class="message">楼间回复</div>
                  </div>
                  <div class="plc cl" id="pid2703">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第二章<br>正文</div>
                  </div>
                </body></html>
                """
            return .response(StubURLProtocolResponse(statusCode: 200, body: body))
        }

        if absolute.contains("tid=28") || absolute.contains("ptid=28") {
            if !absolute.contains("authorid=42") {
                tid28UnfilteredCachePolicy = request.cachePolicy
            }
            let body = absolute.contains("authorid=42")
                ? """
                <html><body>
                  <div class="plc cl" id="pid2801">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第一章<br>正文</div>
                  </div>
                </body></html>
                """
                : """
                <html><body>
                  <div class="plc cl" id="pid2801">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第一章<br>正文</div>
                  </div>
                  <div class="plc cl" id="pid2802">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=77&mobile=2">读者甲</a></li></ul>
                    <div class="message">楼间回复</div>
                  </div>
                </body></html>
                """
            return .response(StubURLProtocolResponse(statusCode: 200, body: body))
        }

        if absolute.contains("tid=29") || absolute.contains("ptid=29") {
            let body: String
            if absolute.contains("authorid=42") {
                body = """
                <html><body>
                  <div class="plc cl" id="pid2901">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第一章<br>正文</div>
                  </div>
                </body></html>
                """
            } else if absolute.contains("mod=redirect"), absolute.contains("pid=2901") {
                body = """
                <html><body>
                  <div class="plc cl" id="pid2901">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=42&mobile=2">楼主</a></li></ul>
                    <div class="message">第一章<br>正文</div>
                  </div>
                  <div class="plc cl" id="pid2902">
                    <ul class="authi"><li class="mtit"><a href="home.php?mod=space&uid=77&mobile=2">读者甲</a></li></ul>
                    <div class="message">真实全帖页回复</div>
                  </div>
                  <div class="pg"><strong>4</strong><a href="forum.php?mod=viewthread&amp;tid=29&amp;page=5&amp;mobile=2">5</a></div>
                </body></html>
                """
            } else {
                body = """
                <html><body>
                  <div class="plc cl" id="pid9999">
                    <div class="message">错误全帖页</div>
                  </div>
                </body></html>
                """
            }
            return .response(StubURLProtocolResponse(statusCode: 200, body: body))
        }

        return .error(URLError(.badServerResponse))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let output = Self.handler?(request)
        guard let output else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch output {
        case let .response(response):
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html; charset=utf-8"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(response.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .error(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
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

@Test func readerHTMLParserPreservesInlineImagePositionWithinMessage() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">
          第一章 相遇<br>
          这里是前文。
          <img src="images/first.jpg" />
          这里是后文。
          <img file="images/second.jpg" src="images/fallback.jpg" />
          这里是尾声。
        </div>
      </body>
    </html>
    """#

    let parsed = ReaderHTMLParser.parseSegments(from: html)

    #expect(parsed.segments == [
        .text("第一章 相遇\n这里是前文。", chapterTitle: "第一章 相遇"),
        .image(try #require(URL(string: "https://bbs.yamibo.com/images/first.jpg")), chapterTitle: "第一章 相遇"),
        .text("这里是后文。", chapterTitle: "第一章 相遇"),
        .image(try #require(URL(string: "https://bbs.yamibo.com/images/second.jpg")), chapterTitle: "第一章 相遇"),
        .text("这里是尾声。", chapterTitle: "第一章 相遇")
    ])
}

@Test func readerHTMLParserPreservesNestedMessageContent() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">
          <div class="wrapper">
            序章<br>这里是开头。
            <div class="nested">
              这里是被嵌套的正文。
              <img src="images/nested.jpg" />
            </div>
          </div>
        </div>
      </body>
    </html>
    """#

    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=2&mobile=2")),
        view: 1
    )
    let document = try ReaderHTMLParser.parseDocument(html: html, request: request)

    #expect(document.segments.count == 2)

    guard case let .text(text, chapterTitle) = document.segments[0] else {
        Issue.record("Expected the first segment to be text")
        return
    }

    #expect(chapterTitle == "序章")
    #expect(text.contains("这里是开头。"))
    #expect(text.contains("这里是被嵌套的正文。"))
    #expect(document.segments[1] == .image(try #require(URL(string: "https://bbs.yamibo.com/images/nested.jpg")), chapterTitle: "序章"))
}

@Test func readerHTMLParserKeepsMessageOrderAndDeduplicatesSharedSelectors() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message" id="postmessage_1">第一章<br>正文一</div>
        <div class="message">第二章<br>正文二</div>
      </body>
    </html>
    """#

    let parsed = ReaderHTMLParser.parseSegments(from: html)

    #expect(parsed.segments.count == 2)
    #expect(parsed.segments[0] == .text("第一章\n正文一", chapterTitle: "第一章"))
    #expect(parsed.segments[1] == .text("第二章\n正文二", chapterTitle: "第二章"))
}

@Test func readerHTMLParserSupportsPostmessageWithoutMessageClass() async throws {
    let html = #"""
    <html>
      <body>
        <table><tr><td id="postmessage_9">尾声<br>只有 postmessage 也要解析</td></tr></table>
      </body>
    </html>
    """#

    let parsed = ReaderHTMLParser.parseSegments(from: html)

    #expect(parsed.segments == [.text("尾声\n只有 postmessage 也要解析", chapterTitle: "尾声")])
}

@Test func readerHTMLParserExtractsImagesFromPreferredAttributesAndSkipsSmiley() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">
          插图回<br>
          <img zoomfile="images/zoom.jpg" src="images/fallback-a.jpg" />
          <img file="images/file.jpg" src="images/fallback-b.jpg" />
          <img src="images/plain.jpg" />
          <img src="images/smiley/icon.png" />
        </div>
      </body>
    </html>
    """#

    let parsed = ReaderHTMLParser.parseSegments(from: html)

    #expect(parsed.segments.count == 4)
    #expect(parsed.segments[0] == .text("插图回", chapterTitle: "插图回"))
    #expect(parsed.segments[1] == .image(try #require(URL(string: "https://bbs.yamibo.com/images/zoom.jpg")), chapterTitle: "插图回"))
    #expect(parsed.segments[2] == .image(try #require(URL(string: "https://bbs.yamibo.com/images/file.jpg")), chapterTitle: "插图回"))
    #expect(parsed.segments[3] == .image(try #require(URL(string: "https://bbs.yamibo.com/images/plain.jpg")), chapterTitle: "插图回"))
}

@Test func readerHTMLParserExtractsMaxViewFromSameThreadLinksOnly() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message">正文里提到第 315 页和 9494 次浏览</div>
        <select id="dumppage">
          <option value="1">1/4</option>
          <option value="4">4/4</option>
        </select>
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
        <a href="forum.php?mod=viewthread&tid=999999&page=1&authorid=1&mobile=2">别的帖子</a>
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

@Test func readerHTMLParserHandlesMalformedHTML() async throws {
    let html = #"""
    <html>
      <body>
        <div class="message"><div>序章<br>这段 HTML 没有正常闭合
      </body>
    </html>
    """#

    let parsed = ReaderHTMLParser.parseSegments(from: html)

    #expect(parsed.segments == [.text("序章\n这段 HTML 没有正常闭合", chapterTitle: "序章")])
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

@Test func readerHTMLParserPreservesChapterBodiesInDirectoryStyleThread() async throws {
    let html = #"""
    <html>
      <head><title>测试书 - 百合会</title></head>
      <body>
        <div class="message">
          目录：<br>
          序章<br>
          1 如弃猫般的她<br>
          译者后记
        </div>
        <div class="message">
          <div class="chapter-shell">
            序章<br>
            我肯定没有不惜伤害他人也要以自己的恋情为优先的勇气。
            <blockquote>
              所以，不是什么道德伦理之类的原因，而是我认为自己绝对不会不忠。
            </blockquote>
          </div>
        </div>
        <div class="message">
          1 如弃猫般的她<br>
          「呐，雪，车站往哪边走？」<br>
          <div class="nested">在涩谷街上，被唤作雪的我指着东北方回答询问的声音。</div>
        </div>
        <div class="message">
          译者后记<br>
          首先感谢看到这的各位，加分及留言一直都给了我不少翻下去的动力。
        </div>
      </body>
    </html>
    """#

    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=557752&mobile=2")),
        view: 1
    )
    let document = try ReaderHTMLParser.parseDocument(html: html, request: request)

    let chapterTitles = document.segments.compactMap { segment -> String? in
        switch segment {
        case let .text(_, chapterTitle), let .image(_, chapterTitle):
            chapterTitle
        }
    }

    #expect(chapterTitles == ["目录：", "序章", "1 如弃猫般的她", "译者后记"])
    #expect(document.segments.contains {
        guard case let .text(text, chapterTitle) = $0 else { return false }
        return chapterTitle == "序章" && text.contains("绝对不会不忠")
    })
    #expect(document.segments.contains {
        guard case let .text(text, chapterTitle) = $0 else { return false }
        return chapterTitle == "1 如弃猫般的她" && text.contains("在涩谷街上")
    })
    #expect(document.segments.contains {
        guard case let .text(text, chapterTitle) = $0 else { return false }
        return chapterTitle == "译者后记" && text.contains("翻下去的动力")
    })
}

@Test func repositoryTreatsLoginFavoritesPageAsNotAuthenticated() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let repository = YamiboRepository(
        client: YamiboClient(session: session, cookie: "sid=1; favorite-delete-success=1", userAgent: "Test-UA")
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

@Test func readerPaginatorAccountsForFontFamilyAndCharacterSpacing() async throws {
    let document = ReaderPageDocument(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=44&mobile=2")),
        view: 1,
        maxView: 1,
        segments: [
            .text(String(repeating: "这是一个很长的段落。", count: 120), chapterTitle: "第一章")
        ]
    )

    let compact = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(
            fontScale: 1.0,
            fontFamily: .systemSans,
            lineHeightScale: 1.45,
            characterSpacingScale: 0,
            readingMode: .paged
        ),
        layout: ReaderContainerLayout(width: 320, height: 568)
    )
    let expanded = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(
            fontScale: 1.0,
            fontFamily: .systemSerif,
            lineHeightScale: 1.45,
            characterSpacingScale: 0.12,
            readingMode: .paged
        ),
        layout: ReaderContainerLayout(width: 320, height: 568)
    )
    let verticalCompact = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(
            fontScale: 1.0,
            fontFamily: .systemSans,
            lineHeightScale: 1.45,
            characterSpacingScale: 0,
            readingMode: .vertical
        ),
        layout: ReaderContainerLayout(width: 320, height: 568)
    )
    let verticalExpanded = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(
            fontScale: 1.0,
            fontFamily: .rounded,
            lineHeightScale: 1.45,
            characterSpacingScale: 0.12,
            readingMode: .vertical
        ),
        layout: ReaderContainerLayout(width: 320, height: 568)
    )

    #expect(expanded.pages.count >= compact.pages.count)
    #expect(verticalExpanded.pages.count >= verticalCompact.pages.count)
}

@Test func readerContainerLayoutComputesReadableFrameFromSafeAreaAndChrome() async throws {
    let layout = ReaderContainerLayout(
        containerSize: CGSize(width: 390, height: 844),
        safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
        contentInsets: ReaderLayoutInsets(top: 0, leading: 20, bottom: 24, trailing: 20),
        chromeInsets: ReaderLayoutInsets(top: 72, bottom: 96),
        readingMode: .paged
    )

    #expect(layout.readableFrame.minX == 20)
    #expect(layout.readableFrame.minY == 131)
    #expect(layout.readableFrame.width == 350)
    #expect(layout.readableFrame.height == 559)
}

@Test func readerPaginatorUsesReadableFrameForPagedTextRanges() async throws {
    let text = Array(repeating: "第一段内容。\n第二段内容 with English words and spacing。\nかな混じりの文章。", count: 28).joined(separator: "\n\n")
    let document = ReaderPageDocument(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=55&mobile=2")),
        view: 1,
        maxView: 1,
        segments: [
            .text(text, chapterTitle: "第一章")
        ]
    )

    let roomyLayout = ReaderContainerLayout(
        containerSize: CGSize(width: 390, height: 844),
        safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
        contentInsets: ReaderLayoutInsets(leading: 20, trailing: 20),
        chromeInsets: .zero,
        readingMode: .paged
    )
    let constrainedLayout = ReaderContainerLayout(
        containerSize: CGSize(width: 390, height: 844),
        safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
        contentInsets: ReaderLayoutInsets(leading: 20, trailing: 20),
        chromeInsets: ReaderLayoutInsets(top: 90, bottom: 120),
        readingMode: .paged
    )

    let roomy = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(readingMode: .paged),
        layout: roomyLayout
    )
    let constrained = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(readingMode: .paged),
        layout: constrainedLayout
    )

    #expect(constrained.pages.count >= roomy.pages.count)

    let textPages = constrained.pages.compactMap { page -> ReaderRenderedPage? in
        page.blocks.contains { if case .text = $0 { return true } else { return false } } ? page : nil
    }
    #expect(textPages.dropLast().allSatisfy { page in
        page.segmentEndOffset - page.segmentStartOffset > 20
    })
    #expect(textPages.first?.segmentStartOffset == 0)
    for index in 1..<textPages.count {
        let previousEnd = textPages[index - 1].segmentEndOffset
        let nextStart = textPages[index].segmentStartOffset
        #expect(nextStart >= previousEnd)
        let gap = String(text.dropFirst(previousEnd).prefix(max(nextStart - previousEnd, 0)))
        #expect(gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    #expect(textPages.last?.segmentEndOffset == text.count)
}

@Test func readerPaginatorMarksOnlyRealParagraphStartsForFirstLineIndent() async throws {
    let text = String(repeating: "这是一个会横跨多个分页的长段落。", count: 160)
    let document = ReaderPageDocument(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=57&mobile=2")),
        view: 1,
        maxView: 1,
        segments: [.text(text, chapterTitle: "第一章")]
    )

    let pagination = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(
            indentsParagraphFirstLine: true,
            readingMode: .paged
        ),
        layout: ReaderContainerLayout(
            containerSize: CGSize(width: 390, height: 260),
            contentInsets: ReaderLayoutInsets(leading: 20, trailing: 20),
            readingMode: .paged
        )
    )
    let textBlocks = pagination.pages.compactMap(\.blocks.first)

    #expect(textBlocks.count > 1)
    #expect(textBlocks.first?.startsAtParagraphBoundary == true)
    #expect(textBlocks.dropFirst().allSatisfy { $0.startsAtParagraphBoundary == false })
}

@Test func readerPaginatorPacksShortAdjacentTextSegmentsInPagedMode() async throws {
    let document = ReaderPageDocument(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=56&mobile=2")),
        view: 1,
        maxView: 1,
        segments: [
            .text("人", chapterTitle: "第一章"),
            .text("在车站前停下脚步。", chapterTitle: "第一章"),
            .text("她抬头看向雪后的街灯，终于松了一口气。", chapterTitle: "第一章")
        ]
    )

    let pagination = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(readingMode: .paged),
        layout: ReaderContainerLayout(
            containerSize: CGSize(width: 390, height: 844),
            safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
            contentInsets: ReaderLayoutInsets(leading: 20, trailing: 20),
            readingMode: .paged
        )
    )

    #expect(pagination.pages.count == 1)
    #expect(pagination.pages.first?.blocks.count == 3)
}

@Test func novelTextLayoutProducesPagedAndVerticalRangesAtModuleSeam() {
    let text = String(repeating: "这是用于模块边界测试的正文。", count: 120)
    let layout = ReaderContainerLayout(width: 320, height: 568)
    let settings = ReaderAppearanceSettings(readingMode: .paged)

    let pagedSlices = NovelTextLayout.renderedTextSlices(
        text,
        chapterTitle: "第一章",
        settings: settings,
        layout: layout,
        readingMode: .paged
    )
    let verticalSlices = NovelTextLayout.renderedTextSlices(
        text,
        chapterTitle: "第一章",
        settings: ReaderAppearanceSettings(readingMode: .vertical),
        layout: layout,
        readingMode: .vertical
    )

    #expect(!pagedSlices.isEmpty)
    #expect(!verticalSlices.isEmpty)
    #expect(pagedSlices.first?.startOffset == 0)
    #expect(pagedSlices.last?.endOffset == text.count)
    #expect(verticalSlices.first?.startOffset == 0)
    #expect(verticalSlices.last?.endOffset == text.count)
    #expect(
        NovelTextLayout.measuredTextHeight(
            text,
            chapterTitle: "第一章",
            settings: settings,
            width: layout.readableFrame.width
        ) > 0
    )
}

@Test func readerPaginatorUsesNovelTextLayoutSeamForSingleTextSegmentRanges() async throws {
    let text = String(repeating: "分页边界应来自 Novel Text Layout。", count: 100)
    let document = ReaderPageDocument(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=58&mobile=2")),
        view: 1,
        maxView: 1,
        segments: [.text(text, chapterTitle: "第一章")]
    )
    let settings = ReaderAppearanceSettings(readingMode: .paged)
    let layout = ReaderContainerLayout(width: 320, height: 568)

    let expectedSlices = NovelTextLayout.renderedTextSlices(
        text,
        chapterTitle: "第一章",
        settings: settings,
        layout: layout,
        readingMode: .paged
    )
    let pagination = ReaderPaginator.paginate(document: document, settings: settings, layout: layout)

    #expect(pagination.pages.map(\.segmentStartOffset) == expectedSlices.map(\.startOffset))
    #expect(pagination.pages.map(\.segmentEndOffset) == expectedSlices.map(\.endOffset))
}

@Test func readerParagraphIndentPlannerKeepsContinuationFirstParagraphUnindentedOnly() {
    let text = "续页正文。\n\n新段落正文。\n第三段正文。"
    let ranges = ReaderParagraphIndentPlanner.indentedParagraphRangesAfterFirst(in: text)
    let substrings = ranges.map { String(text[$0]) }

    #expect(substrings == ["\n\n新段落正文。", "\n第三段正文。"])
}

#if canImport(UIKit)
@Test func readerAttributedTextFactoryUsesParagraphStyleForTitleAndBody() throws {
    let pointSize = 24.0
    let attributedText = ReaderAttributedTextFactory.makeAttributedText(
        text: "第一章\n第一段正文。\n\n第二段正文。",
        chapterTitle: "第一章",
        settings: ReaderAppearanceSettings(lineHeightScale: 1.6),
        baseFontSize: pointSize
    )
    let titleStyle = try #require(
        attributedText.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
    )
    let bodyStyle = try #require(
        attributedText.attribute(
            .paragraphStyle,
            at: "第一章\n".count,
            effectiveRange: nil
        ) as? NSParagraphStyle
    )

    #expect(titleStyle.lineSpacing == 9.6)
    #expect(bodyStyle.lineSpacing == 9.6)
}

@Test func readerAttributedTextFactoryIndentsBodyButNotTitleOrContinuationSlices() throws {
    let pointSize = 24.0
    let settings = ReaderAppearanceSettings(indentsParagraphFirstLine: true)
    let paragraphStart = ReaderAttributedTextFactory.makeAttributedText(
        text: "第一章\n第一段正文。",
        chapterTitle: "第一章",
        startsAtParagraphBoundary: true,
        settings: settings,
        baseFontSize: pointSize
    )
    let continuation = ReaderAttributedTextFactory.makeAttributedText(
        text: "续页正文。",
        chapterTitle: "第一章",
        startsAtParagraphBoundary: false,
        settings: settings,
        baseFontSize: pointSize
    )
    let titleStyle = try #require(
        paragraphStart.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    )
    let bodyStyle = try #require(
        paragraphStart.attribute(.paragraphStyle, at: "第一章\n".count, effectiveRange: nil) as? NSParagraphStyle
    )
    let continuationStyle = try #require(
        continuation.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    )

    #expect(titleStyle.firstLineHeadIndent == 0)
    #expect(bodyStyle.firstLineHeadIndent == 48)
    #expect(continuationStyle.firstLineHeadIndent == 0)
}

@Test func readerAttributedTextFactoryIndentsLaterParagraphsInContinuationSlices() throws {
    let pointSize = 24.0
    let attributedText = ReaderAttributedTextFactory.makeAttributedText(
        text: "续页正文。\n\n新段落正文。",
        chapterTitle: "第一章",
        startsAtParagraphBoundary: false,
        settings: ReaderAppearanceSettings(indentsParagraphFirstLine: true),
        baseFontSize: pointSize
    )
    let continuationStyle = try #require(
        attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    )
    let newParagraphStyle = try #require(
        attributedText.attribute(.paragraphStyle, at: "续页正文。\n\n".count, effectiveRange: nil) as? NSParagraphStyle
    )

    #expect(continuationStyle.firstLineHeadIndent == 0)
    #expect(newParagraphStyle.firstLineHeadIndent == 48)
}
#endif

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
    #expect(await store.cachedViews(for: threadURL, authorID: "12", contentSource: .authorFilteredPage) == [3])

    try await store.deleteViews([3], for: threadURL, authorID: "12", contentSource: .authorFilteredPage)
    let deleted = await store.loadDocument(for: ReaderPageRequest(threadURL: threadURL, view: 3, authorID: "12"))
    #expect(deleted == nil)
}

@Test func readerCacheStoreSeparatesAuthorFilteredAndUnfilteredVariants() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ReaderCacheStore(baseDirectory: directory)
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=21&mobile=2"))
    let unfiltered = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 3,
        contentSource: .fallbackUnfilteredPage,
        segments: [.text("全部回复正文", chapterTitle: "第一章")]
    )
    let authorFiltered = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 3,
        resolvedAuthorID: "42",
        contentSource: .authorFilteredPage,
        segments: [.text("只看楼主正文", chapterTitle: "第一章")]
    )

    try await store.save(unfiltered)
    try await store.save(authorFiltered)

    let loadedUnfiltered = await store.loadDocument(
        for: ReaderPageRequest(threadURL: threadURL, view: 1),
        contentSource: .fallbackUnfilteredPage
    )
    let loadedAuthorFiltered = await store.loadDocument(
        for: ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "42"),
        contentSource: .authorFilteredPage
    )

    #expect(loadedUnfiltered?.segments == unfiltered.segments)
    #expect(loadedAuthorFiltered?.segments == authorFiltered.segments)
    #expect(await store.cachedViews(for: threadURL, authorID: nil, contentSource: .fallbackUnfilteredPage) == [1])
    #expect(await store.cachedViews(for: threadURL, authorID: "42", contentSource: .authorFilteredPage) == [1])

    try await store.deleteViews([1], for: threadURL, authorID: "42", contentSource: .authorFilteredPage)

    let deletedAuthorFiltered = await store.loadDocument(
        for: ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "42"),
        contentSource: .authorFilteredPage
    )
    let preservedUnfiltered = await store.loadDocument(
        for: ReaderPageRequest(threadURL: threadURL, view: 1),
        contentSource: .fallbackUnfilteredPage
    )

    #expect(deletedAuthorFiltered == nil)
    #expect(preservedUnfiltered?.segments == unfiltered.segments)
}

@Test func readerRepositoryDoesNotCrossHitFilteredCacheWhenOffline() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheStore = ReaderCacheStore(baseDirectory: directory)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: cacheStore
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=22&mobile=2"))
    let authorFiltered = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 2,
        resolvedAuthorID: "42",
        contentSource: .authorFilteredPage,
        segments: [.text("只看楼主缓存", chapterTitle: "第一章")]
    )
    try await cacheStore.save(authorFiltered)

    await #expect(throws: YamiboError.offline) {
        _ = try await repository.loadPage(ReaderPageRequest(threadURL: threadURL, view: 1))
    }

    let authorHit = try await repository.loadPage(ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "42"))
    #expect(authorHit.segments == authorFiltered.segments)
}

@Test func readerRepositoryRefreshesOnlyCurrentVariantCache() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheStore = ReaderCacheStore(baseDirectory: directory)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: cacheStore
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=23&mobile=2"))
    let unfiltered = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 2,
        contentSource: .fallbackUnfilteredPage,
        segments: [.text("全部回复旧缓存", chapterTitle: "第一章")]
    )
    let authorFiltered = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 2,
        resolvedAuthorID: "42",
        contentSource: .authorFilteredPage,
        segments: [.text("只看楼主旧缓存", chapterTitle: "第一章")]
    )
    try await cacheStore.save(unfiltered)
    try await cacheStore.save(authorFiltered)

    try await repository.refreshCachedViews(
        [1],
        for: threadURL,
        authorID: "42",
        contentSource: .authorFilteredPage
    )

    let refreshedAuthorFiltered = await cacheStore.loadDocument(
        for: ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "42"),
        contentSource: .authorFilteredPage
    )
    let preservedUnfiltered = await cacheStore.loadDocument(
        for: ReaderPageRequest(threadURL: threadURL, view: 1),
        contentSource: .fallbackUnfilteredPage
    )

    let refreshedText = refreshedAuthorFiltered?.segments.compactMap { segment -> String? in
        if case let .text(text, _) = segment { return text }
        return nil
    }.first
    let preservedText = preservedUnfiltered?.segments.compactMap { segment -> String? in
        if case let .text(text, _) = segment { return text }
        return nil
    }.first

    #expect(refreshedText == "只看楼主新缓存")
    #expect(preservedText == "全部回复旧缓存")
}

@Test func readerRepositoryCachesViewsSequentiallyAndSkipsFailures() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheStore = ReaderCacheStore(baseDirectory: directory)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: cacheStore
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=24&mobile=2"))

    let result = await repository.cacheViews(
        [1, 2, 3],
        for: threadURL,
        authorID: "42",
        contentSource: .authorFilteredPage
    )

    #expect(result.completedViews == [1, 3])
    #expect(result.failedViews == [2])
    #expect(!result.wasCancelled)
    #expect(await cacheStore.cachedViews(for: threadURL, authorID: "42", contentSource: .authorFilteredPage) == [1, 3])
    #expect(await cacheStore.cachedViews(for: threadURL, authorID: nil, contentSource: .fallbackUnfilteredPage).isEmpty)
}

@Test func readerRepositoryRefreshesLegacyCacheMissingChapterCommentSources() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheStore = ReaderCacheStore(baseDirectory: directory)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: cacheStore
    )
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=25&mobile=2"))
    let legacyDocument = ReaderPageDocument(
        threadURL: threadURL,
        view: 1,
        maxView: 1,
        resolvedAuthorID: "42",
        contentSource: .authorFilteredPage,
        retainedChapterCount: 1,
        segments: [.text("旧缓存章节\n旧正文", chapterTitle: "旧缓存章节")]
    )
    try await cacheStore.save(legacyDocument)

    let loaded = try await repository.loadPage(ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "42"))

    #expect(loaded.segments == [.text("新解析章节\n新正文", chapterTitle: "新解析章节")])
    #expect(loaded.source(forSegmentIndex: 0)?.ownerPostID == "41257246")
}

@Test func readerRepositoryLoadsChapterCommentsFromAuthorFilteredPageWhenTargetHasAuthorID() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: ReaderCacheStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true))
    )
    let target = ReaderChapterCommentTarget(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=26&mobile=2")),
        view: 2,
        ownerPostID: "2601",
        title: "episode 16",
        authorID: "42"
    )

    let page = try await repository.loadChapterComments(for: target)

    #expect(page.comments.map(\.body) == ["完整评分理由"])
}

@Test func readerRepositoryLoadsSamePageRepliesFromUnfilteredPageForAuthorFilteredTarget() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: ReaderCacheStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true))
    )
    let target = ReaderChapterCommentTarget(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?authorid=42&mod=viewthread&tid=27&mobile=2")),
        view: 2,
        ownerPostID: "2701",
        title: "第一章",
        authorID: "42"
    )

    let page = try await repository.loadChapterComments(for: target)

    #expect(page.comments.map(\.source) == [.reply])
    #expect(page.comments.map(\.authorName) == ["读者甲"])
    #expect(page.comments.map(\.body) == ["楼间回复"])
    #expect(page.isBoundaryClosed == true)
    #expect(page.nextView == nil)
}

@Test func readerRepositoryReloadsUnfilteredRepliesIgnoringURLCache() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: ReaderCacheStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true))
    )
    let target = ReaderChapterCommentTarget(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?authorid=42&mod=viewthread&tid=28&mobile=2")),
        view: 2,
        ownerPostID: "2801",
        title: "第一章",
        authorID: "42"
    )
    StubURLProtocol.tid28UnfilteredCachePolicy = nil

    let page = try await repository.loadChapterComments(for: target)

    #expect(page.comments.map(\.body) == ["楼间回复"])
    #expect(StubURLProtocol.tid28UnfilteredCachePolicy == .reloadIgnoringLocalCacheData)
}

@Test func readerRepositoryFindsRealUnfilteredPageForAuthorFilteredChapterComments() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let repository = ReaderRepository(
        client: YamiboClient(session: session, cookie: "sid=reader", userAgent: "Test-UA"),
        cacheStore: ReaderCacheStore(baseDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true))
    )
    let target = ReaderChapterCommentTarget(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?authorid=42&mod=viewthread&tid=29&mobile=2")),
        view: 2,
        ownerPostID: "2901",
        title: "第一章",
        authorID: "42"
    )

    let page = try await repository.loadChapterComments(for: target)

    #expect(page.comments.map(\.body) == ["真实全帖页回复"])
    #expect(page.nextView == 5)
}

final class YamiboRepositoryDeleteTests: XCTestCase {
    func testDeletesFavoriteUsingFormhashAndFavoriteID() async throws {
        let repository = makeRepository(cookie: "sid=1; favorite-delete-success=1")
        try await repository.deleteFavorite(remoteFavoriteID: "55")
    }

    func testThrowsWhenDeleteFormhashIsMissing() async {
        let repository = makeRepository(cookie: "sid=1; missing-token=1")

        do {
            try await repository.deleteFavorite(remoteFavoriteID: "55")
            XCTFail("Expected missingFavoriteDeleteToken")
        } catch let error as YamiboError {
            XCTAssertEqual(error, .missingFavoriteDeleteToken)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThrowsWhenDeleteResponseIsFailure() async {
        let repository = makeRepository(cookie: "sid=1")

        do {
            try await repository.deleteFavorite(remoteFavoriteID: "999")
            XCTFail("Expected favoriteDeleteFailed")
        } catch let error as YamiboError {
            XCTAssertEqual(error, .favoriteDeleteFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeRepository(cookie: String) -> YamiboRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return YamiboRepository(
            client: YamiboClient(session: session, cookie: cookie, userAgent: "Test-UA")
        )
    }
}
