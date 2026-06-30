import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
@Test func forumThreadReaderLoadsExistingLocalFavoriteState() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    try await fixture.favoriteStore.saveFavorites([
        Favorite(title: "已收藏标题", url: fixture.threadURL, type: .other)
    ])
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

    let added = try #require(await fixture.favoriteStore.favorite(for: fixture.threadURL))
    #expect(model.isFavorited)
    #expect(added.title == "解析标题")
    #expect(added.type == .other)
    #expect(added.remoteFavoriteID == "8801")
    #expect(await fixture.favoriteRepository.addedThreadURLs == [fixture.threadURL])

    await model.toggleFavorite()

    #expect(!model.isFavorited)
    #expect(await fixture.favoriteStore.favorite(for: fixture.threadURL) == nil)
    #expect(await fixture.favoriteRepository.deletedRemoteFavoriteIDs == ["8801"])
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

private struct ForumThreadReaderViewModelFixture {
    let suiteName: String
    let threadURL: URL
    let favoriteStore: FavoriteStore
    let repository: FakeForumThreadPageLoader
    let favoriteRepository: FakeThreadFavoriteRepository

    init(cachedPages: [Int: ForumThreadPage] = [:]) throws {
        suiteName = "ForumThreadReaderViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2"))
        favoriteStore = FavoriteStore(defaults: defaults, key: "favorites")
        repository = FakeForumThreadPageLoader(threadURL: threadURL, cachedPages: cachedPages)
        favoriteRepository = FakeThreadFavoriteRepository(threadURL: threadURL)
    }

    @MainActor
    func makeModel() -> ForumThreadReaderViewModel {
        ForumThreadReaderViewModel(
            context: ThreadReaderLaunchContext(
                thread: ThreadIdentity(tid: "704", canonicalURL: threadURL),
                title: "上下文标题"
            ),
            repository: repository,
            favoriteStore: favoriteStore,
            favoriteRepository: favoriteRepository
        )
    }
}

private final class FakeForumThreadPageLoader: ForumThreadPageLoading, @unchecked Sendable {
    let threadURL: URL
    private let cachedPages: [Int: ForumThreadPage]
    private var recordedCachedPages: [Int] = []
    private var recordedFetchPages: [Int] = []

    init(threadURL: URL, cachedPages: [Int: ForumThreadPage] = [:]) {
        self.threadURL = threadURL
        self.cachedPages = cachedPages
    }

    func cachedThreadPage(context _: ThreadReaderLaunchContext, page: Int) async -> ForumThreadPage? {
        recordedCachedPages.append(page)
        return cachedPages[page]
    }

    func fetchThreadPage(context: ThreadReaderLaunchContext, page: Int) async throws -> ForumThreadPage {
        recordedFetchPages.append(page)
        return ForumThreadPage(
            thread: ThreadIdentity(tid: "704", canonicalURL: threadURL),
            title: "解析标题",
            posts: [
                ForumThreadPost(
                    postID: "4001",
                    author: BlogReaderUser(uid: "42", name: "楼主"),
                    contentHTML: "",
                    contentText: "正文"
                )
            ],
            pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 4)
        )
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
