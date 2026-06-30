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
@Test func forumThreadReaderTogglesLocalFavorite() async throws {
    let fixture = try ForumThreadReaderViewModelFixture()
    let model = fixture.makeModel()

    await model.load()
    #expect(!model.isFavorited)

    await model.toggleFavorite()

    let added = try #require(await fixture.favoriteStore.favorite(for: fixture.threadURL))
    #expect(model.isFavorited)
    #expect(added.title == "解析标题")
    #expect(added.type == .other)

    await model.toggleFavorite()

    #expect(!model.isFavorited)
    #expect(await fixture.favoriteStore.favorite(for: fixture.threadURL) == nil)
}

private struct ForumThreadReaderViewModelFixture {
    let suiteName: String
    let threadURL: URL
    let favoriteStore: FavoriteStore
    let repository: FakeForumThreadPageLoader

    init() throws {
        suiteName = "ForumThreadReaderViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=704&mobile=2"))
        favoriteStore = FavoriteStore(defaults: defaults, key: "favorites")
        repository = FakeForumThreadPageLoader(threadURL: threadURL)
    }

    @MainActor
    func makeModel() -> ForumThreadReaderViewModel {
        ForumThreadReaderViewModel(
            context: ThreadReaderLaunchContext(
                thread: ThreadIdentity(tid: "704", canonicalURL: threadURL),
                title: "上下文标题"
            ),
            repository: repository,
            favoriteStore: favoriteStore
        )
    }
}

private final class FakeForumThreadPageLoader: ForumThreadPageLoading, @unchecked Sendable {
    let threadURL: URL

    init(threadURL: URL) {
        self.threadURL = threadURL
    }

    func fetchThreadPage(context: ThreadReaderLaunchContext, page: Int) async throws -> ForumThreadPage {
        ForumThreadPage(
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
