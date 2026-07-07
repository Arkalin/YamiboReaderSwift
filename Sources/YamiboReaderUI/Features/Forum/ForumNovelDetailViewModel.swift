import Foundation
import Observation
import YamiboReaderCore

protocol ForumNovelDocumentLoading: Sendable {
    func loadPage(_ request: NovelPageRequest) async throws -> NovelReaderProjection
}

extension NovelReaderRepository: ForumNovelDocumentLoading {}

protocol ForumNovelThreadPageLoading: Sendable {
    func cachedNovelThreadPage(context: NovelDetailLaunchContext, page: Int) async -> ForumThreadPage?
    func fetchNovelThreadPage(context: NovelDetailLaunchContext, page: Int) async throws -> ForumThreadPage
    func clearCachedThreadPages(thread: ThreadIdentity) async throws
    func storeNovelThreadPage(_ page: ForumThreadPage, context: NovelDetailLaunchContext, pageNumber: Int) async throws
}

extension ForumThreadReaderRepository: ForumNovelThreadPageLoading {}

struct ForumNovelChapterSummary: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var view: Int
    var postID: String? = nil
    var floorText: String? = nil
    var resumePoint: NovelResumePoint? = nil
    var progressText: String? = nil
    var isCurrentRead: Bool = false
}

struct ForumNovelChapterSection: Identifiable, Hashable, Sendable {
    var page: Int
    var chapters: [ForumNovelChapterSummary]
    var isLoaded: Bool
    var isLoading: Bool
    var errorMessage: String?

    var id: Int { page }
}

struct ForumNovelDetailHeaderSummary: Equatable, Sendable {
    var title: String
    var threadID: String
    var authorID: String?
    var authorName: String?
    var postedAtText: String?
    var lastUpdatedText: String?
    var forumName: String?
    var totalViews: Int?
    var totalReplies: Int?
    var coverURL: URL?
    var chapterCount: Int
    var firstFloorPreviewText: String?
    var readingProgressText: String?
    var isFavorited: Bool
}

@MainActor
@Observable
final class ForumNovelDetailViewModel {
    var document: NovelReaderProjection?
    var threadPage: ForumThreadPage?
    var chapters: [ForumNovelChapterSummary] = []
    var chapterSections: [ForumNovelChapterSection] = []
    var expandedChapterPages: Set<Int> = [1]
    var favorite: Favorite?
    var readingProgress: ReadingProgressRecord?
    var contentCover: ContentCover?
    var isLoading = false
    var errorMessage: String?
    var favoriteErrorMessage: String?
    var transientMessage: String?
    var favoriteAddPromptPresented = false
    var favoriteRemovePrompt: FavoriteRemovePrompt?

    let context: NovelDetailLaunchContext

    @ObservationIgnored private let dependencies: ForumDependencies
    // Detail-scoped page cache mirroring Android's pagePostsCache; reload owns invalidation.
    @ObservationIgnored private var loadedThreadPages: [Int: ForumThreadPage] = [:]
    @ObservationIgnored private var resolvedAuthorID: String?
    @ObservationIgnored private var loadingChapterPages: Set<Int> = []
    @ObservationIgnored private var chapterPageErrors: [Int: String] = [:]
    @ObservationIgnored private var totalChapterPages = 1
    @ObservationIgnored private var novelReaderSettings = NovelReaderAppearanceSettings()
    @ObservationIgnored private var documentPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var favoriteUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var readingProgressUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private let novelRepositoryProvider: @Sendable () async -> any ForumNovelDocumentLoading
    @ObservationIgnored private let threadRepositoryProvider: @Sendable () async -> any ForumNovelThreadPageLoading

    init(
        context: NovelDetailLaunchContext,
        dependencies: ForumDependencies,
        novelRepositoryProvider: (@Sendable () async -> any ForumNovelDocumentLoading)? = nil,
        threadRepositoryProvider: (@Sendable () async -> any ForumNovelThreadPageLoading)? = nil
    ) {
        self.context = context
        self.dependencies = dependencies
        self.novelRepositoryProvider = novelRepositoryProvider ?? {
            await dependencies.makeNovelReaderRepository()
        }
        self.threadRepositoryProvider = threadRepositoryProvider ?? {
            await dependencies.makeForumThreadReaderRepository()
        }
        favoriteUpdatesTask = Task { @MainActor [weak self, localFavoriteLibraryStore = dependencies.localFavoriteLibraryStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteLibraryStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteLibraryStore.changeIDUserInfoKey] as? String,
                      changeID == localFavoriteLibraryStore.changeID else {
                    continue
                }
                await self.refreshFavorite(from: localFavoriteLibraryStore)
            }
        }
        readingProgressUpdatesTask = Task { @MainActor [weak self, readingProgressStore = dependencies.readingProgressStore] in
            for await notification in NotificationCenter.default.notifications(named: ReadingProgressStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[ReadingProgressStore.changeIDUserInfoKey] as? String,
                      changeID == readingProgressStore.changeID else {
                    continue
                }
                await self.refreshReadingProgress(from: readingProgressStore)
            }
        }
    }

    deinit {
        documentPreloadTask?.cancel()
        favoriteUpdatesTask?.cancel()
        readingProgressUpdatesTask?.cancel()
    }

    var navigationTitle: String {
        displayTitle(threadPage?.title ?? context.title)
    }

    var hasReadingProgress: Bool {
        Self.hasReadingProgress(readingProgress, favorite: favorite)
    }

    var headerSummary: ForumNovelDetailHeaderSummary {
        let firstPost = threadPage?.posts.first
        let previewPost = loadedThreadPages[1]?.posts.first
        return ForumNovelDetailHeaderSummary(
            title: displayTitle(threadPage?.title ?? context.title),
            threadID: context.thread.tid,
            authorID: resolvedAuthorID ?? Self.trimmedNonEmpty(firstPost?.author.uid) ?? context.authorID,
            authorName: Self.trimmedNonEmpty(firstPost?.author.name),
            postedAtText: firstPost?.postedAtText,
            lastUpdatedText: Self.lastUpdatedText(
                editedText: firstPost?.lastEditedText,
                postedAtText: firstPost?.postedAtText
            ),
            forumName: forumName,
            totalViews: threadPage?.totalViews,
            totalReplies: threadPage?.totalReplies,
            coverURL: resolvedHeaderCoverURL,
            chapterCount: chapters.count,
            firstFloorPreviewText: Self.firstFloorPreviewText(from: previewPost),
            readingProgressText: Self.readingProgressText(from: readingProgress, favorite: favorite),
            isFavorited: favorite != nil
        )
    }

    func load() async {
        guard threadPage == nil else { return }
        await reload()
    }

    private var resolvedHeaderCoverURL: URL? {
        contentCover?.resolvedURL
            ?? threadPage.flatMap(ThreadCoverResolver.findThreadCoverCandidate(in:))
    }

    func reload() async {
        await loadDetail(preferCache: true, refreshesPersistentCache: false, preservesCurrentContentOnFailure: false)
    }

    func refresh() async {
        await loadDetail(preferCache: false, refreshesPersistentCache: true, preservesCurrentContentOnFailure: threadPage != nil)
    }

    private func loadDetail(
        preferCache: Bool,
        refreshesPersistentCache: Bool,
        preservesCurrentContentOnFailure: Bool
    ) async {
        isLoading = true
        errorMessage = nil
        transientMessage = nil
        documentPreloadTask?.cancel()
        document = nil
        defer { isLoading = false }

        do {
            favorite = await localFavoriteItem()?.favorite(type: .novel)
            readingProgress = await dependencies.readingProgressStore.load(threadID: context.thread.tid)
            contentCover = await loadContentCover()
            novelReaderSettings = await dependencies.settingsStore.load().novelReader
            favoriteErrorMessage = nil
            let threadRepository = await threadRepositoryProvider()
            let initialPages = try await loadInitialPages(repository: threadRepository, preferCache: preferCache)
            let headerPage = initialPages.headerPage
            let contentPage = initialPages.contentPage
            let authorID = initialPages.authorID
            let contentContext = initialPages.contentContext
            if refreshesPersistentCache {
                try await threadRepository.clearCachedThreadPages(thread: context.thread)
                try await threadRepository.storeNovelThreadPage(headerPage, context: context, pageNumber: 1)
                if contentContext != context {
                    try await threadRepository.storeNovelThreadPage(contentPage, context: contentContext, pageNumber: 1)
                }
            }
            resolvedAuthorID = authorID
            threadPage = headerPage
            loadedThreadPages = [1: contentPage]
            await refreshContentCover(from: headerPage)
            totalChapterPages = Self.totalPages(from: contentPage, fallback: 1)
            chapterPageErrors = [:]
            loadingChapterPages = []
            expandedChapterPages = [1]
            rebuildChapterDirectory()
            preloadReaderDocument()
        } catch {
            readingProgress = await dependencies.readingProgressStore.load(threadID: context.thread.tid)
            contentCover = await loadContentCover()
            if preservesCurrentContentOnFailure {
                document = nil
                errorMessage = nil
                transientMessage = L10n.string("forum.novel_detail.refresh_failed", error.localizedDescription)
            } else {
                document = nil
                threadPage = nil
                chapters = []
                chapterSections = []
                loadedThreadPages = [:]
                resolvedAuthorID = nil
                chapterPageErrors = [:]
                loadingChapterPages = []
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadInitialPages(
        repository: any ForumNovelThreadPageLoading,
        preferCache: Bool
    ) async throws -> (headerPage: ForumThreadPage, contentPage: ForumThreadPage, authorID: String, contentContext: NovelDetailLaunchContext) {
        if let authorID = Self.trimmedNonEmpty(context.authorID) {
            let scopedContext = authorScopedContext(authorID: authorID)
            let page = try await loadNovelThreadPage(context: scopedContext, page: 1, preferCache: preferCache, repository: repository)
            return (page, page, authorID, scopedContext)
        }

        let headerPage = try await loadNovelThreadPage(context: context, page: 1, preferCache: preferCache, repository: repository)
        let authorID = try Self.resolveAuthorID(context: context, page: headerPage)
        let contentContext = authorScopedContext(authorID: authorID)
        let contentPage = try await loadNovelThreadPage(context: contentContext, page: 1, preferCache: preferCache, repository: repository)
        return (headerPage, contentPage, authorID, contentContext)
    }

    private func loadNovelThreadPage(
        context: NovelDetailLaunchContext,
        page: Int,
        preferCache: Bool,
        repository: any ForumNovelThreadPageLoading
    ) async throws -> ForumThreadPage {
        if preferCache,
           let cached = await repository.cachedNovelThreadPage(context: context, page: page) {
            return cached
        }
        return try await repository.fetchNovelThreadPage(context: context, page: page)
    }

    func clearTransientMessage() {
        transientMessage = nil
    }

    private func preloadReaderDocument() {
        let request = NovelPageRequest(
            threadID: context.thread.tid,
            view: 1,
            authorID: resolvedAuthorID ?? context.authorID
        )
        let provider = novelRepositoryProvider
        documentPreloadTask = Task { [weak self] in
            do {
                let repository = await provider()
                let loaded = try await repository.loadPage(request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.document = loaded
                }
            } catch {
                return
            }
        }
    }

    func launchContext(for chapter: ForumNovelChapterSummary?) -> NovelLaunchContext {
        NovelLaunchContext(
            threadID: context.thread.tid,
            threadTitle: context.title,
            source: .forum,
            initialView: chapter?.view ?? 1,
            authorID: chapter?.resumePoint?.authorID ?? resolvedAuthorID ?? context.authorID,
            initialResumePoint: chapter?.resumePoint
        )
    }

    func continueLaunchContext() -> NovelLaunchContext {
        let novelProgress = readingProgress?.novel
        let resumePoint = novelProgress?.novelResumePoint
        let hasProgress = Self.hasReadingProgress(readingProgress, favorite: favorite)
        return NovelLaunchContext(
            threadID: context.thread.tid,
            threadTitle: favorite?.resolvedDisplayTitle ?? context.title,
            source: hasProgress ? .resume : .forum,
            initialView: resumePoint?.view ?? novelProgress?.lastView ?? 1,
            authorID: resumePoint?.authorID ?? novelProgress?.authorID ?? resolvedAuthorID ?? context.authorID,
            initialResumePoint: resumePoint
        )
    }

    func toggleChapterSection(page: Int) async {
        let normalizedPage = max(1, page)
        if expandedChapterPages.contains(normalizedPage) {
            expandedChapterPages.remove(normalizedPage)
            rebuildChapterDirectory()
            return
        }

        expandedChapterPages.insert(normalizedPage)
        rebuildChapterDirectory()
        guard loadedThreadPages[normalizedPage] == nil else { return }
        await loadChapterSection(page: normalizedPage)
    }

    func loadChapterSection(page: Int) async {
        let normalizedPage = max(1, page)
        guard loadedThreadPages[normalizedPage] == nil,
              !loadingChapterPages.contains(normalizedPage) else {
            return
        }

        loadingChapterPages.insert(normalizedPage)
        chapterPageErrors[normalizedPage] = nil
        rebuildChapterDirectory()
        defer {
            loadingChapterPages.remove(normalizedPage)
            rebuildChapterDirectory()
        }

        do {
            let repository = await threadRepositoryProvider()
            let authorID = try Self.resolveAuthorID(context: context, page: threadPage)
            resolvedAuthorID = authorID
            let contentContext = authorScopedContext(authorID: authorID)
            let loaded = if let cached = await repository.cachedNovelThreadPage(context: contentContext, page: normalizedPage) {
                cached
            } else {
                try await repository.fetchNovelThreadPage(context: contentContext, page: normalizedPage)
            }
            loadedThreadPages[normalizedPage] = loaded
            totalChapterPages = max(totalChapterPages, Self.totalPages(from: loaded, fallback: normalizedPage))
            chapterPageErrors[normalizedPage] = nil
        } catch {
            chapterPageErrors[normalizedPage] = error.localizedDescription
        }
    }

    /// Routes the favorite button through the remembered add/remove sync
    /// choices: either performs the action silently or raises the prompt.
    func toggleFavorite() async {
        favoriteErrorMessage = nil
        let settings = await dependencies.settingsStore.load().favorites

        if let favorite {
            let canRemoveRemote = favorite.remoteFavoriteID?.isEmpty == false
            switch FavoriteRemoveRemoteDecision.resolve(settings: settings, canRemoveRemote: canRemoveRemote) {
            case .prompt:
                favoriteRemovePrompt = FavoriteRemovePrompt(favorite: favorite)
            case let .silent(removeRemote):
                await performFavoriteRemoval(favorite, removeRemote: removeRemote)
            }
            return
        }

        switch FavoriteAddSyncDecision.resolve(settings: settings, canSyncRemote: true) {
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
            let result = try await FavoriteQuickActions.addFavorite(
                threadID: context.thread.tid,
                title: favoriteTitle,
                type: .novel,
                authorID: resolvedAuthorID ?? context.authorID,
                forumID: threadPage?.forumID ?? threadPage?.thread.fid ?? context.thread.fid,
                forumName: threadPage?.forumName ?? forumName,
                contentUpdatedAt: Self.contentUpdatedAt(from: threadPage),
                formHash: threadPage?.formHash,
                syncToRemote: syncToRemote,
                localFavoriteLibraryStore: dependencies.localFavoriteLibraryStore,
                remoteRepository: await dependencies.makeFavoriteRepository()
            )
            favorite = result.favorite
            transientMessage = result.remote.addFeedbackMessage
            rebuildChapterDirectory()
        } catch {
            favoriteErrorMessage = error.localizedDescription
            favorite = await localFavoriteItem()?.favorite(type: .novel)
            rebuildChapterDirectory()
        }
    }

    private func performFavoriteRemoval(_ favorite: Favorite, removeRemote: Bool) async {
        do {
            try await FavoriteQuickActions.removeFavorite(
                favorite,
                removeRemote: removeRemote,
                localFavoriteLibraryStore: dependencies.localFavoriteLibraryStore,
                remoteRepository: await dependencies.makeFavoriteRepository()
            )
            self.favorite = nil
            transientMessage = removeRemote
                ? L10n.string("favorites.quick.removed_with_remote")
                : L10n.string("favorites.quick.removed")
            rebuildChapterDirectory()
        } catch {
            favoriteErrorMessage = error.localizedDescription
            self.favorite = await localFavoriteItem()?.favorite(type: .novel)
            rebuildChapterDirectory()
        }
    }

    private func rememberAddSyncChoice(_ syncToRemote: Bool) async {
        var settings = await dependencies.settingsStore.load()
        settings.favorites.addSyncPromptEnabled = false
        settings.favorites.addSyncDefault = syncToRemote
        try? await dependencies.settingsStore.save(settings)
    }

    private func rememberRemoveRemoteChoice(_ removeRemote: Bool) async {
        var settings = await dependencies.settingsStore.load()
        settings.favorites.removeRemotePromptEnabled = false
        settings.favorites.removeRemoteDefault = removeRemote
        try? await dependencies.settingsStore.save(settings)
    }

    func clearFavoriteError() {
        favoriteErrorMessage = nil
    }

    private func refreshFavorite(from localFavoriteLibraryStore: FavoriteLibraryStore) async {
        favorite = await localFavoriteItem(from: localFavoriteLibraryStore)?.favorite(type: .novel)
        rebuildChapterDirectory()
    }

    private func refreshReadingProgress(from readingProgressStore: ReadingProgressStore) async {
        readingProgress = await readingProgressStore.load(threadID: context.thread.tid)
        rebuildChapterDirectory()
    }

    static func chapterSections(
        from loadedPages: [Int: ForumThreadPage],
        totalPages: Int,
        loadingPages: Set<Int> = [],
        pageErrors: [Int: String] = [:],
        readingProgress: ReadingProgressRecord? = nil,
        favorite: Favorite? = nil,
        novelReaderSettings: NovelReaderAppearanceSettings = .init(),
        authorID: String? = nil
    ) -> [ForumNovelChapterSection] {
        let normalizedTotal = max(1, totalPages)
        return (1...normalizedTotal).map { page in
            let pageDocument = loadedPages[page]
            let chapters = pageDocument.map {
                chapterSummaries(
                    from: $0,
                    page: page,
                    novelReaderSettings: novelReaderSettings,
                    authorID: authorID
                )
            } ?? []
            return ForumNovelChapterSection(
                page: page,
                chapters: chapters.map { chapter in
                    var updatedChapter = chapter
                    updatedChapter.progressText = chapterProgressText(
                        for: chapter,
                        readingProgress: readingProgress,
                        favorite: favorite
                    )
                    updatedChapter.isCurrentRead = isCurrentReadChapter(
                        chapter,
                        readingProgress: readingProgress,
                        favorite: favorite
                    )
                    return updatedChapter
                },
                isLoaded: pageDocument != nil,
                isLoading: loadingPages.contains(page),
                errorMessage: pageErrors[page]
            )
        }
    }

    private func rebuildChapterDirectory() {
        chapterSections = Self.chapterSections(
            from: loadedThreadPages,
            totalPages: totalChapterPages,
            loadingPages: loadingChapterPages,
            pageErrors: chapterPageErrors,
            readingProgress: readingProgress,
            favorite: favorite,
            novelReaderSettings: novelReaderSettings,
            authorID: resolvedAuthorID ?? context.authorID
        )
        chapters = chapterSections.flatMap(\.chapters)
    }

    func refreshContentCover(from page: ForumThreadPage) async {
        guard let key = contentCoverKey else { return }
        if let candidate = ThreadCoverResolver.findThreadCoverCandidate(in: page) {
            do {
                _ = try await dependencies.contentCoverStore.setAutomaticCover(candidate, for: key)
            } catch {
                return
            }
        }
        contentCover = await dependencies.contentCoverStore.cover(for: key)
    }

    private static func chapterSummaries(
        from page: ForumThreadPage,
        page pageNumber: Int,
        novelReaderSettings: NovelReaderAppearanceSettings,
        authorID: String?
    ) -> [ForumNovelChapterSummary] {
        let resolvedAuthorID = trimmedNonEmpty(authorID) ?? trimmedNonEmpty(page.posts.first?.author.uid)
        guard let resolvedAuthorID else { return [] }
        let request = NovelPageRequest(
            threadID: page.thread.tid,
            view: pageNumber,
            authorID: resolvedAuthorID
        )
        guard let document = try? NovelReaderProjectionBuilder.build(
            from: page,
            request: request,
            authorID: resolvedAuthorID
        ) else {
            return []
        }
        let floorTextByPostID = page.posts.reduce(into: [String: String]()) { partial, post in
            guard let postID = trimmedNonEmpty(post.postID),
                  let floorText = post.floorText else {
                return
            }
            partial[postID] = floorText
        }
        return NovelChapterDirectoryExtractor
            .entries(from: document, settings: novelReaderSettings)
            .map { entry in
                let postID = entry.ownerPostID
                return ForumNovelChapterSummary(
                    id: "\(pageNumber)|\(postID ?? String(entry.chapter.ordinal))",
                    title: entry.chapter.title,
                    view: pageNumber,
                    postID: postID,
                    floorText: postID.flatMap { floorTextByPostID[$0] },
                    resumePoint: entry.anchor?.resumePoint
                )
            }
    }

    private static func totalPages(from page: ForumThreadPage, fallback: Int) -> Int {
        max(fallback, page.pageNavigation?.totalPages ?? page.pageNavigation?.currentPage ?? fallback)
    }

    private var forumName: String? {
        if let forumName = Self.trimmedNonEmpty(threadPage?.forumName) {
            return forumName
        }
        guard let fid = Self.trimmedNonEmpty(threadPage?.thread.fid)
            ?? Self.trimmedNonEmpty(context.thread.fid) else {
            return nil
        }
        return fid
    }

    private var favoriteTitle: String {
        displayTitle(threadPage?.title ?? context.title)
    }

    private static func contentUpdatedAt(from page: ForumThreadPage?) -> Date? {
        guard let firstPost = page?.posts.first else { return nil }
        return FavoriteContentUpdateDateResolver.date(
            lastEditedText: firstPost.lastEditedText,
            postedAtText: firstPost.postedAtText
        )
    }

    private func authorScopedContext(authorID: String) -> NovelDetailLaunchContext {
        NovelDetailLaunchContext(
            thread: context.thread,
            title: context.title,
            authorID: authorID
        )
    }

    private func displayTitle(_ value: String?) -> String {
        ForumThreadTitleSanitizer.sanitize(value)
            ?? context.thread.tid
    }

    private static func resolveAuthorID(context: NovelDetailLaunchContext, page: ForumThreadPage?) throws -> String {
        if let authorID = trimmedNonEmpty(context.authorID) {
            return authorID
        }
        if let authorID = trimmedNonEmpty(page?.posts.first?.author.uid) {
            return authorID
        }
        throw YamiboError.parsingFailed(context: "小说作者范围")
    }

    private static func firstFloorPreviewText(from post: ForumThreadPost?) -> String? {
        guard let post else { return nil }
        let text = post.contentText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return trimmedNonEmpty(text)
    }

    private static func readingProgressText(from readingProgress: ReadingProgressRecord?, favorite: Favorite?) -> String? {
        if let novel = readingProgress?.novel,
           hasReadingProgress(readingProgress, favorite: nil) {
            return readingProgressText(from: novel)
        }
        return nil
    }

    private static func readingProgressText(from novel: NovelReadingProgressRecord) -> String {
        if let chapterTitle = trimmedNonEmpty(novel.novelResumePoint?.chapterTitle)
            ?? trimmedNonEmpty(novel.lastChapter) {
            return chapterTitle
        }
        if let percent = novel.novelDocumentSurfaceProgressPercent {
            if let maxView = novel.novelMaxView, maxView > 1 {
                return L10n.string(
                    "favorites.progress.novel_page_web",
                    percent,
                    min(max(novel.lastView, 1), maxView),
                    maxView
                )
            }
            return L10n.string("favorites.progress.novel_percent", percent)
        }
        if let maxView = novel.novelMaxView, maxView > 1 {
            return L10n.string(
                "favorites.progress.novel_web",
                min(max(novel.lastView, 1), maxView),
                maxView
            )
        }
        return L10n.string("favorites.progress.page", novel.lastView)
    }

    private static func chapterProgressText(
        for chapter: ForumNovelChapterSummary,
        readingProgress: ReadingProgressRecord?,
        favorite: Favorite?
    ) -> String? {
        guard isCurrentReadChapter(chapter, readingProgress: readingProgress, favorite: favorite) else {
            return nil
        }
        return nil
    }

    private static func isCurrentReadChapter(
        _ chapter: ForumNovelChapterSummary,
        readingProgress: ReadingProgressRecord?,
        favorite: Favorite?
    ) -> Bool {
        let novel = readingProgress?.novel
        let resumePoint = novel?.novelResumePoint
        if let resumeIdentity = resumePoint?.chapterIdentity,
           resumeIdentity == chapter.resumePoint?.chapterIdentity {
            return true
        }
        if let postID = chapter.postID,
           resumePoint?.chapterIdentity?.rawValue.hasPrefix("post:\(postID)#") == true {
            return true
        }
        let lastView = novel?.lastView
        let lastChapter = novel?.lastChapter
        return lastView == chapter.view
            && trimmedNonEmpty(lastChapter) == trimmedNonEmpty(chapter.title)
    }

    private static func hasReadingProgress(_ readingProgress: ReadingProgressRecord?, favorite: Favorite?) -> Bool {
        if let novel = readingProgress?.novel {
            return novel.novelResumePoint != nil
                || novel.lastView > 1
                || trimmedNonEmpty(novel.lastChapter) != nil
                || trimmedNonEmpty(novel.authorID) != nil
                || novel.novelMaxView != nil
                || novel.novelDocumentSurfaceProgressPercent != nil
        }
        return false
    }

    private func localFavoriteItem() async -> FavoriteItem? {
        await localFavoriteItem(from: dependencies.localFavoriteLibraryStore)
    }

    private func localFavoriteItem(from store: FavoriteLibraryStore) async -> FavoriteItem? {
        let target = FavoriteContentTarget.novelThread(threadID: context.thread.tid)
        return await store.load().items.first { item in
            item.target.id == target.id || item.target.threadID == target.threadID
        }
    }

    private var contentCoverKey: ContentCoverKey? {
        let tid = context.thread.tid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tid.isEmpty else { return nil }
        return .thread(tid: tid)
    }

    private func loadContentCover() async -> ContentCover? {
        guard let key = contentCoverKey else { return nil }
        return await dependencies.contentCoverStore.cover(for: key)
    }

    private static func lastUpdatedText(editedText: String?, postedAtText: String?) -> String? {
        guard let editedText = trimmedNonEmpty(editedText) else {
            return trimmedNonEmpty(postedAtText)
        }
        return extractedEditTime(from: editedText) ?? editedText
    }

    private static func extractedEditTime(from text: String) -> String? {
        let patterns = [
            #"(?:本帖最后由|本帖最後由)\s+.+?\s+(?:于|於)\s+(.+?)\s+(?:编辑|編輯)"#,
            #"(?:最后编辑于|最後編輯於)\s*(.+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let searchRange = NSRange(text.startIndex ..< text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: searchRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let value = trimmedNonEmpty(String(text[range])) else {
                continue
            }
            return value
        }
        return nil
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
