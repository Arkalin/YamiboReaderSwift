import SwiftUI
import YamiboReaderCore

public struct ReaderProgressChapterTick: Equatable, Sendable {
    public var chapter: ReaderChapter
    public var position: Double
    public var isCurrent: Bool

    public init(chapter: ReaderChapter, position: Double, isCurrent: Bool) {
        self.chapter = chapter
        self.position = position
        self.isCurrent = isCurrent
    }
}

@MainActor
public final class ReaderContainerModel: ObservableObject {
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var pages: [ReaderRenderedPage] = []
    @Published public private(set) var chapters: [ReaderChapter] = []
    @Published public private(set) var cachedViews: Set<Int> = []
    @Published public private(set) var currentView = 1
    @Published public private(set) var maxView = 1
    @Published public private(set) var currentChapterTitle: String?
    @Published public private(set) var currentContentSource: ReaderContentSource = .allPostsPage
    @Published public private(set) var retainedChapterCount = 0
    @Published public private(set) var filteredChapterCandidateCount = 0
    @Published public var currentPageIndex = 0
    @Published public private(set) var currentPageIntraProgress = 0.0
    @Published public var settings = ReaderAppearanceSettings()
    @Published public var applePencilPageTurnSettings = ApplePencilPageTurnSettings()
    @Published public private(set) var sessionState = SessionState()
    @Published public private(set) var cacheOperationState = ReaderCacheOperationState()
    @Published public private(set) var chapterCommentsState: ReaderChapterCommentsState = .idle
    @Published public private(set) var isLoadingMoreChapterComments = false
    @Published public private(set) var chapterCommentsLoadMoreError: String?
    @Published public private(set) var chapterCommentsRefreshError: String?
    @Published public private(set) var pagedSpreads: [ReaderPagedSpread] = []

    public let context: ReaderLaunchContext

    private let appContext: YamiboAppContext
    private var repository: ReaderRepository?
    private var readingWorkflow: NovelReadingWorkflow?
    private var layout: ReaderContainerLayout = .zero
    private var currentDocument: ReaderPageDocument?
    private var prefetchedDocument: ReaderPageDocument?
    private var currentAuthorID: String?
    private var currentDocumentPageCount = 0
    private var prefetchedStartIndex: Int?
    private var usesPadPresentation = false
    private let progressSync: ProgressSyncModule
    private lazy var chapterCommentsModule = ReaderChapterCommentsModule(
        adapter: ReaderChapterCommentsModule.Adapter(
            loadInitial: { [weak self] target in
                guard let self else {
                    throw ReaderChapterCommentsUnavailableError()
                }
                let repository = await self.ensureReaderRepository()
                return try await repository.loadChapterComments(for: target)
            },
            loadMore: { [weak self] target, view in
                guard let self else {
                    throw ReaderChapterCommentsUnavailableError()
                }
                let repository = await self.ensureReaderRepository()
                return try await repository.loadMoreChapterComments(for: target, view: view)
            }
        ),
        onChange: { [weak self] module in
            self?.syncChapterComments(from: module)
        }
    )
    private let cacheOperationModule = ReaderCacheOperationModule()

    public init(context: ReaderLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
        progressSync = ProgressSyncModule(
            adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore)
        )
        cacheOperationModule.onChange = { [weak self] cachedViews, state in
            self?.cachedViews = cachedViews
            self?.cacheOperationState = state
        }
    }

    public var title: String {
        context.threadTitle.isEmpty ? L10n.string("reader.title") : context.threadTitle
    }

    public var isTwoPageSpreadActive: Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            layout.width > layout.height
    }

    public var progressText: String {
        let chapter = currentChapterTitle ?? ""
        if chapter.isEmpty {
            return L10n.string("reader.progress", displayedPageLabel, max(displayedPageCount, 1), displayedView, max(maxView, 1))
        }
        return L10n.string("reader.progress_with_chapter", displayedPageLabel, max(displayedPageCount, 1), displayedView, max(maxView, 1), chapter)
    }

    public func previewText(
        translationMode: ReaderTranslationMode,
        characterCount: Int,
        fallback: String
    ) -> String {
        let sourceText = rawPreviewTextForCurrentLocation().trimmingCharacters(in: .whitespacesAndNewlines)
        let previewSource = sourceText.isEmpty ? fallback : sourceText
        let transformed = ReaderTextTransformer.transform(previewSource, mode: translationMode)
        return String(transformed.prefix(max(characterCount, 0)))
    }

    public var renderedPageCount: Int {
        max(pages.count, 1)
    }

    public var currentRenderedPage: Int {
        min(max(currentPageIndex + 1, 1), renderedPageCount)
    }

    public var currentProgressFraction: Double {
        guard renderedPageCount > 1 else { return 0 }
        return Double(currentPageIndex) / Double(renderedPageCount - 1)
    }

    public var currentProgressPercent: Int {
        Int((currentProgressFraction * 100).rounded())
    }

    public var currentProgressPercentText: String {
        "\(currentProgressPercent)%"
    }

    public var progressChapterTicks: [ReaderProgressChapterTick] {
        guard renderedPageCount > 1, !chapters.isEmpty else { return [] }

        let currentIndex = currentChapterIndex
        let maxPageIndex = max(renderedPageCount - 1, 1)
        var seenStartIndexes = Set<Int>()

        return chapters.enumerated().compactMap { index, chapter in
            let clampedStartIndex = min(max(chapter.startIndex, 0), maxPageIndex)
            guard seenStartIndexes.insert(clampedStartIndex).inserted else { return nil }
            return ReaderProgressChapterTick(
                chapter: chapter,
                position: Double(clampedStartIndex) / Double(maxPageIndex),
                isCurrent: currentIndex == index
            )
        }
    }

    public func progressSliderLabelText(
        isEditing: Bool,
        sliderValue: Double,
        targetRenderedPageIndex: Int
    ) -> String {
        if settings.readingMode == .vertical {
            guard isEditing else { return currentProgressPercentText }
            let percent = Int(min(max(sliderValue, 0), 100).rounded())
            return "\(percent)%"
        }

        guard isEditing else {
            return "\(currentRenderedPage) / \(renderedPageCount)"
        }
        let page = min(max(targetRenderedPageIndex + 1, 1), renderedPageCount)
        return "\(page) / \(renderedPageCount)"
    }

    public var currentChapterCommentTarget: ReaderChapterCommentTarget? {
        currentRenderedPageMetadata?.chapterCommentTarget
    }

    public var currentWebViewText: String {
        L10n.string("reader.web_view_progress", displayedView, max(maxView, 1))
    }

    public var directoryWebTitle: String {
        L10n.string("reader.web_view_chapters", currentWebViewText)
    }

    public var pagedSelectionIndex: Int {
        guard isTwoPageSpreadActive else { return currentPageIndex }
        return spreadIndex(forPageIndex: currentPageIndex)
    }

    public func updatePagedPresentationEnvironment(isPad: Bool) {
        guard usesPadPresentation != isPad else { return }
        usesPadPresentation = isPad
        guard settings.readingMode == .paged else { return }
        if let state = readingWorkflow?.updatePagedPresentationEnvironment(isPad: isPad) {
            syncFromWorkflowState(state)
        }
    }

    public func updatePagedSelection(_ selectionIndex: Int) {
        let targetPageIndex = isTwoPageSpreadActive
            ? leftPageIndex(forSpreadIndex: selectionIndex)
            : selectionIndex
        updateCurrentPage(targetPageIndex)
    }

    public func chapterTitle(forRenderedPageIndex pageIndex: Int) -> String? {
        guard !pages.isEmpty else { return nil }
        let clampedIndex = min(max(pageIndex, 0), max(pages.count - 1, 0))
        return pages[clampedIndex].chapterTitle ?? chapters.last(where: { $0.startIndex <= clampedIndex })?.title
    }

    public func progressChapterTickStartIndex(forRenderedPageIndex pageIndex: Int) -> Int? {
        guard !chapters.isEmpty else { return nil }
        let clampedIndex = min(max(pageIndex, 0), max(renderedPageCount - 1, 0))
        return chapters
            .map { min(max($0.startIndex, 0), max(renderedPageCount - 1, 0)) }
            .first { $0 == clampedIndex }
    }

    public func targetRenderedPageIndex(forProgressValue value: Double) -> Int {
        guard !pages.isEmpty else { return 0 }

        switch settings.readingMode {
        case .paged:
            let target = min(
                max(Int(value.rounded()), 0),
                max(pages.count - 1, 0)
            )
            return normalizedPagedPageIndex(target)
        case .vertical:
            guard pages.count > 1 else { return 0 }
            let clampedPercent = min(max(value, 0), 100)
            return min(
                max(Int((clampedPercent / 100) * Double(pages.count - 1)), 0),
                max(pages.count - 1, 0)
            )
        }
    }

    public var cacheScopeTitle: String {
        switch currentContentSource {
        case .authorFilteredPage:
            return L10n.string("reader.cache_scope.author")
        case .fallbackUnfilteredPage, .allPostsPage:
            return L10n.string("reader.cache_scope.all_posts")
        }
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

    public var currentChapterIndex: Int? {
        chapters.lastIndex(where: { $0.startIndex <= currentPageIndex })
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
        currentContentSource == .fallbackUnfilteredPage ? L10n.string("reader.source.all_posts") : nil
    }

    public var chapterSummaryText: String {
        L10n.string("reader.chapter_summary", retainedChapterCount, filteredChapterCandidateCount)
    }

    public var forumURL: URL {
        YamiboRoute.thread(url: context.threadURL, page: displayedView, authorID: currentAuthorID ?? context.authorID).url
    }

    public func prepare(layout: ReaderContainerLayout) async {
        self.layout = layout
        if repository == nil {
            repository = await appContext.makeReaderRepository()
            let appSettings = await appContext.settingsStore.load()
            settings = appSettings.reader
            applePencilPageTurnSettings = appSettings.applePencilPageTurn
            sessionState = await appContext.sessionStore.load()
            if let repository {
                readingWorkflow = NovelReadingWorkflow(
                    context: context,
                    settings: settings,
                    layout: layout,
                    repository: repository,
                    usesPadPresentation: usesPadPresentation
                )
            }
        }
        if pages.isEmpty {
            let favorite = await appContext.favoriteStore.favorite(for: context.threadURL)
            await startReadingWorkflow(
                resumePoint: favorite?.novelResumePoint,
                favoriteAuthorID: favorite?.authorID
            )
        } else {
            if let state = readingWorkflow?.updateLayout(layout) {
                syncFromWorkflowState(state)
            }
            await refreshCachedState()
        }
    }

    public func updateLayout(_ layout: ReaderContainerLayout) {
        guard self.layout != layout else { return }
        self.layout = layout
        if let state = readingWorkflow?.updateLayout(layout) {
            syncFromWorkflowState(state)
        }
    }

    public func loadCurrent(forceRefresh: Bool) async {
        await load(
            view: displayedView,
            preferredPage: displayedPageIndex,
            preferredResumePoint: captureCurrentResumePoint(),
            forceRefresh: forceRefresh
        )
    }

    public func loadAdjacent(delta: Int) async {
        let target = max(1, min(maxView, displayedView + delta))
        guard target != displayedView else { return }

        if delta > 0,
           let prefetchedDocument,
           prefetchedDocument.view == target {
            await promotePrefetchedDocument(startingAt: 0)
            return
        }

        await load(view: target, preferredPage: 0, preferredResumePoint: nil, forceRefresh: false)
    }

    public func updateReadingMode(_ mode: ReaderReadingMode) {
        var updatedSettings = settings
        updatedSettings.readingMode = mode
        applySettings(updatedSettings)
    }

    public func updateImageLoading(_ value: Bool) {
        var updatedSettings = settings
        updatedSettings.loadsInlineImages = value
        applySettings(updatedSettings)
    }

    public func updateFontScale(_ value: Double) {
        var updatedSettings = settings
        updatedSettings.fontScale = value
        applySettings(updatedSettings)
    }

    public func updateFontFamily(_ value: ReaderFontFamily) {
        var updatedSettings = settings
        updatedSettings.fontFamily = value
        applySettings(updatedSettings)
    }

    public func updateLineHeightScale(_ value: Double) {
        var updatedSettings = settings
        updatedSettings.lineHeightScale = value
        applySettings(updatedSettings)
    }

    public func updateCharacterSpacingScale(_ value: Double) {
        var updatedSettings = settings
        updatedSettings.characterSpacingScale = value
        applySettings(updatedSettings)
    }

    public func updateHorizontalPadding(_ value: Double) {
        var updatedSettings = settings
        updatedSettings.horizontalPadding = value
        applySettings(updatedSettings)
    }

    public func updateBackgroundStyle(_ value: ReaderBackgroundStyle) {
        var updatedSettings = settings
        updatedSettings.backgroundStyle = value
        applySettings(updatedSettings)
    }

    public func updateTranslationMode(_ value: ReaderTranslationMode) {
        var updatedSettings = settings
        updatedSettings.translationMode = value
        applySettings(updatedSettings)
    }

    public func applySettings(_ newSettings: ReaderAppearanceSettings) {
        applySettings(newSettings, applePencilPageTurnSettings: applePencilPageTurnSettings)
    }

    public func applySettings(
        _ newSettings: ReaderAppearanceSettings,
        applePencilPageTurnSettings newApplePencilPageTurnSettings: ApplePencilPageTurnSettings
    ) {
        let oldSettings = settings
        let shouldRepaginate = oldSettings != newSettings
        settings = newSettings
        applePencilPageTurnSettings = newApplePencilPageTurnSettings
        persistSettings(
            readerSettings: newSettings,
            applePencilPageTurnSettings: newApplePencilPageTurnSettings
        )
        guard shouldRepaginate else { return }
        if let state = readingWorkflow?.updateSettings(newSettings) {
            syncFromWorkflowState(state)
        }
    }

    public func applyApplePencilPageTurnSettings(_ newSettings: ApplePencilPageTurnSettings) {
        applePencilPageTurnSettings = newSettings
        persistSettings(applePencilPageTurnSettings: newSettings)
    }

    public func saveProgress() async {
        await flushProgress()
    }

    public func updateCurrentPage(_ pageIndex: Int) {
        if let state = readingWorkflow?.jumpToRenderedPage(pageIndex) {
            syncFromWorkflowState(state)
        }
        scheduleProgressSync()

        Task {
            await prefetchIfNeeded(for: currentPageIndex)
        }

        promoteIfNeededAfterLocationUpdate()
    }

    public func updateVerticalViewportPosition(pageIndex: Int, intraPageProgress: Double) {
        if let state = readingWorkflow?.updateVerticalViewportPosition(
            pageIndex: pageIndex,
            intraPageProgress: intraPageProgress
        ) {
            syncFromWorkflowState(state)
        }
        scheduleProgressSync()

        Task {
            await prefetchIfNeeded(for: currentPageIndex)
        }

        promoteIfNeededAfterLocationUpdate()
    }

    public func jumpToChapter(_ chapter: ReaderChapter) {
        jumpToRenderedPage(chapter.startIndex)
    }

    public func jumpToRenderedPage(_ pageIndex: Int) {
        updateCurrentPage(pageIndex)
    }

    public func jumpRelativePage(_ delta: Int) async {
        guard let result = readingWorkflow?.jumpRelativePage(delta) else {
            scheduleProgressSync()
            Task {
                await prefetchIfNeeded(for: currentPageIndex)
            }
            return
        }

        syncFromWorkflowState(result.state)
        switch result.request {
        case nil:
            scheduleProgressSync()
            Task {
                await prefetchIfNeeded(for: currentPageIndex)
            }
        case let .loadView(view, preferredPage, resumePoint):
            await load(view: view, preferredPage: preferredPage, preferredResumePoint: resumePoint, forceRefresh: false)
        case let .promotePrefetched(preferredPage, resumePoint):
            await promotePrefetchedDocument(startingAt: preferredPage, preferredResumePoint: resumePoint)
        }
    }

    public func jumpToAdjacentChapter(_ delta: Int) {
        guard let currentChapterIndex else { return }
        let targetIndex = currentChapterIndex + delta
        guard chapters.indices.contains(targetIndex) else { return }
        jumpToRenderedPage(chapters[targetIndex].startIndex)
    }

    public func jumpToWebView(_ view: Int) async {
        let clampedView = max(1, min(maxView, view))

        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           clampedView == displayedView,
           currentPageIndex >= startIndex {
            await promotePrefetchedDocument(startingAt: 0)
            return
        }

        if clampedView == currentView {
            jumpToRenderedPage(0)
            return
        }

        await load(view: clampedView, preferredPage: 0, preferredResumePoint: nil, forceRefresh: false)
    }

    public func refreshCachedState() async {
        let context = cacheContext(forView: displayedView)
        let views = await repository?.cachedViews(
            for: self.context.threadURL,
            authorID: context.authorID,
            contentSource: context.contentSource
        ) ?? []
        syncCachedViews(views)
    }

    public func cacheSelectionState(for selectedViews: Set<Int>) -> ReaderCacheSelectionState {
        cacheOperationModule.selectionState(for: selectedViews, snapshot: cacheOperationSnapshot)
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
            let context = cacheContext(forView: displayedView)
            try await repository?.deleteCachedViews(
                [displayedView],
                for: self.context.threadURL,
                authorID: context.authorID,
                contentSource: context.contentSource
            )
            await refreshCachedState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshCurrentCache() async {
        do {
            let context = cacheContext(forView: displayedView)
            try await repository?.refreshCachedViews(
                [displayedView],
                for: self.context.threadURL,
                authorID: context.authorID,
                contentSource: context.contentSource
            )
            await refreshCachedState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load(
        view: Int,
        preferredPage: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async {
        guard let workflow = await ensureReadingWorkflow() else { return }
        isLoading = true
        errorMessage = nil
        do {
            let state = try await workflow.loadView(
                view,
                preferredPage: preferredPage,
                preferredResumePoint: preferredResumePoint,
                forceRefresh: forceRefresh
            )
            syncFromWorkflowState(state)
            isLoading = false

            Task {
                await prefetchIfNeeded(for: currentPageIndex)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func startReadingWorkflow(resumePoint: ReaderResumePoint?, favoriteAuthorID: String?) async {
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

            Task {
                await prefetchIfNeeded(for: currentPageIndex)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func ensureReaderRepository() async -> ReaderRepository {
        if repository == nil {
            repository = await appContext.makeReaderRepository()
        }
        guard let repository else {
            preconditionFailure("Reader repository should be initialized")
        }
        return repository
    }

    private func ensureReadingWorkflow() async -> NovelReadingWorkflow? {
        let repository = await ensureReaderRepository()
        if readingWorkflow == nil {
            readingWorkflow = NovelReadingWorkflow(
                context: context,
                settings: settings,
                layout: layout,
                repository: repository,
                usesPadPresentation: usesPadPresentation
            )
        }
        readingWorkflow?.updateSettings(settings)
        readingWorkflow?.updateLayout(layout)
        return readingWorkflow
    }

    private func syncChapterComments(from module: ReaderChapterCommentsModule) {
        chapterCommentsState = module.state
        isLoadingMoreChapterComments = module.isLoadingMore
        chapterCommentsLoadMoreError = module.loadMoreError
        chapterCommentsRefreshError = module.refreshError
    }

    private func syncFromWorkflowState(_ state: NovelReadingWorkflowState) {
        currentDocument = state.currentDocument
        prefetchedDocument = state.prefetchedDocument
        currentAuthorID = state.currentAuthorID
        syncFromWorkflowSnapshot(state.snapshot)
        syncCachedViews(state.cachedViews)
    }

    private func syncFromWorkflowSnapshot(_ snapshot: NovelReadingSnapshot) {
        pages = snapshot.pages
        chapters = snapshot.chapters
        currentPageIndex = snapshot.currentPageIndex
        currentPageIntraProgress = snapshot.currentPageIntraProgress
        currentView = snapshot.currentView
        maxView = snapshot.maxView
        currentChapterTitle = snapshot.currentChapterTitle
        currentContentSource = snapshot.currentContentSource
        retainedChapterCount = snapshot.retainedChapterCount
        filteredChapterCandidateCount = snapshot.filteredChapterCandidateCount
        pagedSpreads = snapshot.pagedSpreads
        prefetchedStartIndex = snapshot.prefetchedStartIndex
        currentAuthorID = snapshot.currentAuthorID ?? currentAuthorID
        currentDocumentPageCount = snapshot.pages.filter { $0.documentView == snapshot.currentView }.count
    }

    private func prefetchIfNeeded(for pageIndex: Int) async {
        guard let workflow = await ensureReadingWorkflow(),
              let state = await workflow.prefetchIfNeeded(forPageIndex: pageIndex) else { return }
        syncFromWorkflowState(state)
    }

    private func chapterTitle(for pageIndex: Int) -> String? {
        guard pages.indices.contains(pageIndex) else {
            return chapters.last(where: { $0.startIndex <= pageIndex })?.title
        }
        return pages[pageIndex].chapterTitle ?? chapters.last(where: { $0.startIndex <= pageIndex })?.title
    }

    private var displayedPageLabel: String {
        let leftPageNumber = displayedPageIndex + 1
        guard isTwoPageSpreadActive,
              let spread = pagedSpreads.first(where: { $0.leftPageIndex == currentPageIndex }),
              let rightPageIndex = spread.rightPageIndex,
              pages.indices.contains(rightPageIndex),
              pages[rightPageIndex].documentView == displayedView else {
            return "\(leftPageNumber)"
        }
        let rightPageNumber = displayedPageIndex + 2
        return "\(leftPageNumber)-\(min(rightPageNumber, displayedPageCount))"
    }

    private var displayedView: Int {
        currentRenderedPageMetadata?.documentView ?? currentView
    }

    private var displayedPageIndex: Int {
        let view = displayedView
        guard let firstIndex = pages.firstIndex(where: { $0.documentView == view }) else {
            return currentPageIndex
        }
        return max(currentPageIndex - firstIndex, 0)
    }

    private var displayedPageCount: Int {
        let count = pages.filter { $0.documentView == displayedView }.count
        return max(count, 1)
    }

    private var displayedDocument: ReaderPageDocument? {
        if displayedView == prefetchedDocument?.view,
           let prefetchedDocument {
            return prefetchedDocument
        }
        return currentDocument
    }

    private func rawPreviewTextForCurrentLocation() -> String {
        guard let document = document(for: currentRenderedPageMetadata?.documentView) ?? currentDocument else {
            return ""
        }
        guard !document.segments.isEmpty else { return "" }

        let currentRange = currentRenderedPageMetadata.flatMap {
            textPosition(for: currentPageIntraProgress, in: $0)?.range
        }
        let startSegmentIndex = min(
            max(currentRange?.segmentIndex ?? currentRenderedPageMetadata?.segmentIndex ?? 0, 0),
            max(document.segments.count - 1, 0)
        )
        let startOffset = currentRange?.startOffset ?? currentRenderedPageMetadata?.segmentStartOffset ?? 0

        let fragments = document.segments[startSegmentIndex...].enumerated().compactMap { offset, segment -> String? in
            guard case let .text(text, _) = segment else { return nil }

            let previewText = offset == 0
                ? text.droppingReaderPreviewCharacters(startOffset)
                : text
            let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return fragments.joined(separator: "\n\n")
    }

    private func document(for view: Int?) -> ReaderPageDocument? {
        if view == prefetchedDocument?.view {
            return prefetchedDocument
        }
        if view == currentDocument?.view {
            return currentDocument
        }
        return nil
    }

    private var currentRenderedPageMetadata: ReaderRenderedPage? {
        let normalizedIndex = normalizedPagedPageIndex(currentPageIndex)
        guard pages.indices.contains(normalizedIndex) else { return nil }
        return pages[normalizedIndex]
    }

    private func currentProgressSnapshot() -> NovelReadingPosition {
        let resumePoint = captureCurrentResumePoint()
        return NovelReadingPosition(
            threadURL: context.threadURL,
            view: resumePoint?.view ?? displayedView,
            page: displayedPageIndex,
            chapterTitle: resumePoint?.chapterTitle ?? currentChapterTitle,
            authorID: resumePoint?.authorID ?? currentAuthorID ?? context.authorID,
            resumePoint: resumePoint
        )
    }

    private func captureCurrentResumePoint() -> ReaderResumePoint? {
        if let resumePoint = readingWorkflow?.captureNovelReadingPosition() {
            return resumePoint
        }
        guard let page = currentRenderedPageMetadata,
              let chapterOrdinal = page.chapterOrdinal,
              let position = textPosition(for: currentPageIntraProgress, in: page) else {
            return nil
        }

        let range = position.range
        let segmentLength = range.length
        let offsetWithinSegment = segmentLength > 0
            ? Int((Double(segmentLength) * position.progressInRange).rounded(.towardZero))
            : 0
        let resumePoint = ReaderResumePoint(
            view: page.documentView,
            chapterOrdinal: chapterOrdinal,
            chapterTitle: page.chapterTitle,
            segmentIndex: range.segmentIndex,
            segmentOffset: range.startOffset + min(offsetWithinSegment, segmentLength),
            segmentProgress: currentPageIntraProgress,
            authorID: currentAuthorID ?? context.authorID,
            readingModeHint: settings.readingMode
        )
        return resumePoint
    }

    private func promoteIfNeededAfterLocationUpdate() {
        if settings.readingMode == .vertical,
           let currentPage = currentRenderedPageMetadata,
           currentPage.documentView != currentView,
           prefetchedDocument?.view == currentPage.documentView {
            let resumePoint = captureCurrentResumePoint()
            Task {
                await promotePrefetchedDocument(startingAt: 0, preferredResumePoint: resumePoint)
            }
            return
        }

        if settings.readingMode == .paged,
           let prefetchedDocument,
           currentPageIndex >= max(currentDocumentPageCount - 1, 0),
           prefetchedDocument.view == currentView + 1 {
            Task {
                await promotePrefetchedDocument(startingAt: 0, preferredResumePoint: nil)
            }
        }
    }

    private func textPosition(for intraPageProgress: Double, in page: ReaderRenderedPage) -> ReaderPageTextPosition? {
        guard !page.textRanges.isEmpty else { return nil }
        guard page.textRanges.count > 1 else {
            return page.textRanges.first.map {
                ReaderPageTextPosition(range: $0, progressInRange: min(max(intraPageProgress, 0), 1))
            }
        }

        let totalLength = page.textRanges.reduce(0) { $0 + max($1.length, 1) }
        let targetOffset = Int((Double(totalLength) * min(max(intraPageProgress, 0), 1)).rounded(.towardZero))
        var runningLength = 0

        for range in page.textRanges {
            let length = max(range.length, 1)
            if targetOffset < runningLength + length {
                let progressInRange = Double(targetOffset - runningLength) / Double(length)
                return ReaderPageTextPosition(
                    range: range,
                    progressInRange: min(max(progressInRange, 0), 1)
                )
            }
            runningLength += length
        }

        return page.textRanges.last.map {
            ReaderPageTextPosition(range: $0, progressInRange: 1)
        }
    }

    private func scheduleProgressSync() {
        let snapshot = currentProgressSnapshot()
        Task { [progressSync] in
            await progressSync.queue(.novel(snapshot))
        }
    }

    private func flushProgress() async {
        let snapshot = currentProgressSnapshot()
        try? await progressSync.flush(.novel(snapshot))
    }

    private func spreadIndex(forPageIndex pageIndex: Int) -> Int {
        guard isTwoPageSpreadActive else {
            return max(0, min(pageIndex, max(pages.count - 1, 0)))
        }

        let normalizedIndex = max(0, min(pageIndex, max(pages.count - 1, 0)))
        return pagedSpreads.first(where: { spread in
            spread.leftPageIndex == normalizedIndex || spread.rightPageIndex == normalizedIndex
        })?.index ?? 0
    }

    private func leftPageIndex(forSpreadIndex spreadIndex: Int) -> Int {
        guard let spread = pagedSpreads.first(where: { $0.index == spreadIndex }) ?? pagedSpreads.last else {
            return 0
        }
        return spread.leftPageIndex
    }

    private func normalizedPagedPageIndex(_ pageIndex: Int) -> Int {
        let clampedIndex = max(0, min(pageIndex, max(pages.count - 1, 0)))
        guard isTwoPageSpreadActive else { return clampedIndex }
        return leftPageIndex(forSpreadIndex: spreadIndex(forPageIndex: clampedIndex))
    }

    private func cacheContext(forView view: Int) -> (authorID: String?, contentSource: ReaderContentSource?) {
        if currentDocument?.view == view {
            return cacheContext(for: currentDocument)
        }

        if prefetchedDocument?.view == view {
            return cacheContext(for: prefetchedDocument)
        }

        let displayedAuthorID = displayedDocument?.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        let displayedContentSource = displayedDocument?.contentSource ?? currentContentSource
        return (
            displayedAuthorID,
            displayedContentSource == .allPostsPage
                ? inferredContentSource(for: displayedAuthorID)
                : displayedContentSource
        )
    }

    private func cacheContext(for document: ReaderPageDocument?) -> (authorID: String?, contentSource: ReaderContentSource?) {
        guard let document else {
            let authorID = currentAuthorID ?? context.authorID
            return (authorID, inferredContentSource(for: authorID))
        }

        switch document.contentSource {
        case .authorFilteredPage:
            return (
                document.resolvedAuthorID ?? currentAuthorID ?? context.authorID,
                .authorFilteredPage
            )
        case .fallbackUnfilteredPage:
            return (nil, .fallbackUnfilteredPage)
        case .allPostsPage:
            let authorID = document.resolvedAuthorID ?? currentAuthorID ?? context.authorID
            return (authorID, inferredContentSource(for: authorID))
        }
    }

    private func inferredContentSource(for authorID: String?) -> ReaderContentSource {
        let normalizedAuthorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedAuthorID.isEmpty ? .fallbackUnfilteredPage : .authorFilteredPage
    }

    private var cacheOperationSnapshot: ReaderCacheOperationSnapshot {
        let context = cacheContext(forView: displayedView)
        return ReaderCacheOperationSnapshot(
            cacheableViews: Set(allCacheableViews),
            cachedViews: cachedViews,
            context: ReaderCacheOperationContext(
                threadURL: self.context.threadURL,
                authorID: context.authorID,
                contentSource: context.contentSource
            )
        )
    }

    private var cacheOperationRepository: ReaderCacheOperationRepository? {
        repository.map { ReaderRepositoryCacheOperationAdapter(repository: $0) }
    }

    private func cacheOperationSummary(
        mode: ReaderCacheOperationMode,
        result: ReaderCacheBatchResult
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

    private func promotePrefetchedDocument(startingAt preferredPage: Int) async {
        await promotePrefetchedDocument(startingAt: preferredPage, preferredResumePoint: nil)
    }

    private func promotePrefetchedDocument(startingAt preferredPage: Int, preferredResumePoint: ReaderResumePoint?) async {
        let workflowState = await readingWorkflow?.promotePrefetchedDocument(
            preferredPage: preferredPage,
            resumePoint: preferredResumePoint
        )
        guard let workflowState else { return }
        syncFromWorkflowState(workflowState)
        await prefetchIfNeeded(for: currentPageIndex)
    }

    private func persistSettings(
        readerSettings: ReaderAppearanceSettings? = nil,
        applePencilPageTurnSettings: ApplePencilPageTurnSettings? = nil
    ) {
        Task {
            var appSettings = await appContext.settingsStore.load()
            if let readerSettings {
                appSettings.reader = readerSettings
            }
            if let applePencilPageTurnSettings {
                appSettings.applePencilPageTurn = applePencilPageTurnSettings
            }
            try? await appContext.settingsStore.save(appSettings)
        }
    }

    private func syncCachedViews(_ views: Set<Int>) {
        cacheOperationModule.syncCachedViews(views)
    }
}

private struct ReaderPageTextPosition {
    let range: ReaderRenderedTextRange
    let progressInRange: Double
}

private extension String {
    func droppingReaderPreviewCharacters(_ count: Int) -> String {
        guard count > 0 else { return self }
        guard count < self.count else { return "" }

        let start = index(startIndex, offsetBy: count)
        return String(self[start...])
    }
}
