import Foundation
import Testing
@testable import YamiboReaderCore

@Test func parseForumHomeExtractsCategoriesBoardsAndCarousel() throws {
    let html = #"""
    <html>
    <body id="forum" class="pg_index">
      <div class="yami-swiper">
        <div class="swiper-wrapper">
          <div class="swiper-slide">
            <a href="https://bbs.yamibo.com/thread-570956-1-1.html">
              <img src="data/attachment/block/home.jpg">
            </a>
          </div>
        </div>
      </div>
      <div class="forumlist cl">
        <div class="subforumshow cl" href="#sub-forum_14">
          <h2><a href="javascript:;">庙堂</a></h2>
        </div>
        <div id="sub-forum_14" class="sub-forum mlist1 cl">
          <ul>
            <li>
              <span class="micon">
                <a href="forum.php?mod=forumdisplay&amp;fid=16&amp;mobile=2">
                  <img src="data/attachment/common/c7/common_16_icon.gif" alt="管理版" />
                </a>
              </span>
              <a href="forum.php?mod=forumdisplay&amp;fid=16&amp;mobile=2" class="murl">
                <p class="mtit">管理版</p>
                <p class="mtxt">既无论先民后主，何必辩你们我们。</p>
              </a>
            </li>
          </ul>
        </div>
        <div class="subforumshow cl" href="#sub-forum_2">
          <h2><a href="javascript:;">江湖</a></h2>
        </div>
        <div id="sub-forum_2" class="sub-forum mlist1 cl">
          <ul>
            <li>
              <a href="forum.php?mod=forumdisplay&amp;fid=5&amp;mobile=2" class="murl">
                <p class="mtit">動漫區<span class="mnum">今日 39</span></p>
                <p class="mtxt">请不要在莉莉安女子学院里狂奔……你给我站住！！</p>
              </a>
            </li>
          </ul>
        </div>
      </div>
    </body>
    </html>
    """#

    let page = try ForumHTMLParser.parseHomePage(from: html, fetchedAt: Date(timeIntervalSince1970: 1))

    #expect(page.categories.map(\.title) == ["庙堂", "江湖"])
    #expect(page.categories.first?.boards.first?.fid == "16")
    #expect(page.categories.first?.boards.first?.name == "管理版")
    #expect(page.categories.first?.boards.first?.detail == "既无论先民后主，何必辩你们我们。")
    #expect(page.categories.first?.boards.first?.iconURL?.absoluteString == "https://bbs.yamibo.com/data/attachment/common/c7/common_16_icon.gif")
    #expect(page.categories[1].boards.first?.todayCount == 39)
    #expect(page.carouselItems.first?.threadID == "570956")
    #expect(page.carouselItems.first?.imageURL.absoluteString == "https://bbs.yamibo.com/data/attachment/block/home.jpg")
}

@Test func parseForumHomeFailsWhenNoBoardsAreAvailable() {
    let html = "<html><body><div class=\"forumlist\"></div></body></html>"

    #expect(throws: YamiboError.parsingFailed(context: L10n.string("context.forum_home"))) {
        try ForumHTMLParser.parseHomePage(from: html)
    }
}
