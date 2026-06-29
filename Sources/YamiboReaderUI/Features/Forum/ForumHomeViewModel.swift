import Foundation
import Observation
import YamiboReaderCore

protocol ForumHomePageLoading: Sendable {
    func cachedForumHome(allowExpired: Bool) async -> ForumHomePage?
    func fetchForumHome(preferCache: Bool) async throws -> ForumHomePage
}

extension ForumRepository: ForumHomePageLoading {}

@MainActor
@Observable
final class ForumHomeViewModel {
    var page: ForumHomePage?
    var errorMessage: String?
    var isLoading = false
    var isRefreshing = false
    var expandedCategoryIDs: Set<String> = []

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumHomePageLoading
    @ObservationIgnored private var hasInitializedExpansion = false

    init(appContext: YamiboAppContext) {
        repositoryProvider = {
            await appContext.makeForumRepository()
        }
    }

    init(repository: any ForumHomePageLoading) {
        repositoryProvider = {
            repository
        }
    }

    var categories: [ForumCategory] {
        page?.categories ?? []
    }

    var carouselItems: [ForumHomeCarouselItem] {
        page?.carouselItems ?? []
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let repository = await repositoryProvider()
        if let cached = await repository.cachedForumHome(allowExpired: false) {
            apply(cached)
            await refresh(presentsErrors: false)
            return
        }

        do {
            apply(try await repository.fetchForumHome(preferCache: false))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        await refresh(presentsErrors: true)
    }

    func toggleCategory(id: String) {
        if expandedCategoryIDs.contains(id) {
            expandedCategoryIDs.remove(id)
        } else {
            expandedCategoryIDs.insert(id)
        }
    }

    private func refresh(presentsErrors: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let repository = await repositoryProvider()
            apply(try await repository.fetchForumHome(preferCache: false))
            errorMessage = nil
        } catch {
            if presentsErrors || page == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ page: ForumHomePage) {
        self.page = page
        initializeExpansionIfNeeded(with: page.categories)
    }

    private func initializeExpansionIfNeeded(with categories: [ForumCategory]) {
        guard !hasInitializedExpansion else { return }
        hasInitializedExpansion = true
        expandedCategoryIDs = Set(categories.prefix(3).map(\.id))
    }
}
