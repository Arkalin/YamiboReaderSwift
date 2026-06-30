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
@Test func forumNovelDetailContinueUsesIndependentReadingProgressWithoutFavorite() throws {
    let model = try makeForumNovelDetailViewModel()
    let resumePoint = ReaderResumePoint(
        view: 4,
        displayedTextOffset: 96,
        chapterOrdinal: 3,
        chapterTitle: "第四章",
        segmentProgress: 0.3,
        authorID: "77",
        readingModeHint: .vertical
    )
    model.favorite = nil
    model.readingProgress = ReadingProgressRecord(
        threadURL: model.context.thread.canonicalURL,
        kind: .novel,
        novel: NovelReadingProgressRecord(
            lastView: 4,
            lastChapter: "第四章",
            authorID: "77",
            novelResumePoint: resumePoint,
            novelMaxView: 6,
            novelDocumentSurfaceProgressPercent: 33
        )
    )

    let context = model.continueLaunchContext()

    #expect(model.hasReadingProgress)
    #expect(model.headerSummary.isFavorited == false)
    #expect(model.headerSummary.readingProgressText == "页内 33 % · 网页 4 / 6")
    #expect(context.source == .resume)
    #expect(context.initialView == 4)
    #expect(context.authorID == "77")
    #expect(context.initialResumePoint == resumePoint)
}

@MainActor
@Test func forumNovelDetailContinueTreatsFavoriteChapterAsReadingProgress() throws {
    let model = try makeForumNovelDetailViewModel()
    model.favorite = Favorite(
        title: "收藏标题",
        url: model.context.thread.canonicalURL,
        lastView: 1,
        lastChapter: "第一章",
        type: .novel
    )

    let context = model.continueLaunchContext()

    #expect(model.hasReadingProgress)
    #expect(context.source == .resume)
    #expect(context.initialView == 1)
    #expect(model.headerSummary.readingProgressText == "第一章")
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
                lastEditedText: "本帖最后由 楼主名 于 2026-6-2 12:00 编辑",
                contentHTML: "",
                contentText: "首楼简介\n正文",
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
    #expect(summary.threadURL == model.context.thread.canonicalURL)
    #expect(summary.authorID == "42")
    #expect(summary.authorName == "楼主名")
    #expect(summary.postedAtText == "2026-6-1 10:00")
    #expect(summary.lastUpdatedText == "2026-6-2 12:00")
    #expect(summary.totalViews == 321)
    #expect(summary.totalReplies == 45)
    #expect(summary.forumName == "#原创小说")
    #expect(summary.chapterCount == 2)
    #expect(summary.coverURL == coverURL)
    #expect(summary.firstFloorPreviewText == "首楼简介\n正文")
}

@MainActor
@Test func forumNovelDetailUsesSanitizedDiscuzTitle() throws {
    let model = try makeForumNovelDetailViewModel()
    model.threadPage = ForumThreadPage(
        thread: model.context.thread,
        title: "文学区版规已更新 请各位会员阅读知悉 - 文學區 - 百合会 - 手机版 - Powered by Discuz!",
        posts: [
            ForumThreadPost(
                postID: "1001",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "正文",
                contentBlocks: []
            )
        ]
    )

    #expect(model.navigationTitle == "文学区版规已更新 请各位会员阅读知悉")
    #expect(model.headerSummary.title == "文学区版规已更新 请各位会员阅读知悉")
}

@MainActor
@Test func forumNovelDetailHeaderFallsBackToPostedAtForLastUpdatedText() throws {
    let model = try makeForumNovelDetailViewModel()
    model.threadPage = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                postedAtText: "2026-6-1 10:00",
                lastEditedText: nil,
                contentHTML: "",
                contentText: "正文",
                contentBlocks: []
            )
        ]
    )

    #expect(model.headerSummary.lastUpdatedText == "2026-6-1 10:00")
}

@MainActor
@Test func forumNovelDetailHeaderPrefersPersistedContentCover() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "novel-detail-cover")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let coverStore = ContentCoverStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
        key: "content-covers"
    )
    let key = ContentCoverKey(targetType: .threadNovel, targetID: "900")
    let persisted = try #require(URL(string: "https://img.example.com/persisted.jpg"))
    let pageCandidate = try #require(URL(string: "https://img.example.com/page.jpg"))
    try await coverStore.setAutomaticCover(persisted, for: key)
    let appContext = YamiboAppContext(
        favoriteStore: FavoriteStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "favorites"),
        contentCoverStore: coverStore
    )
    let model = try makeForumNovelDetailViewModel(appContext: appContext)
    model.contentCover = await coverStore.cover(for: key)
    model.threadPage = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                floorText: "1#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "首楼",
                contentBlocks: [
                    ForumThreadContentBlock(
                        id: "page",
                        kind: .image(ForumThreadImageBlock(url: pageCandidate))
                    )
                ]
            )
        ]
    )

    #expect(model.headerSummary.coverURL == persisted)
}

@MainActor
@Test func forumNovelDetailRefreshContentCoverStoresOwnerPostCandidateOnly() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "novel-detail-auto-cover")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let coverStore = ContentCoverStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
        key: "content-covers"
    )
    let appContext = YamiboAppContext(
        favoriteStore: FavoriteStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "favorites"),
        contentCoverStore: coverStore
    )
    let model = try makeForumNovelDetailViewModel(appContext: appContext)
    let key = ContentCoverKey(targetType: .threadNovel, targetID: "900")
    let replyImage = try #require(URL(string: "https://img.example.com/reply.jpg"))
    let ownerImage = try #require(URL(string: "https://img.example.com/owner.jpg"))
    let page = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                floorText: "1#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "首楼无图",
                contentBlocks: []
            ),
            ForumThreadPost(
                postID: "1002",
                floorText: "2#",
                author: BlogReaderUser(uid: "99", name: "读者", avatarURL: nil),
                contentHTML: "",
                contentText: "回复图",
                contentBlocks: [
                    ForumThreadContentBlock(
                        id: "reply",
                        kind: .image(ForumThreadImageBlock(url: replyImage))
                    )
                ]
            ),
            ForumThreadPost(
                postID: "1003",
                floorText: "3#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "楼主补图",
                contentBlocks: [
                    ForumThreadContentBlock(
                        id: "owner",
                        kind: .image(ForumThreadImageBlock(url: ownerImage))
                    )
                ]
            )
        ]
    )

    #expect(ForumNovelDetailViewModel.coverCandidate(in: page) == ownerImage)

    await model.refreshContentCover(from: page)

    let cover = try #require(await coverStore.cover(for: key))
    #expect(cover.automaticCoverURL == ownerImage)
    #expect(model.contentCover?.resolvedURL == ownerImage)
}

@MainActor
@Test func forumNovelDetailGroupsChapterDirectoryByThreadPage() throws {
    let model = try makeForumNovelDetailViewModel()
    let firstPage = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                floorText: "1#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "序章\n正文",
                contentBlocks: []
            ),
            ForumThreadPost(
                postID: "1002",
                floorText: "2#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "第一章\n正文",
                contentBlocks: []
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: 1, totalPages: 2)
    )
    let secondPage = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "2001",
                floorText: "11#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "第二章\n正文",
                contentBlocks: []
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: 2, totalPages: 2)
    )

    let sections = ForumNovelDetailViewModel.chapterSections(
        from: [
            1: firstPage,
            2: secondPage
        ],
        totalPages: 2
    )

    #expect(sections.map(\.page) == [1, 2])
    #expect(sections[0].chapters.map(\.title) == ["序章", "第一章"])
    #expect(sections[0].chapters.map(\.view) == [1, 1])
    #expect(sections[0].chapters.map(\.postID) == ["1001", "1002"])
    #expect(sections[0].chapters[0].resumePoint?.view == 1)
    #expect(sections[0].chapters[0].resumePoint?.chapterIdentity?.rawValue == "post:1001#chapter:0")
    #expect(sections[0].chapters[0].resumePoint?.textSegmentIdentity == nil)
    #expect(sections[1].chapters.map(\.title) == ["第二章"])
    #expect(sections[1].chapters.map(\.view) == [2])
    #expect(sections[1].chapters.map(\.floorText) == ["11#"])
}

@MainActor
@Test func forumNovelDetailChapterTapUsesPostResumePoint() throws {
    let model = try makeForumNovelDetailViewModel()
    let section = ForumNovelDetailViewModel.chapterSections(
        from: [
            1: ForumThreadPage(
                thread: model.context.thread,
                title: "小说标题",
                posts: [
                    ForumThreadPost(
                        postID: "1001",
                        floorText: "1#",
                        author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                        contentHTML: "",
                        contentText: "序章\n正文",
                        contentBlocks: []
                    )
                ]
            )
        ],
        totalPages: 1
    )[0]

    let launchContext = model.launchContext(for: section.chapters[0])

    #expect(launchContext.initialView == 1)
    #expect(launchContext.authorID == "42")
    #expect(launchContext.initialResumePoint?.chapterIdentity?.rawValue == "post:1001#chapter:0")
    #expect(launchContext.initialResumePoint?.chapterTitle == "序章")
}

@MainActor
@Test func forumNovelDetailChapterTitleSkipsQuotedText() throws {
    let model = try makeForumNovelDetailViewModel()
    let page = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                floorText: "1#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "引用里的旧标题\n真正章节\n正文",
                contentBlocks: [
                    ForumThreadContentBlock(
                        id: "quote",
                        kind: .quote([
                            ForumThreadContentBlock(
                                id: "quote-text",
                                kind: .text(ForumThreadTextBlock(text: "引用里的旧标题"))
                            )
                        ])
                    ),
                    ForumThreadContentBlock(
                        id: "body",
                        kind: .text(ForumThreadTextBlock(text: "真正章节\n正文"))
                    )
                ]
            )
        ]
    )

    let sections = ForumNovelDetailViewModel.chapterSections(from: [1: page], totalPages: 1)

    #expect(sections[0].chapters.map(\.title) == ["真正章节"])
}

@MainActor
@Test func forumNovelDetailMarksCurrentReadChapterFromFavoriteResumePoint() throws {
    let model = try makeForumNovelDetailViewModel()
    model.favorite = Favorite(
        title: "小说标题",
        url: model.context.thread.canonicalURL,
        lastView: 1,
        lastChapter: "第一章",
        novelResumePoint: ReaderResumePoint(
            view: 1,
            chapterIdentity: NovelChapterIdentity(rawValue: "post:1002#chapter:0"),
            displayedTextOffset: 20,
            chapterOrdinal: 1,
            chapterTitle: "第一章",
            segmentProgress: 0.2,
            readingModeHint: .vertical
        ),
        novelDocumentSurfaceProgressPercent: 20,
        type: .novel
    )
    let firstPage = ForumThreadPage(
        thread: model.context.thread,
        title: "小说标题",
        posts: [
            ForumThreadPost(
                postID: "1001",
                floorText: "1#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "序章\n正文",
                contentBlocks: []
            ),
            ForumThreadPost(
                postID: "1002",
                floorText: "2#",
                author: BlogReaderUser(uid: "42", name: "楼主名", avatarURL: nil),
                contentHTML: "",
                contentText: "第一章\n正文",
                contentBlocks: []
            )
        ]
    )

    let sections = ForumNovelDetailViewModel.chapterSections(
        from: [1: firstPage],
        totalPages: 1,
        favorite: model.favorite
    )

    #expect(sections[0].chapters.map(\.isCurrentRead) == [false, true])
    #expect(sections[0].chapters[1].progressText == "20 %")
    #expect(model.headerSummary.readingProgressText == "20 %")
}

@MainActor
@Test func forumNovelDetailRefreshesReadingProgressWhenFavoriteStoreChanges() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "novel-detail-progress-refresh")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let favoriteStore = FavoriteStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
        key: "favorites"
    )
    let appContext = YamiboAppContext(
        favoriteStore: favoriteStore,
        contentCoverStore: ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
    )
    let model = try makeForumNovelDetailViewModel(appContext: appContext)
    let url = model.context.thread.canonicalURL

    try await favoriteStore.saveFavorites([
        Favorite(
            title: "小说标题",
            url: url,
            lastView: 1,
            lastChapter: "第一章",
            novelDocumentSurfaceProgressPercent: 10,
            type: .novel
        )
    ])
    model.favorite = await favoriteStore.favorite(for: url)
    #expect(model.headerSummary.readingProgressText == "10 %")
    await Task.yield()

    _ = try await favoriteStore.updateNovelReadingPosition(
        NovelReadingPosition(
            threadURL: url,
            view: 2,
            maxView: 3,
            chapterTitle: "第二章",
            authorID: "42",
            resumePoint: ReaderResumePoint(
                view: 2,
                chapterIdentity: NovelChapterIdentity(rawValue: "post:2001#chapter:0"),
                displayedTextOffset: 80,
                chapterOrdinal: 1,
                chapterTitle: "第二章",
                segmentProgress: 0.8,
                authorID: "42",
                readingModeHint: .vertical
            ),
            documentSurfaceProgressPercent: 80
        )
    )

    for _ in 0..<20 where model.favorite?.lastView != 2 {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(model.favorite?.lastView == 2)
    #expect(model.favorite?.novelResumePoint?.chapterTitle == "第二章")
    #expect(model.headerSummary.readingProgressText == "页内 80 % · 网页 2 / 3")
}

@MainActor
private func makeForumNovelDetailViewModel(appContext: YamiboAppContext? = nil) throws -> ForumNovelDetailViewModel {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=900&mobile=2"))
    let resolvedAppContext: YamiboAppContext
    if let appContext {
        resolvedAppContext = appContext
    } else {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "novel-detail")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        resolvedAppContext = YamiboAppContext(
            favoriteStore: FavoriteStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "favorites"),
            contentCoverStore: ContentCoverStore(
                defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
                key: "content-covers"
            )
        )
    }
    return ForumNovelDetailViewModel(
        context: NovelDetailLaunchContext(
            thread: ThreadIdentity(tid: "900", canonicalURL: url, fid: "49"),
            title: "小说标题",
            authorID: "42"
        ),
        appContext: resolvedAppContext
    )
}
