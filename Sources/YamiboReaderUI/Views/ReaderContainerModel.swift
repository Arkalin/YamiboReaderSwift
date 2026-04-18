import SwiftUI
import YamiboReaderCore

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

    public let context: ReaderLaunchContext

    private let appContext: YamiboAppContext
    private var repository: ReaderRepository?
    private var layout: ReaderContainerLayout = .zero
    private var currentDocument: ReaderPageDocument?
    private var prefetchedDocument: ReaderPageDocument?
    private var currentAuthorID: String?
    private var currentDocumentPageCount = 0
    private var prefetchedStartIndex: Int?

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
        cachedViews = await repository?.cachedViews(for: context.threadURL) ?? []
        if pages.isEmpty {
            let favorite = await appContext.favoriteStore.favorite(for: context.threadURL)
            let initialView = favorite?.lastView ?? context.initialView ?? 1
            let initialPage = favorite?.lastPage ?? context.initialPage ?? 0
            currentAuthorID = favorite?.authorID ?? context.authorID
            await load(view: initialView, preferredPage: initialPage, forceRefresh: false)
        } else {
            repaginate(anchor: currentAnchor())
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
        cachedViews = await repository?.cachedViews(for: context.threadURL) ?? []
    }

    public func deleteCurrentCache() async {
        do {
            try await repository?.deleteCachedViews([displayedView], for: context.threadURL)
            await refreshCachedState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refreshCurrentCache() async {
        do {
            try await repository?.refreshCachedViews([displayedView], for: context.threadURL)
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
                try await repository.deleteCachedViews([view], for: context.threadURL)
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
            cachedViews = await repository.cachedViews(for: context.threadURL)
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
}

private struct ReaderPageAnchor {
    let chapterTitle: String?
    let offsetInChapter: Int
}
