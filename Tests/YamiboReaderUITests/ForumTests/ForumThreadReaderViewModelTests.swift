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

    await model.toggleFavorite()

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
    #expect(await fixture.favoriteRepository.addedThreadURLs == [fixture.threadURL])

    await model.toggleFavorite()

    #expect(!model.isFavorited)
    #expect(await fixture.localFavoriteItem() == nil)
    #expect(await fixture.favoriteRepository.deletedRemoteFavoriteIDs == ["8801"])
}

@MainActor
@Test func forumThreadReaderToggleBeforePageLoadUsesContextForumID() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.toggleFavorite()

    let added = try #require(await fixture.localFavoriteItem())
    #expect(added.title == "上下文标题")
    #expect(added.forumID == "40")
    #expect(added.sourceGroup == .forumBoard(id: "40", label: "40"))
}

@MainActor
@Test func forumThreadReaderLoadUsesCachedPageWithoutFetching() async throws {
    let cachedPage = ForumThreadPage(
        thread: ThreadIdentity(tid: "704", canonicalURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2"))),
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
        thread: ThreadIdentity(tid: "704", canonicalURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2"))),
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
    threadURL: URL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2")!
) -> ForumThreadPage {
    ForumThreadPage(
        thread: ThreadIdentity(tid: "704", canonicalURL: threadURL),
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
        forumName: "综合讨论"
    )
}

private struct ForumThreadReaderViewModelFixture {
    let suiteName: String
    let threadURL: URL
    let localFavoriteLibraryStore: FavoriteLibraryStore
    let repository: FakeForumThreadPageLoader
    let favoriteRepository: FakeThreadFavoriteRepository

    init(cachedPages: [Int: ForumThreadPage] = [:], fetchError: Error? = nil) throws {
        suiteName = "ForumThreadReaderViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2"))
        localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            key: "local-favorites"
        )
        repository = FakeForumThreadPageLoader(threadURL: threadURL, cachedPages: cachedPages, fetchError: fetchError)
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
            context: ThreadReaderLaunchContext(
                thread: ThreadIdentity(tid: "704", canonicalURL: threadURL, fid: "40"),
                title: "上下文标题"
            ),
            repository: repository,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            favoriteRepository: favoriteRepository
        )
    }
}

private final class FakeForumThreadPageLoader: ForumThreadPageLoading, @unchecked Sendable {
    let threadURL: URL
    private let cachedPages: [Int: ForumThreadPage]
    var fetchError: Error?
    private var recordedCachedPages: [Int] = []
    private var recordedFetchPages: [Int] = []

    init(threadURL: URL, cachedPages: [Int: ForumThreadPage] = [:], fetchError: Error? = nil) {
        self.threadURL = threadURL
        self.cachedPages = cachedPages
        self.fetchError = fetchError
    }

    func cachedThreadPage(context _: ThreadReaderLaunchContext, page: Int) async -> ForumThreadPage? {
        recordedCachedPages.append(page)
        return cachedPages[page]
    }

    func fetchThreadPage(context: ThreadReaderLaunchContext, page: Int) async throws -> ForumThreadPage {
        recordedFetchPages.append(page)
        if let fetchError {
            throw fetchError
        }
        return makeThreadPage(title: "解析标题", postID: "4001", contentText: "正文", page: page, threadURL: threadURL)
    }

    func cachedPageCalls() -> [Int] {
        recordedCachedPages
    }

    func fetchPageCalls() -> [Int] {
        recordedFetchPages
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
        ""
    }

    func ratePost(
        threadID: String,
        postID: String,
        score: Int,
        reason: String,
        formHash: String,
        noticeAuthor: Bool
    ) async throws -> String {
        ""
    }

    func commentPost(threadID: String, postID: String, message: String, formHash: String, page: Int) async throws -> String {
        ""
    }
}

private actor FakeThreadFavoriteRepository: ForumThreadFavoriteRemoteOperating {
    let threadURL: URL
    var addedThreadURLs: [URL] = []
    var deletedRemoteFavoriteIDs: [String] = []

    init(threadURL: URL) {
        self.threadURL = threadURL
    }

    func addThreadFavorite(threadURL: URL, formHash: String?) async throws -> Favorite? {
        addedThreadURLs.append(threadURL)
        return Favorite(title: "远端标题", url: threadURL, remoteFavoriteID: "8801")
    }

    func deleteFavorite(remoteFavoriteID: String) async throws {
        deletedRemoteFavoriteIDs.append(remoteFavoriteID)
    }

    func remoteFavorite(for threadURL: URL, maxPages: Int) async throws -> Favorite? {
        Favorite(title: "远端标题", url: threadURL, remoteFavoriteID: "8801")
    }
}
