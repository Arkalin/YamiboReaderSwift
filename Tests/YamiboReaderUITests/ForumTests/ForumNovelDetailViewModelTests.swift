import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
@Test func forumNovelDetailContinueStartsAtFirstViewWithoutHistory() throws {
    let model = try makeForumNovelDetailViewModel()

    let context = model.continueLaunchContext()

    #expect(context.source == .forum)
    #expect(context.initialView == 1)
    #expect(context.initialResumePoint == nil)
    #expect(context.authorID == "42")
}

@MainActor
@Test func forumNovelDetailContinueUsesFavoriteResumePointWhenAvailable() throws {
    let model = try makeForumNovelDetailViewModel()
    let resumePoint = ReaderResumePoint(
        view: 5,
        displayedTextOffset: 128,
        chapterOrdinal: 4,
        chapterTitle: "第五章",
        segmentProgress: 0.4,
        authorID: "99",
        readingModeHint: .vertical
    )
    model.favorite = Favorite(
        title: "收藏标题",
        url: model.context.thread.canonicalURL,
        lastView: 3,
        lastChapter: "旧章",
        authorID: "88",
        novelResumePoint: resumePoint,
        type: .novel
    )

    let context = model.continueLaunchContext()

    #expect(context.source == .resume)
    #expect(context.threadTitle == "收藏标题")
    #expect(context.initialView == 5)
    #expect(context.authorID == "99")
    #expect(context.initialResumePoint == resumePoint)
}

@MainActor
@Test func forumNovelDetailHeaderSummaryUsesThreadPageMetadataAndCoverCandidate() throws {
    let model = try makeForumNovelDetailViewModel()
    let coverURL = try #require(URL(string: "https://bbs.yamibo.com/data/attachment/forum/cover.jpg"))
    let ignoredURL = try #require(URL(string: "https://bbs.yamibo.com/static/image/smiley/default/none.gif"))
    model.chapters = [
        ForumNovelChapterSummary(id: "1|序章", title: "序章", view: 1),
        ForumNovelChapterSummary(id: "1|第一章", title: "第一章", view: 1)
    ]
    model.threadPage = ForumThreadPage(
        thread: ThreadIdentity(
            tid: "900",
            canonicalURL: model.context.thread.canonicalURL,
            fid: "123"
        ),
        title: "解析标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                postedAtText: "2026-6-1 10:00",
                contentHTML: "",
                contentText: "",
                contentBlocks: [
                    ForumThreadContentBlock(
                        id: "ignored",
                        kind: .image(ForumThreadImageBlock(url: ignoredURL, isEmoticon: true))
                    ),
                    ForumThreadContentBlock(
                        id: "cover",
                        kind: .image(ForumThreadImageBlock(url: coverURL))
                    )
                ]
            )
        ],
        totalViews: 321,
        totalReplies: 45,
        forumName: "原创小说"
    )

    let summary = model.headerSummary

    #expect(summary.title == "解析标题")
    #expect(summary.authorName == "楼主名")
    #expect(summary.postedAtText == "2026-6-1 10:00")
    #expect(summary.totalViews == 321)
    #expect(summary.totalReplies == 45)
    #expect(summary.forumName == "#原创小说")
    #expect(summary.chapterCount == 2)
    #expect(summary.coverURL == coverURL)
}

@MainActor
private func makeForumNovelDetailViewModel() throws -> ForumNovelDetailViewModel {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=900&mobile=2"))
    return ForumNovelDetailViewModel(
        context: NovelDetailLaunchContext(
            thread: ThreadIdentity(tid: "900", canonicalURL: url, fid: YamiboForumTaxonomy.defaultNovelForumIDs.first),
            title: "小说标题",
            authorID: "42"
        ),
        appContext: YamiboAppContext()
    )
}
