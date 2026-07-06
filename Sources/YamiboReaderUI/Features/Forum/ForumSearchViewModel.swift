import Foundation
import Observation
import YamiboReaderCore

protocol ForumSearchPageLoading: Sendable {
    func searchForum(query: String, forumID: String?, formHash: String?) async throws -> ForumSearchPage
    func searchForumPage(query: String, searchID: String, page: Int) async throws -> ForumSearchPage
}

extension ForumRepository: ForumSearchPageLoading {}

@MainActor
@Observable
final class ForumSearchViewModel {
    private struct PageSnapshot {
        var page: ForumSearchPage?
        var errorMessage: String?
        var currentPage: Int
        var currentSearchID: String?
    }

    var query = ""
    var page: ForumSearchPage?
    var errorMessage: String?
    var isLoading = false
    var currentPage = 1
    var currentSearchID: String?

    let forumID: String?

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumSearchPageLoading
    @ObservationIgnored private let formHashProvider: @Sendable () async -> String?
    @ObservationIgnored private lazy var pageNavigator = ForumPageNavigator<PageSnapshot>(
        capture: { [unowned self] in
            PageSnapshot(
                page: page,
                errorMessage: errorMessage,
                currentPage: currentPage,
                currentSearchID: currentSearchID
            )
        },
        restore: { [unowned self] snapshot in
            page = snapshot.page
            errorMessage = snapshot.errorMessage
            currentPage = snapshot.currentPage
            currentSearchID = snapshot.currentSearchID
        }
    )

    init(forumID: String?, appContext: YamiboAppContext) {
        self.forumID = forumID
        repositoryProvider = {
            await appContext.makeForumRepository()
        }
        formHashProvider = {
            await appContext.profileStore.load()?.formHash
        }
    }

    init(
        forumID: String?,
        repository: any ForumSearchPageLoading,
        formHash: String?
    ) {
        self.forumID = forumID
        repositoryProvider = {
            repository
        }
        formHashProvider = {
            formHash
        }
    }

    var results: [ForumThreadSummary] {
        page?.results ?? []
    }

    var pageNavigation: ForumPageNavigation? {
        page?.pageNavigation
    }

    var resultCountText: String? {
        guard let totalCount = page?.totalCount else { return nil }
        return L10n.string("forum.search.result_count", totalCount)
    }

    var canRestorePreviousPage: Bool {
        pageNavigator.canRestorePreviousPage
    }

    func searchFirstPage() async {
        pageNavigator.reset()
        currentPage = 1
        currentSearchID = nil
        await search(pageNumber: 1, recordsHistory: false)
    }

    func goToPage(_ pageNumber: Int) async {
        let nextPage = max(1, pageNumber)
        guard nextPage != currentPage else { return }
        await search(pageNumber: nextPage, recordsHistory: true)
    }

    @discardableResult
    func restorePreviousPage() -> Bool {
        pageNavigator.restorePreviousPage()
    }

    private func search(pageNumber: Int, recordsHistory: Bool) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        if recordsHistory {
            pageNavigator.recordCurrentPage()
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let repository = await repositoryProvider()
            let nextPage: ForumSearchPage
            if pageNumber == 1 || currentSearchID == nil {
                nextPage = try await repository.searchForum(
                    query: trimmedQuery,
                    forumID: forumID,
                    formHash: await formHashProvider()
                )
                currentSearchID = nextPage.searchID
            } else {
                nextPage = try await repository.searchForumPage(
                    query: trimmedQuery,
                    searchID: currentSearchID ?? "",
                    page: pageNumber
                )
            }
            page = nextPage
            currentPage = nextPage.pageNavigation?.currentPage ?? pageNumber
            errorMessage = nil
        } catch {
            if recordsHistory {
                pageNavigator.discardLastRecord()
            }
            page = nil
            currentPage = pageNumber
            errorMessage = error.localizedDescription
        }
    }
}
