import Foundation
import Observation
import YamiboReaderCore

protocol ForumBoardPageLoading: Sendable {
    func cachedForumBoard(
        fid: String,
        page: Int,
        filterID: String?,
        orderFilter: String?,
        orderBy: String?,
        allowExpired: Bool
    ) async -> ForumBoardPage?

    func fetchForumBoard(
        fid: String,
        title: String?,
        page: Int,
        filterID: String?,
        orderFilter: String?,
        orderBy: String?,
        preferCache: Bool
    ) async throws -> ForumBoardPage

    func addBoardFavorite(fid: String, formHash: String?) async throws -> String
}

extension ForumRepository: ForumBoardPageLoading {}

@MainActor
@Observable
final class ForumBoardViewModel {
    private struct PageSnapshot {
        var page: ForumBoardPage?
        var errorMessage: String?
        var currentPage: Int
        var selectedFilterID: String?
        var selectedOrderOptionID: String?
    }

    var page: ForumBoardPage?
    var errorMessage: String?
    var favoriteMessage: String?
    var isLoading = false
    var isRefreshing = false
    var isFavoriting = false
    var selectedFilterID: String?
    var selectedOrderOptionID: String?
    var currentPage: Int

    let fid: String
    let initialTitle: String?

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumBoardPageLoading
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pageHistory: [PageSnapshot] = []

    init(fid: String, title: String?, initialPage: Int = 1, appContext: YamiboAppContext) {
        self.fid = fid
        initialTitle = title
        currentPage = max(1, initialPage)
        repositoryProvider = {
            await appContext.makeForumRepository()
        }
    }

    init(
        fid: String,
        title: String?,
        initialPage: Int = 1,
        repository: any ForumBoardPageLoading
    ) {
        self.fid = fid
        initialTitle = title
        currentPage = max(1, initialPage)
        repositoryProvider = {
            repository
        }
    }

    var title: String {
        page?.board.name ?? initialTitle ?? L10n.string("forum.board")
    }

    var subBoards: [ForumBoardSummary] {
        page?.subBoards ?? []
    }

    var pinnedItems: [ForumPinnedItem] {
        page?.pinnedItems ?? []
    }

    var threads: [ForumThreadSummary] {
        page?.threads ?? []
    }

    var pageNavigation: ForumPageNavigation? {
        page?.pageNavigation
    }

    var canRestorePreviousPage: Bool {
        !pageHistory.isEmpty
    }

    var filters: [ForumFilterOption] {
        page?.filters ?? []
    }

    var orders: [ForumOrderOption] {
        page?.orders ?? []
    }

    var selectedFilterTitle: String {
        filters.first(where: { $0.id == selectedFilterID })?.title ?? L10n.string("forum.board.all")
    }

    var selectedOrderTitle: String {
        selectedOrderOption?.title ?? L10n.string("forum.board.all")
    }

    private var selectedOrderOption: ForumOrderOption? {
        orders.first(where: { $0.id == selectedOrderOptionID })
    }

    func load() async {
        guard !isLoading else { return }
        generation += 1
        let requestGeneration = generation
        isLoading = true
        defer { isLoading = false }

        let repository = await repositoryProvider()
        if let cached = await repository.cachedForumBoard(
            fid: fid,
            page: currentPage,
            filterID: selectedFilterID,
            orderFilter: selectedOrderOption?.filter,
            orderBy: selectedOrderOption?.orderBy,
            allowExpired: false
        ) {
            apply(cached)
            await refresh(presentsErrors: false, requestGeneration: requestGeneration)
            return
        }

        await fetchPage(currentPage, preferCache: false, presentsErrors: true, requestGeneration: requestGeneration)
    }

    func refresh() async {
        generation += 1
        await refresh(presentsErrors: true, requestGeneration: generation)
    }

    func goToPage(_ page: Int) async {
        let nextPage = max(1, page)
        guard nextPage != currentPage else { return }
        pushCurrentPageSnapshot()
        generation += 1
        let requestGeneration = generation
        currentPage = nextPage
        isLoading = true
        defer { isLoading = false }
        await fetchPage(nextPage, preferCache: true, presentsErrors: true, requestGeneration: requestGeneration)
    }

    func selectFilter(id: String?) async {
        guard selectedFilterID != id else { return }
        selectedFilterID = id
        currentPage = 1
        pageHistory.removeAll()
        await reloadForOptionChange()
    }

    func selectOrder(id: String?) async {
        guard selectedOrderOptionID != id else { return }
        selectedOrderOptionID = id
        currentPage = 1
        pageHistory.removeAll()
        await reloadForOptionChange()
    }

    @discardableResult
    func restorePreviousPage() -> Bool {
        guard let snapshot = pageHistory.popLast() else { return false }
        generation += 1
        page = snapshot.page
        errorMessage = snapshot.errorMessage
        currentPage = snapshot.currentPage
        selectedFilterID = snapshot.selectedFilterID
        selectedOrderOptionID = snapshot.selectedOrderOptionID
        isLoading = false
        isRefreshing = false
        return true
    }

    func addFavorite() async {
        guard !isFavoriting else { return }
        isFavoriting = true
        defer { isFavoriting = false }

        do {
            let repository = await repositoryProvider()
            favoriteMessage = try await repository.addBoardFavorite(fid: fid, formHash: page?.formHash)
        } catch {
            favoriteMessage = error.localizedDescription
        }
    }

    private func reloadForOptionChange() async {
        generation += 1
        let requestGeneration = generation
        isLoading = true
        defer { isLoading = false }
        await fetchPage(1, preferCache: true, presentsErrors: true, requestGeneration: requestGeneration)
    }

    private func refresh(presentsErrors: Bool, requestGeneration: Int) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await fetchPage(currentPage, preferCache: false, presentsErrors: presentsErrors, requestGeneration: requestGeneration)
    }

    private func fetchPage(
        _ pageNumber: Int,
        preferCache: Bool,
        presentsErrors: Bool,
        requestGeneration: Int
    ) async {
        do {
            let repository = await repositoryProvider()
            let nextPage = try await repository.fetchForumBoard(
                fid: fid,
                title: initialTitle,
                page: pageNumber,
                filterID: selectedFilterID,
                orderFilter: selectedOrderOption?.filter,
                orderBy: selectedOrderOption?.orderBy,
                preferCache: preferCache
            )
            guard requestGeneration == generation else { return }
            apply(nextPage)
            errorMessage = nil
        } catch {
            guard requestGeneration == generation else { return }
            if presentsErrors || page == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ page: ForumBoardPage) {
        self.page = page
        currentPage = page.pageNavigation?.currentPage ?? currentPage
    }

    private func pushCurrentPageSnapshot() {
        pageHistory.append(
            PageSnapshot(
                page: page,
                errorMessage: errorMessage,
                currentPage: currentPage,
                selectedFilterID: selectedFilterID,
                selectedOrderOptionID: selectedOrderOptionID
            )
        )
    }
}
