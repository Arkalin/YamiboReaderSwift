import Foundation
import Testing
@testable import YamiboReaderCore

@Test func readerDocumentCarriesOwnerPostIDToRenderedPages() throws {
    let html = """
    <html><body>
      <div class="t_f" id="postmessage_100">第一章<br>正文</div>
    </body></html>
    """
    let request = ReaderPageRequest(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&mobile=2")),
        view: 3,
        authorID: "7"
    )

    let document = try ReaderHTMLParser.parseDocument(
        html: html,
        request: request,
        contentSource: .authorFilteredPage
    )
    let pagination = ReaderPaginator.paginate(
        document: document,
        settings: ReaderAppearanceSettings(),
        layout: ReaderContainerLayout(width: 390, height: 844)
    )

    #expect(pagination.pages.first?.chapterCommentTarget?.ownerPostID == "100")
    #expect(pagination.pages.first?.chapterCommentTarget?.view == 3)
    #expect(pagination.pages.first?.chapterCommentTarget?.title == "第一章")
}

@Test func chapterCommentsParserReadsOwnerPostCommentsAndFilteredRatings() throws {
    let html = """
    <html><body>
      <div id="postlist">
        <div class="pcb">
          <div class="t_f" id="postmessage_100">第一章<br>正文</div>
          <div id="comment_100" class="cm">
            <div class="pstl xs1 cl">
              <div class="psta vm"><a class="xi2 xw1">读者甲</a></div>
              <div class="psti">这章很好 <span class="xg1">发表于 2026-5-1 12:00</span></div>
            </div>
          </div>
          <dl id="ratelog_100" class="rate">
            <dd>
              <table>
                <tbody class="ratl_l">
                  <tr>
                    <td><a>读者乙</a></td><td class="xi1"> + 1</td><td class="xg1">我很赞同</td>
                  </tr>
                  <tr>
                    <td><a>读者丙</a></td><td class="xi1"> + 5</td><td class="xg1">这期神了</td>
                  </tr>
                  <tr>
                    <td><a>读者丁</a></td><td class="xi1"> + 1</td><td class="xg1">   </td>
                  </tr>
                </tbody>
              </table>
            </dd>
          </dl>
        </div>
      </div>
    </body></html>
    """
    let target = ReaderChapterCommentTarget(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&mobile=2")),
        view: 3,
        ownerPostID: "100",
        title: "第一章"
    )

    let page = try ChapterCommentsHTMLParser.parseInitialPage(html: html, target: target)

    #expect(page.comments.map(\.source) == [.postComment, .ratingReason])
    #expect(page.comments.map(\.authorName) == ["读者甲", "读者丙"])
    #expect(page.comments.map(\.body) == ["这章很好", "这期神了"])
    #expect(page.comments.first?.metadata == "发表于 2026-5-1 12:00")
    #expect(page.isBoundaryClosed == true)
}

@Test func chapterCommentsParserFiltersDefaultRatingReasonTemplatesExactly() throws {
    let filteredReasons = ["你太可爱", "好萌好萌好萌", "我很赞同", "精品文章", "原创内容"]
    let rows = filteredReasons.enumerated().map { index, reason in
        """
        <tr><td><a>读者\(index)</a></td><td class="xi1"> + 1</td><td class="xg1">\(reason)</td></tr>
        """
    }.joined()
    let html = """
    <html><body>
      <div class="t_f" id="postmessage_100">第一章<br>正文</div>
      <dl id="ratelog_100" class="rate"><dd><table><tbody class="ratl_l">
        \(rows)
        <tr><td><a>读者保留</a></td><td class="xi1"> + 1</td><td class="xg1">我很赞同这个观点</td></tr>
      </tbody></table></dd></dl>
    </body></html>
    """
    let target = ReaderChapterCommentTarget(
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&mobile=2")),
        view: 1,
        ownerPostID: "100",
        title: "第一章"
    )

    let page = try ChapterCommentsHTMLParser.parseInitialPage(html: html, target: target)

    #expect(page.comments.map(\.body) == ["我很赞同这个观点"])
}
