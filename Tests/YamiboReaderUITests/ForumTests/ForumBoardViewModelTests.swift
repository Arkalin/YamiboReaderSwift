import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class ForumBoardViewModelTests: XCTestCase {
    func testLoadShowsCachedBoardThenRefreshes() async throws {
        let cached = makeBoardPage(fid: "5", title: "Cached", page: 1, threadIDs: ["cached"])
        let fetched = makeBoardPage(fid: "5", title: "Fetched", page: 1, threadIDs: ["fresh"])
        let repository = ForumBoardRepositoryStub(cached: cached, fetched: fetched)
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", repository: repository)

        await model.load()

        XCTAssertEqual(model.title, "Fetched")
        XCTAssertEqual(model.threads.map(\.tid), ["fresh"])
        let requests = await repository.requests()
        XCTAssertEqual(requests.count, 1)
    }

    func testSelectingFilterReloadsFirstPageWithFilterID() async throws {
        let fetched = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 2,
            filters: [ForumFilterOption(id: "400", title: "动画讨论")],
            threadIDs: ["before"]
        )
        let filtered = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 1,
            filters: [ForumFilterOption(id: "400", title: "动画讨论")],
            threadIDs: ["after"]
        )
        let repository = ForumBoardRepositoryStub(cached: nil, fetchedPages: [fetched, filtered])
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", initialPage: 2, repository: repository)

        await model.load()
        await model.selectFilter(id: "400")

        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.selectedFilterID, "400")
        XCTAssertEqual(model.threads.map(\.tid), ["after"])
        let requests = await repository.requests()
        XCTAssertEqual(requests.map(\.page), [2, 1])
        XCTAssertEqual(requests.last?.filterID, "400")
    }

    func testSelectingOrderReloadsWithOrderFilterAndOrderBy() async throws {
        let fetched = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 1,
            orders: [ForumOrderOption(id: "lastpost", title: "最新", filter: "lastpost", orderBy: "lastpost")],
            threadIDs: ["before"]
        )
        let ordered = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 1,
            orders: [ForumOrderOption(id: "lastpost", title: "最新", filter: "lastpost", orderBy: "lastpost")],
            threadIDs: ["after"]
        )
        let repository = ForumBoardRepositoryStub(cached: nil, fetchedPages: [fetched, ordered])
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", repository: repository)

        await model.load()
        await model.selectOrder(id: "lastpost")

        XCTAssertEqual(model.selectedOrderOptionID, "lastpost")
        XCTAssertEqual(model.threads.map(\.tid), ["after"])
        let requests = await repository.requests()
        XCTAssertEqual(requests.last?.orderFilter, "lastpost")
        XCTAssertEqual(requests.last?.orderBy, "lastpost")
    }

    func testPagingCanRestorePreviousBoardSnapshot() async throws {
        let first = makeBoardPage(fid: "5", title: "動漫區", page: 1, threadIDs: ["first"])
        let second = makeBoardPage(fid: "5", title: "動漫區", page: 2, threadIDs: ["second"])
        let repository = ForumBoardRepositoryStub(cached: nil, fetchedPages: [first, second])
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", repository: repository)

        await model.load()
        await model.goToPage(2)

        XCTAssertTrue(model.canRestorePreviousPage)
        XCTAssertEqual(model.currentPage, 2)
        XCTAssertEqual(model.threads.map(\.tid), ["second"])

        XCTAssertTrue(model.restorePreviousPage())

        XCTAssertFalse(model.canRestorePreviousPage)
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.threads.map(\.tid), ["first"])
        let requests = await repository.requests()
        XCTAssertEqual(requests.map(\.page), [1, 2])
    }

    func testSelectingFilterClearsBoardPageHistory() async throws {
        let first = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 1,
            filters: [ForumFilterOption(id: "400", title: "动画讨论")],
            threadIDs: ["first"]
        )
        let second = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 2,
            filters: [ForumFilterOption(id: "400", title: "动画讨论")],
            threadIDs: ["second"]
        )
        let filtered = makeBoardPage(
            fid: "5",
            title: "動漫區",
            page: 1,
            filters: [ForumFilterOption(id: "400", title: "动画讨论")],
            threadIDs: ["filtered"]
        )
        let repository = ForumBoardRepositoryStub(cached: nil, fetchedPages: [first, second, filtered])
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", repository: repository)

        await model.load()
        await model.goToPage(2)
        await model.selectFilter(id: "400")

        XCTAssertFalse(model.canRestorePreviousPage)
        XCTAssertFalse(model.restorePreviousPage())
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.selectedFilterID, "400")
        XCTAssertEqual(model.threads.map(\.tid), ["filtered"])
    }

    func testAddFavoriteUsesCurrentPageFormHash() async throws {
        let fetched = makeBoardPage(fid: "5", title: "動漫區", page: 1, formHash: "f47bb54f", threadIDs: ["fresh"])
        let repository = ForumBoardRepositoryStub(cached: nil, fetched: fetched, favoriteMessage: "收藏成功")
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", repository: repository)

        await model.load()
        await model.addFavorite()

        XCTAssertEqual(model.favoriteMessage, "收藏成功")
        let favorites = await repository.favoriteRequests()
        XCTAssertEqual(favorites, [.init(fid: "5", formHash: "f47bb54f")])
    }

    func testLoadPresentsErrorWhenNoCacheAndFetchFails() async throws {
        let repository = ForumBoardRepositoryStub(cached: nil, error: YamiboError.parsingFailed(context: "fixture"))
        let model = ForumBoardViewModel(fid: "5", title: "動漫區", repository: repository)

        await model.load()

        XCTAssertNil(model.page)
        XCTAssertNotNil(model.errorMessage)
    }
}

private actor ForumBoardRepositoryStub: ForumBoardPageLoading {
    struct FetchRequest: Equatable {
        var page: Int
        var filterID: String?
        var orderFilter: String?
        var orderBy: String?
        var preferCache: Bool
    }

    struct FavoriteRequest: Equatable {
        var fid: String
        var formHash: String?
    }

    let cached: ForumBoardPage?
    let error: Error?
    let favoriteMessage: String
    var fetchedPages: [ForumBoardPage]
    var fetchRequests: [FetchRequest] = []
    var boardFavoriteRequests: [FavoriteRequest] = []

    init(
        cached: ForumBoardPage?,
        fetched: ForumBoardPage? = nil,
        fetchedPages: [ForumBoardPage] = [],
        favoriteMessage: String = "收藏成功",
        error: Error? = nil
    ) {
        self.cached = cached
        self.error = error
        self.favoriteMessage = favoriteMessage
        if let fetched {
            self.fetchedPages = [fetched]
        } else {
            self.fetchedPages = fetchedPages
        }
    }

    func cachedForumBoard(
        fid _: String,
        page _: Int,
        filterID _: String?,
        orderFilter _: String?,
        orderBy _: String?,
        allowExpired _: Bool
    ) async -> ForumBoardPage? {
        cached
    }

    func fetchForumBoard(
        fid _: String,
        title _: String?,
        page: Int,
        filterID: String?,
        orderFilter: String?,
        orderBy: String?,
        preferCache: Bool
    ) async throws -> ForumBoardPage {
        fetchRequests.append(
            FetchRequest(page: page, filterID: filterID, orderFilter: orderFilter, orderBy: orderBy, preferCache: preferCache)
        )
        if let error {
            throw error
        }
        if !fetchedPages.isEmpty {
            return fetchedPages.removeFirst()
        }
        return makeBoardPage(fid: "5", title: "Fallback", page: page, threadIDs: ["fallback"])
    }

    func addBoardFavorite(fid: String, formHash: String?) async throws -> String {
        boardFavoriteRequests.append(.init(fid: fid, formHash: formHash))
        if let error {
            throw error
        }
        return favoriteMessage
    }

    func requests() -> [FetchRequest] {
        fetchRequests
    }

    func favoriteRequests() -> [FavoriteRequest] {
        boardFavoriteRequests
    }
}

private func makeBoardPage(
    fid: String,
    title: String,
    page: Int,
    formHash: String? = nil,
    filters: [ForumFilterOption] = [],
    orders: [ForumOrderOption] = [],
    threadIDs: [String]
) -> ForumBoardPage {
    ForumBoardPage(
        board: ForumBoardSummary(
            fid: fid,
            name: title,
            url: ForumRouteResolver.boardURL(fid: fid)
        ),
        threads: threadIDs.map { id in
            ForumThreadSummary(
                tid: id,
                title: "Thread \(id)",
                url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(id)&mobile=2")!
            )
        },
        pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 3),
        filters: filters,
        orders: orders,
        formHash: formHash
    )
}
