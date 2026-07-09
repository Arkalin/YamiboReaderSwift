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
    var favoriteAddPromptPresented = false
    var favoriteRemovePrompt: FavoriteRemovePrompt?

    let context: ThreadNovelLaunchContext

    @ObservationIgnored private let repositoryProvider: @Sendable () async -> any ForumThreadPageLoading
    @ObservationIgnored private let localFavoriteLibraryStoreProvider: @Sendable () async -> FavoriteLibraryStore?
    @ObservationIgnored private let readingProgressStoreProvider: @Sendable () async -> ReadingProgressStore?
    @ObservationIgnored private let favoriteRepositoryProvider: @Sendable () async -> (any ForumThreadFavoriteRemoteOperating)?
    @ObservationIgnored private let contentCoverStoreProvider: @Sendable () async -> ContentCoverStore?
    @ObservationIgnored private let mangaDirectoryStoreProvider: @Sendable () async -> (any MangaDirectoryPersisting)?
    @ObservationIgnored private let settingsStoreProvider: @Sendable () async -> SettingsStore?

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
        settingsStoreProvider = {
            dependencies.settingsStore
        }
    }

    init(
        context: ThreadNovelLaunchContext,
        repository: any ForumThreadPageLoading,
        localFavoriteLibraryStore: FavoriteLibraryStore? = nil,
        readingProgressStore: ReadingProgressStore? = nil,
        favoriteRepository: (any ForumThreadFavoriteRemoteOperating)? = nil,
        contentCoverStore: ContentCoverStore? = nil,
        mangaDirectoryStore: (any MangaDirectoryPersisting)? = nil,
        settingsStore: SettingsStore? = nil
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
        settingsStoreProvider = {
            settingsStore
        }
    }

    var navigationTitle: String {
        page?.title ?? context.title
    }

    /// Cover menu entries for images opened from this thread: thread cover
    /// always, manga cover when the thread is a chapter of a local directory
    /// and its board currently has Smart Comic Mode on (design decision
    /// #16 — mode off hides this entry outright, even if a `MangaDirectory`
    /// technically still exists for this tid).
    var imageBrowserCoverActionsProvider: ImageBrowserCoverActionsProvider {
        let forumID = resolvedForumID
        return ImageBrowserThreadCoverActions.provider(
            tid: context.thread.tid,
            contentCoverStore: contentCoverStoreProvider,
            mangaDirectoryStore: mangaDirectoryStoreProvider,
            isSmartComicModeEnabled: { [settingsStoreProvider] in
                guard let settingsStore = await settingsStoreProvider() else { return true }
                return await settingsStore.load().isSmartComicModeEnabled(forumID: forumID)
            }
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

    /// Routes the star button through the remembered add/remove sync choices:
    /// either performs the action silently or raises the matching prompt.
    func toggleFavorite() async {
        let settings = await favoriteSettings()
        if let favoriteItem = await localFavoriteItem(forThreadID: context.thread.tid) {
            let favorite = favoriteItem.favorite(type: .other)
            let canRemoveRemote = await favoriteRepositoryProvider() != nil
                && favorite.remoteFavoriteID?.isEmpty == false
            switch FavoriteRemoveRemoteDecision.resolve(settings: settings, canRemoveRemote: canRemoveRemote) {
            case .prompt:
                favoriteRemovePrompt = FavoriteRemovePrompt(favorite: favorite)
            case let .silent(removeRemote):
                await performFavoriteRemoval(favorite, removeRemote: removeRemote)
            }
            return
        }

        let canSyncRemote = await favoriteRepositoryProvider() != nil
        switch FavoriteAddSyncDecision.resolve(settings: settings, canSyncRemote: canSyncRemote) {
        case .prompt:
            favoriteAddPromptPresented = true
        case let .silent(syncToRemote):
            await performFavoriteAdd(syncToRemote: syncToRemote)
        }
    }

    func confirmFavoriteAdd(syncToRemote: Bool, remember: Bool) async {
        favoriteAddPromptPresented = false
        if remember {
            await rememberAddSyncChoice(syncToRemote)
        }
        await performFavoriteAdd(syncToRemote: syncToRemote)
    }

    func confirmFavoriteRemoval(_ favorite: Favorite, removeRemote: Bool, remember: Bool) async {
        favoriteRemovePrompt = nil
        if remember {
            await rememberRemoveRemoteChoice(removeRemote)
        }
        await performFavoriteRemoval(favorite, removeRemote: removeRemote)
    }

    private func performFavoriteAdd(syncToRemote: Bool) async {
        do {
            guard let localFavoriteLibraryStore = await localFavoriteLibraryStoreProvider() else {
                throw YamiboError.persistenceFailed("Local favorite library store is unavailable")
            }
            let result = try await FavoriteQuickActions.addFavorite(
                threadID: context.thread.tid,
                title: favoriteTitle,
                type: .other,
                authorID: nil,
                forumID: resolvedForumID,
                forumName: page?.forumName,
                contentUpdatedAt: Self.contentUpdatedAt(from: page),
                formHash: page?.formHash,
                syncToRemote: syncToRemote,
                localFavoriteLibraryStore: localFavoriteLibraryStore,
                remoteRepository: await favoriteRepositoryProvider()
            )
            if let coverCandidate = ThreadCoverResolver.findThreadCoverCandidate(in: page),
               let coverStore = await contentCoverStoreProvider() {
                do {
                    _ = try await coverStore.setAutomaticCover(coverCandidate, for: .thread(tid: context.thread.tid))
                } catch {
                    YamiboLog.library.error("Failed to set automatic cover for thread \(self.context.thread.tid) during favorite add: \(error)")
                }
            }
            isFavorited = true
            if let directoryTitle = await autoAttributionDirectoryTitle(localFavoriteLibraryStore: localFavoriteLibraryStore) {
                transientMessage = L10n.string("favorites.quick.auto_attributed", result.remote.addFeedbackMessage, directoryTitle)
            } else {
                transientMessage = result.remote.addFeedbackMessage
            }
        } catch {
            favoriteErrorMessage = error.localizedDescription
            await refreshFavoriteState()
        }
    }

    private func performFavoriteRemoval(_ favorite: Favorite, removeRemote: Bool) async {
        do {
            guard let localFavoriteLibraryStore = await localFavoriteLibraryStoreProvider() else {
                throw YamiboError.persistenceFailed("Local favorite library store is unavailable")
            }
            try await FavoriteQuickActions.removeFavorite(
                favorite,
                removeRemote: removeRemote,
                localFavoriteLibraryStore: localFavoriteLibraryStore,
                remoteRepository: await favoriteRepositoryProvider()
            )
            isFavorited = false
            transientMessage = removeRemote
                ? L10n.string("favorites.quick.removed_with_remote")
                : L10n.string("favorites.quick.removed")
        } catch {
            favoriteErrorMessage = error.localizedDescription
            await refreshFavoriteState()
        }
    }

    /// Local half of decision #8's "auto-attribution" feedback (the
    /// remote-sync half is a later phase) — the star-button add path is the
    /// most common way users hit this feature, so it gets an immediate toast
    /// rather than waiting for a sync warning that may never come.
    ///
    /// Fires only when every one of these holds, checked in this order so
    /// the cheapest gate runs first:
    /// - This board's Smart Comic Mode is on, via an explicit
    ///   `settingsStore` lookup (never inferred from a proxy signal like
    ///   "a directory happened to resolve" — that exact mistake bit three
    ///   earlier smart-comic-mode phases).
    /// - A `MangaDirectory` actually resolves for this tid (a single-tid
    ///   `directory(containingTID:)` lookup is enough here — this is one
    ///   favorite, not the batch grouping the favorites page does).
    /// - At least one *other* already-favorited `.mangaThread` item (the one
    ///   just added is already persisted by the time this runs) shares that
    ///   directory's chapter tids.
    ///
    /// Returns the directory's `cleanBookName` to interpolate into the toast,
    /// or nil to leave `transientMessage` as the plain add-feedback string.
    private func autoAttributionDirectoryTitle(localFavoriteLibraryStore: FavoriteLibraryStore) async -> String? {
        guard let settingsStore = await settingsStoreProvider() else { return nil }
        let settings = await settingsStore.load()
        guard settings.isSmartComicModeEnabled(forumID: resolvedForumID) else { return nil }
        guard let mangaDirectoryStore = await mangaDirectoryStoreProvider(),
              let directory = try? await mangaDirectoryStore.directory(containingTID: context.thread.tid) else {
            return nil
        }
        let siblingTIDs = Set(directory.chapters.map(\.tid))
        guard let document = try? await localFavoriteLibraryStore.load() else { return nil }
        // A sibling favorite only actually merges on the Favorites page if ITS
        // OWN board also has Smart Comic Mode on (LocalFavoriteLibraryProjection's
        // rawGroupedFavorites checks isEnabled(forumID:) per-member, not just for
        // the item just favorited) — a MangaDirectory can span threads from
        // different boards (e.g. a `.searched` strategy match isn't fid-scoped).
        // Without this check the toast could claim "merged" for a sibling that
        // the Favorites page will actually keep standalone.
        let hasOtherFavoriteInDirectory = document.items.contains { item in
            item.target.kind == .mangaThread
                && item.target.threadID != context.thread.tid
                && siblingTIDs.contains(item.target.threadID ?? "")
                && settings.isSmartComicModeEnabled(forumID: item.forumID)
        }
        guard hasOtherFavoriteInDirectory else { return nil }
        return directory.cleanBookName
    }

    private func favoriteSettings() async -> FavoriteLibrarySettings {
        guard let settingsStore = await settingsStoreProvider() else {
            return FavoriteLibrarySettings()
        }
        return await settingsStore.load().favorites
    }

    private func rememberAddSyncChoice(_ syncToRemote: Bool) async {
        guard let settingsStore = await settingsStoreProvider() else { return }
        var settings = await settingsStore.load()
        settings.favorites.addSyncPromptEnabled = false
        settings.favorites.addSyncDefault = syncToRemote
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.forum.error("Failed to save remembered add-sync choice: \(error)")
        }
    }

    private func rememberRemoveRemoteChoice(_ removeRemote: Bool) async {
        guard let settingsStore = await settingsStoreProvider() else { return }
        var settings = await settingsStore.load()
        settings.favorites.removeRemotePromptEnabled = false
        settings.favorites.removeRemoteDefault = removeRemote
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.forum.error("Failed to save remembered remove-remote choice: \(error)")
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

    /// Best-known forum id for this thread, falling back from the freshest
    /// loaded page down to the launch context — used wherever a forumID is
    /// needed opportunistically (favorite add, cover-action mode gating)
    /// rather than requiring the page to already be loaded.
    private var resolvedForumID: String? {
        page?.forumID ?? page?.thread.fid ?? context.thread.fid
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
        let target = FavoriteItemTarget.normalThread(threadID: threadID)
        return (try? await localFavoriteLibraryStore.load())?.items.first { item in
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
