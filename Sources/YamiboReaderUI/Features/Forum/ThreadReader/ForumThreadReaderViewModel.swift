import Foundation
import Observation
import YamiboReaderCore

protocol ForumThreadPageLoading: Sendable {
    func cachedThreadPage(context: ThreadNovelLaunchContext, page: Int) async -> ForumThreadPage?
    func fetchThreadPage(context: ThreadNovelLaunchContext, page: Int) async throws -> ForumThreadPage
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

    let context: ThreadNovelLaunchContext

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumThreadPageLoading
    @ObservationIgnored private let localFavoriteLibraryStoreProvider: @Sendable () async -> FavoriteLibraryStore?
    @ObservationIgnored private let readingProgressStoreProvider: @Sendable () async -> ReadingProgressStore?
    @ObservationIgnored private let favoriteRepositoryProvider: @Sendable () async -> (any ForumThreadFavoriteRemoteOperating)?
    @ObservationIgnored private let contentCoverStoreProvider: @Sendable () async -> ContentCoverStore?
    @ObservationIgnored private let mangaDirectoryStoreProvider: @Sendable () async -> (any MangaDirectoryPersisting)?

    init(context: ThreadNovelLaunchContext, dependencies: ForumDependencies) {
        self.context = context
        repositoryProvider = {
            await dependencies.makeForumThreadReaderRepository()
        }
        localFavoriteLibraryStoreProvider = {
            dependencies.localFavoriteLibraryStore
        }
        readingProgressStoreProvider = {
            dependencies.readingProgressStore
        }
        favoriteRepositoryProvider = {
            await dependencies.makeFavoriteRepository()
        }
        contentCoverStoreProvider = {
            dependencies.contentCoverStore
        }
        mangaDirectoryStoreProvider = {
            dependencies.mangaDirectoryStore
        }
    }

    init(
        context: ThreadNovelLaunchContext,
        repository: any ForumThreadPageLoading,
        localFavoriteLibraryStore: FavoriteLibraryStore? = nil,
        readingProgressStore: ReadingProgressStore? = nil,
        favoriteRepository: (any ForumThreadFavoriteRemoteOperating)? = nil,
        contentCoverStore: ContentCoverStore? = nil,
        mangaDirectoryStore: (any MangaDirectoryPersisting)? = nil
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
        contentCoverStoreProvider = {
            contentCoverStore
        }
        mangaDirectoryStoreProvider = {
            mangaDirectoryStore
        }
    }

    var navigationTitle: String {
        page?.title ?? context.title
    }

    /// Cover menu entries for images opened from this thread: thread cover
    /// always, manga cover when the thread is a chapter of a local directory.
    var imageBrowserCoverActionsProvider: ImageBrowserCoverActionsProvider {
        ImageBrowserThreadCoverActions.provider(
            tid: context.thread.tid,
            contentCoverStore: contentCoverStoreProvider,
            mangaDirectoryStore: mangaDirectoryStoreProvider
        )
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
        do {
            guard let localFavoriteLibraryStore = await localFavoriteLibraryStoreProvider() else {
                throw YamiboError.persistenceFailed("Local favorite library store is unavailable")
            }
            if let favoriteItem = await localFavoriteItem(forThreadID: context.thread.tid) {
                try await ForumThreadFavoriteSync.removeFavorite(
                    favoriteItem.favorite(type: .other),
                    localFavoriteLibraryStore: localFavoriteLibraryStore,
                    readingProgressStore: await readingProgressStoreProvider(),
                    remoteRepository: await favoriteRepositoryProvider()
                )
                isFavorited = false
                return
            }

            _ = try await ForumThreadFavoriteSync.addFavorite(
                threadID: context.thread.tid,
                title: favoriteTitle,
                type: .other,
                authorID: nil,
                forumID: page?.forumID ?? page?.thread.fid ?? context.thread.fid,
                forumName: page?.forumName,
                contentUpdatedAt: Self.contentUpdatedAt(from: page),
                formHash: page?.formHash,
                localFavoriteLibraryStore: localFavoriteLibraryStore,
                remoteRepository: await favoriteRepositoryProvider()
            )
            if let coverCandidate = ThreadCoverResolver.findThreadCoverCandidate(in: page),
               let coverStore = await contentCoverStoreProvider() {
                _ = try? await coverStore.setAutomaticCover(coverCandidate, for: .thread(tid: context.thread.tid))
            }
            isFavorited = true
        } catch {
            favoriteErrorMessage = error.localizedDescription
            await refreshFavoriteState()
        }
    }

    func loadRatingResults(postID: String) async throws -> ForumThreadRatingResultsPage {
        let repository = await repositoryProvider()
        return try await repository.fetchRatingResults(threadID: threadID, postID: postID)
    }

    func loadRateOptions(postID: String) async throws -> ForumThreadRateOptionsPage {
        let repository = await repositoryProvider()
        return try await repository.fetchRateOptions(threadID: threadID, postID: postID)
    }

    func loadPollVoters(optionID: String?, page: Int) async throws -> ForumThreadPollVotersPage {
        let repository = await repositoryProvider()
        return try await repository.fetchPollVoters(threadID: threadID, optionID: optionID, page: page)
    }

    func votePoll(optionIDs: [String]) async throws -> String {
        guard let forumID = normalizedForumID, let formHash = normalizedFormHash else {
            throw YamiboError.underlying(L10n.string("forum.thread.login_info_failed"))
        }
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
        postID: String,
        score: Int,
        reason: String,
        noticeAuthor: Bool
    ) async throws -> String {
        guard let formHash = normalizedFormHash else {
            throw YamiboError.underlying(L10n.string("forum.thread.login_info_failed"))
        }
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

    func commentPost(postID: String, message: String) async throws -> String {
        guard let formHash = normalizedFormHash else {
            throw YamiboError.underlying(L10n.string("forum.thread.login_info_failed"))
        }
        let repository = await repositoryProvider()
        let result = try await repository.commentPost(
            threadID: threadID,
            postID: postID,
            message: message,
            formHash: formHash,
            page: currentPage
        )
        await refresh()
        return result
    }

    func imageBrowserRequest(
        imageID: String,
        url: URL,
        title: String?,
        refererURL: URL
    ) -> ForumThreadImageBrowserRequest? {
        guard let page else { return nil }
        let defaultTitle = L10n.string("forum.thread.image")
        let gallery = ForumThreadImageBrowserGallery(
            page: page,
            refererURL: refererURL,
            selectedBlockID: imageID,
            defaultTitle: defaultTitle
        )
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackItem = ImageBrowserItem(
            id: imageID,
            source: YamiboImageSource(url: url, refererPageURL: refererURL),
            title: trimmedTitle.isEmpty ? defaultTitle : trimmedTitle
        )
        return ForumThreadImageBrowserRequest(
            items: gallery.items.isEmpty ? [fallbackItem] : gallery.items,
            initialItemID: gallery.initialItemID ?? fallbackItem.id
        )
    }

    private var threadID: String {
        page?.thread.tid ?? context.thread.tid
    }

    private var normalizedForumID: String? {
        normalized(page?.forumID)
    }

    private var normalizedFormHash: String? {
        normalized(page?.formHash)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
        return contextTitle.isEmpty ? context.thread.tid : contextTitle
    }

    private static func contentUpdatedAt(from page: ForumThreadPage?) -> Date? {
        guard let firstPost = page?.posts.first else { return nil }
        return FavoriteContentUpdateDateResolver.date(
            lastEditedText: firstPost.lastEditedText,
            postedAtText: firstPost.postedAtText
        )
    }

    private func refreshFavoriteState() async {
        isFavorited = await localFavoriteItem(forThreadID: context.thread.tid) != nil
    }

    private func localFavoriteItem(forThreadID threadID: String) async -> FavoriteItem? {
        guard let localFavoriteLibraryStore = await localFavoriteLibraryStoreProvider() else { return nil }
        let target = FavoriteContentTarget.normalThread(threadID: threadID)
        return await localFavoriteLibraryStore.load().items.first { item in
            item.target.id == target.id || item.target.threadID == target.threadID
        }
    }
}

private extension FavoriteItem {
    func favorite(type: FavoriteType) -> Favorite {
        guard let threadID = target.threadID else {
            preconditionFailure("Thread favorite conversion requires thread target")
        }
        return Favorite(
            id: id,
            title: title,
            displayName: displayName,
            threadID: threadID,
            remoteFavoriteID: remoteMapping?.yamiboFavoriteID,
            type: type,
            tagIDs: tagIDs
        )
    }
}
