import SwiftUI
import YamiboReaderCore

public struct ReaderCacheOperationState: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case idle
        case running
        case completed
        case cancelled
    }

    public var cachedViews: Set<Int>
    public var queuedViews: [Int]
    public var completedViews: [Int]
    public var failedViews: [Int]
    public var totalCount: Int
    public var completedCount: Int
    public var currentView: Int?
    public var isProgressHidden: Bool
    public var status: Status
    public var summaryMessage: String?

    public init(
        cachedViews: Set<Int> = [],
        queuedViews: [Int] = [],
        completedViews: [Int] = [],
        failedViews: [Int] = [],
        totalCount: Int = 0,
        completedCount: Int = 0,
        currentView: Int? = nil,
        isProgressHidden: Bool = false,
        status: Status = .idle,
        summaryMessage: String? = nil
    ) {
        self.cachedViews = cachedViews
        self.queuedViews = queuedViews
        self.completedViews = completedViews
        self.failedViews = failedViews
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.currentView = currentView
        self.isProgressHidden = isProgressHidden
        self.status = status
        self.summaryMessage = summaryMessage
    }

    public var isRunning: Bool {
        status == .running
    }

    public var isFinished: Bool {
        status == .completed || status == .cancelled
    }

    public var hasSession: Bool {
        isRunning || isFinished
    }
}

public struct ReaderCacheSelectionState: Equatable, Sendable {
    public var selectedViews: Set<Int>
    public var cachedSelectedViews: Set<Int>
    public var uncachedSelectedViews: Set<Int>
    public var canCache: Bool
    public var canUpdate: Bool
    public var canDelete: Bool
    public var isAllSelected: Bool

    public init(
        selectedViews: Set<Int>,
        cachedSelectedViews: Set<Int>,
        uncachedSelectedViews: Set<Int>,
        canCache: Bool,
        canUpdate: Bool,
        canDelete: Bool,
        isAllSelected: Bool
    ) {
        self.selectedViews = selectedViews
        self.cachedSelectedViews = cachedSelectedViews
        self.uncachedSelectedViews = uncachedSelectedViews
        self.canCache = canCache
        self.canUpdate = canUpdate
        self.canDelete = canDelete
        self.isAllSelected = isAllSelected
    }
}

private enum ReaderCacheOperationMode {
    case cache
    case update
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
    @Published public var settings = ReaderAppearanceSettings()
    @Published public private(set) var sessionState = SessionState()
    @Published public private(set) var cacheOperationState = ReaderCacheOperationState()

    public let context: ReaderLaunchContext

    private let appContext: YamiboAppContext
    private var repository: ReaderRepository?
    private var layout: ReaderContainerLayout = .zero
    private var currentDocument: ReaderPageDocument?
    private var prefetchedDocument: ReaderPageDocument?
    private var currentAuthorID: String?
    private var currentDocumentPageCount = 0
    private var prefetchedStartIndex: Int?
    private var cacheOperationTask: Task<Void, Never>?

    public init(context: ReaderLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
    }

    public var title: String {
        context.threadTitle.isEmpty ? "小说阅读" : context.threadTitle
    }

    public var progressText: String {
        let chapter = currentChapterTitle.map { " · \($0)" } ?? ""
        return "第 \(displayedPageIndex + 1) / \(max(displayedPageCount, 1)) 页 · 网页第 \(displayedView) / \(max(maxView, 1)) 页\(chapter)"
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

    public var currentWebViewText: String {
        "网页 \(displayedView) / \(max(maxView, 1))"
    }

    public func chapterTitle(forRenderedPageIndex pageIndex: Int) -> String? {
        guard !pages.isEmpty else { return nil }
        let clampedIndex = min(max(pageIndex, 0), max(pages.count - 1, 0))
        return chapters.last(where: { $0.startIndex <= clampedIndex })?.title
    }

    public func targetRenderedPageIndex(forProgressValue value: Double) -> Int {
        guard !pages.isEmpty else { return 0 }

        switch settings.readingMode {
        case .paged:
            return min(
                max(Int(value.rounded()), 0),
                max(pages.count - 1, 0)
            )
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
            return "当前为只看楼主缓存范围"
        case .fallbackUnfilteredPage, .allPostsPage:
            return "当前为全部回复缓存范围"
        }
    }

    public var cacheScopeDescription: String {
        "缓存内容固定为纯文本，不包含图片。"
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
        currentContentSource == .fallbackUnfilteredPage ? "当前为全部回复页" : nil
    }

    public var chapterSummaryText: String {
        "目录项 \(retainedChapterCount) · 过滤 \(filteredChapterCandidateCount)"
    }

    public var forumURL: URL {
        YamiboRoute.thread(url: context.threadURL, page: displayedView, authorID: currentAuthorID ?? context.authorID).url
    }

    public func prepare(layout: ReaderContainerLayout) async {
        self.layout = layout
        if repository == nil {
            repository = await appContext.makeReaderRepository()
            settings = await appContext.settingsStore.load().reader
            sessionState = await appContext.sessionStore.load()
        }
        if pages.isEmpty {
            let favorite = await appContext.favoriteStore.favorite(for: context.threadURL)
            let initialView = favorite?.lastView ?? context.initialView ?? 1
            let initialPage = favorite?.lastPage ?? context.initialPage ?? 0
            currentAuthorID = favorite?.authorID ?? context.authorID
            await load(view: initialView, preferredPage: initialPage, forceRefresh: false)
        } else {
            repaginate(anchor: currentAnchor())
            await refreshCachedState()
        }
    }

    public func loadCurrent(forceRefresh: Bool) async {
        await load(view: displayedView, preferredPage: displayedPageIndex, forceRefresh: forceRefresh)
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

        await load(view: target, preferredPage: 0, forceRefresh: false)
    }

    public func updateReadingMode(_ mode: ReaderReadingMode) {
        settings.readingMode = mode
        persistSettings()
        repaginate(anchor: currentAnchor())
    }

    public func updateNightMode(_ value: Bool) {
        settings.usesNightMode = value
        persistSettings()
    }

    public func updateSystemStatusBarVisibility(_ value: Bool) {
        settings.showsSystemStatusBar = value
        persistSettings()
    }

    public func updateImageLoading(_ value: Bool) {
        settings.loadsInlineImages = value
        persistSettings()
        repaginate(anchor: currentAnchor())
    }

    public func updateFontScale(_ value: Double) {
        settings.fontScale = value
        persistSettings()
        repaginate(anchor: currentAnchor())
    }

    public func updateLineHeightScale(_ value: Double) {
        settings.lineHeightScale = value
        persistSettings()
        repaginate(anchor: currentAnchor())
    }

    public func updateHorizontalPadding(_ value: Double) {
        settings.horizontalPadding = value
        persistSettings()
        repaginate(anchor: currentAnchor())
    }

    public func updateBackgroundStyle(_ value: ReaderBackgroundStyle) {
        settings.backgroundStyle = value
        persistSettings()
    }

    public func updateTranslationMode(_ value: ReaderTranslationMode) {
        settings.translationMode = value
        persistSettings()
        repaginate(anchor: currentAnchor())
    }

    public func saveProgress() async {
        let progress = ReaderProgress(
            view: displayedView,
            page: displayedPageIndex,
            chapterTitle: currentChapterTitle,
            authorID: currentAuthorID ?? context.authorID
        )
        _ = try? await appContext.favoriteStore.updateReadingProgress(for: context.threadURL, progress: progress)
    }

    public func updateCurrentPage(_ pageIndex: Int) {
        currentPageIndex = max(0, min(pageIndex, max(pages.count - 1, 0)))
        currentChapterTitle = chapterTitle(for: currentPageIndex)

        Task {
            await prefetchIfNeeded(for: currentPageIndex)
        }

        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           currentPageIndex >= startIndex {
            let targetPage = currentPageIndex - startIndex
            Task {
                await promotePrefetchedDocument(startingAt: targetPage)
            }
            return
        }

        if settings.readingMode == .paged,
           let prefetchedDocument,
           currentPageIndex >= max(currentDocumentPageCount - 1, 0),
           prefetchedDocument.view == currentView + 1 {
            Task {
                await promotePrefetchedDocument(startingAt: 0)
            }
        }
    }

    public func jumpToChapter(_ chapter: ReaderChapter) {
        jumpToRenderedPage(chapter.startIndex)
    }

    public func jumpToRenderedPage(_ pageIndex: Int) {
        updateCurrentPage(pageIndex)
    }

    public func jumpRelativePage(_ delta: Int) async {
        guard delta != 0 else { return }

        let targetIndex = currentPageIndex + delta
        if targetIndex >= 0, targetIndex < pages.count {
            jumpToRenderedPage(targetIndex)
            return
        }

        if targetIndex < 0 {
            let previousView = max(displayedView - 1, 1)
            guard previousView < displayedView else {
                jumpToRenderedPage(0)
                return
            }
            await load(view: previousView, preferredPage: .max, forceRefresh: false)
            return
        }

        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           targetIndex >= startIndex {
            await promotePrefetchedDocument(startingAt: targetIndex - startIndex)
            return
        }

        if settings.readingMode == .paged,
           prefetchedDocument?.view == currentView + 1 {
            await promotePrefetchedDocument(startingAt: 0)
            return
        }

        let nextView = min(displayedView + 1, maxView)
        guard nextView > displayedView else {
            jumpToRenderedPage(max(pages.count - 1, 0))
            return
        }
        await load(view: nextView, preferredPage: 0, forceRefresh: false)
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

        await load(view: clampedView, preferredPage: 0, forceRefresh: false)
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
        let validSelections = selectedViews.intersection(Set(allCacheableViews))
        let cachedSelectedViews = validSelections.intersection(cachedViews)
        let uncachedSelectedViews = validSelections.subtracting(cachedViews)
        return ReaderCacheSelectionState(
            selectedViews: validSelections,
            cachedSelectedViews: cachedSelectedViews,
            uncachedSelectedViews: uncachedSelectedViews,
            canCache: !uncachedSelectedViews.isEmpty,
            canUpdate: !cachedSelectedViews.isEmpty,
            canDelete: !cachedSelectedViews.isEmpty,
            isAllSelected: !allCacheableViews.isEmpty && validSelections.count == allCacheableViews.count
        )
    }

    public func startCaching(views: Set<Int>) {
        guard !cacheOperationState.isRunning else { return }
        let selection = cacheSelectionState(for: views)
        guard !selection.uncachedSelectedViews.isEmpty else { return }
        let context = cacheContext(forView: displayedView)
        startCacheOperation(
            mode: .cache,
            views: selection.uncachedSelectedViews,
            context: context
        )
    }

    public func updateCachedViews(_ views: Set<Int>) {
        guard !cacheOperationState.isRunning else { return }
        let selection = cacheSelectionState(for: views)
        guard !selection.cachedSelectedViews.isEmpty else { return }
        let context = cacheContext(forView: displayedView)
        let targetViews = selection.cachedSelectedViews

        cacheOperationState = ReaderCacheOperationState(
            cachedViews: cachedViews.subtracting(targetViews),
            queuedViews: targetViews.sorted(),
            completedViews: [],
            failedViews: [],
            totalCount: targetViews.count,
            completedCount: 0,
            currentView: nil,
            isProgressHidden: false,
            status: .running,
            summaryMessage: nil
        )

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.repository?.deleteCachedViews(
                    targetViews,
                    for: self.context.threadURL,
                    authorID: context.authorID,
                    contentSource: context.contentSource
                )
                self.syncCachedViews(self.cachedViews.subtracting(targetViews))
                self.startCacheOperation(mode: .update, views: targetViews, context: context)
            } catch {
                self.cacheOperationState = ReaderCacheOperationState(cachedViews: self.cachedViews)
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func deleteCachedViews(_ views: Set<Int>) async {
        guard !cacheOperationState.isRunning else { return }
        let selection = cacheSelectionState(for: views)
        guard !selection.cachedSelectedViews.isEmpty else { return }
        let context = cacheContext(forView: displayedView)

        do {
            try await repository?.deleteCachedViews(
                selection.cachedSelectedViews,
                for: self.context.threadURL,
                authorID: context.authorID,
                contentSource: context.contentSource
            )
            syncCachedViews(cachedViews.subtracting(selection.cachedSelectedViews))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func showCacheProgressIfRunning() {
        guard cacheOperationState.hasSession else { return }
        cacheOperationState.isProgressHidden = false
    }

    public func hideCacheProgress() {
        guard cacheOperationState.hasSession else { return }
        cacheOperationState.isProgressHidden = true
    }

    public func dismissCacheProgress() {
        cacheOperationTask = nil
        cacheOperationState = ReaderCacheOperationState(cachedViews: cachedViews)
    }

    public func stopCaching() {
        guard cacheOperationState.isRunning else { return }
        cacheOperationTask?.cancel()
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

    private func load(view: Int, preferredPage: Int, forceRefresh: Bool) async {
        guard let repository else { return }
        isLoading = true
        errorMessage = nil
        do {
            if forceRefresh {
                let context = cacheContext(forView: view)
                try await repository.deleteCachedViews(
                    [view],
                    for: self.context.threadURL,
                    authorID: context.authorID,
                    contentSource: context.contentSource
                )
            }
            let request = ReaderPageRequest(
                threadURL: context.threadURL,
                view: view,
                authorID: currentAuthorID ?? context.authorID
            )
            let document = forceRefresh
                ? try await repository.loadPageIgnoringCache(request)
                : try await repository.loadPage(request)
            currentDocument = document
            prefetchedDocument = nil
            currentAuthorID = document.resolvedAuthorID ?? currentAuthorID ?? context.authorID
            currentView = document.view
            maxView = document.maxView
            applyPagination(for: document, preferredPage: preferredPage)
            await refreshCachedState()
            isLoading = false

            Task {
                await prefetchIfNeeded(for: currentPageIndex)
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func repaginate(anchor: ReaderPageAnchor?) {
        guard let document = currentDocument else { return }
        applyPagination(for: document, preferredPage: resolvedPageIndex(for: anchor))
    }

    private func applyPagination(for document: ReaderPageDocument, preferredPage: Int) {
        let pagination = ReaderPaginator.paginate(document: document, settings: settings, layout: layout)
        currentDocumentPageCount = pagination.pages.count

        var renderedPages = pagination.pages
        var renderedChapters = pagination.chapters
        prefetchedStartIndex = nil

        if settings.readingMode == .vertical,
           let prefetchedDocument,
           prefetchedDocument.view == document.view + 1 {
            let nextPagination = ReaderPaginator.paginate(document: prefetchedDocument, settings: settings, layout: layout)
            let startIndex = renderedPages.count
            prefetchedStartIndex = startIndex
            renderedPages += nextPagination.pages.enumerated().map { offset, page in
                ReaderRenderedPage(index: startIndex + offset, blocks: page.blocks)
            }
            renderedChapters += nextPagination.chapters.map { chapter in
                ReaderChapter(title: chapter.title, startIndex: chapter.startIndex + startIndex)
            }
        }

        pages = renderedPages.enumerated().map { index, page in
            ReaderRenderedPage(index: index, blocks: page.blocks)
        }
        chapters = renderedChapters
        currentContentSource = document.contentSource
        retainedChapterCount = document.retainedChapterCount
        filteredChapterCandidateCount = document.filteredChapterCandidateCount
        currentPageIndex = max(0, min(preferredPage, max(currentDocumentPageCount - 1, 0)))
        currentChapterTitle = chapterTitle(for: currentPageIndex)
    }

    private func prefetchIfNeeded(for pageIndex: Int) async {
        guard let repository, let currentDocument else { return }
        guard currentDocument.view < currentDocument.maxView else { return }
        let thresholdIndex = max(currentDocumentPageCount - 2, 0)
        guard pageIndex >= thresholdIndex else { return }
        if let prefetchedDocument, prefetchedDocument.view == currentDocument.view + 1 { return }

        let nextRequest = ReaderPageRequest(
            threadURL: context.threadURL,
            view: currentDocument.view + 1,
            authorID: currentAuthorID ?? currentDocument.resolvedAuthorID ?? context.authorID
        )
        guard let nextDocument = try? await repository.loadPage(nextRequest) else { return }

        prefetchedDocument = nextDocument
        currentAuthorID = nextDocument.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        maxView = max(maxView, nextDocument.maxView)
        if settings.readingMode == .vertical {
            applyPagination(for: currentDocument, preferredPage: currentPageIndex)
        }
    }

    private func chapterTitle(for pageIndex: Int) -> String? {
        chapters.last(where: { $0.startIndex <= pageIndex })?.title
    }

    private func currentAnchor() -> ReaderPageAnchor? {
        guard !chapters.isEmpty else { return nil }
        let startIndex = chapters.last(where: { $0.startIndex <= currentPageIndex })?.startIndex ?? 0
        return ReaderPageAnchor(
            chapterTitle: currentChapterTitle,
            offsetInChapter: max(currentPageIndex - startIndex, 0)
        )
    }

    private func resolvedPageIndex(for anchor: ReaderPageAnchor?) -> Int {
        guard let anchor,
              let chapterTitle = anchor.chapterTitle,
              let chapter = chapters.first(where: { $0.title == chapterTitle }) else {
            return currentPageIndex
        }
        return max(0, min(chapter.startIndex + anchor.offsetInChapter, max(currentDocumentPageCount - 1, 0)))
    }

    private var displayedView: Int {
        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           currentPageIndex >= startIndex,
           let prefetchedDocument {
            return prefetchedDocument.view
        }
        return currentView
    }

    private var displayedPageIndex: Int {
        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           currentPageIndex >= startIndex {
            return currentPageIndex - startIndex
        }
        return currentPageIndex
    }

    private var displayedPageCount: Int {
        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           currentPageIndex >= startIndex {
            return max(pages.count - startIndex, 1)
        }
        return max(currentDocumentPageCount, 1)
    }

    private var displayedDocument: ReaderPageDocument? {
        if let startIndex = prefetchedStartIndex,
           settings.readingMode == .vertical,
           currentPageIndex >= startIndex,
           let prefetchedDocument {
            return prefetchedDocument
        }
        return currentDocument
    }

    private func cacheContext(forView view: Int) -> (authorID: String?, contentSource: ReaderContentSource?) {
        if currentDocument?.view == view {
            return (
                currentDocument?.resolvedAuthorID ?? currentAuthorID ?? context.authorID,
                currentDocument?.contentSource ?? inferredContentSource(for: currentDocument?.resolvedAuthorID ?? currentAuthorID ?? context.authorID)
            )
        }

        if prefetchedDocument?.view == view {
            return (
                prefetchedDocument?.resolvedAuthorID ?? currentAuthorID ?? context.authorID,
                prefetchedDocument?.contentSource ?? inferredContentSource(for: prefetchedDocument?.resolvedAuthorID ?? currentAuthorID ?? context.authorID)
            )
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

    private func inferredContentSource(for authorID: String?) -> ReaderContentSource {
        let normalizedAuthorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedAuthorID.isEmpty ? .fallbackUnfilteredPage : .authorFilteredPage
    }

    private func promotePrefetchedDocument(startingAt preferredPage: Int) async {
        guard let nextDocument = prefetchedDocument else { return }
        currentDocument = nextDocument
        prefetchedDocument = nil
        currentAuthorID = nextDocument.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        currentView = nextDocument.view
        maxView = nextDocument.maxView
        applyPagination(for: nextDocument, preferredPage: preferredPage)
        await prefetchIfNeeded(for: currentPageIndex)
    }

    private func persistSettings() {
        let settings = settings
        Task {
            var appSettings = await appContext.settingsStore.load()
            appSettings.reader = settings
            try? await appContext.settingsStore.save(appSettings)
        }
    }

    private func startCacheOperation(
        mode: ReaderCacheOperationMode,
        views: Set<Int>,
        context: (authorID: String?, contentSource: ReaderContentSource?)
    ) {
        guard let repository else { return }
        let targets = views.sorted()
        guard !targets.isEmpty else { return }

        cacheOperationState = ReaderCacheOperationState(
            cachedViews: cachedViews,
            queuedViews: targets,
            completedViews: [],
            failedViews: [],
            totalCount: targets.count,
            completedCount: 0,
            currentView: nil,
            isProgressHidden: false,
            status: .running,
            summaryMessage: nil
        )

        cacheOperationTask?.cancel()
        cacheOperationTask = Task { [weak self] in
            guard let self else { return }
            let result = await repository.cacheViews(
                Set(targets),
                for: self.context.threadURL,
                authorID: context.authorID,
                contentSource: context.contentSource
            ) { [weak self] progress in
                await self?.applyCacheBatchProgress(progress, allTargets: targets)
            }
            await self.finalizeCacheOperation(result: result, mode: mode)
        }
    }

    private func applyCacheBatchProgress(_ progress: ReaderCacheBatchProgress, allTargets: [Int]) {
        cacheOperationState.totalCount = progress.totalCount
        cacheOperationState.completedCount = progress.completedCount
        cacheOperationState.currentView = progress.currentView
        cacheOperationState.completedViews = progress.completedViews
        cacheOperationState.failedViews = progress.failedViews
        cacheOperationState.status = progress.status == .cancelled ? .cancelled : .running

        let completed = Set(progress.completedViews)
        let failed = Set(progress.failedViews)
        cacheOperationState.queuedViews = allTargets.filter { !completed.contains($0) && !failed.contains($0) }
        syncCachedViews(cachedViews.union(completed))
    }

    private func finalizeCacheOperation(result: ReaderCacheBatchResult, mode: ReaderCacheOperationMode) async {
        cacheOperationTask = nil
        await refreshCachedState()

        let actionText = switch mode {
        case .cache: "缓存"
        case .update: "更新"
        }

        var summary = result.wasCancelled
            ? "已终止，已完成 \(result.completedViews.count) / \(result.totalCount) 页\(actionText)"
            : "已完成 \(result.completedViews.count) / \(result.totalCount) 页\(actionText)"
        if !result.failedViews.isEmpty {
            summary += "，\(result.failedViews.count) 页失败，已跳过"
        }

        cacheOperationState.cachedViews = cachedViews
        cacheOperationState.queuedViews = []
        cacheOperationState.completedViews = result.completedViews
        cacheOperationState.failedViews = result.failedViews
        cacheOperationState.totalCount = result.totalCount
        cacheOperationState.completedCount = result.completedViews.count
        cacheOperationState.currentView = nil
        cacheOperationState.status = result.wasCancelled ? .cancelled : .completed
        cacheOperationState.summaryMessage = summary
        cacheOperationState.isProgressHidden = false
    }

    private func syncCachedViews(_ views: Set<Int>) {
        cachedViews = views
        cacheOperationState.cachedViews = views
    }
}

private struct ReaderPageAnchor {
    let chapterTitle: String?
    let offsetInChapter: Int
}
