import Foundation
import Observation
import YamiboReaderCore

protocol ForumThreadPageLoading: Sendable {
    func cachedThreadPage(context: ThreadReaderLaunchContext, page: Int) async -> ForumThreadPage?
    func fetchThreadPage(context: ThreadReaderLaunchContext, page: Int) async throws -> ForumThreadPage
    func fetchRatingResults(threadID: String, postID: String) async throws -> ForumThreadRatingResultsPage
    func fetchRateOptions(threadID: String, postID: String) async throws -> ForumThreadRateOptionsPage
    func fetchPollVoters(threadID: String, optionID: String?, page: Int) async throws -> ForumThreadPollVotersPage
    func votePoll(forumID: String, threadID: String, optionIDs: [String], formHash: String) async throws -> String
    func ratePost(
        threadID: String,
        postID: String,
        score: Int,
        reason: String,
        formHash: String,
        noticeAuthor: Bool
    ) async throws -> String
    func commentPost(threadID: String, postID: String, message: String, formHash: String, page: Int) async throws -> String
}

extension ForumThreadReaderRepository: ForumThreadPageLoading {}

@MainActor
@Observable
final class ForumThreadReaderViewModel {
    var page: ForumThreadPage?
    var currentPage = 1
    var isLoading = false
    var errorMessage: String?
    var transientMessage: String?
    var isFavorited = false
    var favoriteErrorMessage: String?
    var inlineImageLoadingContext: NovelInlineImageLoadingContext?

    let context: ThreadReaderLaunchContext

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumThreadPageLoading
    @ObservationIgnored private let localFavoriteLibraryStoreProvider: @Sendable () async -> LocalFirstFavoriteLibraryStore?
    @ObservationIgnored private let readingProgressStoreProvider: @Sendable () async -> ReadingProgressStore?
    @ObservationIgnored private let favoriteRepositoryProvider: @Sendable () async -> (any ForumThreadFavoriteRemoteOperating)?
    @ObservationIgnored private let inlineImageLoadingContextProvider: @Sendable () async -> NovelInlineImageLoadingContext?

    init(context: ThreadReaderLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        repositoryProvider = {
            await appContext.makeForumThreadReaderRepository()
        }
        localFavoriteLibraryStoreProvider = {
            appContext.localFavoriteLibraryStore
        }
        readingProgressStoreProvider = {
            appContext.readingProgressStore
        }
        favoriteRepositoryProvider = {
            await appContext.makeFavoriteRepository()
        }
        inlineImageLoadingContextProvider = {
            await appContext.makeNovelInlineImageLoadingContext()
        }
    }

    init(
        context: ThreadReaderLaunchContext,
        repository: any ForumThreadPageLoading,
        localFavoriteLibraryStore: LocalFirstFavoriteLibraryStore? = nil,
        readingProgressStore: ReadingProgressStore? = nil,
        favoriteRepository: (any ForumThreadFavoriteRemoteOperating)? = nil
    ) {
        self.context = context
        repositoryProvider = {
            repository
        }
        localFavoriteLibraryStoreProvider = {
            localFavoriteLibraryStore
        }
        readingProgressStoreProvider = {
            readingProgressStore
        }
        favoriteRepositoryProvider = {
            favoriteRepository
        }
        inlineImageLoadingContextProvider = {
            nil
        }
    }

    var navigationTitle: String {
        page?.title ?? context.title
    }

    var pageNavigation: ForumPageNavigation? {
        page?.pageNavigation
    }

    var targetPostID: String? {
        context.targetPostID
    }

    func load() async {
        guard page == nil else { return }
        await refreshFavoriteState()
        await loadPage(context.initialPage)
    }

    func refresh() async {
        await loadPage(
            currentPage,
            preferCache: false,
            preservesCurrentContentOnFailure: true,
            usesCachedFallbackOnFailure: true
        )
    }

    func retry() {
        Task {
            await refresh()
        }
    }

    func goToPage(_ page: Int) async {
        let nextPage = max(1, page)
        guard nextPage != currentPage else { return }
        await loadPage(nextPage)
    }

    func clearFavoriteError() {
        favoriteErrorMessage = nil
    }

    func clearTransientMessage() {
        transientMessage = nil
    }

    func toggleFavorite() async {
        let url = context.thread.canonicalURL

        do {
            guard let localFavoriteLibraryStore = await localFavoriteLibraryStoreProvider() else {
                throw YamiboError.persistenceFailed("Local favorite library store is unavailable")
            }
            if let favoriteItem = await localFavoriteItem(for: url) {
                try await ForumThreadFavoriteSync.removeFavorite(
                    favoriteItem.favorite(threadURL: url, type: .other),
                    localFavoriteLibraryStore: localFavoriteLibraryStore,
                    readingProgressStore: await readingProgressStoreProvider(),
                    remoteRepository: await favoriteRepositoryProvider()
                )
                isFavorited = false
                return
            }

            _ = try await ForumThreadFavoriteSync.addFavorite(
                threadURL: url,
                title: favoriteTitle,
                type: .other,
                authorID: nil,
                forumID: page?.forumID ?? page?.thread.fid ?? context.thread.fid,
                forumName: page?.forumName,
                coverURL: ThreadCoverResolver.findThreadCoverCandidate(in: page),
                contentUpdatedAt: Self.contentUpdatedAt(from: page),
                formHash: page?.formHash,
                localFavoriteLibraryStore: localFavoriteLibraryStore,
                remoteRepository: await favoriteRepositoryProvider()
            )
            isFavorited = true
        } catch {
            favoriteErrorMessage = error.localizedDescription
            await refreshFavoriteState()
        }
    }

    func loadRatingResults(threadID: String, postID: String) async throws -> ForumThreadRatingResultsPage {
        let repository = await repositoryProvider()
        return try await repository.fetchRatingResults(threadID: threadID, postID: postID)
    }

    func loadRateOptions(threadID: String, postID: String) async throws -> ForumThreadRateOptionsPage {
        let repository = await repositoryProvider()
        return try await repository.fetchRateOptions(threadID: threadID, postID: postID)
    }

    func loadPollVoters(threadID: String, optionID: String?, page: Int) async throws -> ForumThreadPollVotersPage {
        let repository = await repositoryProvider()
        return try await repository.fetchPollVoters(threadID: threadID, optionID: optionID, page: page)
    }

    func votePoll(forumID: String, threadID: String, optionIDs: [String], formHash: String) async throws -> String {
        let repository = await repositoryProvider()
        let message = try await repository.votePoll(
            forumID: forumID,
            threadID: threadID,
            optionIDs: optionIDs,
            formHash: formHash
        )
        await refresh()
        return message
    }

    func ratePost(
        threadID: String,
        postID: String,
        score: Int,
        reason: String,
        formHash: String,
        noticeAuthor: Bool
    ) async throws -> String {
        let repository = await repositoryProvider()
        let message = try await repository.ratePost(
            threadID: threadID,
            postID: postID,
            score: score,
            reason: reason,
            formHash: formHash,
            noticeAuthor: noticeAuthor
        )
        await refresh()
        return message
    }

    func commentPost(
        threadID: String,
        postID: String,
        message: String,
        formHash: String,
        page: Int
    ) async throws -> String {
        let repository = await repositoryProvider()
        let result = try await repository.commentPost(
            threadID: threadID,
            postID: postID,
            message: message,
            formHash: formHash,
            page: page
        )
        await refresh()
        return result
    }

    private func loadPage(
        _ page: Int,
        preferCache: Bool = true,
        preservesCurrentContentOnFailure: Bool = false,
        usesCachedFallbackOnFailure: Bool = false
    ) async {
        isLoading = true
        errorMessage = nil
        transientMessage = nil
        defer { isLoading = false }

        do {
            if inlineImageLoadingContext == nil {
                inlineImageLoadingContext = await inlineImageLoadingContextProvider()
            }
            let repository = await repositoryProvider()
            let loaded = if preferCache, let cached = await repository.cachedThreadPage(context: context, page: page) {
                cached
            } else {
                try await repository.fetchThreadPage(context: context, page: page)
            }
            self.page = loaded
            currentPage = loaded.pageNavigation?.currentPage ?? page
        } catch {
            let repository = await repositoryProvider()
            if usesCachedFallbackOnFailure,
               let cached = await repository.cachedThreadPage(context: context, page: page) {
                self.page = cached
                currentPage = cached.pageNavigation?.currentPage ?? page
                errorMessage = nil
                transientMessage = L10n.string("forum.thread.refresh_failed", error.localizedDescription)
                return
            }

            if preservesCurrentContentOnFailure, self.page != nil {
                errorMessage = nil
                transientMessage = L10n.string("forum.thread.refresh_failed", error.localizedDescription)
            } else {
                self.page = nil
                currentPage = page
                errorMessage = error.localizedDescription
            }
        }
    }

    private var favoriteTitle: String {
        let loadedTitle = page?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !loadedTitle.isEmpty {
            return loadedTitle
        }
        let contextTitle = context.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return contextTitle.isEmpty ? context.thread.canonicalURL.absoluteString : contextTitle
    }

    private static func contentUpdatedAt(from page: ForumThreadPage?) -> Date? {
        guard let firstPost = page?.posts.first else { return nil }
        return FavoriteContentUpdateDateResolver.date(
            lastEditedText: firstPost.lastEditedText,
            postedAtText: firstPost.postedAtText
        )
    }

    private func refreshFavoriteState() async {
        isFavorited = await localFavoriteItem(for: context.thread.canonicalURL) != nil
    }

    private func localFavoriteItem(for url: URL) async -> FavoriteItem? {
        guard let localFavoriteLibraryStore = await localFavoriteLibraryStoreProvider() else { return nil }
        let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
        let threadID = target.threadID
        return await localFavoriteLibraryStore.load().items.first { item in
            item.target.id == target.id || item.target.threadID == threadID
        }
    }
}

private extension FavoriteItem {
    func favorite(threadURL: URL, type: FavoriteType) -> Favorite {
        Favorite(
            id: id,
            title: title,
            displayName: displayName,
            url: target.canonicalURL ?? threadURL,
            remoteFavoriteID: remoteMapping?.yamiboFavoriteID,
            type: type,
            tagIDs: tagIDs
        )
    }
}
