import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class ForumSearchViewModelTests: XCTestCase {
    func testSearchFirstPageUsesFormHashAndForumScope() async throws {
        let firstPage = makeSearchPage(query: "百合", searchID: "99", page: 1, threadIDs: ["100"])
        let repository = ForumSearchRepositoryStub(pages: [firstPage])
        let model = ForumSearchViewModel(forumID: "5", repository: repository, formHash: "f47bb54f")
        model.query = " 百合 "

        await model.searchFirstPage()

        XCTAssertEqual(model.results.map(\.tid), ["100"])
        XCTAssertEqual(model.currentSearchID, "99")
        XCTAssertEqual(model.currentPage, 1)
        let searches = await repository.searchRequests()
        XCTAssertEqual(searches, [.init(query: "百合", forumID: "5", formHash: "f47bb54f")])
    }

    func testGoToPageUsesCurrentSearchIDAndRestoresPreviousPage() async throws {
        let firstPage = makeSearchPage(query: "百合", searchID: "99", page: 1, threadIDs: ["100"])
        let secondPage = makeSearchPage(query: "百合", searchID: "99", page: 2, threadIDs: ["200"])
        let repository = ForumSearchRepositoryStub(pages: [firstPage, secondPage])
        let model = ForumSearchViewModel(forumID: nil, repository: repository, formHash: "f47bb54f")
        model.query = "百合"

        await model.searchFirstPage()
        await model.goToPage(2)

        XCTAssertEqual(model.results.map(\.tid), ["200"])
        XCTAssertEqual(model.currentPage, 2)
        let pageRequests = await repository.pageRequests()
        XCTAssertEqual(pageRequests, [.init(query: "百合", searchID: "99", page: 2)])
        XCTAssertTrue(model.restorePreviousPage())
        XCTAssertEqual(model.results.map(\.tid), ["100"])
        XCTAssertEqual(model.currentPage, 1)
    }

    func testSearchFirstPageShowsMissingTokenError() async throws {
        let repository = ForumSearchRepositoryStub(error: YamiboError.missingForumSearchToken)
        let model = ForumSearchViewModel(forumID: nil, repository: repository, formHash: nil)
        model.query = "百合"

        await model.searchFirstPage()

        XCTAssertTrue(model.results.isEmpty)
        XCTAssertEqual(model.errorMessage, YamiboError.missingForumSearchToken.localizedDescription)
    }
}

private actor ForumSearchRepositoryStub: ForumSearchPageLoading {
    struct SearchRequest: Equatable {
        var query: String
        var forumID: String?
        var formHash: String?
    }

    struct PageRequest: Equatable {
        var query: String
        var searchID: String
        var page: Int
    }

    let error: Error?
    var pages: [ForumSearchPage]
    var searches: [SearchRequest] = []
    var searchPages: [PageRequest] = []

    init(pages: [ForumSearchPage] = [], error: Error? = nil) {
        self.pages = pages
        self.error = error
    }

    func searchForum(query: String, forumID: String?, formHash: String?) async throws -> ForumSearchPage {
        searches.append(.init(query: query, forumID: forumID, formHash: formHash))
        if let error {
            throw error
        }
        return pages.removeFirst()
    }

    func searchForumPage(query: String, searchID: String, page: Int) async throws -> ForumSearchPage {
        searchPages.append(.init(query: query, searchID: searchID, page: page))
        if let error {
            throw error
        }
        return pages.removeFirst()
    }

    func searchRequests() -> [SearchRequest] {
        searches
    }

    func pageRequests() -> [PageRequest] {
        searchPages
    }
}

private func makeSearchPage(
    query: String,
    searchID: String,
    page: Int,
    threadIDs: [String]
) -> ForumSearchPage {
    ForumSearchPage(
        query: query,
        searchID: searchID,
        totalCount: threadIDs.count,
        results: threadIDs.map { id in
            ForumThreadSummary(
                tid: id,
                title: "Thread \(id)",
                url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(id)&mobile=2")!
            )
        },
        pageNavigation: ForumPageNavigation(currentPage: page, totalPages: 3)
    )
}
