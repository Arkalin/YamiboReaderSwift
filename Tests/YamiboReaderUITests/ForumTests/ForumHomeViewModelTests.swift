import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class ForumHomeViewModelTests: XCTestCase {
    func testLoadShowsCachedHomeThenRefreshesWithoutResettingExpansion() async throws {
        let cached = makeHome(categoryIDs: ["a", "b", "c", "d"])
        let refreshed = makeHome(categoryIDs: ["a", "b", "c", "d", "e"])
        let repository = ForumHomeRepositoryStub(cached: cached, fetched: refreshed)
        let model = ForumHomeViewModel(repository: repository)

        await model.load()
        model.toggleCategory(id: "b")
        await model.refresh()

        XCTAssertEqual(model.categories.map(\.id), ["a", "b", "c", "d", "e"])
        XCTAssertTrue(model.expandedCategoryIDs.contains("a"))
        XCTAssertFalse(model.expandedCategoryIDs.contains("b"))
        XCTAssertTrue(model.expandedCategoryIDs.contains("c"))
        XCTAssertFalse(model.expandedCategoryIDs.contains("d"))
    }

    func testLoadPresentsErrorWhenNoCacheAndFetchFails() async throws {
        let repository = ForumHomeRepositoryStub(cached: nil, error: YamiboError.parsingFailed(context: "fixture"))
        let model = ForumHomeViewModel(repository: repository)

        await model.load()

        XCTAssertNil(model.page)
        XCTAssertNotNil(model.errorMessage)
    }

    func testManualRefreshFailureKeepsCachedHomeAndPresentsTransientMessage() async throws {
        let cached = makeHome(categoryIDs: ["a", "b"])
        let error = YamiboError.parsingFailed(context: "fixture")
        let repository = ForumHomeRepositoryStub(cached: cached, error: error)
        let model = ForumHomeViewModel(repository: repository)

        await model.load()
        await model.refresh()

        XCTAssertEqual(model.categories.map(\.id), ["a", "b"])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.transientMessage, L10n.string("forum.home.refresh_failed", error.localizedDescription))
    }

    func testCachedLoadBackgroundRefreshFailureDoesNotPresentTransientMessage() async throws {
        let cached = makeHome(categoryIDs: ["a", "b"])
        let repository = ForumHomeRepositoryStub(cached: cached, error: YamiboError.parsingFailed(context: "fixture"))
        let model = ForumHomeViewModel(repository: repository)

        await model.load()

        XCTAssertEqual(model.categories.map(\.id), ["a", "b"])
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.transientMessage)
    }
}

private actor ForumHomeRepositoryStub: ForumHomePageLoading {
    let cached: ForumHomePage?
    let fetched: ForumHomePage?
    let error: Error?

    init(cached: ForumHomePage?, fetched: ForumHomePage? = nil, error: Error? = nil) {
        self.cached = cached
        self.fetched = fetched
        self.error = error
    }

    func cachedForumHome(allowExpired _: Bool) async -> ForumHomePage? {
        cached
    }

    func fetchForumHome(preferCache _: Bool) async throws -> ForumHomePage {
        if let error {
            throw error
        }
        return fetched ?? cached ?? makeHome(categoryIDs: ["fallback"])
    }
}

private func makeHome(categoryIDs: [String]) -> ForumHomePage {
    ForumHomePage(
        categories: categoryIDs.map { id in
            ForumCategory(
                id: id,
                title: "Category \(id)",
                boards: [
                    ForumBoardSummary(
                        fid: id,
                        name: "Board \(id)",
                        url: ForumRouteResolver.boardURL(fid: id)
                    )
                ]
            )
        }
    )
}
