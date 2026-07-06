import SwiftUI
import YamiboReaderCore

private struct NovelReaderLinearReadingPageKey: Equatable, Sendable {
    var view: Int
    var surfaceIndex: Int
}

@MainActor
public final class NovelReaderViewModel: ObservableObject {
    @Published public private(set) var isLoading = false
    @Published public private(set) var isNavigatingNovelReaderProjection = false
    @Published public private(set) var isApplyingAppearanceSettings = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var cachedViews: Set<Int> = []
    @Published public private(set) var cachingViews: Set<Int> = []
    @Published public private(set) var cachedViewUpdateTimes: [Int: Date] = [:]
    @Published public private(set) var offlineCacheQueueEntryCount = 0
    @Published private var bootstrapSettings = NovelReaderAppearanceSettings()
    @Published public var applePencilPageTurnSettings = ApplePencilPageTurnSettings()
    @Published public private(set) var sessionState = SessionState()
    @Published public private(set) var cacheOperationState = NovelReaderCacheOperationState()
    @Published public private(set) var chapterCommentsState: ReaderChapterCommentsState = .idle
    @Published public private(set) var isLoadingMoreChapterComments = false
    @Published public private(set) var chapterCommentsLoadMoreError: String?
    @Published public private(set) var chapterCommentsRefreshError: String?
    @Published public private(set) var chapterDirectoryView: Int?
    @Published public private(set) var chapterDirectoryChapters: [NovelReaderChapter] = []
    @Published public private(set) var chapterDirectoryPageCount = 0
    @Published public private(set) var isLoadingChapterDirectory = false
    @Published public private(set) var chapterDirectoryError: String?
    @Published public private(set) var novelReaderPresentation: NovelReaderPresentation?
    @Published private var navigationHistory = ReaderNavigationHistory<NovelResumePoint>()
    private var linearReadingHistoryExpiration = ReaderNavigationLinearReadingExpiration<NovelReaderLinearReadingPageKey>()
    public private(set) var chromeProgressSnapshot = NovelReaderChromeProgressSnapshot.empty

    public let context: NovelLaunchContext

    private let appContext: YamiboAppContext
    private var repository: NovelReaderRepository?
    private var chapterCommentsRepository: ReaderChapterCommentsRepository?
    private var readingWorkflow: NovelReadingWorkflow?
    private var appearanceSettingsApplicationSequence: UInt64 = 0
    private var layout: NovelReaderLayout = .zero
    private var latestRequestedLayout: NovelReaderLayout = .zero
    private var layoutRequestSequence: UInt64 = 0
    private var navigationRequestSequence: UInt64 = 0
    private var usesPadPresentation = false
    private var chapterDirectoryAnchors: [Int: NovelChapterAnchor] = [:]
    private var currentStableResumePoint: NovelResumePoint?
    private var offlineCacheUpdatesTask: Task<Void, Never>?
    private let runtimeAdapter: (any NovelTextLayoutRuntimeAdapter)?
    private let onReaderResumeRouteChange: ReaderResumeRouteChangeHandler
    package var runtimeUpdatePreparation: NovelReadingWorkflowRuntimeUpdatePreparation = { $0 }
    package var novelReaderPageDocumentNavigationOverlayPreparation: (@MainActor () async -> Void) = {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    package var novelReaderPageDocumentNavigationStateDidChange: (@MainActor (Bool) -> Void)?
    private let progressSync: ProgressSyncModule
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
        onChange: { [weak self] snapshot in
            // The module is driven exclusively from this main-actor view model,
            // so its caller-isolated onChange provably fires on the main actor.
            MainActor.assumeIsolated {
                self?.syncChapterComments(snapshot)
            }
        }
    )
    private let cacheOperationModule = NovelReaderCacheOperationModule()

    public init(
        context: NovelLaunchContext,
        appContext: YamiboAppContext,
        initialSettings: NovelReaderAppearanceSettings? = nil,
        onReaderResumeRouteChange: @escaping ReaderResumeRouteChangeHandler = { _ in }
    ) {
        self.context = context
        self.appContext = appContext
        self.onReaderResumeRouteChange = onReaderResumeRouteChange
        if let initialSettings {
            bootstrapSettings = initialSettings
        }
        runtimeAdapter = nil
        progressSync = ProgressSyncModule(
            adapter: FavoriteLibraryProgressSyncAdapter(
                readingProgressStore: appContext.readingProgressStore
            )
        )
        cacheOperationModule.onChange = { [weak self] snapshot, state in
            self?.cachedViews = snapshot.cachedViews
            self?.cachingViews = snapshot.cachingViews
            self?.cachedViewUpdateTimes = snapshot.updateTimesByView
            self?.cacheOperationState = state
            Task { [weak self] in
                await self?.refreshOfflineCacheQueueCount()
            }
        }
    }

    package init(
        context: NovelLaunchContext,
        appContext: YamiboAppContext,
        initialSettings: NovelReaderAppearanceSettings? = nil,
        runtimeAdapter: any NovelTextLayoutRuntimeAdapter,
        onReaderResumeRouteChange: @escaping ReaderResumeRouteChangeHandler = { _ in }
    ) {
        self.context = context
        self.appContext = appContext
        self.onReaderResumeRouteChange = onReaderResumeRouteChange
        if let initialSettings {
            bootstrapSettings = initialSettings
        }
        self.runtimeAdapter = runtimeAdapter
        progressSync = ProgressSyncModule(
            adapter: FavoriteLibraryProgressSyncAdapter(
                readingProgressStore: appContext.readingProgressStore
            )
        )
        cacheOperationModule.onChange = { [weak self] snapshot, state in
            self?.cachedViews = snapshot.cachedViews
            self?.cachingViews = snapshot.cachingViews
            self?.cachedViewUpdateTimes = snapshot.updateTimesByView
            self?.cacheOperationState = state
            Task { [weak self] in
                await self?.refreshOfflineCacheQueueCount()
            }
        }
    }

    deinit {
        offlineCacheUpdatesTask?.cancel()
    }

    public var title: String {
        context.threadTitle.isEmpty ? L10n.string("reader.title") : context.threadTitle
    }

    public var settings: NovelReaderAppearanceSettings {
        novelReaderPresentation?.committedSettings ?? bootstrapSettings
    }

    public var isTwoPageSpreadActive: Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            layout.width > layout.height
    }

    public var novelReaderSurfaces: [NovelReaderSurface] {
        novelReaderPresentation?.surfaces ?? []
    }

    public var chapters: [NovelReaderChapter] {
        novelReaderPresentation?.chapters ?? []
    }

    public var currentView: Int {
        novelReaderPresentation?.readingState.currentView ?? 1
    }

    public var maxView: Int {
        novelReaderPresentation?.readingState.maxView ?? 1
    }

    public var currentChapterTitle: String? {
        novelReaderPresentation?.readingState.currentChapterTitle
    }

    private var currentAuthorID: String? {
        novelReaderPresentation?.readingState.authorID
    }

    public var currentContentSource: ReaderProjectionContentSource {
        novelReaderPresentation?.currentContentSource ?? .allPostsPage
    }

    public var retainedChapterCount: Int {
        novelReaderPresentation?.retainedChapterCount ?? 0
    }

    public var filteredChapterCandidateCount: Int {
        novelReaderPresentation?.filteredChapterCandidateCount ?? 0
    }

    public var selectedSurfaceIndex: Int {
        normalizedPagedSurfaceIndex(novelReaderPresentation?.selectedSurfaceIndex ?? 0)
    }

    public var currentSurfaceIntraProgress: Double {
        novelReaderPresentation?.readingState.currentSurfaceIntraProgress ?? 0
    }

    package var presentationSpreads: [NovelReaderPresentationSpread] {
        novelReaderPresentation?.spreads ?? []
    }

    package var novelReaderDebugState: NovelReadingWorkflowDebugState? {
        readingWorkflow?.debugState
    }

    public var progressText: String {
        chromeProgressSnapshot.progressText
    }

    public func previewText(
        translationMode: ReaderTranslationMode,
        characterCount: Int,
        fallback: String
    ) -> String {
        let sourceText = readingWorkflow?.currentPreviewSourceText().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let previewSource = sourceText.isEmpty ? fallback : sourceText
        let transformed = NovelTextTransformer.transform(previewSource, mode: translationMode)
        return String(transformed.prefix(max(characterCount, 0)))
    }

    public var surfaceCount: Int {
        chromeProgressSnapshot.surfaceCount
    }

    public var currentSurfaceNumber: Int {
        chromeProgressSnapshot.currentSurfaceNumber
    }

    public var currentProgressFraction: Double {
        chromeProgressSnapshot.currentProgressFraction
    }

    public var currentProgressPercent: Int {
        chromeProgressSnapshot.currentProgressPercent
    }

    public var currentProgressPercentText: String {
        chromeProgressSnapshot.currentProgressPercentText
    }

    public var progressChapterTicks: [NovelReaderProgressChapterTick] {
        chromeProgressSnapshot.progressChapterTicks
    }

    public func progressSliderLabelText(
        isEditing: Bool,
        sliderValue: Double,
        targetSurfaceIndex: Int
    ) -> String {
        chromeProgressSnapshot.progressSliderLabelText(
            isEditing: isEditing,
            sliderValue: sliderValue,
            targetSurfaceIndex: targetSurfaceIndex
        )
    }

    public var currentChapterCommentTarget: ReaderChapterCommentTarget? {
        selectedSurface?.chapterCommentTarget
    }

    public var currentWebViewText: String {
        L10n.string("reader.web_view_progress", displayedView, max(maxView, 1))
    }

    public var directoryWebTitle: String {
        L10n.string("reader.web_view_chapters", currentWebViewText)
    }

    public var visibleChapterDirectoryView: Int {
        chapterDirectoryView ?? visibleView
    }

    public var visibleChapterDirectoryChapters: [NovelReaderChapter] {
        chapterDirectoryView == nil ? chapters : chapterDirectoryChapters
    }

    public var visibleChapterDirectoryPageCount: Int {
        chapterDirectoryView == nil ? surfaceCount : max(chapterDirectoryPageCount, 1)
    }

    public var previousChapterDirectoryWebView: Int? {
        let target = visibleChapterDirectoryView - 1
        return target >= 1 ? target : nil
    }

    public var nextChapterDirectoryWebView: Int? {
        let target = visibleChapterDirectoryView + 1
        return target <= maxView ? target : nil
    }

    public var chapterDirectoryWebTitle: String {
        L10n.string(
            "reader.web_view_chapters",
            L10n.string("reader.web_view_progress", visibleChapterDirectoryView, max(maxView, 1))
        )
    }

    public var currentChapterDirectoryIndex: Int? {
        guard chapterDirectoryView == nil || visibleChapterDirectoryView == visibleView else { return nil }
        return currentChapterIndex
    }

    public func isCurrentChapterDirectoryChapter(_ chapter: NovelReaderChapter) -> Bool {
        guard visibleChapterDirectoryView == visibleView,
              let currentChapterDirectoryIndex else { return false }
        return chapter.ordinal == currentChapterDirectoryIndex
    }

    public var pagedViewportSelectionIndex: Int {
        guard isTwoPageSpreadActive else { return selectedSurfaceIndex }
        return spreadIndex(forSurfaceIndex: selectedSurfaceIndex)
    }

    public func commitNovelTextPresentationEnvironment(isPad: Bool) async {
        guard usesPadPresentation != isPad else { return }
        let previousUsesPadPresentation = usesPadPresentation
        guard settings.readingMode == .paged,
              readingWorkflow?.state != nil else {
            usesPadPresentation = isPad
            return
        }
        do {
            guard let state = try await requestRuntimeUpdate(
                settings: settings,
                layout: layout,
                usesPadPresentation: isPad
            ) else { return }
            usesPadPresentation = isPad
            syncFromWorkflowState(state)
        } catch {
            usesPadPresentation = previousUsesPadPresentation
            errorMessage = error.localizedDescription
        }
    }

    public func selectPagedViewportIndex(_ selectionIndex: Int) {
        let targetSurfaceIndex = isTwoPageSpreadActive
            ? progressSurfaceIndex(forSpreadIndex: selectionIndex)
            : selectionIndex
        selectSurface(targetSurfaceIndex)
    }

    public func novelTextViewportDisplayReference(
        for surfaceIdentity: NovelReaderSurfaceIdentity
    ) -> NovelTextViewportDisplayReference? {
        readingWorkflow?.displayReference(for: surfaceIdentity)
    }

    public func updateNovelTextViewportVisibleSurfaceIdentities(_ surfaceIdentities: [NovelReaderSurfaceIdentity]) {
        readingWorkflow?.updateVisibleSurfaceIdentities(surfaceIdentities)
    }

    public func chapterTitle(forSurfaceIndex surfaceIndex: Int) -> String? {
        chromeProgressSnapshot.chapterTitle(forSurfaceIndex: surfaceIndex)
    }

    public func progressChapterTickStartIndex(forSurfaceIndex surfaceIndex: Int) -> Int? {
        chromeProgressSnapshot.progressChapterTickStartIndex(forSurfaceIndex: surfaceIndex)
    }

    public var verticalProgressScrubContext: ReaderProgressScrubContext {
        chromeProgressSnapshot.progressScrubContext
    }

    public func targetSurfaceIndex(forProgressValue value: Double) -> Int {
        chromeProgressSnapshot.targetSurfaceIndex(forProgressValue: value)
    }

    public var cacheScopeTitle: String {
        L10n.string("reader.cache_scope.author")
    }

    public var cacheScopeDescription: String {
        L10n.string("reader.cache_scope.description")
    }

    public var allCacheableViews: [Int] {
        guard maxView > 0 else { return [] }
        return Array(1 ... maxView)
    }

    public var hasCacheOperationSession: Bool {
        cacheOperationState.hasSession
    }

    public var visibleView: Int {
        displayedView
    }

    public var currentNovelResumePoint: NovelResumePoint? {
        readingWorkflow?.captureNovelReadingPosition()
    }

    public var canNavigateBack: Bool {
        currentStableResumePoint != nil && navigationHistory.canGoBack
    }

    public var canNavigateForward: Bool {
        currentStableResumePoint != nil && navigationHistory.canGoForward
    }

    public func handleMemoryPressure() {
        readingWorkflow?.handleMemoryPressure()
    }

    public func close() {
        appearanceSettingsApplicationSequence &+= 1
        layoutRequestSequence &+= 1
        latestRequestedLayout = layout
        isApplyingAppearanceSettings = false
        readingWorkflow?.close()
        readingWorkflow = nil
        resetNavigationHistory()
        currentStableResumePoint = nil
        chromeProgressSnapshot = .empty
        novelReaderPresentation = nil
    }

    public var currentChapterIndex: Int? {
        chapters.lastIndex(where: { $0.startIndex <= selectedSurfaceIndex })
    }

    public var hasPreviousChapter: Bool {
        guard let currentChapterIndex else { return false }
        return currentChapterIndex > 0
    }

    public var hasNextChapter: Bool {
        guard let currentChapterIndex else { return false }
        return currentChapterIndex < chapters.count - 1
    }

    public var sourceStatusText: String? {
        guard let pageLoadSource = novelReaderPresentation?.pageLoadSource,
              case let .offlineFallback(updatedAt) = pageLoadSource else {
            return nil
        }
        guard let updatedAt else {
            return L10n.string("reader.offline_stale_notice")
        }
        return L10n.string(
            "reader.offline_stale_notice_with_time",
            updatedAt.formatted(date: .abbreviated, time: .shortened)
        )
    }

    public var chapterSummaryText: String {
        L10n.string("reader.chapter_summary", retainedChapterCount, filteredChapterCandidateCount)
    }

    public var inlineImageOfflineScope: YamiboImageOfflineScope? {
        YamiboImageOfflineScope(tid: context.threadID)
    }

    public var forumURL: URL {
        YamiboRoute.threadByID(
            tid: context.threadID,
            page: displayedView,
            authorID: currentAuthorID ?? context.authorID,
            reverse: false
        ).url
    }

    public var currentForumTargetURL: URL {
        guard let target = currentChapterCommentTarget else { return forumURL }
        return YamiboRoute.findPostURL(threadID: target.threadID, postID: target.ownerPostID) ?? forumURL
    }

    public func prepare(layout: NovelReaderLayout) async {
        self.layout = layout
        latestRequestedLayout = layout
        layoutRequestSequence &+= 1
        if repository == nil {
            repository = await appContext.makeNovelReaderRepository()
            let appSettings = await appContext.settingsStore.load()
            bootstrapSettings = appSettings.novelReader
            applePencilPageTurnSettings = appSettings.system.applePencilPageTurn
            sessionState = await appContext.sessionStore.load()
            if let repository {
                readingWorkflow = makeReadingWorkflow(repository: repository)
            }
        }
        if novelReaderSurfaces.isEmpty {
            let progress = await appContext.readingProgressStore.load(threadID: context.threadID)
            let novelProgress = progress?.novel
            await startReadingWorkflow(
                resumePoint: context.initialResumePoint ?? novelProgress?.novelResumePoint,
                favoriteAuthorID: novelProgress?.authorID
            )
        } else {
            if let state = try? await requestRuntimeUpdate(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            ) {
                syncFromWorkflowState(state)
            }
            await refreshCachedState()
        }
    }

    public func commitNovelTextLayout(_ layout: NovelReaderLayout) async {
        guard latestRequestedLayout != layout else { return }
        latestRequestedLayout = layout
        layoutRequestSequence &+= 1
        let requestSequence = layoutRequestSequence
        guard readingWorkflow?.state != nil else {
            self.layout = layout
            return
        }
        do {
            guard let state = try await requestRuntimeUpdate(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            ) else {
                if layoutRequestSequence == requestSequence {
                    latestRequestedLayout = self.layout
                }
                return
            }
            guard layoutRequestSequence == requestSequence else { return }
            self.layout = layout
            syncFromWorkflowState(state)
        } catch is CancellationError {
            if layoutRequestSequence == requestSequence {
                latestRequestedLayout = self.layout
            }
        } catch {
            guard layoutRequestSequence == requestSequence else { return }
            latestRequestedLayout = self.layout
            errorMessage = error.localizedDescription
        }
    }

    public func loadCurrent(forceRefresh: Bool) async {
        let didLoad = await load(
            view: displayedView,
            preferredSurfaceOrdinal: displayedPageIndex,
            preferredResumePoint: readingWorkflow?.captureNovelReadingPosition(),
            forceRefresh: forceRefresh
        )
        if didLoad {
            resetNavigationHistory()
        }
    }

    public func loadAdjacent(delta: Int) async {
        let target = max(1, min(maxView, displayedView + delta))
        guard target != displayedView else { return }

        if delta > 0,
           readingWorkflow?.canPromotePrefetchedDocument(forView: target) == true {
            await promotePrefetchedDocument(
                startingAt: 0,
                preferredResumePoint: nil,
                showsNovelReaderProjectionNavigationOverlay: true
            )
            return
        }

        await load(
            view: target,
            preferredSurfaceOrdinal: 0,
            preferredResumePoint: nil,
            forceRefresh: false,
            showsNovelReaderProjectionNavigationOverlay: true
        )
    }

    public func commitNovelTextAppearance(_ newSettings: NovelReaderAppearanceSettings) async {
        await commitNovelTextAppearance(newSettings, applePencilPageTurnSettings: applePencilPageTurnSettings)
    }

    public func commitNovelTextAppearance(
        _ newSettings: NovelReaderAppearanceSettings,
        applePencilPageTurnSettings newApplePencilPageTurnSettings: ApplePencilPageTurnSettings
    ) async {
        let oldSettings = settings
        let oldApplePencilPageTurnSettings = applePencilPageTurnSettings
        let novelReaderSettingsChanged = oldSettings != newSettings
        let applePencilSettingsChanged = oldApplePencilPageTurnSettings != newApplePencilPageTurnSettings
        guard novelReaderSettingsChanged else {
            guard applePencilSettingsChanged else { return }
            applePencilPageTurnSettings = newApplePencilPageTurnSettings
            persistSettings(applePencilPageTurnSettings: newApplePencilPageTurnSettings)
            return
        }

        if oldSettings.isSurfaceOnlyAppearanceChange(to: newSettings) {
            applePencilPageTurnSettings = newApplePencilPageTurnSettings
            if let state = readingWorkflow?.commitSurfaceAppearance(newSettings) {
                syncFromWorkflowState(state)
            }
            bootstrapSettings = newSettings
            persistSettings(
                novelReaderSettings: newSettings,
                applePencilPageTurnSettings: applePencilSettingsChanged ? newApplePencilPageTurnSettings : nil
            )
            return
        }

        guard readingWorkflow?.state != nil else {
            bootstrapSettings = newSettings
            applePencilPageTurnSettings = newApplePencilPageTurnSettings
            persistSettings(
                novelReaderSettings: newSettings,
                applePencilPageTurnSettings: applePencilSettingsChanged ? newApplePencilPageTurnSettings : nil
            )
            return
        }

        let applicationSequence = beginApplyingAppearanceSettings()
        defer { finishApplyingAppearanceSettings(applicationSequence) }

        do {
            guard let state = try await requestRuntimeUpdate(
                settings: newSettings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            ) else { return }
            guard appearanceSettingsApplicationSequence == applicationSequence else { return }
            applePencilPageTurnSettings = newApplePencilPageTurnSettings
            syncFromWorkflowState(state)
            bootstrapSettings = newSettings
            persistSettings(
                novelReaderSettings: newSettings,
                applePencilPageTurnSettings: applePencilSettingsChanged ? newApplePencilPageTurnSettings : nil
            )
        } catch is CancellationError {
        } catch {
            guard appearanceSettingsApplicationSequence == applicationSequence else { return }
            applePencilPageTurnSettings = oldApplePencilPageTurnSettings
            errorMessage = error.localizedDescription
        }
    }

    public func applyApplePencilPageTurnSettings(_ newSettings: ApplePencilPageTurnSettings) {
        applePencilPageTurnSettings = newSettings
        persistSettings(applePencilPageTurnSettings: newSettings)
    }

    @discardableResult
    public func saveProgress() async -> NovelLaunchContext {
        await flushProgress()
    }

    public func selectSurface(_ surfaceIndex: Int) {
        selectSurface(surfaceIndex, recordsLinearReading: true)
    }

    private func selectSurface(_ surfaceIndex: Int, recordsLinearReading: Bool) {
        guard let presentation = novelReaderPresentation,
              presentation.surfaces.indices.contains(surfaceIndex) else {
            return
        }
        if let state = readingWorkflow?.selectSurface(
            presentation.surfaces[surfaceIndex].identity,
            presentationRevision: presentation.revision
        ) {
            syncFromWorkflowState(state)
            if recordsLinearReading {
                recordLinearReadingForNavigationHistory()
            }
        }
        scheduleProgressSync()

        Task {
            await prefetchIfNeeded(for: selectedSurfaceIndex)
        }

        promoteIfNeededAfterLocationUpdate()
    }

    package func updateVerticalViewportPosition(surfaceIndex: Int, intraSurfaceProgress: Double, force: Bool = false) {
        let normalizedProgress = min(max(intraSurfaceProgress, 0), 1)
        let progressUpdateThreshold = force ? 0.002 : 0.02
        guard surfaceIndex != selectedSurfaceIndex ||
            abs(normalizedProgress - currentSurfaceIntraProgress) >= progressUpdateThreshold else {
            return
        }
        guard let presentation = novelReaderPresentation,
              presentation.surfaces.indices.contains(surfaceIndex) else { return }
        guard let state = readingWorkflow?.updateVerticalViewportPosition(
            surfaceIdentity: presentation.surfaces[surfaceIndex].identity,
            intraSurfaceProgress: normalizedProgress,
            presentationRevision: presentation.revision
        ) else { return }
        let oldSurfaceIndex = selectedSurfaceIndex
        syncFromWorkflowState(state)
        if oldSurfaceIndex != selectedSurfaceIndex {
            recordLinearReadingForNavigationHistory()
        }
        scheduleProgressSync()

        Task {
            await prefetchIfNeeded(for: selectedSurfaceIndex)
        }

        promoteIfNeededAfterLocationUpdate()
    }

    package func updateVerticalViewportPosition(sample: NovelTextViewportSample) {
        let oldSurfaceIndex = selectedSurfaceIndex
        let oldProgress = currentSurfaceIntraProgress
        let oldResumePoint = currentNovelResumePoint
        guard let presentation = novelReaderPresentation,
              presentation.surfaces.contains(where: {
                  $0.identity == sample.surfaceIdentity
              }) else {
            return
        }
        if let state = readingWorkflow?.updateVerticalViewportPosition(
            sample: sample,
            presentationRevision: presentation.revision
        ) {
            syncFromWorkflowState(state)
            if oldSurfaceIndex != selectedSurfaceIndex {
                recordLinearReadingForNavigationHistory()
            }
            let newResumePoint = currentNovelResumePoint
            let didChangePosition = oldSurfaceIndex != selectedSurfaceIndex ||
                oldProgress != currentSurfaceIntraProgress ||
                oldResumePoint != newResumePoint
            guard didChangePosition else {
                return
            }
        } else {
            return
        }
        scheduleProgressSync()

        Task {
            await prefetchIfNeeded(for: selectedSurfaceIndex)
        }

        promoteIfNeededAfterLocationUpdate()
    }

    public func jumpToChapter(_ chapter: NovelReaderChapter) {
        jumpToSurface(chapter.startIndex)
    }

    package func jumpToSurface(_ surfaceIndex: Int) {
        let navigationSequence = beginNavigationRequest()
        let sourceResumePoint = currentStableResumePoint
        selectSurface(surfaceIndex, recordsLinearReading: false)
        if isCurrentNavigationRequest(navigationSequence) {
            recordSuccessfulNonlinearNavigation(from: sourceResumePoint, to: currentStableResumePoint)
        }
    }

    public func navigateBack() async {
        await restoreNavigationAnchor(direction: .back)
    }

    public func navigateForward() async {
        await restoreNavigationAnchor(direction: .forward)
    }

    public func jumpRelativeSurface(_ delta: Int) async {
        guard let result = readingWorkflow?.jumpRelativeSurface(delta) else {
            scheduleProgressSync()
            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
            }
            return
        }

        syncFromWorkflowState(result.state)
        switch result.request {
        case nil:
            recordLinearReadingForNavigationHistory()
            scheduleProgressSync()
            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
            }
        case let .loadView(view, preferredSurfaceOrdinal, resumePoint):
            let didLoad = await load(
                view: view,
                preferredSurfaceOrdinal: preferredSurfaceOrdinal,
                preferredResumePoint: resumePoint,
                forceRefresh: false,
                showsNovelReaderProjectionNavigationOverlay: true
            )
            if didLoad {
                recordLinearReadingForNavigationHistory()
            }
        case let .promotePrefetched(preferredSurfaceOrdinal, resumePoint):
            let didPromote = await promotePrefetchedDocument(
                startingAt: preferredSurfaceOrdinal,
                preferredResumePoint: resumePoint,
                showsNovelReaderProjectionNavigationOverlay: true
            )
            if didPromote {
                recordLinearReadingForNavigationHistory()
            }
        }
    }

    public func jumpToAdjacentChapter(_ delta: Int) {
        guard let currentChapterIndex else { return }
        let targetIndex = currentChapterIndex + delta
        guard chapters.indices.contains(targetIndex) else { return }
        jumpToSurface(chapters[targetIndex].startIndex)
    }

    public func jumpToWebView(_ view: Int) async {
        await jumpToWebView(view, preferredSurfaceOrdinal: 0)
    }

    public func jumpToWebView(_ view: Int, preferredSurfaceOrdinal: Int) async {
        let navigationSequence = beginNavigationRequest()
        let sourceResumePoint = currentStableResumePoint
        let clampedView = max(1, min(maxView, view))

        if readingWorkflow?.canPromotePrefetchedDocument(forView: clampedView) == true {
            let didPromote = await promotePrefetchedDocument(
                startingAt: preferredSurfaceOrdinal,
                preferredResumePoint: nil,
                showsNovelReaderProjectionNavigationOverlay: true
            )
            if didPromote, isCurrentNavigationRequest(navigationSequence) {
                recordSuccessfulNonlinearNavigation(from: sourceResumePoint, to: currentStableResumePoint)
            }
            return
        }

        if clampedView == currentView {
            jumpToSurface(normalizedPagedSurfaceIndex(preferredSurfaceOrdinal))
            return
        }

        let didLoad = await load(
            view: clampedView,
            preferredSurfaceOrdinal: preferredSurfaceOrdinal,
            preferredResumePoint: nil,
            forceRefresh: false,
            showsNovelReaderProjectionNavigationOverlay: true
        )
        if didLoad, isCurrentNavigationRequest(navigationSequence) {
            recordSuccessfulNonlinearNavigation(from: sourceResumePoint, to: currentStableResumePoint)
        }
    }

    public func resetChapterDirectoryBrowsing() {
        chapterDirectoryView = nil
        chapterDirectoryChapters = []
        chapterDirectoryPageCount = 0
        chapterDirectoryAnchors = [:]
        isLoadingChapterDirectory = false
        chapterDirectoryError = nil
    }

    public func previewChapterDirectoryWebView(_ view: Int) async {
        let clampedView = max(1, min(maxView, view))
        if clampedView == visibleView {
            resetChapterDirectoryBrowsing()
            return
        }

        chapterDirectoryView = clampedView
        chapterDirectoryChapters = []
        chapterDirectoryPageCount = 0
        isLoadingChapterDirectory = true
        chapterDirectoryError = nil
        do {
            guard let workflow = await ensureReadingWorkflow() else {
                throw ReaderChapterCommentsUnavailableError()
            }
            let entries = try await workflow.previewChapterDirectory(view: clampedView)
            chapterDirectoryChapters = entries.map(\.chapter)
            chapterDirectoryAnchors = Dictionary(
                uniqueKeysWithValues: entries.compactMap { entry in
                    entry.anchor.map { (entry.chapter.ordinal, $0) }
                }
            )
            chapterDirectoryPageCount = 0
            isLoadingChapterDirectory = false
        } catch {
            chapterDirectoryError = error.localizedDescription
            isLoadingChapterDirectory = false
        }
    }

    public func jumpToChapterDirectoryChapter(_ chapter: NovelReaderChapter) async {
        let navigationSequence = beginNavigationRequest()
        let sourceResumePoint = currentStableResumePoint
        let targetView = visibleChapterDirectoryView
        let anchor = chapterDirectoryAnchors[chapter.ordinal]
        resetChapterDirectoryBrowsing()
        if targetView == visibleView {
            jumpToChapter(chapter)
            return
        }
        guard let anchor,
              let workflow = await ensureReadingWorkflow() else {
            let didLoad = await load(
                view: targetView,
                preferredSurfaceOrdinal: 0,
                preferredResumePoint: nil,
                forceRefresh: false,
                showsNovelReaderProjectionNavigationOverlay: true
            )
            if didLoad, isCurrentNavigationRequest(navigationSequence) {
                recordSuccessfulNonlinearNavigation(from: sourceResumePoint, to: currentStableResumePoint)
            }
            return
        }
        await beginNovelReaderProjectionNavigation()
        defer { setNovelReaderProjectionNavigation(false) }
        isLoading = true
        errorMessage = nil
        do {
            let state = try await workflow.loadChapter(anchor)
            syncFromWorkflowState(state)
            isLoading = false
            scheduleProgressSync()
            if isCurrentNavigationRequest(navigationSequence) {
                recordSuccessfulNonlinearNavigation(from: sourceResumePoint, to: currentStableResumePoint)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    public func refreshCachedState() async {
        startObservingOfflineCacheUpdates()
        guard let cacheOperationRepository else {
            syncCacheState(NovelOfflineCacheViewsSnapshot())
            return
        }
        syncCacheState(await cacheOperationRepository.cacheState(for: cacheOperationSnapshot.context))
        await refreshOfflineCacheQueueCount()
    }

    private func startObservingOfflineCacheUpdates() {
        guard offlineCacheUpdatesTask == nil else { return }
        let updates = appContext.makeOfflineCacheStore().offlineCacheUpdates()
        offlineCacheUpdatesTask = Task { @MainActor [weak self] in
            for await _ in updates {
                guard !Task.isCancelled else { return }
                await self?.refreshCachedState()
            }
        }
    }

    public func cacheSelectionState(for selectedViews: Set<Int>) -> NovelReaderCacheSelectionState {
        cacheOperationModule.selectionState(for: selectedViews, snapshot: cacheOperationSnapshot)
    }

    public func cacheStatus(for view: Int) -> NovelOfflineCacheViewStatus {
        NovelOfflineCacheViewsSnapshot(
            cachedViews: cachedViews,
            cachingViews: cachingViews,
            updateTimesByView: cachedViewUpdateTimes
        ).state(for: view).status
    }

    public func cacheUpdateTime(for view: Int) -> Date? {
        cachedViewUpdateTimes[max(1, view)]
    }

    public func startCaching(views: Set<Int>) {
        guard let cacheOperationRepository else { return }
        cacheOperationModule.startCaching(
            views: views,
            snapshot: cacheOperationSnapshot,
            repository: cacheOperationRepository,
            summary: cacheOperationSummary
        )
    }

    public func updateCachedViews(_ views: Set<Int>) {
        guard let cacheOperationRepository else { return }
        cacheOperationModule.updateCachedViews(
            views,
            snapshot: cacheOperationSnapshot,
            repository: cacheOperationRepository,
            summary: cacheOperationSummary,
            onFailure: { [weak self] error in
                self?.errorMessage = error.localizedDescription
            }
        )
    }

    public func deleteCachedViews(_ views: Set<Int>) async {
        guard let cacheOperationRepository else { return }
        do {
            try await cacheOperationModule.deleteCachedViews(
                views,
                snapshot: cacheOperationSnapshot,
                repository: cacheOperationRepository
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func showCacheProgressIfRunning() {
        cacheOperationModule.showProgressIfRunning()
    }

    public func hideCacheProgress() {
        cacheOperationModule.hideProgress()
    }

    public func loadChapterComments(for target: ReaderChapterCommentTarget?) async {
        await chapterCommentsModule.load(target)
    }

    public func refreshChapterComments(for target: ReaderChapterCommentTarget?) async {
        await chapterCommentsModule.refresh(target)
    }

    public func loadNextChapterCommentsPage() async {
        await chapterCommentsModule.loadNextPage()
    }

    public func dismissCacheProgress() {
        cacheOperationModule.dismissProgress()
    }

    public func stopCaching() {
        cacheOperationModule.stopCaching()
    }

    public func deleteCurrentCache() async {
        do {
            try await cacheOperationRepository?.deleteCachedViews(
                [displayedView],
                for: cacheOperationSnapshot.context
            )
            await refreshCachedState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshCurrentCache() async {
        guard let cacheOperationRepository else { return }
        let result = await cacheOperationRepository.updateCachedViews(
            [displayedView],
            for: cacheOperationSnapshot.context,
            progress: nil
        )
        if result.failedViews.isEmpty {
            await refreshCachedState()
        } else {
            errorMessage = L10n.string("common.operation_failed")
        }
    }

    func makeOfflineCacheQueueViewModel() -> MineHomeViewModel {
        MineHomeViewModel(appContext: appContext)
    }

    public func refreshOfflineCacheQueueCount() async {
        let store = appContext.makeOfflineCacheStore()
        offlineCacheQueueEntryCount = await store.offlineCacheQueueWorks().count
    }

    @discardableResult
    private func load(
        view: Int,
        preferredSurfaceOrdinal: Int,
        preferredResumePoint: NovelResumePoint?,
        forceRefresh: Bool,
        showsNovelReaderProjectionNavigationOverlay: Bool = false,
        reportsError: Bool = true
    ) async -> Bool {
        guard let workflow = await ensureReadingWorkflow() else { return false }
        if showsNovelReaderProjectionNavigationOverlay {
            await beginNovelReaderProjectionNavigation()
        }
        defer {
            if showsNovelReaderProjectionNavigationOverlay {
                setNovelReaderProjectionNavigation(false)
            }
        }
        isLoading = true
        errorMessage = nil
        do {
            let state = try await workflow.loadView(
                view,
                preferredSurfaceOrdinal: preferredSurfaceOrdinal,
                preferredResumePoint: preferredResumePoint,
                forceRefresh: forceRefresh
            )
            syncFromWorkflowState(state)
            isLoading = false
            await refreshCachedState()

            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
            }
            return true
        } catch {
            if reportsError {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            return false
        }
    }

    private func startReadingWorkflow(resumePoint: NovelResumePoint?, favoriteAuthorID: String?) async {
        guard let workflow = await ensureReadingWorkflow() else { return }
        isLoading = true
        errorMessage = nil
        do {
            let state = try await workflow.start(
                initial: NovelReadingInitialPosition(
                    resumePoint: resumePoint,
                    favoriteAuthorID: favoriteAuthorID
                )
            )
            syncFromWorkflowState(state)
            isLoading = false
            await refreshCachedState()

            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func ensureNovelReaderRepository() async -> NovelReaderRepository {
        if repository == nil {
            repository = await appContext.makeNovelReaderRepository()
        }
        guard let repository else {
            preconditionFailure("Reader repository should be initialized")
        }
        return repository
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

    private func ensureReadingWorkflow() async -> NovelReadingWorkflow? {
        let repository = await ensureNovelReaderRepository()
        if readingWorkflow == nil {
            readingWorkflow = makeReadingWorkflow(repository: repository)
        }
        return readingWorkflow
    }

    private func makeReadingWorkflow(repository: NovelReaderRepository) -> NovelReadingWorkflow {
        if let runtimeAdapter {
            return NovelReadingWorkflow(
                context: context,
                settings: settings,
                layout: layout,
                repository: repository,
                usesPadPresentation: usesPadPresentation,
                runtimeAdapter: runtimeAdapter
            )
        }
        return NovelReadingWorkflow(
            context: context,
            settings: settings,
            layout: layout,
            repository: repository,
            usesPadPresentation: usesPadPresentation
        )
    }

    private func requestRuntimeUpdate(
        settings: NovelReaderAppearanceSettings,
        layout: NovelReaderLayout,
        usesPadPresentation: Bool
    ) async throws -> NovelReadingWorkflowState? {
        try await readingWorkflow?.requestRuntimeUpdate(
            NovelReadingWorkflowRuntimeUpdate(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            ),
            preparation: runtimeUpdatePreparation
        )
    }

    private func beginNavigationRequest() -> UInt64 {
        navigationRequestSequence &+= 1
        return navigationRequestSequence
    }

    private func isCurrentNavigationRequest(_ sequence: UInt64) -> Bool {
        navigationRequestSequence == sequence
    }

    private func syncChapterComments(_ snapshot: ReaderChapterCommentsSnapshot) {
        chapterCommentsState = snapshot.state
        isLoadingMoreChapterComments = snapshot.isLoadingMore
        chapterCommentsLoadMoreError = snapshot.loadMoreError
        chapterCommentsRefreshError = snapshot.refreshError
    }

    private func syncFromWorkflowState(_ state: NovelReadingWorkflowState) {
        chromeProgressSnapshot = state.presentation.map(NovelReaderChromeProgressSnapshot.init) ?? .empty
        novelReaderPresentation = state.presentation
        currentStableResumePoint = readingWorkflow?.captureNovelReadingPosition()
    }

    private enum NavigationRestoreDirection {
        case back
        case forward
    }

    private func restoreNavigationAnchor(direction: NavigationRestoreDirection) async {
        guard let sourceResumePoint = currentStableResumePoint else { return }
        let navigationSequence = beginNavigationRequest()

        while let targetResumePoint = navigationTarget(for: direction) {
            let didRestore = await restoreResumePoint(targetResumePoint)
            if didRestore {
                guard isCurrentNavigationRequest(navigationSequence) else { return }
                commitNavigationRestore(direction: direction, sourceResumePoint: sourceResumePoint)
                scheduleProgressSync()
                return
            }
            guard isCurrentNavigationRequest(navigationSequence) else { return }
            discardNavigationTarget(for: direction)
        }
    }

    private func restoreResumePoint(_ resumePoint: NovelResumePoint) async -> Bool {
        if resumePoint.view == currentView,
           let state = readingWorkflow?.restoreResumePointInCurrentDocument(resumePoint) {
            syncFromWorkflowState(state)
            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
            }
            return true
        }

        if readingWorkflow?.canPromotePrefetchedDocument(forView: resumePoint.view) == true {
            return await promotePrefetchedDocument(
                startingAt: 0,
                preferredResumePoint: resumePoint,
                showsNovelReaderProjectionNavigationOverlay: true,
                reportsError: false
            )
        }

        return await load(
            view: resumePoint.view,
            preferredSurfaceOrdinal: 0,
            preferredResumePoint: resumePoint,
            forceRefresh: false,
            showsNovelReaderProjectionNavigationOverlay: true,
            reportsError: false
        )
    }

    private func navigationTarget(for direction: NavigationRestoreDirection) -> NovelResumePoint? {
        switch direction {
        case .back:
            navigationHistory.peekBack()
        case .forward:
            navigationHistory.peekForward()
        }
    }

    private func commitNavigationRestore(
        direction: NavigationRestoreDirection,
        sourceResumePoint: NovelResumePoint
    ) {
        switch direction {
        case .back:
            navigationHistory.commitBack(from: sourceResumePoint)
        case .forward:
            navigationHistory.commitForward(from: sourceResumePoint)
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
        from sourceResumePoint: NovelResumePoint?,
        to targetResumePoint: NovelResumePoint?
    ) {
        guard let sourceResumePoint, let targetResumePoint, sourceResumePoint != targetResumePoint else { return }
        navigationHistory.recordNonlinearJump(from: sourceResumePoint, to: targetResumePoint)
        armLinearReadingHistoryExpirationIfNeeded()
    }

    private func recordLinearReadingForNavigationHistory() {
        guard navigationHistory.canGoBack || navigationHistory.canGoForward else {
            linearReadingHistoryExpiration.reset()
            return
        }
        guard let pageKey = currentLinearReadingPageKey else { return }
        if linearReadingHistoryExpiration.recordLinearReading(at: pageKey) {
            navigationHistory.clear()
        }
    }

    private func armLinearReadingHistoryExpirationIfNeeded() {
        guard navigationHistory.canGoBack || navigationHistory.canGoForward,
              let pageKey = currentLinearReadingPageKey else {
            linearReadingHistoryExpiration.reset()
            return
        }
        linearReadingHistoryExpiration.arm(at: pageKey)
    }

    private func resetNavigationHistory() {
        navigationHistory = ReaderNavigationHistory()
        linearReadingHistoryExpiration.reset()
    }

    private func resetLinearReadingHistoryExpirationIfHistoryIsEmpty() {
        guard !navigationHistory.canGoBack, !navigationHistory.canGoForward else { return }
        linearReadingHistoryExpiration.reset()
    }

    private var currentLinearReadingPageKey: NovelReaderLinearReadingPageKey? {
        guard currentStableResumePoint != nil, novelReaderPresentation != nil else { return nil }
        return NovelReaderLinearReadingPageKey(view: currentView, surfaceIndex: selectedSurfaceIndex)
    }

    private func beginNovelReaderProjectionNavigation() async {
        setNovelReaderProjectionNavigation(true)
        await novelReaderPageDocumentNavigationOverlayPreparation()
    }

    private func setNovelReaderProjectionNavigation(_ isNavigating: Bool) {
        guard isNavigatingNovelReaderProjection != isNavigating else { return }
        isNavigatingNovelReaderProjection = isNavigating
        novelReaderPageDocumentNavigationStateDidChange?(isNavigating)
    }

    private func prefetchIfNeeded(for surfaceIndex: Int) async {
        guard let workflow = await ensureReadingWorkflow(),
              let presentation = novelReaderPresentation,
              presentation.surfaces.indices.contains(surfaceIndex),
              let state = await workflow.prefetchIfNeeded(near: presentation.surfaces[surfaceIndex].identity) else {
            return
        }
        syncFromWorkflowState(state)
    }

    private func chapterTitle(for surfaceIndex: Int) -> String? {
        guard novelReaderSurfaces.indices.contains(surfaceIndex) else {
            return chapters.last(where: { $0.startIndex <= surfaceIndex })?.title
        }
        return novelReaderSurfaces[surfaceIndex].chapterTitle ?? chapters.last(where: { $0.startIndex <= surfaceIndex })?.title
    }

    private var displayedPageLabel: String {
        novelReaderPresentation?.progressProjection.displayedPageLabel ?? "1"
    }

    private var displayedView: Int {
        chromeProgressSnapshot.visibleView
    }

    private var displayedPageIndex: Int {
        novelReaderPresentation?.progressProjection.displayedPageIndex ?? 0
    }

    private var displayedPageCount: Int {
        novelReaderPresentation?.progressProjection.displayedPageCount ?? 1
    }

    private var selectedSurface: NovelReaderSurface? {
        let normalizedIndex = normalizedPagedSurfaceIndex(selectedSurfaceIndex)
        guard novelReaderSurfaces.indices.contains(normalizedIndex) else { return nil }
        return novelReaderSurfaces[normalizedIndex]
    }

    private func currentProgressSnapshot() -> NovelReadingPosition {
        readingWorkflow?.currentProgressPosition() ?? NovelReadingPosition(
            threadID: context.threadID,
            view: displayedView,
            maxView: maxView,
            chapterTitle: currentChapterTitle,
            authorID: currentAuthorID ?? context.authorID,
            documentSurfaceProgressPercent: currentDocumentSurfaceProgressPercent,
            threadCoverURL: context.threadCoverURL
        )
    }

    private var currentDocumentSurfaceProgressPercent: Int? {
        guard let projection = novelReaderPresentation?.progressProjection else { return nil }
        guard projection.displayedPageCount > 1 else { return 0 }
        let fraction = Double(projection.displayedPageIndex) / Double(projection.displayedPageCount - 1)
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    private func promoteIfNeededAfterLocationUpdate() {
        if settings.readingMode == .paged,
           isAtPagedDocumentEnd,
           readingWorkflow?.canPromotePrefetchedDocument(forView: currentView + 1) == true {
            Task {
                await promotePrefetchedDocument(
                    startingAt: 0,
                    preferredResumePoint: nil,
                    showsNovelReaderProjectionNavigationOverlay: true
                )
            }
        }
    }

    private var isAtPagedDocumentEnd: Bool {
        guard settings.readingMode == .paged else { return false }
        if isTwoPageSpreadActive {
            let currentDocumentSpreads = presentationSpreads.filter { spread in
                guard novelReaderSurfaces.indices.contains(spread.leftSurfaceIndex) else { return false }
                return novelReaderSurfaces[spread.leftSurfaceIndex].documentView == currentView
            }
            guard let lastSpread = currentDocumentSpreads.last else { return false }
            return pagedViewportSelectionIndex >= lastSpread.index
        }

        let currentDocumentSurfaceIndexes = novelReaderSurfaces.indices.filter {
            novelReaderSurfaces[$0].documentView == currentView
        }
        guard let lastSurfaceIndex = currentDocumentSurfaceIndexes.last else { return false }
        return selectedSurfaceIndex >= lastSurfaceIndex
    }

    private func scheduleProgressSync() {
        let snapshot = currentProgressSnapshot()
        Task { [weak self, progressSync] in
            await self?.persistNovelResumeRoute(snapshot)
            await progressSync.queue(.novel(snapshot))
        }
    }

    private func flushProgress() async -> NovelLaunchContext {
        let snapshot = currentProgressSnapshot()
        let resumeContext = resumeContext(for: snapshot)
        await persistNovelResumeRoute(resumeContext)
        try? await progressSync.flush(.novel(snapshot))
        return resumeContext
    }

    private func persistNovelResumeRoute(_ snapshot: NovelReadingPosition) async {
        await persistNovelResumeRoute(resumeContext(for: snapshot))
    }

    private func persistNovelResumeRoute(_ resumeContext: NovelLaunchContext) async {
        await onReaderResumeRouteChange(.novel(resumeContext))
    }

    private func resumeContext(for snapshot: NovelReadingPosition) -> NovelLaunchContext {
        NovelLaunchContext(
            threadID: context.threadID,
            threadTitle: context.threadTitle,
            source: .resume,
            initialView: snapshot.view,
            authorID: snapshot.authorID ?? context.authorID,
            initialResumePoint: snapshot.resumePoint
        )
    }

    private func spreadIndex(forSurfaceIndex surfaceIndex: Int) -> Int {
        guard isTwoPageSpreadActive else {
            return max(0, min(surfaceIndex, max(novelReaderSurfaces.count - 1, 0)))
        }

        let normalizedIndex = max(0, min(surfaceIndex, max(novelReaderSurfaces.count - 1, 0)))
        return presentationSpreads.first(where: { spread in
            spread.leftSurfaceIndex == normalizedIndex || spread.rightSurfaceIndex == normalizedIndex
        })?.index ?? 0
    }

    private func progressSurfaceIndex(forSpreadIndex spreadIndex: Int) -> Int {
        guard let spread = presentationSpreads.first(where: { $0.index == spreadIndex }) ?? presentationSpreads.last else {
            return 0
        }
        switch settings.pageTurnDirection {
        case .leftToRight:
            return spread.rightSurfaceIndex ?? spread.leftSurfaceIndex
        case .rightToLeft:
            return spread.leftSurfaceIndex
        }
    }

    private func normalizedPagedSurfaceIndex(_ surfaceIndex: Int) -> Int {
        let clampedIndex = max(0, min(surfaceIndex, max(novelReaderSurfaces.count - 1, 0)))
        guard isTwoPageSpreadActive else { return clampedIndex }
        return progressSurfaceIndex(forSpreadIndex: spreadIndex(forSurfaceIndex: clampedIndex))
    }

    private func cacheContext(forView view: Int) -> (authorID: String?, contentSource: ReaderProjectionContentSource?) {
        guard let workflowContext = readingWorkflow?.cacheContext(forView: view) else {
            let authorID = currentAuthorID ?? context.authorID
            return (authorID, inferredContentSource(for: authorID))
        }
        return (workflowContext.authorID, workflowContext.contentSource)
    }

    private func inferredContentSource(for authorID: String?) -> ReaderProjectionContentSource {
        .authorFilteredPage
    }

    private var cacheOperationSnapshot: NovelReaderCacheOperationSnapshot {
        let context = cacheContext(forView: displayedView)
        return NovelReaderCacheOperationSnapshot(
            cacheableViews: Set(allCacheableViews),
            cachedViews: cachedViews,
            cachingViews: cachingViews,
            updateTimesByView: cachedViewUpdateTimes,
            context: NovelReaderCacheOperationContext(
                ownerTitle: title,
                threadID: self.context.threadID,
                authorID: context.authorID,
                contentSource: context.contentSource
            )
        )
    }

    private var cacheOperationRepository: NovelReaderCacheOperationRepository? {
        NovelOfflineStoreReaderCacheOperationAdapter(
            store: appContext.makeOfflineCacheStore(),
            novelOfflineCacheSettings: { [settingsStore = appContext.settingsStore] in
                await settingsStore.load().novelOfflineCache
            },
            continueOfflineCacheQueue: { [appContext] in
                try await appContext.makeOfflineCacheQueueExecutor().continueQueue()
            }
        )
    }

    private func cacheOperationSummary(
        mode: NovelReaderCacheOperationMode,
        result: NovelReaderCacheBatchResult
    ) -> String {
        let actionText = switch mode {
        case .cache: L10n.string("reader.cache_action.cache")
        case .update: L10n.string("reader.cache_action.update")
        }

        var summary = result.wasCancelled
            ? L10n.string("reader.cache_summary.cancelled", result.completedViews.count, result.totalCount, actionText)
            : L10n.string("reader.cache_summary.completed", result.completedViews.count, result.totalCount, actionText)
        if !result.failedViews.isEmpty {
            summary += L10n.string("reader.cache_summary.failed_suffix", result.failedViews.count)
        }
        return summary
    }

    @discardableResult
    private func promotePrefetchedDocument(startingAt preferredSurfaceOrdinal: Int) async -> Bool {
        await promotePrefetchedDocument(startingAt: preferredSurfaceOrdinal, preferredResumePoint: nil)
    }

    @discardableResult
    private func promotePrefetchedDocument(
        startingAt preferredSurfaceOrdinal: Int,
        preferredResumePoint: NovelResumePoint?,
        showsNovelReaderProjectionNavigationOverlay: Bool = false,
        reportsError: Bool = true
    ) async -> Bool {
        if showsNovelReaderProjectionNavigationOverlay {
            await beginNovelReaderProjectionNavigation()
        }
        defer {
            if showsNovelReaderProjectionNavigationOverlay {
                setNovelReaderProjectionNavigation(false)
            }
        }
        do {
            guard let workflowState = try await readingWorkflow?.promotePrefetchedDocument(
                preferredSurfaceOrdinal: preferredSurfaceOrdinal,
                resumePoint: preferredResumePoint
            ) else { return false }
            syncFromWorkflowState(workflowState)
            await prefetchIfNeeded(for: selectedSurfaceIndex)
            return true
        } catch {
            if reportsError {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    private func persistSettings(
        novelReaderSettings: NovelReaderAppearanceSettings? = nil,
        applePencilPageTurnSettings: ApplePencilPageTurnSettings? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            var appSettings = await appContext.settingsStore.load()
            if let novelReaderSettings {
                appSettings.novelReader = novelReaderSettings
            }
            if let applePencilPageTurnSettings {
                appSettings.system.applePencilPageTurn = applePencilPageTurnSettings
            }
            do {
                try await appContext.settingsStore.save(appSettings)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func syncCacheState(_ snapshot: NovelOfflineCacheViewsSnapshot) {
        cacheOperationModule.syncCacheState(snapshot)
    }

    private func beginApplyingAppearanceSettings() -> UInt64 {
        appearanceSettingsApplicationSequence &+= 1
        isApplyingAppearanceSettings = true
        return appearanceSettingsApplicationSequence
    }

    private func finishApplyingAppearanceSettings(_ sequence: UInt64) {
        guard appearanceSettingsApplicationSequence == sequence else { return }
        isApplyingAppearanceSettings = false
    }
}

private extension NovelReaderAppearanceSettings {
    func isSurfaceOnlyAppearanceChange(to other: NovelReaderAppearanceSettings) -> Bool {
        var lhs = self
        var rhs = other
        lhs.backgroundStyle = .system
        rhs.backgroundStyle = .system
        lhs.pagedTurnStyle = .slide
        rhs.pagedTurnStyle = .slide
        return lhs == rhs &&
            (backgroundStyle != other.backgroundStyle || pagedTurnStyle != other.pagedTurnStyle)
    }
}
