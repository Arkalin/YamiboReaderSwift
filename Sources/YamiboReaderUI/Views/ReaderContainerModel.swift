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

private struct ReaderProgressScrubData: Equatable, Sendable {
    var readingMode: ReaderReadingMode
    var surfaceCount: Int
    var currentProgressPercent: Int
    var visibleSurfaceIndexes: [Int]
    var fallbackVisibleSurfaceIndex: Int
    var chapterTitlesBySurfaceIndex: [Int: String]
    var chapterTickStartIndexes: Set<Int>
    var isTwoPageSpreadActive: Bool

    func targetSurfaceIndex(for value: Double) -> Int {
        guard surfaceCount > 1 else { return 0 }
        switch readingMode {
        case .paged:
            let target = min(max(Int(value.rounded()), 0), max(surfaceCount - 1, 0))
            guard isTwoPageSpreadActive else { return target }
            return max(0, min(target - (target % 2), max(surfaceCount - 1, 0)))
        case .vertical:
            guard !visibleSurfaceIndexes.isEmpty,
                  visibleSurfaceIndexes.count > 1 else {
                return fallbackVisibleSurfaceIndex
            }
            let clampedPercent = min(max(value, 0), 100)
            let localSurfaceIndex = min(
                max(Int((clampedPercent / 100) * Double(visibleSurfaceIndexes.count - 1)), 0),
                max(visibleSurfaceIndexes.count - 1, 0)
            )
            return visibleSurfaceIndexes[localSurfaceIndex]
        }
    }

    func chapterTitle(for surfaceIndex: Int) -> String? {
        let clampedIndex = min(max(surfaceIndex, 0), max(surfaceCount - 1, 0))
        return chapterTitlesBySurfaceIndex[clampedIndex]
    }

    func chapterTickStartIndex(for surfaceIndex: Int) -> Int? {
        let clampedIndex = min(max(surfaceIndex, 0), max(surfaceCount - 1, 0))
        return chapterTickStartIndexes.contains(clampedIndex) ? clampedIndex : nil
    }
}

public struct ReaderChromeProgressSnapshot: Equatable, Sendable {
    public var readingMode: ReaderReadingMode
    public var visibleView: Int
    public var surfaceCount: Int
    public var currentSurfaceNumber: Int
    public var currentChapterTitle: String?
    public var progressText: String
    public var currentProgressFraction: Double
    public var currentProgressPercent: Int
    public var currentProgressPercentText: String
    public var progressChapterTicks: [ReaderProgressChapterTick]
    private var scrubData: ReaderProgressScrubData

    public static var empty: ReaderChromeProgressSnapshot {
        ReaderChromeProgressSnapshot(
            readingMode: .paged,
            visibleView: 1,
            surfaceCount: 1,
            currentSurfaceNumber: 1,
            currentChapterTitle: nil,
            progressText: "",
            currentProgressFraction: 0,
            currentProgressPercent: 0,
            currentProgressPercentText: "0%",
            progressChapterTicks: [],
            scrubData: ReaderProgressScrubData(
                readingMode: .paged,
                surfaceCount: 1,
                currentProgressPercent: 0,
                visibleSurfaceIndexes: [],
                fallbackVisibleSurfaceIndex: 0,
                chapterTitlesBySurfaceIndex: [:],
                chapterTickStartIndexes: [],
                isTwoPageSpreadActive: false
            )
        )
    }

    public init(presentation: NovelReaderPresentation) {
        let projection = presentation.progressProjection
        let chapter = presentation.readingState.currentChapterTitle ?? ""
        let progressText = if chapter.isEmpty {
            L10n.string(
                "reader.progress",
                projection.displayedPageLabel,
                max(projection.displayedPageCount, 1),
                projection.displayedView,
                max(presentation.readingState.maxView, 1)
            )
        } else {
            L10n.string(
                "reader.progress_with_chapter",
                projection.displayedPageLabel,
                max(projection.displayedPageCount, 1),
                projection.displayedView,
                max(presentation.readingState.maxView, 1),
                chapter
            )
        }
        let maxIndex = max(projection.surfaceCount - 1, 0)
        let currentChapterIndex = presentation.chapters.lastIndex {
            $0.startIndex <= projection.selectedSurfaceIndex
        }
        let progressChapterTicks: [ReaderProgressChapterTick] = {
            guard projection.surfaceCount > 1, !presentation.chapters.isEmpty else { return [] }
            var seenStartIndexes = Set<Int>()
            return presentation.chapters.enumerated().compactMap { index, chapter -> ReaderProgressChapterTick? in
                let clampedStartIndex = min(max(chapter.startIndex, 0), max(maxIndex, 1))
                guard seenStartIndexes.insert(clampedStartIndex).inserted else { return nil }
                return ReaderProgressChapterTick(
                    chapter: chapter,
                    position: Double(clampedStartIndex) / Double(max(maxIndex, 1)),
                    isCurrent: currentChapterIndex == index
                )
            }
        }()
        let chapterTitlesBySurfaceIndex = Self.chapterTitlesBySurfaceIndex(
            surfaces: presentation.surfaces,
            chapters: presentation.chapters,
            maxIndex: maxIndex
        )
        let tickStartIndexes = Set(presentation.chapters.map { min(max($0.startIndex, 0), maxIndex) })

        self.init(
            readingMode: projection.readingMode,
            visibleView: projection.displayedView,
            surfaceCount: projection.surfaceCount,
            currentSurfaceNumber: projection.currentSurfaceNumber,
            currentChapterTitle: presentation.readingState.currentChapterTitle,
            progressText: progressText,
            currentProgressFraction: projection.currentProgressFraction,
            currentProgressPercent: projection.currentProgressPercent,
            currentProgressPercentText: projection.currentProgressPercentText,
            progressChapterTicks: progressChapterTicks,
            scrubData: ReaderProgressScrubData(
                readingMode: projection.readingMode,
                surfaceCount: projection.surfaceCount,
                currentProgressPercent: projection.currentProgressPercent,
                visibleSurfaceIndexes: projection.visibleSurfaceIndexes,
                fallbackVisibleSurfaceIndex: projection.fallbackVisibleSurfaceIndex,
                chapterTitlesBySurfaceIndex: chapterTitlesBySurfaceIndex,
                chapterTickStartIndexes: tickStartIndexes,
                isTwoPageSpreadActive: projection.usesTwoPageSpread
            )
        )
    }

    private init(
        readingMode: ReaderReadingMode,
        visibleView: Int,
        surfaceCount: Int,
        currentSurfaceNumber: Int,
        currentChapterTitle: String?,
        progressText: String,
        currentProgressFraction: Double,
        currentProgressPercent: Int,
        currentProgressPercentText: String,
        progressChapterTicks: [ReaderProgressChapterTick],
        scrubData: ReaderProgressScrubData
    ) {
        self.readingMode = readingMode
        self.visibleView = max(visibleView, 1)
        self.surfaceCount = max(surfaceCount, 1)
        self.currentSurfaceNumber = min(max(currentSurfaceNumber, 1), self.surfaceCount)
        self.currentChapterTitle = currentChapterTitle
        self.progressText = progressText
        self.currentProgressFraction = min(max(currentProgressFraction, 0), 1)
        self.currentProgressPercent = min(max(currentProgressPercent, 0), 100)
        self.currentProgressPercentText = currentProgressPercentText
        self.progressChapterTicks = progressChapterTicks
        self.scrubData = scrubData
    }

    public func progressSliderLabelText(
        isEditing: Bool,
        sliderValue: Double,
        targetSurfaceIndex: Int
    ) -> String {
        if readingMode == .vertical {
            guard isEditing else { return currentProgressPercentText }
            let percent = Int(min(max(sliderValue, 0), 100).rounded())
            return "\(percent)%"
        }

        guard isEditing else {
            return "\(currentSurfaceNumber) / \(surfaceCount)"
        }
        let page = min(max(targetSurfaceIndex + 1, 1), surfaceCount)
        return "\(page) / \(surfaceCount)"
    }

    public func targetSurfaceIndex(forProgressValue value: Double) -> Int {
        scrubData.targetSurfaceIndex(for: value)
    }

    public func chapterTitle(forSurfaceIndex surfaceIndex: Int) -> String? {
        scrubData.chapterTitle(for: surfaceIndex)
    }

    public func progressChapterTickStartIndex(forSurfaceIndex surfaceIndex: Int) -> Int? {
        scrubData.chapterTickStartIndex(for: surfaceIndex)
    }

    public var progressScrubContext: ReaderProgressScrubContext {
        ReaderProgressScrubContext(
            readingMode: scrubData.readingMode,
            surfaceCount: scrubData.surfaceCount,
            currentProgressPercent: scrubData.currentProgressPercent,
            targetSurfaceIndex: { value in
                scrubData.targetSurfaceIndex(for: value)
            },
            chapterTitle: { surfaceIndex in
                scrubData.chapterTitle(for: surfaceIndex)
            },
            chapterTickStartIndex: { surfaceIndex in
                scrubData.chapterTickStartIndex(for: surfaceIndex)
            }
        )
    }

    private static func chapterTitlesBySurfaceIndex(
        surfaces: [NovelReaderSurface],
        chapters: [ReaderChapter],
        maxIndex: Int
    ) -> [Int: String] {
        guard maxIndex >= 0, !surfaces.isEmpty else { return [:] }
        var result: [Int: String] = [:]
        var chapterIndex = 0
        let sortedChapters = chapters.sorted { $0.startIndex < $1.startIndex }
        for index in surfaces.indices {
            while chapterIndex + 1 < sortedChapters.count,
                  sortedChapters[chapterIndex + 1].startIndex <= index {
                chapterIndex += 1
            }
            if let title = surfaces[index].chapterTitle {
                result[index] = title
            } else if sortedChapters.indices.contains(chapterIndex),
                      sortedChapters[chapterIndex].startIndex <= index {
                result[index] = sortedChapters[chapterIndex].title
            }
        }
        return result
    }
}

@MainActor
public final class ReaderContainerModel: ObservableObject {
    @Published public private(set) var isLoading = false
    @Published public private(set) var isApplyingAppearanceSettings = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var cachedViews: Set<Int> = []
    @Published private var bootstrapSettings = ReaderAppearanceSettings()
    @Published public var applePencilPageTurnSettings = ApplePencilPageTurnSettings()
    @Published public private(set) var sessionState = SessionState()
    @Published public private(set) var cacheOperationState = ReaderCacheOperationState()
    @Published public private(set) var chapterCommentsState: ReaderChapterCommentsState = .idle
    @Published public private(set) var isLoadingMoreChapterComments = false
    @Published public private(set) var chapterCommentsLoadMoreError: String?
    @Published public private(set) var chapterCommentsRefreshError: String?
    @Published public private(set) var chapterDirectoryView: Int?
    @Published public private(set) var chapterDirectoryChapters: [ReaderChapter] = []
    @Published public private(set) var chapterDirectoryPageCount = 0
    @Published public private(set) var isLoadingChapterDirectory = false
    @Published public private(set) var chapterDirectoryError: String?
    @Published public private(set) var readerPresentation: NovelReaderPresentation?
    public private(set) var chromeProgressSnapshot = ReaderChromeProgressSnapshot.empty

    public let context: ReaderLaunchContext

    private let appContext: YamiboAppContext
    private var repository: ReaderRepository?
    private var readingWorkflow: NovelReadingWorkflow?
    private var appearanceSettingsApplicationSequence: UInt64 = 0
    private var layout: ReaderContainerLayout = .zero
    private var usesPadPresentation = false
    private var chapterDirectoryAnchors: [Int: NovelChapterAnchor] = [:]
    private let runtimeAdapter: (any NovelTextLayoutRuntimeAdapter)?
    package var runtimeUpdatePreparation: NovelReadingWorkflowRuntimeUpdatePreparation = { $0 }
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

    public init(
        context: ReaderLaunchContext,
        appContext: YamiboAppContext,
        initialSettings: ReaderAppearanceSettings? = nil
    ) {
        self.context = context
        self.appContext = appContext
        if let initialSettings {
            bootstrapSettings = initialSettings
        }
        runtimeAdapter = nil
        progressSync = ProgressSyncModule(
            adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore)
        )
        cacheOperationModule.onChange = { [weak self] cachedViews, state in
            self?.cachedViews = cachedViews
            self?.cacheOperationState = state
        }
    }

    package init(
        context: ReaderLaunchContext,
        appContext: YamiboAppContext,
        initialSettings: ReaderAppearanceSettings? = nil,
        runtimeAdapter: any NovelTextLayoutRuntimeAdapter
    ) {
        self.context = context
        self.appContext = appContext
        if let initialSettings {
            bootstrapSettings = initialSettings
        }
        self.runtimeAdapter = runtimeAdapter
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

    public var settings: ReaderAppearanceSettings {
        readerPresentation?.committedSettings ?? bootstrapSettings
    }

    public var isTwoPageSpreadActive: Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            layout.width > layout.height
    }

    public var readerSurfaces: [NovelReaderSurface] {
        readerPresentation?.surfaces ?? []
    }

    public var chapters: [ReaderChapter] {
        readerPresentation?.chapters ?? []
    }

    public var currentView: Int {
        readerPresentation?.readingState.currentView ?? 1
    }

    public var maxView: Int {
        readerPresentation?.readingState.maxView ?? 1
    }

    public var currentChapterTitle: String? {
        readerPresentation?.readingState.currentChapterTitle
    }

    private var currentAuthorID: String? {
        readerPresentation?.readingState.authorID
    }

    public var currentContentSource: ReaderContentSource {
        readerPresentation?.currentContentSource ?? .allPostsPage
    }

    public var retainedChapterCount: Int {
        readerPresentation?.retainedChapterCount ?? 0
    }

    public var filteredChapterCandidateCount: Int {
        readerPresentation?.filteredChapterCandidateCount ?? 0
    }

    public var selectedSurfaceIndex: Int {
        normalizedPagedSurfaceIndex(readerPresentation?.selectedSurfaceIndex ?? 0)
    }

    public var currentSurfaceIntraProgress: Double {
        readerPresentation?.readingState.currentSurfaceIntraProgress ?? 0
    }

    package var presentationSpreads: [NovelReaderPresentationSpread] {
        readerPresentation?.spreads ?? []
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
        let transformed = ReaderTextTransformer.transform(previewSource, mode: translationMode)
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

    public var progressChapterTicks: [ReaderProgressChapterTick] {
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

    public var visibleChapterDirectoryChapters: [ReaderChapter] {
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
            ? leftSurfaceIndex(forSpreadIndex: selectionIndex)
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

    public var currentNovelResumePoint: ReaderResumePoint? {
        readingWorkflow?.captureNovelReadingPosition()
    }

    public func handleMemoryPressure() {
        readingWorkflow?.handleMemoryPressure()
    }

    public func close() {
        appearanceSettingsApplicationSequence &+= 1
        isApplyingAppearanceSettings = false
        readingWorkflow?.close()
        readingWorkflow = nil
        chromeProgressSnapshot = .empty
        readerPresentation = nil
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
            bootstrapSettings = appSettings.reader
            applePencilPageTurnSettings = appSettings.applePencilPageTurn
            sessionState = await appContext.sessionStore.load()
            if let repository {
                readingWorkflow = makeReadingWorkflow(repository: repository)
            }
        }
        if readerSurfaces.isEmpty {
            let favorite = await appContext.favoriteStore.favorite(for: context.threadURL)
            await startReadingWorkflow(
                resumePoint: context.initialResumePoint ?? favorite?.novelResumePoint,
                favoriteAuthorID: favorite?.authorID
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

    public func commitNovelTextLayout(_ layout: ReaderContainerLayout) async {
        guard self.layout != layout else { return }
        guard readingWorkflow?.state != nil else {
            self.layout = layout
            return
        }
        do {
            guard let state = try await requestRuntimeUpdate(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            ) else { return }
            self.layout = layout
            syncFromWorkflowState(state)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadCurrent(forceRefresh: Bool) async {
        await load(
            view: displayedView,
            preferredSurfaceOrdinal: displayedPageIndex,
            preferredResumePoint: readingWorkflow?.captureNovelReadingPosition(),
            forceRefresh: forceRefresh
        )
    }

    public func loadAdjacent(delta: Int) async {
        let target = max(1, min(maxView, displayedView + delta))
        guard target != displayedView else { return }

        if delta > 0,
           readingWorkflow?.canPromotePrefetchedDocument(forView: target) == true {
            await promotePrefetchedDocument(startingAt: 0)
            return
        }

        await load(view: target, preferredSurfaceOrdinal: 0, preferredResumePoint: nil, forceRefresh: false)
    }

    public func commitNovelTextAppearance(_ newSettings: ReaderAppearanceSettings) async {
        await commitNovelTextAppearance(newSettings, applePencilPageTurnSettings: applePencilPageTurnSettings)
    }

    public func commitNovelTextAppearance(
        _ newSettings: ReaderAppearanceSettings,
        applePencilPageTurnSettings newApplePencilPageTurnSettings: ApplePencilPageTurnSettings
    ) async {
        let oldSettings = settings
        let oldApplePencilPageTurnSettings = applePencilPageTurnSettings
        let readerSettingsChanged = oldSettings != newSettings
        let applePencilSettingsChanged = oldApplePencilPageTurnSettings != newApplePencilPageTurnSettings
        guard readerSettingsChanged else {
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
                readerSettings: newSettings,
                applePencilPageTurnSettings: applePencilSettingsChanged ? newApplePencilPageTurnSettings : nil
            )
            return
        }

        guard readingWorkflow?.state != nil else {
            bootstrapSettings = newSettings
            applePencilPageTurnSettings = newApplePencilPageTurnSettings
            persistSettings(
                readerSettings: newSettings,
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
                readerSettings: newSettings,
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

    public func saveProgress() async {
        await flushProgress()
    }

    public func selectSurface(_ surfaceIndex: Int) {
        guard let presentation = readerPresentation,
              presentation.surfaces.indices.contains(surfaceIndex) else {
            return
        }
        if let state = readingWorkflow?.selectSurface(
            presentation.surfaces[surfaceIndex].identity,
            presentationRevision: presentation.revision
        ) {
            syncFromWorkflowState(state)
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
        guard let presentation = readerPresentation,
              presentation.surfaces.indices.contains(surfaceIndex) else { return }
        guard let state = readingWorkflow?.updateVerticalViewportPosition(
            surfaceIdentity: presentation.surfaces[surfaceIndex].identity,
            intraSurfaceProgress: normalizedProgress,
            presentationRevision: presentation.revision
        ) else { return }
        syncFromWorkflowState(state)
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
        guard let presentation = readerPresentation,
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

    public func jumpToChapter(_ chapter: ReaderChapter) {
        jumpToSurface(chapter.startIndex)
    }

    package func jumpToSurface(_ surfaceIndex: Int) {
        selectSurface(surfaceIndex)
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
            scheduleProgressSync()
            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
            }
        case let .loadView(view, preferredSurfaceOrdinal, resumePoint):
            await load(view: view, preferredSurfaceOrdinal: preferredSurfaceOrdinal, preferredResumePoint: resumePoint, forceRefresh: false)
        case let .promotePrefetched(preferredSurfaceOrdinal, resumePoint):
            await promotePrefetchedDocument(startingAt: preferredSurfaceOrdinal, preferredResumePoint: resumePoint)
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
        let clampedView = max(1, min(maxView, view))

        if readingWorkflow?.canPromotePrefetchedDocument(forView: clampedView) == true {
            await promotePrefetchedDocument(startingAt: preferredSurfaceOrdinal, preferredResumePoint: nil)
            return
        }

        if clampedView == currentView {
            jumpToSurface(normalizedPagedSurfaceIndex(preferredSurfaceOrdinal))
            return
        }

        await load(view: clampedView, preferredSurfaceOrdinal: preferredSurfaceOrdinal, preferredResumePoint: nil, forceRefresh: false)
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

    public func jumpToChapterDirectoryChapter(_ chapter: ReaderChapter) async {
        let targetView = visibleChapterDirectoryView
        let anchor = chapterDirectoryAnchors[chapter.ordinal]
        resetChapterDirectoryBrowsing()
        if targetView == visibleView {
            jumpToChapter(chapter)
            return
        }
        guard let anchor,
              let workflow = await ensureReadingWorkflow() else {
            await load(
                view: targetView,
                preferredSurfaceOrdinal: 0,
                preferredResumePoint: nil,
                forceRefresh: false
            )
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let state = try await workflow.loadChapter(anchor)
            syncFromWorkflowState(state)
            isLoading = false
            scheduleProgressSync()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
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
        preferredSurfaceOrdinal: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async {
        guard let workflow = await ensureReadingWorkflow() else { return }
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

            Task {
                await prefetchIfNeeded(for: selectedSurfaceIndex)
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
                await prefetchIfNeeded(for: selectedSurfaceIndex)
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
            readingWorkflow = makeReadingWorkflow(repository: repository)
        }
        return readingWorkflow
    }

    private func makeReadingWorkflow(repository: ReaderRepository) -> NovelReadingWorkflow {
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
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
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

    private func syncChapterComments(from module: ReaderChapterCommentsModule) {
        chapterCommentsState = module.state
        isLoadingMoreChapterComments = module.isLoadingMore
        chapterCommentsLoadMoreError = module.loadMoreError
        chapterCommentsRefreshError = module.refreshError
    }

    private func syncFromWorkflowState(_ state: NovelReadingWorkflowState) {
        chromeProgressSnapshot = state.presentation.map(ReaderChromeProgressSnapshot.init) ?? .empty
        readerPresentation = state.presentation
        syncCachedViews(state.cachedViews)
    }

    private func prefetchIfNeeded(for surfaceIndex: Int) async {
        guard let workflow = await ensureReadingWorkflow(),
              let presentation = readerPresentation,
              presentation.surfaces.indices.contains(surfaceIndex),
              let state = await workflow.prefetchIfNeeded(near: presentation.surfaces[surfaceIndex].identity) else {
            return
        }
        syncFromWorkflowState(state)
    }

    private func chapterTitle(for surfaceIndex: Int) -> String? {
        guard readerSurfaces.indices.contains(surfaceIndex) else {
            return chapters.last(where: { $0.startIndex <= surfaceIndex })?.title
        }
        return readerSurfaces[surfaceIndex].chapterTitle ?? chapters.last(where: { $0.startIndex <= surfaceIndex })?.title
    }

    private var displayedPageLabel: String {
        readerPresentation?.progressProjection.displayedPageLabel ?? "1"
    }

    private var displayedView: Int {
        chromeProgressSnapshot.visibleView
    }

    private var displayedPageIndex: Int {
        readerPresentation?.progressProjection.displayedPageIndex ?? 0
    }

    private var displayedPageCount: Int {
        readerPresentation?.progressProjection.displayedPageCount ?? 1
    }

    private var selectedSurface: NovelReaderSurface? {
        let normalizedIndex = normalizedPagedSurfaceIndex(selectedSurfaceIndex)
        guard readerSurfaces.indices.contains(normalizedIndex) else { return nil }
        return readerSurfaces[normalizedIndex]
    }

    private func currentProgressSnapshot() -> NovelReadingPosition {
        readingWorkflow?.currentProgressPosition() ?? NovelReadingPosition(
            threadURL: context.threadURL,
            view: displayedView,
            maxView: maxView,
            chapterTitle: currentChapterTitle,
            authorID: currentAuthorID ?? context.authorID
        )
    }

    private func promoteIfNeededAfterLocationUpdate() {
        if settings.readingMode == .paged,
           selectedSurfaceIndex >= max(readerSurfaces.filter({ $0.documentView == currentView }).count - 1, 0),
           readingWorkflow?.canPromotePrefetchedDocument(forView: currentView + 1) == true {
            Task {
                await promotePrefetchedDocument(startingAt: 0, preferredResumePoint: nil)
            }
        }
    }

    private func scheduleProgressSync() {
        let snapshot = currentProgressSnapshot()
        Task { [weak self, progressSync] in
            await self?.persistReaderResumeRoute(snapshot)
            await progressSync.queue(.novel(snapshot))
        }
    }

    private func flushProgress() async {
        let snapshot = currentProgressSnapshot()
        await persistReaderResumeRoute(snapshot)
        try? await progressSync.flush(.novel(snapshot))
    }

    private func persistReaderResumeRoute(_ snapshot: NovelReadingPosition) async {
        let resumeContext = ReaderLaunchContext(
            threadURL: context.threadURL,
            threadTitle: context.threadTitle,
            source: .resume,
            initialView: snapshot.view,
            authorID: snapshot.authorID ?? context.authorID,
            initialResumePoint: snapshot.resumePoint
        )
        try? await appContext.readerResumeRouteStore.saveReadingPosition(.novel(resumeContext))
    }

    private func spreadIndex(forSurfaceIndex surfaceIndex: Int) -> Int {
        guard isTwoPageSpreadActive else {
            return max(0, min(surfaceIndex, max(readerSurfaces.count - 1, 0)))
        }

        let normalizedIndex = max(0, min(surfaceIndex, max(readerSurfaces.count - 1, 0)))
        return presentationSpreads.first(where: { spread in
            spread.leftSurfaceIndex == normalizedIndex || spread.rightSurfaceIndex == normalizedIndex
        })?.index ?? 0
    }

    private func leftSurfaceIndex(forSpreadIndex spreadIndex: Int) -> Int {
        guard let spread = presentationSpreads.first(where: { $0.index == spreadIndex }) ?? presentationSpreads.last else {
            return 0
        }
        return spread.leftSurfaceIndex
    }

    private func normalizedPagedSurfaceIndex(_ surfaceIndex: Int) -> Int {
        let clampedIndex = max(0, min(surfaceIndex, max(readerSurfaces.count - 1, 0)))
        guard isTwoPageSpreadActive else { return clampedIndex }
        return leftSurfaceIndex(forSpreadIndex: spreadIndex(forSurfaceIndex: clampedIndex))
    }

    private func cacheContext(forView view: Int) -> (authorID: String?, contentSource: ReaderContentSource?) {
        guard let workflowContext = readingWorkflow?.cacheContext(forView: view) else {
            let authorID = currentAuthorID ?? context.authorID
            return (authorID, inferredContentSource(for: authorID))
        }
        return (workflowContext.authorID, workflowContext.contentSource)
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

    private func promotePrefetchedDocument(startingAt preferredSurfaceOrdinal: Int) async {
        await promotePrefetchedDocument(startingAt: preferredSurfaceOrdinal, preferredResumePoint: nil)
    }

    private func promotePrefetchedDocument(startingAt preferredSurfaceOrdinal: Int, preferredResumePoint: ReaderResumePoint?) async {
        do {
            guard let workflowState = try await readingWorkflow?.promotePrefetchedDocument(
                preferredSurfaceOrdinal: preferredSurfaceOrdinal,
                resumePoint: preferredResumePoint
            ) else { return }
            syncFromWorkflowState(workflowState)
            await prefetchIfNeeded(for: selectedSurfaceIndex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSettings(
        readerSettings: ReaderAppearanceSettings? = nil,
        applePencilPageTurnSettings: ApplePencilPageTurnSettings? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            var appSettings = await appContext.settingsStore.load()
            if let readerSettings {
                appSettings.reader = readerSettings
            }
            if let applePencilPageTurnSettings {
                appSettings.applePencilPageTurn = applePencilPageTurnSettings
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

    private func syncCachedViews(_ views: Set<Int>) {
        cacheOperationModule.syncCachedViews(views)
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

private extension ReaderAppearanceSettings {
    func isSurfaceOnlyAppearanceChange(to other: ReaderAppearanceSettings) -> Bool {
        var lhs = self
        var rhs = other
        lhs.backgroundStyle = .system
        rhs.backgroundStyle = .system
        return lhs == rhs && backgroundStyle != other.backgroundStyle
    }
}
