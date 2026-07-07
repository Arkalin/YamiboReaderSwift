import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
@Test func forumThreadReaderLoadsExistingLocalFavoriteState() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    var document = FavoriteLibraryDocument()
    document.addItem(try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "704"),
        title: "已收藏标题",
        locations: [.category(document.defaultCategory.id)]
    ))
    try await fixture.localFavoriteLibraryStore.save(document)
    let model = fixture.makeModel()

    await model.load()

    #expect(model.isFavorited)
}

@MainActor
@Test func forumThreadReaderTogglesRemoteFavoriteAndSyncsLocalState() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.load()
    #expect(!model.isFavorited)

    // Default settings ask about the Yamibo push before adding.
    await model.toggleFavorite()
    #expect(model.favoriteAddPromptPresented)
    await model.confirmFavoriteAdd(syncToRemote: true, remember: false)

    let added = try #require(await fixture.localFavoriteItem())
    #expect(model.isFavorited)
    #expect(added.title == "解析标题")
    #expect(added.remoteMapping?.yamiboFavoriteID == "8801")
    #expect(added.forumID == "40")
    #expect(added.forumName == "综合讨论")
    #expect(added.sourceGroup == .forumBoard(id: "40", label: "综合讨论"))
    #expect(added.contentUpdatedAt == FavoriteContentUpdateDateResolver.date(
        lastEditedText: "本帖最后由 楼主 于 2026-6-2 12:00 编辑",
        postedAtText: "2026-6-1 10:00"
    ))
    #expect(await fixture.favoriteRepository.addedThreadIDs == ["704"])

    // Removing a mapped favorite asks about the remote delete.
    await model.toggleFavorite()
    let removePrompt = try #require(model.favoriteRemovePrompt)
    await model.confirmFavoriteRemoval(removePrompt.favorite, removeRemote: true, remember: false)

    #expect(!model.isFavorited)
    #expect(await fixture.localFavoriteItem() == nil)
    #expect(await fixture.favoriteRepository.deletedRemoteFavoriteIDs == ["8801"])
}

@MainActor
@Test func forumThreadReaderLocalOnlyAddSkipsRemotePushAndRemovesWithoutPrompt() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.load()
    await model.toggleFavorite()
    #expect(model.favoriteAddPromptPresented)
    await model.confirmFavoriteAdd(syncToRemote: false, remember: false)

    let added = try #require(await fixture.localFavoriteItem())
    #expect(model.isFavorited)
    #expect(added.remoteMapping?.yamiboFavoriteID == nil)
    #expect(await fixture.favoriteRepository.addedThreadIDs.isEmpty)

    // Unmapped favorites delete locally without the remote question.
    await model.toggleFavorite()
    #expect(model.favoriteRemovePrompt == nil)
    #expect(!model.isFavorited)
    #expect(await fixture.localFavoriteItem() == nil)
    #expect(await fixture.favoriteRepository.deletedRemoteFavoriteIDs.isEmpty)
}

@MainActor
@Test func forumThreadReaderRememberedAddChoiceSkipsPrompt() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.load()
    await model.toggleFavorite()
    #expect(model.favoriteAddPromptPresented)
    await model.confirmFavoriteAdd(syncToRemote: true, remember: true)
    let settings = await fixture.settingsStore.load().favorites
    #expect(!settings.addSyncPromptEnabled)
    #expect(settings.addSyncDefault)

    // Remove (prompted), then add again: the remembered choice syncs silently.
    await model.toggleFavorite()
    let removePrompt = try #require(model.favoriteRemovePrompt)
    await model.confirmFavoriteRemoval(removePrompt.favorite, removeRemote: false, remember: false)

    await model.toggleFavorite()
    #expect(!model.favoriteAddPromptPresented)
    #expect(model.isFavorited)
    #expect(await fixture.favoriteRepository.addedThreadIDs == ["704", "704"])
}

@MainActor
@Test func forumThreadReaderToggleBeforePageLoadUsesContextForumID() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.toggleFavorite()
    #expect(model.favoriteAddPromptPresented)
    await model.confirmFavoriteAdd(syncToRemote: false, remember: false)

    let added = try #require(await fixture.localFavoriteItem())
    #expect(added.title == "上下文标题")
    #expect(added.forumID == "40")
    #expect(added.sourceGroup == .forumBoard(id: "40", label: "40"))
}

@MainActor
@Test func forumThreadReaderLoadUsesCachedPageWithoutFetching() async throws {
    let cachedPage = ForumThreadPage(
        thread: ThreadIdentity(tid: "704"),
        title: "缓存标题",
        posts: [
            ForumThreadPost(
                postID: "cached",
                author: BlogReaderUser(uid: "42", name: "楼主"),
                contentHTML: "",
                contentText: "缓存正文"
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: 1, totalPages: 4)
    )
    let fixture = try ForumThreadReaderViewModelFixture(cachedPages: [1: cachedPage])
    let model = fixture.makeModel()

    await model.load()

    #expect(model.page?.title == "缓存标题")
    #expect(fixture.repository.cachedPageCalls() == [1])
    #expect(fixture.repository.fetchPageCalls().isEmpty)
}

@MainActor
@Test func forumThreadReaderRefreshBypassesCachedPageAndFetches() async throws {
    let cachedPage = ForumThreadPage(
        thread: ThreadIdentity(tid: "704"),
        title: "缓存标题",
        posts: [
            ForumThreadPost(
                postID: "cached",
                author: BlogReaderUser(uid: "42", name: "楼主"),
                contentHTML: "",
                contentText: "缓存正文"
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: 1, totalPages: 4)
    )
    let fixture = try ForumThreadReaderViewModelFixture(cachedPages: [1: cachedPage])
    let model = fixture.makeModel()

    await model.load()
    await model.refresh()

    #expect(model.page?.title == "解析标题")
    #expect(fixture.repository.cachedPageCalls() == [1])
    #expect(fixture.repository.fetchPageCalls() == [1])
}

@MainActor
@Test func forumThreadReaderRefreshFailurePreservesExistingPageAndShowsTransientMessage() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.load()
    fixture.repository.fetchError = ForumThreadReaderTestError.plannedFailure
    await model.refresh()

    #expect(model.page?.title == "解析标题")
    #expect(model.errorMessage == nil)
    #expect(model.transientMessage == L10n.string("forum.thread.refresh_failed", ForumThreadReaderTestError.plannedFailure.localizedDescription))
    #expect(fixture.repository.cachedPageCalls() == [1, 1])
    #expect(fixture.repository.fetchPageCalls() == [1, 1])
}

@MainActor
@Test func forumThreadReaderRefreshFailureFallsBackToCachedPage() async throws {
    let cachedPage = makeThreadPage(title: "缓存标题", postID: "cached", contentText: "缓存正文")
    let fixture = try ForumThreadReaderViewModelFixture(cachedPages: [1: cachedPage], fetchError: ForumThreadReaderTestError.plannedFailure)
    let model = fixture.makeModel()

    await model.load()
    await model.refresh()

    #expect(model.page?.title == "缓存标题")
    #expect(model.errorMessage == nil)
    #expect(model.transientMessage == L10n.string("forum.thread.refresh_failed", ForumThreadReaderTestError.plannedFailure.localizedDescription))
    #expect(fixture.repository.cachedPageCalls() == [1, 1])
    #expect(fixture.repository.fetchPageCalls() == [1])
}

@MainActor
@Test func forumThreadReaderInitialLoadFailureWithoutCacheUsesPageError() async throws {
    let fixture = try ForumThreadReaderViewModelFixture(fetchError: ForumThreadReaderTestError.plannedFailure)
    let model = fixture.makeModel()

    await model.load()

    #expect(model.page == nil)
    #expect(model.errorMessage == ForumThreadReaderTestError.plannedFailure.localizedDescription)
    #expect(model.transientMessage == nil)
    #expect(fixture.repository.cachedPageCalls() == [1])
    #expect(fixture.repository.fetchPageCalls() == [1])
}

@MainActor
@Test func forumThreadReaderVotePollWithoutLoadedPageThrowsLoginInfoError() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await #expect(throws: YamiboError.underlying(L10n.string("forum.thread.login_info_failed"))) {
        try await model.votePoll(optionIDs: ["1"])
    }
    #expect(fixture.repository.votePollCalls().isEmpty)
}

@MainActor
@Test func forumThreadReaderVotePollUsesPageForumIDAndFormHashThenRefreshes() async throws {
    let fixture = try ForumThreadReaderViewModelFixture(formHash: " hash-1 ")
    let model = fixture.makeModel()

    await model.load()
    let message = try await model.votePoll(optionIDs: ["2", "5"])

    #expect(message == "投票成功")
    #expect(fixture.repository.votePollCalls() == ["40|704|2,5|hash-1"])
    #expect(fixture.repository.fetchPageCalls() == [1, 1])
}

@MainActor
@Test func forumThreadReaderRatePostWithoutFormHashThrowsLoginInfoError() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.load()

    await #expect(throws: YamiboError.underlying(L10n.string("forum.thread.login_info_failed"))) {
        try await model.ratePost(postID: "4001", score: 2, reason: "赞", noticeAuthor: true)
    }
    #expect(fixture.repository.ratePostCalls().isEmpty)
}

@MainActor
@Test func forumThreadReaderCommentPostUsesFormHashAndCurrentPage() async throws {
    let fixture = try ForumThreadReaderViewModelFixture(formHash: "hash-2")
    let model = fixture.makeModel()

    await model.load()
    _ = try await model.commentPost(postID: "4001", message: "评论内容")

    #expect(fixture.repository.commentPostCalls() == ["704|4001|评论内容|hash-2|1"])
}

@MainActor
@Test func forumThreadReaderImageBrowserRequestCollectsPageImagesAroundTappedImage() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()
    let firstURL = try #require(URL(string: "https://img.example.com/first.jpg"))
    let secondURL = try #require(URL(string: "https://img.example.com/second.jpg"))
    let refererURL = try #require(URL(string: "https://bbs.yamibo.com/thread-704-1-1.html"))
    model.page = ForumThreadPage(
        thread: ThreadIdentity(tid: "704"),
        title: "标题",
        posts: [
            ForumThreadPost(
                postID: "4001",
                author: BlogReaderUser(uid: "42", name: "楼主"),
                contentHTML: "",
                contentText: "",
                contentBlocks: [
                    ForumThreadContentBlock(id: "first", kind: .image(ForumThreadImageBlock(url: firstURL))),
                    ForumThreadContentBlock(id: "second", kind: .image(ForumThreadImageBlock(url: secondURL, altText: "第二张")))
                ]
            )
        ]
    )

    let request = try #require(model.imageBrowserRequest(
        imageID: "second",
        url: secondURL,
        title: "第二张",
        refererURL: refererURL
    ))

    #expect(request.items.map(\.id) == ["first", "second"])
    #expect(request.initialItemID == "second")
    #expect(request.items.allSatisfy { $0.source.refererPageURL == refererURL })
}

@MainActor
@Test func forumThreadReaderImageBrowserRequestFallsBackToTappedImageWhenPageHasNoGalleryImages() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()
    let tappedURL = try #require(URL(string: "https://img.example.com/only.jpg"))
    let refererURL = try #require(URL(string: "https://bbs.yamibo.com/thread-704-1-1.html"))

    #expect(model.imageBrowserRequest(imageID: "only", url: tappedURL, title: nil, refererURL: refererURL) == nil)

    model.page = makeThreadPage(title: "标题", postID: "4001", contentText: "纯文本")
    let request = try #require(model.imageBrowserRequest(
        imageID: "only",
        url: tappedURL,
        title: "  ",
        refererURL: refererURL
    ))

    #expect(request.items.map(\.id) == ["only"])
    #expect(request.initialItemID == "only")
    #expect(request.items.first?.title == L10n.string("forum.thread.image"))
    #expect(request.items.first?.source == YamiboImageSource(url: tappedURL, refererPageURL: refererURL))
}

private enum ForumThreadReaderTestError: LocalizedError {
    case plannedFailure

    var errorDescription: String? {
        "planned failure"
    }
}

private func makeThreadPage(
    title: String,
    postID: String,
    contentText: String,
    page: Int = 1,
    formHash: String? = nil
) -> ForumThreadPage {
    ForumThreadPage(
        thread: ThreadIdentity(tid: "704"),
        title: title,
        posts: [
            ForumThreadPost(
                postID: postID,
                author: BlogReaderUser(uid: "42", name: "楼主"),
                postedAtText: "2026-6-1 10:00",
                lastEditedText: "本帖最后由 楼主 于 2026-6-2 12:00 编辑",
                contentHTML: "",
                contentText: contentText
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 4),
        forumID: "40",
        forumName: "综合讨论",
        formHash: formHash
    )
}

private struct ForumThreadReaderViewModelFixture {
    let suiteName: String
    let threadURL: URL
    let localFavoriteLibraryStore: FavoriteLibraryStore
    let settingsStore: SettingsStore
    let repository: FakeForumThreadPageLoader
    let favoriteRepository: FakeThreadFavoriteRepository

    init(cachedPages: [Int: ForumThreadPage] = [:], fetchError: Error? = nil, formHash: String? = nil) throws {
        suiteName = "ForumThreadReaderViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2"))
        localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            key: "local-favorites"
        )
        settingsStore = SettingsStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            key: "settings"
        )
        repository = FakeForumThreadPageLoader(
            threadURL: threadURL,
            cachedPages: cachedPages,
            fetchError: fetchError,
            formHash: formHash
        )
        favoriteRepository = FakeThreadFavoriteRepository(threadURL: threadURL)
    }

    func localFavoriteItem() async -> FavoriteItem? {
        let target = FavoriteContentTarget(kind: .normalThread, threadID: "704")
        return await localFavoriteLibraryStore.load().items.first { item in
            item.target.id == target.id
        }
    }

    @MainActor
    func makeModel() -> ForumThreadReaderViewModel {
        ForumThreadReaderViewModel(
            context: ThreadNovelLaunchContext(
                thread: ThreadIdentity(tid: "704", fid: "40"),
                title: "上下文标题"
            ),
            repository: repository,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            favoriteRepository: favoriteRepository,
            settingsStore: settingsStore
        )
    }
}

private final class FakeForumThreadPageLoader: ForumThreadPageLoading, @unchecked Sendable {
    let threadURL: URL
    private let cachedPages: [Int: ForumThreadPage]
    private let formHash: String?
    var fetchError: Error?
    private var recordedCachedPages: [Int] = []
    private var recordedFetchPages: [Int] = []
    private var recordedVotePolls: [String] = []
    private var recordedRatePosts: [String] = []
    private var recordedCommentPosts: [String] = []

    init(
        threadURL: URL,
        cachedPages: [Int: ForumThreadPage] = [:],
        fetchError: Error? = nil,
        formHash: String? = nil
    ) {
        self.threadURL = threadURL
        self.cachedPages = cachedPages
        self.fetchError = fetchError
        self.formHash = formHash
    }

    func cachedThreadPage(context _: ThreadNovelLaunchContext, page: Int) async -> ForumThreadPage? {
        recordedCachedPages.append(page)
        return cachedPages[page]
    }

    func fetchThreadPage(context: ThreadNovelLaunchContext, page: Int) async throws -> ForumThreadPage {
        recordedFetchPages.append(page)
        if let fetchError {
            throw fetchError
        }
        return makeThreadPage(title: "解析标题", postID: "4001", contentText: "正文", page: page, formHash: formHash)
    }

    func cachedPageCalls() -> [Int] {
        recordedCachedPages
    }

    func fetchPageCalls() -> [Int] {
        recordedFetchPages
    }

    func votePollCalls() -> [String] {
        recordedVotePolls
    }

    func ratePostCalls() -> [String] {
        recordedRatePosts
    }

    func commentPostCalls() -> [String] {
        recordedCommentPosts
    }

    func fetchRatingResults(threadID: String, postID: String) async throws -> ForumThreadRatingResultsPage {
        ForumThreadRatingResultsPage(ratings: [])
    }

    func fetchRateOptions(threadID: String, postID: String) async throws -> ForumThreadRateOptionsPage {
        ForumThreadRateOptionsPage(availableScores: [], defaultReasons: [])
    }

    func fetchPollVoters(threadID: String, optionID: String?, page: Int) async throws -> ForumThreadPollVotersPage {
        ForumThreadPollVotersPage(threadID: threadID, selectedOptionID: optionID, pollOptions: [], voters: [])
    }

    func votePoll(forumID: String, threadID: String, optionIDs: [String], formHash: String) async throws -> String {
        recordedVotePolls.append("\(forumID)|\(threadID)|\(optionIDs.joined(separator: ","))|\(formHash)")
        return "投票成功"
    }

    func ratePost(
        threadID: String,
        postID: String,
        score: Int,
        reason: String,
        formHash: String,
        noticeAuthor: Bool
    ) async throws -> String {
        recordedRatePosts.append("\(threadID)|\(postID)|\(score)|\(reason)|\(formHash)|\(noticeAuthor)")
        return ""
    }

    func commentPost(threadID: String, postID: String, message: String, formHash: String, page: Int) async throws -> String {
        recordedCommentPosts.append("\(threadID)|\(postID)|\(message)|\(formHash)|\(page)")
        return ""
    }
}

private actor FakeThreadFavoriteRepository: ForumThreadFavoriteRemoteOperating {
    let threadID: String
    var addedThreadIDs: [String] = []
    var deletedRemoteFavoriteIDs: [String] = []

    init(threadURL: URL) {
        self.threadID = YamiboThreadURLCanonicalizer.threadID(from: threadURL) ?? "704"
    }

    func addThreadFavorite(threadID: String, formHash: String?, resolveRemoteFavorite: Bool) async throws -> Favorite? {
        addedThreadIDs.append(threadID)
        return Favorite(title: "远端标题", threadID: threadID, remoteFavoriteID: "8801")
    }

    func deleteFavorite(remoteFavoriteID: String) async throws {
        deletedRemoteFavoriteIDs.append(remoteFavoriteID)
    }

    func remoteFavorite(forThreadID threadID: String, maxPages: Int) async throws -> Favorite? {
        Favorite(title: "远端标题", threadID: threadID, remoteFavoriteID: "8801")
    }
}
