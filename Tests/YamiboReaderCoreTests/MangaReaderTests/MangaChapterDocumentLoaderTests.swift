import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Chapter Document Loader", .serialized)
struct MangaReaderTestsChapterDocumentLoader {
    @Test func loadsChapterDocumentFromAuthenticatedThreadHTML() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { request in
            #expect(request.value(forHTTPHeaderField: "Cookie") == "auth=1")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "TestAgent/1")
            #expect(request.url?.absoluteString.contains("page=1") == true)
            return MangaReaderDataTestResponse(html: """
            <html>
              <head><title>【作者】作品 第12话 - 中文百合漫画区 - 百合会</title></head>
              <body>
                <div id="postmessage_9001">
                  <div class="message">
                    <img zsrc="/images/700-1.jpg" />
                    <img src="https://img.example.com/700-2.png" />
                  </div>
                </div>
              </body>
            </html>
            """)
        }

        let client = YamiboClient(
            session: harness.session,
            cookie: "auth=1",
            userAgent: "TestAgent/1"
        )
        let loader = YamiboMangaChapterDocumentLoader(client: client)
        let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&page=5&authorid=42"))

        let document = try await loader.loadChapterDocument(at: url)
        let requestURL = try #require(harness.requests.first?.url?.absoluteString)

        #expect(document.tid == "700")
        #expect(document.ownerPostID == "9001")
        #expect(document.chapterTitle == "【作者】作品 第12话")
        #expect(requestURL.contains("tid=700"))
        #expect(requestURL.contains("page=1"))
        #expect(requestURL.contains("authorid=42") == false)
        #expect(document.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=700")
        #expect(document.imageURLs.map(\.absoluteString) == [
            "https://bbs.yamibo.com/images/700-1.jpg",
            "https://img.example.com/700-2.png"
        ])
    }

    @Test func loginPageThrowsNotAuthenticatedBeforeParsing() async throws {
        try await expectChapterDocumentError(
            html: #"<html><body class="pg_logging"><form id="member_login"></form></body></html>"#,
            expected: YamiboError.notAuthenticated
        )
    }

    @Test func floodControlThrowsFloodControlBeforeParsing() async throws {
        try await expectChapterDocumentError(
            html: "<html><body>防灌水机制已开启</body></html>",
            expected: YamiboError.floodControl
        )
    }

    @Test func missingImagesThrowsParsingFailure() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            MangaReaderDataTestResponse(html: """
            <html>
              <head><title>第1话</title></head>
              <body><div id="pid9001"><div class="message">no images</div></div></body>
            </html>
            """)
        }
        let loader = YamiboMangaChapterDocumentLoader(client: YamiboClient(session: harness.session))
        let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=701"))

        await #expect(throws: YamiboError.parsingFailed(context: L10n.string("context.current_page_not_manga_chapter"))) {
            _ = try await loader.loadChapterDocument(at: url)
        }
    }

    private func expectChapterDocumentError(html: String, expected: YamiboError) async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }

        harness.setHandler { _ in
            MangaReaderDataTestResponse(html: html)
        }
        let loader = YamiboMangaChapterDocumentLoader(client: YamiboClient(session: harness.session))
        let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=701"))

        await #expect(throws: expected) {
            _ = try await loader.loadChapterDocument(at: url)
        }
    }
}
