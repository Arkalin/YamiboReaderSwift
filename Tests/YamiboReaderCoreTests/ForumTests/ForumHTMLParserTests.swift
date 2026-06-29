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

@Test func parseForumBoardExtractsMetadataControlsPinnedItemsAndThreads() throws {
    let html = #"""
    <html>
    <head>
      <title>動漫區 -  百合会 -  手机版 - Powered by Discuz!</title>
      <base href="https://bbs.yamibo.com/" />
    </head>
    <body id="forum" class="pg_forumdisplay">
      <div class="header cl"><h2>動漫區</h2></div>
      <div id="nav-more-menu">
        <a href="home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=5&amp;handlekey=favoriteforum&amp;formhash=f47bb54f&amp;mobile=2">收藏本版</a>
      </div>
      <div class="forumdisplay-top cl">
        <h2>
          <img src="data/attachment/common/e4/common_5_icon.gif" alt="動漫區" />
          <a href="forum.php?mod=post&amp;action=newthread&amp;fid=5&amp;mobile=2" title="发帖">发帖</a>
          動漫區
        </h2>
        <p>今日: <span>40</span>主题: <span>28169</span>排名: <span>4</span></p>
      </div>
      <div class="dhnav_box">
        <ul>
          <li><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;mobile=2">全部</a></li>
          <li><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;filter=lastpost&amp;orderby=lastpost&amp;mobile=2">最新</a></li>
          <li><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;orderby=dateline&amp;filter=dateline&amp;mobile=2">新帖</a></li>
        </ul>
      </div>
      <div class="dhnavs_box">
        <ul>
          <li><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;filter=typeid&amp;typeid=400&amp;mobile=2">动画讨论</a></li>
          <li><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;filter=typeid&amp;typeid=403&amp;mobile=2">求推</a></li>
        </ul>
      </div>
      <div class="forumlist cl">
        <div id="sub-forum_5" class="sub-forum mlist4 cl">
          <ul>
            <li>
              <span class="subforumshow cl">子版块</span>
              <span class="micon"><a href="forum.php?mod=forumdisplay&amp;fid=52&amp;mobile=2"><img src="data/attachment/common/9a/common_52_icon.gif" alt="百合会最萌世界杯专版！" /></a></span>
              <a href="forum.php?mod=forumdisplay&amp;fid=52&amp;mobile=2" class="murl"><p class="mtit">百合会最萌世界杯专版！</p></a>
            </li>
          </ul>
        </div>
      </div>
      <div class="threadlist_box mt10 cl">
        <div class="threadlist cl">
          <ul>
            <li class="list_top"><a href="forum.php?mod=announcement&amp;id=17#17&amp;mobile=2"><span class="micon gonggao">公告</span>欢迎光临。</a></li>
            <li class="list_top">
              <a href="forum.php?mod=viewthread&amp;tid=533721&amp;extra=page%3D1&amp;mobile=2">
                <span class="micon">置顶</span>
                <em>如何找回账号/如何修改密码</em>
              </a>
            </li>
            <li class="list">
              <div class="threadlist_top cl">
                <a href="home.php?mod=space&amp;uid=705216&amp;mobile=2" class="mimg"><img src="https://bbs.yamibo.com/uc_server/data/avatar/000/70/52/16_avatar_middle.jpg"></a>
                <div class="muser">
                  <h3><a href="home.php?mod=space&amp;uid=705216&amp;mobile=2" class="mmc">张瑞泽</a></h3>
                  <span class="mtime">2025-12-22 14:33</span>
                </div>
              </div>
              <a href="forum.php?mod=viewthread&amp;tid=565409&amp;extra=page%3D1&amp;mobile=2">
                <div class="threadlist_tit cl">
                  <span class="micon">投票</span>
                  <em>那对cp是你心中的no1</em>
                </div>
              </a>
              <a href="forum.php?mod=viewthread&amp;tid=565409&amp;extra=page%3D1&amp;mobile=2"><div class="threadlist_mes cl">还有好多就不一个一个写了</div></a>
              <div class="threadlist_foot cl">
                <ul>
                  <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;filter=typeid&amp;typeid=3&amp;mobile=2">#其他</a></li>
                  <li><i class="dm-eye-fill"></i>35530</li>
                  <li><i class="dm-chat-s-fill"></i>189</li>
                </ul>
              </div>
            </li>
          </ul>
        </div>
        <div class="pg"><strong>1</strong><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;page=2&amp;mobile=2">2</a><a href="forum.php?mod=forumdisplay&amp;fid=5&amp;page=1409&amp;mobile=2" class="last">.. 1409</a><label><span title="共 1409 页"> / 1409 页</span></label></div>
      </div>
    </body>
    </html>
    """#

    let page = try ForumHTMLParser.parseBoardPage(from: html, fid: "5", fetchedAt: Date(timeIntervalSince1970: 2))

    #expect(page.board.name == "動漫區")
    #expect(page.board.todayCount == 40)
    #expect(page.board.threadCount == 28169)
    #expect(page.board.rank == 4)
    #expect(page.board.iconURL?.absoluteString == "https://bbs.yamibo.com/data/attachment/common/e4/common_5_icon.gif")
    #expect(page.formHash == "f47bb54f")
    #expect(page.subBoards.map(\.fid) == ["52"])
    #expect(page.subBoards.first?.name == "百合会最萌世界杯专版！")
    #expect(page.orders.map(\.id) == ["lastpost", "dateline"])
    #expect(page.filters.map(\.title) == ["动画讨论", "求推"])
    #expect(page.pinnedItems.map(\.kind) == [.announcement, .thread])
    #expect(page.pinnedItems[1].threadID == "533721")
    #expect(page.threads.first?.tid == "565409")
    #expect(page.threads.first?.authorName == "张瑞泽")
    #expect(page.threads.first?.authorID == "705216")
    #expect(page.threads.first?.isPoll == true)
    #expect(page.threads.first?.description == "还有好多就不一个一个写了")
    #expect(page.threads.first?.tag == "其他")
    #expect(page.threads.first?.viewCount == 35530)
    #expect(page.threads.first?.replyCount == 189)
    #expect(page.pageNavigation == ForumPageNavigation(currentPage: 1, totalPages: 1409))
}
