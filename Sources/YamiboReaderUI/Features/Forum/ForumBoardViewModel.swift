import Foundation
import Observation
import YamiboReaderCore

protocol ForumBoardPageLoading: Sendable {
    func cachedForumBoard(
        fid: String,
        page: Int,
        filterID: String?,
        orderID: String?,
        allowExpired: Bool
    ) async -> ForumBoardPage?

    func fetchForumBoard(
        fid: String,
        title: String?,
        page: Int,
        filterID: String?,
        orderID: String?,
        preferCache: Bool
    ) async throws -> ForumBoardPage
}

extension ForumRepository: ForumBoardPageLoading {}

@MainActor
@Observable
final class ForumBoardViewModel {
    var page: ForumBoardPage?
    var errorMessage: String?
    var isLoading = false
    var isRefreshing = false
    var selectedFilterID: String?
    var selectedOrderID: String?
    var currentPage: Int

    let fid: String
    let initialTitle: String?

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumBoardPageLoading
    @ObservationIgnored private var generation = 0

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
        orders.first(where: { $0.id == selectedOrderID })?.title ?? L10n.string("forum.board.all")
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
            orderID: selectedOrderID,
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
        await reloadForOptionChange()
    }

    func selectOrder(id: String?) async {
        guard selectedOrderID != id else { return }
        selectedOrderID = id
        currentPage = 1
        await reloadForOptionChange()
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
                orderID: selectedOrderID,
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
}
