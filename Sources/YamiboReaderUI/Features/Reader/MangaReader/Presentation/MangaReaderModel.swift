import SwiftUI
import YamiboReaderCore

struct MangaReaderModelDependencies {
    var makeDocumentLoader: @Sendable () async -> any MangaChapterDocumentLoading
    var makeDirectoryRepository: @Sendable () async -> any MangaDirectoryRepository
    var makeDirectoryStore: @Sendable () -> any MangaDirectoryPersisting
    var makeOfflineCacheStore: @Sendable () -> (any MangaOfflineCacheStoring)?
    var makeDirectorySearchCooldownState: @Sendable () -> MangaDirectorySearchCooldownState
    var directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration
    #if os(iOS)
    var makeImageDataLoader: @Sendable () async -> any MangaImageDataLoading
    #endif
    var progressSync: ProgressSyncModule

    #if os(iOS)
    init(
        makeDocumentLoader: @escaping @Sendable () async -> any MangaChapterDocumentLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeDirectoryStore: @escaping @Sendable () -> any MangaDirectoryPersisting,
        makeOfflineCacheStore: @escaping @Sendable () -> (any MangaOfflineCacheStoring)? = { nil },
        makeDirectorySearchCooldownState: @escaping @Sendable () -> MangaDirectorySearchCooldownState = {
            MangaDirectorySearchCooldownState()
        },
        directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration = MangaDirectoryWorkflowConfiguration(),
        makeImageDataLoader: @escaping @Sendable () async -> any MangaImageDataLoading,
        progressSync: ProgressSyncModule
    ) {
        self.makeDocumentLoader = makeDocumentLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeDirectoryStore = makeDirectoryStore
        self.makeOfflineCacheStore = makeOfflineCacheStore
        self.makeDirectorySearchCooldownState = makeDirectorySearchCooldownState
        self.directoryWorkflowConfiguration = directoryWorkflowConfiguration
        self.makeImageDataLoader = makeImageDataLoader
        self.progressSync = progressSync
    }
    #else
    init(
        makeDocumentLoader: @escaping @Sendable () async -> any MangaChapterDocumentLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeDirectoryStore: @escaping @Sendable () -> any MangaDirectoryPersisting,
        makeOfflineCacheStore: @escaping @Sendable () -> (any MangaOfflineCacheStoring)? = { nil },
        makeDirectorySearchCooldownState: @escaping @Sendable () -> MangaDirectorySearchCooldownState = {
            MangaDirectorySearchCooldownState()
        },
        directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration = MangaDirectoryWorkflowConfiguration(),
        progressSync: ProgressSyncModule
    ) {
        self.makeDocumentLoader = makeDocumentLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeDirectoryStore = makeDirectoryStore
        self.makeOfflineCacheStore = makeOfflineCacheStore
        self.makeDirectorySearchCooldownState = makeDirectorySearchCooldownState
        self.directoryWorkflowConfiguration = directoryWorkflowConfiguration
        self.progressSync = progressSync
    }
    #endif

    init(appContext: YamiboAppContext) {
        #if os(iOS)
        self.init(
            makeDocumentLoader: { await appContext.makeMangaChapterDocumentLoader() },
            makeDirectoryRepository: { await appContext.makeMangaDirectoryRepository() },
            makeDirectoryStore: { appContext.makeMangaDirectoryStore() },
            makeOfflineCacheStore: { appContext.makeMangaOfflineCacheStore() },
            makeDirectorySearchCooldownState: { appContext.mangaDirectorySearchCooldownState },
            makeImageDataLoader: { await appContext.makeMangaImageDataLoader() },
            progressSync: ProgressSyncModule(
                adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore)
            )
        )
        #else
        self.init(
            makeDocumentLoader: { await appContext.makeMangaChapterDocumentLoader() },
            makeDirectoryRepository: { await appContext.makeMangaDirectoryRepository() },
            makeDirectoryStore: { appContext.makeMangaDirectoryStore() },
            makeOfflineCacheStore: { appContext.makeMangaOfflineCacheStore() },
            makeDirectorySearchCooldownState: { appContext.mangaDirectorySearchCooldownState },
            progressSync: ProgressSyncModule(
                adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore)
            )
        )
        #endif
    }
}

@MainActor
public final class MangaReaderModel: ObservableObject {
    @Published public private(set) var presentation: MangaReaderPresentation
    @Published public private(set) var applePencilPageTurnSettings = ApplePencilPageTurnSettings()
    @Published public private(set) var chapterCommentsState: ReaderChapterCommentsState = .idle
    @Published public private(set) var isLoadingMoreChapterComments = false
    @Published public private(set) var chapterCommentsLoadMoreError: String?
    @Published public private(set) var chapterCommentsRefreshError: String?
    @Published private var navigationHistory = ReaderNavigationHistory<MangaReadingPosition>()
    private var linearReadingHistoryExpiration = ReaderNavigationLinearReadingExpiration<MangaReadingPosition>()

    public let context: MangaLaunchContext
    #if os(iOS)
    private(set) var imagePipeline: MangaImagePipeline?
    #endif

    private let appContext: YamiboAppContext
    private let dependencies: MangaReaderModelDependencies
    private let onReaderResumeRouteChange: ReaderResumeRouteChangeHandler
    private var chapterCommentsRepository: ReaderChapterCommentsRepository?
    private var workflow: MangaReaderWorkflow?
    private var hasPrepared = false
    private var committedSettings = MangaReaderSettings()
    private var directoryCooldownExpiresAt: Date?
    private var forcedSearchShortcutExpiresAt: Date?
    private var directoryTickTask: Task<Void, Never>?
    private var directoryMutationTask: Task<Void, Never>?
    private var automaticDirectoryUpdateTask: Task<Void, Never>?
    private var chapterJumpTask: Task<Void, Never>?
    private var adjacentPrefetchTask: Task<Void, Never>?
    private var readerContentGeneration = 0
    private var navigationRequestGeneration = 0
    private var currentStableReadingPosition: MangaReadingPosition?
    private var lastQueuedProgressSnapshot: MangaReaderProgressSnapshot?
    private var directoryMutationGeneration = 0
    private var chapterJumpGeneration = 0
    private var offlineCacheOwnerName: String?
    private lazy var chapterCommentsModule = ReaderChapterCommentsModule(
        adapter: ReaderChapterCommentsModule.Adapter(
            loadInitial: { [weak self] target in
                guard let self else {
                    throw ReaderChapterCommentsUnavailableError()
                }
                let repository = await self.ensureChapterCommentsRepository()
                return try await repository.loadChapterComments(for: target)
            },
            loadMore: { [weak self] target, view in
                guard let self else {
                    throw ReaderChapterCommentsUnavailableError()
                }
                let repository = await self.ensureChapterCommentsRepository()
                return try await repository.loadMoreChapterComments(for: target, view: view)
            }
        ),
        onChange: { [weak self] module in
            self?.syncChapterComments(from: module)
        }
    )

    deinit {
        directoryTickTask?.cancel()
        directoryMutationTask?.cancel()
        automaticDirectoryUpdateTask?.cancel()
        chapterJumpTask?.cancel()
        adjacentPrefetchTask?.cancel()
    }

    public init(
        context: MangaLaunchContext,
        appContext: YamiboAppContext,
        onReaderResumeRouteChange: @escaping ReaderResumeRouteChangeHandler = { _ in }
    ) {
        self.context = context
        self.appContext = appContext
        self.dependencies = MangaReaderModelDependencies(appContext: appContext)
        self.onReaderResumeRouteChange = onReaderResumeRouteChange
        #if os(iOS)
        self.imagePipeline = nil
        #endif
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    init(
        context: MangaLaunchContext,
        appContext: YamiboAppContext,
        dependencies: MangaReaderModelDependencies,
        onReaderResumeRouteChange: @escaping ReaderResumeRouteChangeHandler = { _ in }
    ) {
        self.context = context
        self.appContext = appContext
        self.dependencies = dependencies
        self.onReaderResumeRouteChange = onReaderResumeRouteChange
        #if os(iOS)
        self.imagePipeline = nil
        #endif
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    public func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        invalidateReaderContent()
        lastQueuedProgressSnapshot = nil

        let appSettings = await appContext.settingsStore.load()
        committedSettings = Self.normalizedSettings(appSettings.manga)
        applePencilPageTurnSettings = appSettings.applePencilPageTurn
        presentation = presentationWithCommittedSettings(presentation)
        #if os(iOS)
        let imagePipeline = MangaImagePipeline(
            dataLoader: await dependencies.makeImageDataLoader(),
            offlineCacheContext: { [weak self] page in
                MangaImageOfflineCacheContext(ownerName: self?.offlineCacheOwnerName, tid: page.tid)
            }
        )
        #endif
        let workflow = MangaReaderWorkflow(
            context: context,
            documentLoader: await dependencies.makeDocumentLoader(),
            directoryRepository: await dependencies.makeDirectoryRepository(),
            directoryStore: dependencies.makeDirectoryStore(),
            offlineCacheStore: dependencies.makeOfflineCacheStore(),
            settings: committedSettings,
            directoryWorkflowConfiguration: dependencies.directoryWorkflowConfiguration,
            directorySearchCooldownState: dependencies.makeDirectorySearchCooldownState()
        )
        self.workflow = workflow
        #if os(iOS)
        self.imagePipeline = imagePipeline
        #endif
        presentation = workflow.presentation
        presentation = await workflow.prepare()
        currentStableReadingPosition = stableReadingPosition(from: presentation)
        updateOfflineCacheOwnerName(from: presentation)
        refreshDirectoryPanelTiming(errorMessage: nil)
        if workflow.shouldAutoUpdateDirectoryAfterPrepare {
            startAutomaticDirectoryUpdate()
        }
    }

    public func retryInitialLoad() async {
        cancelReaderTasks()
        workflow = nil
        #if os(iOS)
        imagePipeline = nil
        #endif
        hasPrepared = false
        offlineCacheOwnerName = nil
        resetNavigationHistory()
        currentStableReadingPosition = nil
        lastQueuedProgressSnapshot = nil
        directoryCooldownExpiresAt = nil
        forcedSearchShortcutExpiresAt = nil
        presentation = presentationWithCommittedSettings(
            MangaReaderPresentation(
                state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
            )
        )

        await prepare()
    }

    public func updateCurrentPage(globalIndex: Int) {
        guard let workflow else { return }
        adjacentPrefetchTask?.cancel()
        readerContentGeneration += 1
        let previousProgressSnapshot = progressSnapshot(from: presentation)
        let nextPresentation = workflow.moveToLoadedPage(at: globalIndex)
        publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
        recordLinearReadingForNavigationHistory()
        scheduleAdjacentPrefetch(around: currentPageIndex(in: nextPresentation) ?? globalIndex)
    }

    public func jumpToPage(localIndex: Int) async {
        guard let workflow,
              case let .loaded(loaded) = presentation.state,
              let currentPage = loaded.currentPage else {
            return
        }
        let navigationGeneration = beginNavigationRequest()
        let sourcePosition = currentStableReadingPosition
        let itemCount = max(currentPage.chapterPageCount, 1)
        let targetLocalIndex = min(max(localIndex, 0), itemCount - 1)
        guard let targetPage = loaded.pages.first(where: { page in
            page.tid == currentPage.tid && page.localIndex == targetLocalIndex
        }) else {
            return
        }
        let targetPosition = MangaReadingPosition(tid: targetPage.tid, localIndex: targetPage.localIndex)

        adjacentPrefetchTask?.cancel()
        readerContentGeneration += 1
        let previousProgressSnapshot = progressSnapshot(from: presentation)
        let nextPresentation = workflow.jumpToLoadedPage(at: targetPage.globalIndex)
        publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
        if isCurrentNavigationRequest(navigationGeneration) {
            recordSuccessfulNonlinearNavigation(from: sourcePosition, to: targetPosition)
        }
        scheduleAdjacentPrefetch(around: currentPageIndex(in: nextPresentation) ?? targetPage.globalIndex)
    }

    public func jumpRelativePage(_ delta: Int, usesTwoPageSpread: Bool) async {
        guard delta != 0,
              let workflow,
              presentation.settings.readingMode == .paged,
              case let .loaded(loaded) = presentation.state,
              !loaded.pages.isEmpty else {
            return
        }

        let plan = MangaPagedReadingPlan(
            pages: loaded.pages,
            currentPageIndex: loaded.currentPageIndex,
            pageTurnDirection: presentation.settings.pageTurnDirection,
            usesTwoPageSpread: usesTwoPageSpread
        )
        let targetGlobalIndex: Int?
        if usesTwoPageSpread {
            targetGlobalIndex = plan.currentSpreadIndex.flatMap { currentSpreadIndex in
                plan.globalIndex(forSpreadAt: currentSpreadIndex + delta)
            }
        } else {
            targetGlobalIndex = plan.currentPageIndex.flatMap { currentPageIndex in
                plan.globalIndex(forPageAt: currentPageIndex + delta)
            }
        }
        guard let targetGlobalIndex else { return }

        adjacentPrefetchTask?.cancel()
        readerContentGeneration += 1
        let previousProgressSnapshot = progressSnapshot(from: presentation)
        let nextPresentation = workflow.jumpToLoadedPage(at: targetGlobalIndex, animated: true)
        publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
        recordLinearReadingForNavigationHistory()
        scheduleAdjacentPrefetch(around: currentPageIndex(in: nextPresentation) ?? targetGlobalIndex)
    }

    public var currentChapterCommentTarget: ReaderChapterCommentTarget? {
        guard case let .loaded(loaded) = presentation.state,
              let currentPage = loaded.currentPage else {
            return nil
        }
        return ReaderChapterCommentTarget(
            threadURL: currentPage.refererURL,
            view: Self.webViewPage(from: currentPage.refererURL),
            ownerPostID: currentPage.ownerPostID,
            title: currentPage.chapterTitle
        )
    }

    public func loadChapterComments(for target: ReaderChapterCommentTarget?) async {
        guard let target else {
            let emptyTarget = ReaderChapterCommentTarget(
                threadURL: context.originalThreadURL,
                view: 1,
                ownerPostID: "",
                title: nil
            )
            chapterCommentsState = .loaded(
                emptyTarget,
                ChapterCommentsPage(
                    target: emptyTarget,
                    comments: [],
                    isBoundaryClosed: true,
                    nextView: nil
                )
            )
            isLoadingMoreChapterComments = false
            chapterCommentsLoadMoreError = nil
            chapterCommentsRefreshError = nil
            return
        }
        await chapterCommentsModule.load(target)
    }

    public func refreshChapterComments(for target: ReaderChapterCommentTarget?) async {
        guard let target else { return }
        await chapterCommentsModule.refresh(target)
    }

    public func loadNextChapterCommentsPage() async {
        await chapterCommentsModule.loadNextPage()
    }

    public func applySettings(_ settings: MangaReaderSettings) {
        let normalizedSettings = Self.normalizedSettings(settings)
        guard normalizedSettings != committedSettings else { return }

        committedSettings = normalizedSettings
        if let workflow {
            presentation = workflow.applySettings(normalizedSettings)
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } else {
            presentation = presentationWithCommittedSettings(presentation)
        }

        Task { [appContext, normalizedSettings] in
            var appSettings = await appContext.settingsStore.load()
            appSettings.manga = normalizedSettings
            try? await appContext.settingsStore.save(appSettings)
        }
    }

    public func updateDirectoryFromPanel() async {
        guard case let .loaded(loaded) = presentation.state else { return }
        await updateDirectory(isForcedSearch: loaded.directoryPanel.shouldForceSearchOnUpdate)
    }

    public func updateDirectory(isForcedSearch: Bool = false) async {
        if isForcedSearch {
            automaticDirectoryUpdateTask?.cancel()
            automaticDirectoryUpdateTask = nil
        }
        await enqueueDirectoryUpdate(isForcedSearch: isForcedSearch, isAutomatic: false)
    }

    public func renameDirectory(cleanBookName: String, searchKeyword: String) async {
        automaticDirectoryUpdateTask?.cancel()
        automaticDirectoryUpdateTask = nil
        directoryMutationTask?.cancel()
        invalidateReaderContent()
        directoryMutationGeneration += 1
        let generation = directoryMutationGeneration
        directoryMutationTask = Task { @MainActor [weak self] in
            await self?.performRenameDirectory(
                cleanBookName: cleanBookName,
                searchKeyword: searchKeyword,
                mutationGeneration: generation
            )
        }
        await directoryMutationTask?.value
    }

    public func renameDirectory(with draft: MangaDirectoryEditDraft) async {
        await renameDirectory(
            cleanBookName: draft.cleanBookName,
            searchKeyword: MangaDirectoryWorkflow.searchKeyword(from: draft)
        )
    }

    public func deleteDirectoryChapters(tids: Set<String>) async {
        guard case let .loaded(loaded) = presentation.state else { return }
        let targetTIDs = Set(tids.compactMap(Self.normalizedNonEmpty))
        guard !targetTIDs.isEmpty else { return }
        if let currentChapterTID = loaded.directoryPanel.currentChapterTID,
           targetTIDs.contains(currentChapterTID) {
            return
        }

        automaticDirectoryUpdateTask?.cancel()
        automaticDirectoryUpdateTask = nil
        directoryMutationTask?.cancel()
        invalidateReaderContent()
        directoryMutationGeneration += 1
        let generation = directoryMutationGeneration
        directoryMutationTask = Task { @MainActor [weak self] in
            await self?.performDeleteDirectoryChapters(
                tids: targetTIDs,
                mutationGeneration: generation
            )
        }
        await directoryMutationTask?.value
    }

    public func jumpToChapter(_ chapter: MangaChapter) async {
        chapterJumpTask?.cancel()
        invalidateReaderContent()
        chapterJumpGeneration += 1
        let generation = chapterJumpGeneration
        let navigationGeneration = beginNavigationRequest()
        let sourcePosition = currentStableReadingPosition
        chapterJumpTask = Task { @MainActor [weak self] in
            await self?.performJumpToChapter(
                chapter,
                sourcePosition: sourcePosition,
                navigationGeneration: navigationGeneration,
                jumpGeneration: generation
            )
        }
        await chapterJumpTask?.value
    }

    public var canNavigateBack: Bool {
        currentStableReadingPosition != nil && navigationHistory.canGoBack
    }

    public var canNavigateForward: Bool {
        currentStableReadingPosition != nil && navigationHistory.canGoForward
    }

    public func navigateBack() async {
        await restoreNavigationAnchor(direction: .back)
    }

    public func navigateForward() async {
        await restoreNavigationAnchor(direction: .forward)
    }

    private func startAutomaticDirectoryUpdate() {
        automaticDirectoryUpdateTask?.cancel()
        automaticDirectoryUpdateTask = Task { @MainActor [weak self] in
            await self?.enqueueDirectoryUpdate(isForcedSearch: false, isAutomatic: true)
        }
    }

    private func enqueueDirectoryUpdate(isForcedSearch: Bool, isAutomatic: Bool) async {
        if isAutomatic, directoryMutationTask != nil {
            automaticDirectoryUpdateTask = nil
            return
        }

        if !isAutomatic {
            directoryMutationTask?.cancel()
        }

        invalidateReaderContent()
        directoryMutationGeneration += 1
        let generation = directoryMutationGeneration
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performDirectoryUpdate(
                isForcedSearch: isForcedSearch,
                isAutomatic: isAutomatic,
                mutationGeneration: generation
            )
        }
        directoryMutationTask = task
        await task.value
    }

    private func performDirectoryUpdate(
        isForcedSearch: Bool,
        isAutomatic: Bool,
        mutationGeneration: Int
    ) async {
        guard let workflow else { return }
        let previousProgressSnapshot = progressSnapshot(from: presentation)

        defer {
            if directoryMutationGeneration == mutationGeneration {
                directoryMutationTask = nil
            }
            if isAutomatic {
                automaticDirectoryUpdateTask = nil
            }
        }

        setDirectoryPanelCommandState(isUpdating: true, errorMessage: nil)
        do {
            let result = try await workflow.updateDirectory(isForcedSearch: isForcedSearch)
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            publishPresentation(workflow.presentation, previousProgressSnapshot: previousProgressSnapshot)
            if let cooldownExpiresAt = result.cooldownExpiresAt {
                directoryCooldownExpiresAt = cooldownExpiresAt
                forcedSearchShortcutExpiresAt = nil
            } else if result.shouldOfferForcedSearch {
                directoryCooldownExpiresAt = nil
                forcedSearchShortcutExpiresAt = dependencies.directoryWorkflowConfiguration.now()
                    .addingTimeInterval(dependencies.directoryWorkflowConfiguration.forcedSearchShortcutDuration)
            } else {
                directoryCooldownExpiresAt = nil
                forcedSearchShortcutExpiresAt = nil
            }
            refreshDirectoryPanelTiming(errorMessage: nil)
        } catch is CancellationError {
            guard directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } catch {
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            if case let YamiboError.searchCooldown(seconds) = error {
                directoryCooldownExpiresAt = dependencies.directoryWorkflowConfiguration.now()
                    .addingTimeInterval(TimeInterval(seconds))
                forcedSearchShortcutExpiresAt = nil
            } else if let cooldown = await workflow.currentDirectorySearchCooldownExpiresAt() {
                directoryCooldownExpiresAt = cooldown
                forcedSearchShortcutExpiresAt = nil
            }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
        }
    }

    private func performRenameDirectory(
        cleanBookName: String,
        searchKeyword: String,
        mutationGeneration: Int
    ) async {
        guard let workflow else { return }
        let previousProgressSnapshot = progressSnapshot(from: presentation)
        defer {
            if directoryMutationGeneration == mutationGeneration {
                directoryMutationTask = nil
            }
        }

        setDirectoryPanelCommandState(isUpdating: true, errorMessage: nil)
        do {
            let oldOwnerName = offlineCacheOwnerName
            let updated = try await workflow.renameDirectory(cleanBookName: cleanBookName, searchKeyword: searchKeyword)
            let cacheRenameError: Error?
            if let oldOwnerName,
               oldOwnerName != updated.cleanBookName,
               let offlineCacheStore = dependencies.makeOfflineCacheStore() {
                do {
                    try await offlineCacheStore.renameOwner(from: oldOwnerName, to: updated.cleanBookName)
                    cacheRenameError = nil
                } catch {
                    cacheRenameError = error
                }
            } else {
                cacheRenameError = nil
            }
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            publishPresentation(workflow.presentation, previousProgressSnapshot: previousProgressSnapshot)
            refreshDirectoryPanelTiming(errorMessage: cacheRenameError?.localizedDescription)
        } catch is CancellationError {
            guard directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } catch {
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
        }
    }

    private func performDeleteDirectoryChapters(
        tids: Set<String>,
        mutationGeneration: Int
    ) async {
        guard let workflow else { return }
        let previousProgressSnapshot = progressSnapshot(from: presentation)
        defer {
            if directoryMutationGeneration == mutationGeneration {
                directoryMutationTask = nil
            }
        }

        setDirectoryPanelCommandState(isUpdating: true, errorMessage: nil)
        do {
            let nextPresentation = try await workflow.deleteDirectoryChapters(tids: tids)
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
            refreshDirectoryPanelTiming(errorMessage: nil)
        } catch is CancellationError {
            guard directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: currentDirectoryPanelErrorMessage)
        } catch {
            guard !Task.isCancelled, directoryMutationGeneration == mutationGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
        }
    }

    private func performJumpToChapter(
        _ chapter: MangaChapter,
        sourcePosition: MangaReadingPosition?,
        navigationGeneration: Int,
        jumpGeneration: Int
    ) async {
        guard let workflow else { return }
        let previousProgressSnapshot = progressSnapshot(from: presentation)
        defer {
            if chapterJumpGeneration == jumpGeneration {
                chapterJumpTask = nil
            }
        }

        do {
            let nextPresentation = try await workflow.jumpToChapter(chapter)
            guard !Task.isCancelled, chapterJumpGeneration == jumpGeneration else { return }
            publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
            if isCurrentNavigationRequest(navigationGeneration) {
                recordSuccessfulNonlinearNavigation(
                    from: sourcePosition,
                    to: MangaReadingPosition(tid: chapter.tid, localIndex: 0)
                )
            }
            refreshDirectoryPanelTiming(errorMessage: nil)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, chapterJumpGeneration == jumpGeneration else { return }
            refreshDirectoryPanelTiming(errorMessage: error.localizedDescription)
        }
    }

    @discardableResult
    public func saveProgress() async -> MangaPresentationRoute {
        guard let snapshot = progressSnapshot(from: presentation) else {
            return .native(context)
        }

        await onReaderResumeRouteChange(.manga(snapshot.resumeRoute))
        try? await dependencies.progressSync.flush(.manga(snapshot.progress))
        lastQueuedProgressSnapshot = snapshot
        return snapshot.resumeRoute
    }

    private func scheduleAdjacentPrefetch(around globalIndex: Int) {
        guard workflow != nil else { return }
        let generation = readerContentGeneration
        adjacentPrefetchTask = Task { @MainActor [weak self] in
            await self?.performAdjacentPrefetch(
                around: globalIndex,
                readerContentGeneration: generation
            )
        }
    }

    private func performAdjacentPrefetch(
        around globalIndex: Int,
        readerContentGeneration generation: Int
    ) async {
        guard let workflow else { return }
        defer {
            if readerContentGeneration == generation {
                adjacentPrefetchTask = nil
            }
        }

        let previousProgressSnapshot = progressSnapshot(from: presentation)
        guard let nextPresentation = await workflow.prefetchAdjacentChaptersIfNeeded(around: globalIndex) else {
            return
        }
        guard !Task.isCancelled, readerContentGeneration == generation else { return }
        publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
    }

    private func invalidateReaderContent() {
        adjacentPrefetchTask?.cancel()
        adjacentPrefetchTask = nil
        readerContentGeneration += 1
    }

    private func beginNavigationRequest() -> Int {
        navigationRequestGeneration += 1
        return navigationRequestGeneration
    }

    private func isCurrentNavigationRequest(_ generation: Int) -> Bool {
        navigationRequestGeneration == generation
    }

    private func cancelReaderTasks() {
        directoryTickTask?.cancel()
        directoryTickTask = nil
        directoryMutationTask?.cancel()
        directoryMutationTask = nil
        automaticDirectoryUpdateTask?.cancel()
        automaticDirectoryUpdateTask = nil
        chapterJumpTask?.cancel()
        chapterJumpTask = nil
        adjacentPrefetchTask?.cancel()
        adjacentPrefetchTask = nil
        readerContentGeneration += 1
    }

    private func publishPresentation(
        _ nextPresentation: MangaReaderPresentation,
        previousProgressSnapshot: MangaReaderProgressSnapshot?
    ) {
        if nextPresentation != presentation {
            presentation = nextPresentation
        }
        updateOfflineCacheOwnerName(from: nextPresentation)
        currentStableReadingPosition = stableReadingPosition(from: nextPresentation)
        let nextProgressSnapshot = progressSnapshot(from: nextPresentation)
        guard nextProgressSnapshot != previousProgressSnapshot
            || nextProgressSnapshot != lastQueuedProgressSnapshot else {
            return
        }
        scheduleProgressSync(snapshot: nextProgressSnapshot)
    }

    private func scheduleProgressSync(snapshot: MangaReaderProgressSnapshot?) {
        guard let snapshot else { return }
        lastQueuedProgressSnapshot = snapshot
        let progressSync = dependencies.progressSync
        Task { [onReaderResumeRouteChange, snapshot, progressSync] in
            await onReaderResumeRouteChange(.manga(snapshot.resumeRoute))
            await progressSync.queue(.manga(snapshot.progress))
        }
    }

    private func updateOfflineCacheOwnerName(from presentation: MangaReaderPresentation) {
        guard case let .loaded(loaded) = presentation.state else {
            offlineCacheOwnerName = nil
            return
        }
        offlineCacheOwnerName = normalizedDirectoryName(loaded.directoryTitle)
    }

    private func currentPageIndex(in presentation: MangaReaderPresentation) -> Int? {
        guard case let .loaded(loaded) = presentation.state else { return nil }
        return loaded.currentPageIndex
    }

    private func stableReadingPosition(from presentation: MangaReaderPresentation) -> MangaReadingPosition? {
        guard case let .loaded(loaded) = presentation.state else { return nil }
        if let readingPosition = loaded.readingPosition {
            return readingPosition
        }
        guard let currentPage = loaded.currentPage else { return nil }
        return MangaReadingPosition(tid: currentPage.tid, localIndex: currentPage.localIndex)
    }

    private enum NavigationRestoreDirection {
        case back
        case forward
    }

    private func restoreNavigationAnchor(direction: NavigationRestoreDirection) async {
        guard let sourcePosition = currentStableReadingPosition else { return }
        let navigationGeneration = beginNavigationRequest()

        while let targetPosition = navigationTarget(for: direction) {
            guard let workflow else { return }
            adjacentPrefetchTask?.cancel()
            readerContentGeneration += 1
            let previousProgressSnapshot = progressSnapshot(from: presentation)
            do {
                let nextPresentation = try await workflow.jumpToPosition(targetPosition)
                publishPresentation(nextPresentation, previousProgressSnapshot: previousProgressSnapshot)
                guard isCurrentNavigationRequest(navigationGeneration) else { return }
                commitNavigationRestore(direction: direction, sourcePosition: sourcePosition)
                scheduleAdjacentPrefetch(around: currentPageIndex(in: nextPresentation) ?? 0)
                return
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentNavigationRequest(navigationGeneration) else { return }
                discardNavigationTarget(for: direction)
            }
        }
    }

    private func navigationTarget(for direction: NavigationRestoreDirection) -> MangaReadingPosition? {
        switch direction {
        case .back:
            navigationHistory.peekBack()
        case .forward:
            navigationHistory.peekForward()
        }
    }

    private func commitNavigationRestore(
        direction: NavigationRestoreDirection,
        sourcePosition: MangaReadingPosition
    ) {
        switch direction {
        case .back:
            navigationHistory.commitBack(from: sourcePosition)
        case .forward:
            navigationHistory.commitForward(from: sourcePosition)
        }
        armLinearReadingHistoryExpirationIfNeeded()
    }

    private func discardNavigationTarget(for direction: NavigationRestoreDirection) {
        switch direction {
        case .back:
            navigationHistory.discardBackCandidate()
        case .forward:
            navigationHistory.discardForwardCandidate()
        }
        resetLinearReadingHistoryExpirationIfHistoryIsEmpty()
    }

    private func recordSuccessfulNonlinearNavigation(
        from sourcePosition: MangaReadingPosition?,
        to targetPosition: MangaReadingPosition
    ) {
        guard let sourcePosition, sourcePosition != targetPosition else { return }
        navigationHistory.recordNonlinearJump(from: sourcePosition, to: targetPosition)
        armLinearReadingHistoryExpirationIfNeeded()
    }

    private func recordLinearReadingForNavigationHistory() {
        guard navigationHistory.canGoBack || navigationHistory.canGoForward else {
            linearReadingHistoryExpiration.reset()
            return
        }
        guard let position = currentStableReadingPosition else { return }
        if linearReadingHistoryExpiration.recordLinearReading(at: position) {
            navigationHistory.clear()
        }
    }

    private func armLinearReadingHistoryExpirationIfNeeded() {
        guard navigationHistory.canGoBack || navigationHistory.canGoForward,
              let position = currentStableReadingPosition else {
            linearReadingHistoryExpiration.reset()
            return
        }
        linearReadingHistoryExpiration.arm(at: position)
    }

    private func resetNavigationHistory() {
        navigationHistory = ReaderNavigationHistory()
        linearReadingHistoryExpiration.reset()
    }

    private func resetLinearReadingHistoryExpirationIfHistoryIsEmpty() {
        guard !navigationHistory.canGoBack, !navigationHistory.canGoForward else { return }
        linearReadingHistoryExpiration.reset()
    }

    private var currentDirectoryPanelErrorMessage: String? {
        guard case let .loaded(loaded) = presentation.state else { return nil }
        return loaded.directoryPanel.errorMessage
    }

    private func refreshDirectoryPanelTiming(errorMessage: String?) {
        setDirectoryPanelCommandState(
            isUpdating: false,
            errorMessage: errorMessage
        )
        updateDirectoryTickTask()
    }

    private func setDirectoryPanelCommandState(
        isUpdating: Bool,
        errorMessage: String?
    ) {
        guard let workflow else { return }
        let now = dependencies.directoryWorkflowConfiguration.now()
        let cooldownRemaining = remainingSecondsValue(until: directoryCooldownExpiresAt, now: now)
        let forcedRemaining = remainingSeconds(until: forcedSearchShortcutExpiresAt, now: now)
        if cooldownRemaining == 0 {
            directoryCooldownExpiresAt = nil
        }
        if forcedRemaining == nil {
            forcedSearchShortcutExpiresAt = nil
        }
        presentation = workflow.updateDirectoryPanelCommandState(
            MangaDirectoryPanelCommandState(
                isUpdating: isUpdating,
                cooldownRemaining: cooldownRemaining,
                forcedSearchShortcutRemaining: forcedRemaining,
                errorMessage: errorMessage
            )
        )
    }

    private func updateDirectoryTickTask() {
        let hasActiveDeadline = directoryCooldownExpiresAt != nil || forcedSearchShortcutExpiresAt != nil
        guard hasActiveDeadline else {
            directoryTickTask?.cancel()
            directoryTickTask = nil
            return
        }
        guard directoryTickTask == nil else { return }

        directoryTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.setDirectoryPanelCommandState(
                    isUpdating: false,
                    errorMessage: self?.currentDirectoryPanelErrorMessage
                )
                guard self?.directoryCooldownExpiresAt != nil || self?.forcedSearchShortcutExpiresAt != nil else {
                    self?.directoryTickTask = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func remainingSeconds(until deadline: Date?, now: Date) -> Int? {
        guard let deadline else { return nil }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return max(1, Int(ceil(remaining)))
    }

    private func remainingSecondsValue(until deadline: Date?, now: Date) -> Int {
        remainingSeconds(until: deadline, now: now) ?? 0
    }

    private func progressSnapshot(from presentation: MangaReaderPresentation) -> MangaReaderProgressSnapshot? {
        guard case let .loaded(loaded) = presentation.state,
              let currentPage = loaded.currentPage else {
            return nil
        }

        let progress = MangaProgressReadingPosition(
            threadURL: context.originalThreadURL,
            chapterURL: currentPage.refererURL,
            chapterTitle: currentPage.chapterTitle,
            pageIndex: currentPage.localIndex
        )
        let directoryName = normalizedDirectoryName(loaded.directoryTitle) ?? normalizedDirectoryName(context.directoryName)
        let resumeContext = MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: currentPage.refererURL,
            displayTitle: context.displayTitle,
            source: .resume,
            initialPage: currentPage.localIndex,
            directoryName: directoryName,
            offlineCacheFavoriteID: context.offlineCacheFavoriteID
        )
        return MangaReaderProgressSnapshot(
            progress: progress,
            resumeRoute: .native(resumeContext)
        )
    }

    private func presentationWithCommittedSettings(
        _ presentation: MangaReaderPresentation
    ) -> MangaReaderPresentation {
        var nextPresentation = presentation
        nextPresentation.settings = committedSettings
        return nextPresentation
    }

    private func normalizedDirectoryName(_ directoryName: String?) -> String? {
        let normalized = directoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private func ensureChapterCommentsRepository() async -> ReaderChapterCommentsRepository {
        if chapterCommentsRepository == nil {
            chapterCommentsRepository = await appContext.makeReaderChapterCommentsRepository()
        }
        guard let chapterCommentsRepository else {
            preconditionFailure("Reader chapter comments repository should be initialized")
        }
        return chapterCommentsRepository
    }

    private func syncChapterComments(from module: ReaderChapterCommentsModule) {
        chapterCommentsState = module.state
        isLoadingMoreChapterComments = module.isLoadingMore
        chapterCommentsLoadMoreError = module.loadMoreError
        chapterCommentsRefreshError = module.refreshError
    }

    private static func webViewPage(from url: URL) -> Int {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value
            .flatMap(Int.init) ?? 1
    }

    private static func normalizedSettings(_ settings: MangaReaderSettings) -> MangaReaderSettings {
        var normalized = settings
        normalized.brightness = normalizedBrightness(settings.brightness)
        return normalized
    }

    private static func normalizedBrightness(_ brightness: Double) -> Double {
        guard brightness.isFinite else { return 1.0 }
        return min(1.5, max(0.25, brightness))
    }

    private static func normalizedNonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func presentationTitle(for context: MangaLaunchContext) -> String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.string("manga.reader.title") : title
    }
}

private struct MangaReaderProgressSnapshot: Hashable, Sendable {
    var progress: MangaProgressReadingPosition
    var resumeRoute: MangaPresentationRoute
}
