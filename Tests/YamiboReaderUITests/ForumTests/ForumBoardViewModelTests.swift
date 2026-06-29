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
        var orderID: String?
        var preferCache: Bool
    }

    let cached: ForumBoardPage?
    let error: Error?
    var fetchedPages: [ForumBoardPage]
    var fetchRequests: [FetchRequest] = []

    init(
        cached: ForumBoardPage?,
        fetched: ForumBoardPage? = nil,
        fetchedPages: [ForumBoardPage] = [],
        error: Error? = nil
    ) {
        self.cached = cached
        self.error = error
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
        orderID _: String?,
        allowExpired _: Bool
    ) async -> ForumBoardPage? {
        cached
    }

    func fetchForumBoard(
        fid _: String,
        title _: String?,
        page: Int,
        filterID: String?,
        orderID: String?,
        preferCache: Bool
    ) async throws -> ForumBoardPage {
        fetchRequests.append(
            FetchRequest(page: page, filterID: filterID, orderID: orderID, preferCache: preferCache)
        )
        if let error {
            throw error
        }
        if !fetchedPages.isEmpty {
            return fetchedPages.removeFirst()
        }
        return makeBoardPage(fid: "5", title: "Fallback", page: page, threadIDs: ["fallback"])
    }

    func requests() -> [FetchRequest] {
        fetchRequests
    }
}

private func makeBoardPage(
    fid: String,
    title: String,
    page: Int,
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
        orders: orders
    )
}
