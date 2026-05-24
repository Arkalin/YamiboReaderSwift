import Foundation
import SwiftUI
import YamiboReaderCore

public struct MangaViewportRequest: Equatable, Sendable {
    public var targetIndex: Int
    public var targetPageID: MangaPage.ID
    public var animated: Bool
    public var revision: UUID

    public init(targetIndex: Int, targetPageID: MangaPage.ID, animated: Bool, revision: UUID) {
        self.targetIndex = targetIndex
        self.targetPageID = targetPageID
        self.animated = animated
        self.revision = revision
    }
}

public struct MangaPagedSpread: Identifiable, Equatable, Sendable {
    public let index: Int
    public let leftPageIndex: Int
    public let rightPageIndex: Int?
    public let chapterTitle: String

    public var id: Int { index }

    public init(index: Int, leftPageIndex: Int, rightPageIndex: Int?, chapterTitle: String) {
        self.index = max(0, index)
        self.leftPageIndex = max(0, leftPageIndex)
        self.rightPageIndex = rightPageIndex
        self.chapterTitle = chapterTitle
    }
}

@MainActor
public final class MangaReaderModel: ObservableObject {
    @Published public private(set) var pages: [MangaPage] = []
    @Published public private(set) var pagedSpreads: [MangaPagedSpread] = []
    @Published public private(set) var currentDirectory: MangaDirectory?
    @Published public private(set) var isLoading = false
    @Published public var errorMessage: String?
    @Published public var settings = MangaReaderSettings()
    @Published public var applePencilPageTurnSettings = ApplePencilPageTurnSettings()
    @Published public var currentPageIndex = 0
    @Published public private(set) var viewportRequest: MangaViewportRequest?
    @Published public private(set) var isUpdatingDirectory = false
    @Published public private(set) var directoryCooldownRemaining = 0
    @Published public private(set) var showsForceSearchShortcut = false
    @Published public private(set) var forceSearchShortcutRemaining = 0
    @Published public private(set) var chapterTransitionState: MangaChapterTransitionState = .idle
    @Published public private(set) var navigationRequest: MangaReaderNavigationRequest?
    @Published public private(set) var chapterCommentsState: ReaderChapterCommentsState = .idle
    @Published public private(set) var isLoadingMoreChapterComments = false
    @Published public private(set) var chapterCommentsLoadMoreError: String?
    @Published public private(set) var chapterCommentsRefreshError: String?

    public let context: MangaLaunchContext

    private let appContext: YamiboAppContext
    private let imageRepository: MangaImageRepository
    private let chapterProbe: @MainActor (MangaLaunchContext) async -> MangaProbeOutcome
    private var repository: MangaRepository?
    private var readerRepository: ReaderRepository?
    private var chapterCommentsCache: [ReaderChapterCommentTarget: ChapterCommentsPage] = [:]
    private var chapterWindow: MangaChapterWindow?
    private var chapterDocumentTasks: [String: Task<MangaChapterDocument, Error>] = [:]
    private var chapterJumpTask: Task<Void, Never>?
    private var imagePrefetchTask: Task<Void, Never>?
    private var directoryCooldownTask: Task<Void, Never>?
    private var forceSearchShortcutTask: Task<Void, Never>?
    private var prepared = false
    private let maxLoadedDocuments = 10
    private let chapterLoadTimeoutNanoseconds: UInt64 = 12_000_000_000
    private let chapterTransitionTimeoutNanoseconds: UInt64 = 18_000_000_000
    private var viewportRevision = UUID()
    private var chapterJumpGeneration = 0
    private var progressSyncTask: Task<Void, Never>?
    private var lastQueuedProgress: MangaProgressSnapshot?
    private var lastSyncedProgress: MangaProgressSnapshot?
    private let progressSyncDelayNanoseconds: UInt64 = 350_000_000
    private var usesPadPresentation = false
    private var pagedViewportSize: CGSize = .zero

    public init(
        context: MangaLaunchContext,
        appContext: YamiboAppContext,
        chapterProbe: (@MainActor (MangaLaunchContext) async -> MangaProbeOutcome)? = nil
    ) {
        self.context = context
        self.appContext = appContext
        self.imageRepository = appContext.mangaImageRepository
        self.chapterProbe = chapterProbe ?? { launchContext in
            let service = MangaProbeService(appContext: appContext)
            return await service.probe(
                launchContext: launchContext,
                currentHTML: nil,
                currentTitle: nil
            )
        }
    }

    public var title: String {
        currentPage?.chapterTitle ?? currentDirectory?.cleanBookName ?? context.displayTitle
    }

    public var currentPage: MangaPage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    public var currentPageText: String {
        guard let currentPage else { return "0 / 0" }
        return "\(currentPage.localIndex + 1) / \(max(1, currentPage.chapterTotalPages))"
    }

    public var currentChapterCommentTarget: ReaderChapterCommentTarget? {
        guard let currentPage else { return nil }
        return ReaderChapterCommentTarget(
            threadURL: currentPage.chapterURL,
            view: webViewPage(from: currentPage.chapterURL),
            ownerPostID: currentPage.ownerPostID,
            title: currentPage.chapterTitle
        )
    }

    public var progressLabelText: String {
        currentPageText
    }

    public var isTwoPageSpreadActive: Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            pagedViewportSize.width > pagedViewportSize.height
    }

    public var pagedSelectionIndex: Int {
        guard isTwoPageSpreadActive else { return currentPageIndex }
        return spreadIndex(forPageIndex: currentPageIndex)
    }

    public var sliderRange: ClosedRange<Double> {
        0 ... Double(max(0, (currentPage?.chapterTotalPages ?? 1) - 1))
    }

    public var sliderHasAvailableRange: Bool {
        sliderRange.lowerBound < sliderRange.upperBound
    }

    public func clampedLocalPageIndex(for localIndex: Int) -> Int {
        let upperBound = max(0, (currentPage?.chapterTotalPages ?? 1) - 1)
        return min(max(localIndex, 0), upperBound)
    }

    public func previewLabel(forLocalIndex localIndex: Int) -> String {
        guard let currentPage else { return L10n.string("manga.preview_page", 1, 1) }
        let clampedIndex = clampedLocalPageIndex(for: localIndex)
        return L10n.string("manga.preview_page", clampedIndex + 1, max(1, currentPage.chapterTotalPages))
    }

    public var hasPreviousChapter: Bool {
        adjacentChapter(delta: -1) != nil
    }

    public var hasNextChapter: Bool {
        adjacentChapter(delta: 1) != nil
    }

    public var currentDirectoryTitle: String {
        currentDirectory?.cleanBookName ?? context.displayTitle
    }

    public var sortedDirectoryChapters: [MangaChapter] {
        let chapters = currentDirectory?.chapters ?? []
        switch settings.directorySortOrder {
        case .ascending:
            return chapters
        case .descending:
            return chapters.reversed()
        }
    }

    public var latestChapterText: String? {
        guard let currentDirectory,
              let latestChapter = MangaChapterDisplayFormatter.latestChapter(in: currentDirectory.chapters)
        else {
            return nil
        }
        return L10n.string("manga.latest_chapter", MangaChapterDisplayFormatter.displayNumber(for: latestChapter))
    }

    public var directoryUpdateButtonTitle: String {
        if isUpdatingDirectory {
            return L10n.string("common.updating")
        }
        if directoryCooldownRemaining > 0 {
            return "\(directoryCooldownRemaining)s"
        }
        if showsForceSearchShortcut {
            return forceSearchShortcutRemaining > 0
                ? L10n.string("manga.global_search_countdown", forceSearchShortcutRemaining)
                : L10n.string("manga.global_search")
        }
        if currentDirectory?.strategy != .tag {
            return L10n.string("manga.global_search")
        }
        return L10n.string("reader.cache_action.update")
    }

    public var isDirectoryUpdateButtonEnabled: Bool {
        !isUpdatingDirectory && directoryCooldownRemaining <= 0
    }

    public var isDirectoryUpdateSearchMode: Bool {
        showsForceSearchShortcut || currentDirectory?.strategy != .tag
    }

    public var isTransitioningChapter: Bool {
        if case .loading = chapterTransitionState {
            return true
        }
        return false
    }

    public func prepare() async {
        guard !prepared else { return }
        prepared = true
        isLoading = true
        defer { isLoading = false }

        repository = await appContext.makeMangaRepository()
        let appSettings = await appContext.settingsStore.load()
        settings = appSettings.manga
        applePencilPageTurnSettings = appSettings.applePencilPageTurn
        await loadInitialChapter()
    }

    public func retryCurrentChapter() async {
        errorMessage = nil
        await loadInitialChapter()
    }

    public func consumeNavigationRequest() {
        navigationRequest = nil
    }

    public func loadChapterComments(for target: ReaderChapterCommentTarget?) async {
        guard let target else {
            chapterCommentsState = .unsupported
            return
        }
        if let cached = chapterCommentsCache[target] {
            chapterCommentsRefreshError = nil
            chapterCommentsState = .loaded(target, cached)
            return
        }
        await refreshChapterComments(for: target)
    }

    public func refreshChapterComments(for target: ReaderChapterCommentTarget?) async {
        guard let target else {
            chapterCommentsState = .unsupported
            return
        }
        if readerRepository == nil {
            readerRepository = await appContext.makeReaderRepository()
        }
        guard let readerRepository else {
            chapterCommentsState = .failed(target, L10n.string("reader.chapter_comments_failed"))
            return
        }
        chapterCommentsState = .loading(target)
        chapterCommentsLoadMoreError = nil
        chapterCommentsRefreshError = nil
        do {
            let page = try await readerRepository.loadChapterComments(for: target)
            chapterCommentsCache[target] = page
            chapterCommentsState = .loaded(target, page)
        } catch {
            if let cached = chapterCommentsCache[target] {
                chapterCommentsRefreshError = error.localizedDescription
                chapterCommentsState = .loaded(target, cached)
            } else {
                chapterCommentsState = .failed(target, error.localizedDescription)
            }
        }
    }

    public func loadNextChapterCommentsPage() async {
        guard case let .loaded(target, currentPage) = chapterCommentsState,
              let nextView = currentPage.nextView,
              !isLoadingMoreChapterComments else {
            return
        }
        if readerRepository == nil {
            readerRepository = await appContext.makeReaderRepository()
        }
        guard let readerRepository else { return }

        isLoadingMoreChapterComments = true
        chapterCommentsLoadMoreError = nil
        do {
            let nextPage = try await readerRepository.loadMoreChapterComments(for: target, view: nextView)
            let mergedPage = ChapterCommentsPage(
                target: target,
                comments: currentPage.comments + nextPage.comments,
                isBoundaryClosed: nextPage.isBoundaryClosed,
                nextView: nextPage.nextView
            )
            chapterCommentsCache[target] = mergedPage
            chapterCommentsState = .loaded(target, mergedPage)
            chapterCommentsRefreshError = nil
        } catch {
            chapterCommentsLoadMoreError = error.localizedDescription
        }
        isLoadingMoreChapterComments = false
    }

    public func clearTransitionFailureIfNeeded() {
        if case .failed = chapterTransitionState {
            chapterTransitionState = .idle
        }
    }

    public func updateCurrentPage(_ index: Int) {
        guard !pages.isEmpty else { return }
        currentPageIndex = normalizedPagedPageIndex(index)
        scheduleProgressSync()
        scheduleImagePrefetch()
        Task {
            await prefetchIfNeeded(for: currentPageIndex)
        }
    }

    public func updateCurrentPage(forPageID pageID: MangaPage.ID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        guard index != currentPageIndex else { return }
        updateCurrentPage(index)
    }

    public func updatePagedPresentationEnvironment(isPad: Bool, viewportSize: CGSize) {
        let normalizedSize = CGSize(
            width: max(0, viewportSize.width),
            height: max(0, viewportSize.height)
        )
        guard usesPadPresentation != isPad || pagedViewportSize != normalizedSize else { return }
        let wasTwoPageSpreadActive = isTwoPageSpreadActive
        usesPadPresentation = isPad
        pagedViewportSize = normalizedSize
        guard wasTwoPageSpreadActive != isTwoPageSpreadActive else { return }
        currentPageIndex = normalizedPagedPageIndex(currentPageIndex)
        emitViewportRequest(targetIndex: currentPageIndex, animated: false, resetRevision: true)
    }

    public func updatePagedSelection(_ selectionIndex: Int) {
        let targetPageIndex = isTwoPageSpreadActive
            ? leftPageIndex(forSpreadIndex: selectionIndex)
            : selectionIndex
        updateCurrentPage(targetPageIndex)
    }

    public func requestCurrentChapterPage(_ localIndex: Int, animated: Bool = true) {
        guard let currentPage else { return }
        let clampedLocalIndex = max(0, min(localIndex, max(0, currentPage.chapterTotalPages - 1)))
        guard let targetIndex = pages.firstIndex(where: {
            $0.chapterURL == currentPage.chapterURL && $0.localIndex == clampedLocalIndex
        }) else {
            return
        }
        jumpToLoadedPage(targetIndex, animated: animated)
    }

    public func jumpRelativePage(_ delta: Int, animated: Bool = true) async {
        guard delta != 0, !pages.isEmpty else { return }

        if settings.readingMode == .paged, isTwoPageSpreadActive {
            let targetSpreadIndex = pagedSelectionIndex + delta
            if pagedSpreads.indices.contains(targetSpreadIndex) {
                jumpToLoadedPage(leftPageIndex(forSpreadIndex: targetSpreadIndex), animated: animated)
                return
            }
        } else {
            let targetIndex = currentPageIndex + delta
            if pages.indices.contains(targetIndex) {
                jumpToLoadedPage(targetIndex, animated: animated)
                return
            }
        }

        jumpToLoadedPage(delta < 0 ? 0 : pages.count - 1, animated: animated)
    }

    public func saveProgress() async {
        await flushProgress()
    }

    public func applySettings(_ newSettings: MangaReaderSettings) {
        let wasTwoPageSpreadActive = isTwoPageSpreadActive
        settings = newSettings
        if wasTwoPageSpreadActive != isTwoPageSpreadActive {
            currentPageIndex = normalizedPagedPageIndex(currentPageIndex)
            emitViewportRequest(targetIndex: currentPageIndex, animated: false, resetRevision: true)
        }
        Task {
            await persistSettings(mangaSettings: newSettings)
        }
    }

    public func applyApplePencilPageTurnSettings(_ newSettings: ApplePencilPageTurnSettings) {
        applePencilPageTurnSettings = newSettings
        Task {
            await persistSettings(applePencilPageTurnSettings: newSettings)
        }
    }

    public func applyDirectorySortOrder(_ sortOrder: MangaDirectorySortOrder) {
        guard settings.directorySortOrder != sortOrder else { return }
        settings.directorySortOrder = sortOrder
        Task {
            await persistSettings()
        }
    }

    public func jumpToAdjacentChapter(_ delta: Int) async {
        guard let chapter = adjacentChapter(delta: delta) else { return }
        await jumpToChapter(chapter, source: .adjacent)
    }

    public func jumpToChapter(_ chapter: MangaChapter) async {
        await jumpToChapter(chapter, source: .directory)
    }

    private func jumpToChapter(_ chapter: MangaChapter, source: MangaChapterTransitionSource) async {
        if let index = firstPageIndex(for: chapter.url) {
            currentPageIndex = index
            emitViewportRequest(targetIndex: index, animated: true, resetRevision: true)
            scheduleImagePrefetch()
            chapterTransitionState = .idle
            return
        }

        guard let currentDirectory,
              let targetIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == chapter.tid }),
              let currentPage,
              let currentIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == currentPage.tid }) else {
            chapterTransitionState = .failed(message: L10n.string("manga.chapter_state_invalid"))
            return
        }

        if abs(targetIndex - currentIndex) > 1 {
            emitNavigationRequest(.reopenNative(makeNativeLaunchContext(for: chapter)))
            return
        }

        await performAdjacentChapterJump(to: chapter, source: source)
    }

    public func updateDirectoryFromPanel() async {
        await updateDirectory(isForcedSearch: showsForceSearchShortcut)
    }

    public func updateDirectory(isForcedSearch: Bool = false) async {
        guard let repository, let currentDirectory else { return }
        isUpdatingDirectory = true
        defer { isUpdatingDirectory = false }
        clearDirectoryShortcutState()

        do {
            let result = try await appContext.mangaDirectoryStore.updateDirectory(
                currentDirectory,
                currentTID: currentPage?.tid,
                isForcedSearch: isForcedSearch,
                using: repository
            )
            self.currentDirectory = result.directory
            if let snapshot = chapterWindow?.updateDirectory(result.directory, preserving: currentReadingPosition) {
                applyWindowSnapshot(snapshot, animated: false, resetRevision: false)
            }
            errorMessage = nil
            handleDirectoryUpdateSuccess(
                result: result,
                isForcedSearch: isForcedSearch
            )
        } catch {
            errorMessage = error.localizedDescription
            handleDirectoryUpdateFailure(error)
        }
    }

    public func renameDirectory(cleanBookName: String, searchKeyword: String) async {
        guard let currentDirectory else { return }
        do {
            let updated = try await appContext.mangaDirectoryStore.renameAndMergeDirectory(
                currentDirectory,
                newCleanName: cleanBookName,
                newSearchKeyword: searchKeyword
            )
            self.currentDirectory = updated
            if let snapshot = chapterWindow?.updateDirectory(updated, preserving: currentReadingPosition) {
                applyWindowSnapshot(snapshot, animated: false, resetRevision: false)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentReadingPosition: MangaReadingPosition? {
        guard let currentPage else { return nil }
        return MangaReadingPosition(tid: currentPage.tid, localIndex: currentPage.localIndex)
    }

    private func loadInitialChapter() async {
        chapterJumpTask?.cancel()
        chapterTransitionState = .idle
        navigationRequest = nil
        do {
            let document = try await loadDocument(for: context.chapterURL, htmlOverride: nil)
            let directory = try await resolveDirectory(from: document)
            currentDirectory = directory
            let initialLocalPage = max(0, context.initialPage)
            let window = MangaChapterWindow(
                directory: directory,
                initialDocument: document,
                position: MangaReadingPosition(tid: document.tid, localIndex: initialLocalPage),
                maxLoadedDocuments: maxLoadedDocuments
            )
            chapterWindow = window
            applyWindowSnapshot(
                window.snapshot,
                animated: false,
                resetRevision: true
            )
            if shouldAutoUpdateDirectory(directory) {
                await updateDirectory(isForcedSearch: false)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveDirectory(from document: MangaChapterDocument) async throws -> MangaDirectory {
        if let directoryName = context.directoryName,
           let existing = await appContext.mangaDirectoryStore.directory(named: directoryName) {
            return existing
        }

        return try await appContext.mangaDirectoryStore.initializeDirectory(
            currentURL: document.chapterURL,
            rawTitle: document.chapterTitle,
            html: document.html
        )
    }

    private func loadDocument(for url: URL, htmlOverride: String?) async throws -> MangaChapterDocument {
        let tid = MangaTitleCleaner.extractTid(from: url.absoluteString) ?? url.absoluteString
        if let existingTask = chapterDocumentTasks[tid] {
            return try await existingTask.value
        }
        guard let repository else {
            throw YamiboError.underlying(L10n.string("manga.repository_uninitialized"))
        }
        let task = Task {
            try await repository.loadChapter(url: url, htmlOverride: htmlOverride)
        }
        chapterDocumentTasks[tid] = task
        defer { chapterDocumentTasks.removeValue(forKey: tid) }
        return try await task.value
    }

    private func prefetchIfNeeded(for index: Int) async {
        guard !pages.isEmpty else { return }
        if index >= pages.count - 6 {
            await loadAdjacentDocument(delta: 1)
        }
        if index <= 2 {
            await loadAdjacentDocument(delta: -1)
        }
    }

    private func loadAdjacentDocument(delta: Int) async {
        guard let chapter = chapterWindow?.adjacentChapterForLoadedRange(delta: delta) else { return }
        guard firstPageIndex(for: chapter.url) == nil else { return }
        do {
            let position = currentReadingPosition
            let document = try await loadDocument(for: chapter.url, htmlOverride: nil)
            guard firstPageIndex(for: document.chapterURL) == nil else { return }
            guard let result = chapterWindow?.insertAdjacentDocument(document, preserving: position) else { return }
            if case let .changed(snapshot) = result {
                applyWindowSnapshot(snapshot, animated: false, resetRevision: delta < 0)
            }
        } catch {
            // Preload failures should not interrupt reading.
        }
    }

    private func applyWindowSnapshot(
        _ snapshot: MangaChapterWindowSnapshot,
        animated: Bool,
        resetRevision: Bool
    ) {
        pages = snapshot.pages
        pagedSpreads = makePagedSpreads(from: snapshot.pages)

        guard !snapshot.pages.isEmpty else {
            currentPageIndex = 0
            pagedSpreads = []
            viewportRequest = nil
            return
        }

        if let targetIndex = snapshot.resolvedPageIndex {
            currentPageIndex = normalizedPagedPageIndex(targetIndex)
            emitViewportRequest(targetIndex: currentPageIndex, animated: animated, resetRevision: resetRevision)
        } else {
            currentPageIndex = normalizedPagedPageIndex(currentPageIndex)
            emitViewportRequest(
                targetIndex: currentPageIndex,
                animated: animated,
                resetRevision: resetRevision
            )
        }
        scheduleImagePrefetch()
    }

    private func makePagedSpreads(from pages: [MangaPage]) -> [MangaPagedSpread] {
        guard !pages.isEmpty else { return [] }

        var spreads: [MangaPagedSpread] = []
        var pageIndex = 0

        while pageIndex < pages.count {
            let leftPage = pages[pageIndex]
            let candidateRightIndex = pageIndex + 1
            let rightPageIndex: Int? = if pages.indices.contains(candidateRightIndex),
                                          pages[candidateRightIndex].chapterURL == leftPage.chapterURL {
                candidateRightIndex
            } else {
                nil
            }

            spreads.append(
                MangaPagedSpread(
                    index: spreads.count,
                    leftPageIndex: leftPage.globalIndex,
                    rightPageIndex: rightPageIndex,
                    chapterTitle: leftPage.chapterTitle
                )
            )
            pageIndex += rightPageIndex == nil ? 1 : 2
        }

        return spreads
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

    private func emitViewportRequest(
        targetIndex: Int,
        animated: Bool,
        resetRevision: Bool
    ) {
        guard pages.indices.contains(targetIndex) else { return }
        if resetRevision {
            viewportRevision = UUID()
        }
        viewportRequest = MangaViewportRequest(
            targetIndex: targetIndex,
            targetPageID: pages[targetIndex].id,
            animated: animated,
            revision: viewportRevision
        )
    }

    private func adjacentChapter(delta: Int) -> MangaChapter? {
        guard let currentReadingPosition else { return nil }
        return chapterWindow?.adjacentChapter(from: currentReadingPosition, delta: delta)
    }

    private func firstPageIndex(for chapterURL: URL) -> Int? {
        pages.firstIndex(where: { $0.chapterURL == chapterURL && $0.localIndex == 0 })
    }

    private func jumpToLoadedPage(_ pageIndex: Int, animated: Bool) {
        guard pages.indices.contains(pageIndex) else { return }
        let normalizedTargetIndex = normalizedPagedPageIndex(pageIndex)
        currentPageIndex = normalizedTargetIndex
        emitViewportRequest(targetIndex: normalizedTargetIndex, animated: animated, resetRevision: false)
        scheduleImagePrefetch()
        Task {
            await prefetchIfNeeded(for: normalizedTargetIndex)
        }
    }

    private func scheduleImagePrefetch() {
        imagePrefetchTask?.cancel()
        let requests = prefetchImageRequests(around: currentPageIndex)
        guard !requests.isEmpty else { return }
        let settingsStore = appContext.settingsStore
        let imageRepository = self.imageRepository
        imagePrefetchTask = Task {
            let appSettings = await settingsStore.load()
            guard !appSettings.usesDataSaverMode else { return }
            guard !Task.isCancelled else { return }
            await imageRepository.prefetch(requests)
        }
    }

    private func prefetchImageRequests(around index: Int) -> [MangaImageRequest] {
        guard !pages.isEmpty, pages.indices.contains(index) else { return [] }
        let lowerBound = max(0, index - 3)
        let upperBound = min(pages.count - 1, index + 6)
        var requests: [MangaImageRequest] = []
        requests.reserveCapacity(upperBound - lowerBound + 1)
        var seen = Set<String>()

        for currentIndex in lowerBound ... upperBound {
            let page = pages[currentIndex]
            let cacheKey = page.imageURL.absoluteString
            guard seen.insert(cacheKey).inserted else { continue }
            requests.append(
                MangaImageRequest(
                    imageURL: page.imageURL,
                    refererURL: page.chapterURL
                )
            )
        }

        return requests
    }

    private func performAdjacentChapterJump(
        to chapter: MangaChapter,
        source: MangaChapterTransitionSource
    ) async {
        chapterJumpGeneration += 1
        let generation = chapterJumpGeneration
        chapterJumpTask?.cancel()
        imagePrefetchTask?.cancel()
        chapterTransitionState = .loading(targetTID: chapter.tid, source: source)
        errorMessage = nil

        let task = Task { @MainActor in
            await self.runAdjacentChapterJump(
                to: chapter,
                source: source,
                generation: generation
            )
        }
        chapterJumpTask = task
        await task.value
    }

    private func runAdjacentChapterJump(
        to chapter: MangaChapter,
        source: MangaChapterTransitionSource,
        generation: Int
    ) async {
        do {
            let document = try await self.withTimeout(nanoseconds: self.chapterTransitionTimeoutNanoseconds) {
                do {
                    return try await self.withTimeout(nanoseconds: self.chapterLoadTimeoutNanoseconds) {
                        try await self.loadDocument(for: chapter.url, htmlOverride: nil)
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return try await self.loadDocumentViaProbe(for: chapter)
                }
            }

            try Task.checkCancellation()
            guard generation == chapterJumpGeneration else { return }

            applyLoadedChapterDocument(document, animated: false, resetRevision: true)
            chapterTransitionState = .idle
            errorMessage = nil
        } catch is CancellationError {
            guard generation == chapterJumpGeneration else { return }
            chapterTransitionState = .idle
        } catch {
            guard generation == chapterJumpGeneration else { return }
            errorMessage = error.localizedDescription
            chapterTransitionState = .idle
            emitNavigationRequest(
                .fallbackWeb(
                    makeWebFallbackContext(
                        currentURL: chapter.url,
                        initialPage: 0
                    )
                )
            )
        }
    }

    private func applyLoadedChapterDocument(
        _ document: MangaChapterDocument,
        animated: Bool,
        resetRevision: Bool
    ) {
        let position = MangaReadingPosition(tid: document.tid, localIndex: 0)
        guard let result = chapterWindow?.insertAdjacentDocument(document, preserving: position) else { return }

        let snapshot: MangaChapterWindowSnapshot
        switch result {
        case let .changed(changedSnapshot):
            snapshot = changedSnapshot
        case let .unchanged(unchangedSnapshot, reason):
            if reason == .duplicateChapter {
                snapshot = unchangedSnapshot
            } else if let resetSnapshot = chapterWindow?.reset(to: document, position: position) {
                snapshot = resetSnapshot
            } else {
                return
            }
        }
        applyWindowSnapshot(snapshot, animated: animated, resetRevision: resetRevision)
    }

    private func loadDocumentViaProbe(for chapter: MangaChapter) async throws -> MangaChapterDocument {
        let outcome = await chapterProbe(makeNativeLaunchContext(for: chapter))
        switch outcome {
        case let .success(payload):
            guard !payload.images.isEmpty else {
                throw YamiboError.parsingFailed(context: L10n.string("context.manga_images"))
            }
            let title = MangaTitleCleaner.cleanThreadTitle(
                payload.title.isEmpty ? chapter.rawTitle : payload.title
            )
            return MangaChapterDocument(
                tid: chapter.tid,
                ownerPostID: MangaHTMLParser.extractFirstPostID(from: payload.html ?? "") ?? chapter.tid,
                chapterTitle: title,
                chapterURL: YamiboRoute.thread(url: chapter.url, page: 1, authorID: nil).url,
                pages: payload.images,
                html: payload.html ?? ""
            )
        case let .fallback(reason, _):
            switch reason {
            case .retryableNetwork:
                throw YamiboError.underlying(L10n.string("manga.chapter_load_timeout"))
            case .timeout:
                throw YamiboError.underlying(L10n.string("manga.chapter_load_timeout"))
            case .notManga:
                throw YamiboError.parsingFailed(context: L10n.string("context.current_page_not_manga_chapter"))
            case .noImages:
                throw YamiboError.parsingFailed(context: L10n.string("context.manga_images"))
            case .webProcessTerminated:
                throw YamiboError.underlying(L10n.string("manga.chapter_probe_failed"))
            }
        }
    }

    private func makeNativeLaunchContext(for chapter: MangaChapter) -> MangaLaunchContext {
        MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: chapter.url,
            displayTitle: currentDirectoryTitle,
            source: context.source,
            initialPage: 0,
            directoryName: currentDirectory?.cleanBookName
        )
    }

    private func emitNavigationRequest(_ request: MangaReaderNavigationRequest) {
        chapterJumpTask?.cancel()
        chapterTransitionState = .idle
        navigationRequest = request
    }

    private func currentProgressSnapshot() -> MangaProgressSnapshot? {
        guard let currentPage else { return nil }
        return MangaProgressSnapshot(
            chapterURL: currentPage.chapterURL,
            chapterTitle: currentPage.chapterTitle,
            pageIndex: currentPage.localIndex
        )
    }

    private func scheduleProgressSync() {
        guard let snapshot = currentProgressSnapshot() else { return }
        guard snapshot != lastQueuedProgress else { return }

        lastQueuedProgress = snapshot
        progressSyncTask?.cancel()
        progressSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.progressSyncDelayNanoseconds ?? 0)
            guard !Task.isCancelled else { return }
            await self?.flushProgress()
        }
    }

    private func flushProgress() async {
        progressSyncTask?.cancel()
        progressSyncTask = nil

        guard let snapshot = currentProgressSnapshot() else { return }
        guard snapshot != lastSyncedProgress else {
            lastQueuedProgress = snapshot
            await persistSettings()
            return
        }

        do {
            _ = try await appContext.favoriteStore.updateMangaProgress(
                for: context.originalThreadURL,
                chapterURL: snapshot.chapterURL,
                chapterTitle: snapshot.chapterTitle,
                pageIndex: snapshot.pageIndex,
                createIfMissing: false
            )
        } catch {
            await persistSettings()
            return
        }
        lastQueuedProgress = snapshot
        lastSyncedProgress = snapshot
        await persistSettings()
    }

    private func withTimeout<T: Sendable>(
        nanoseconds: UInt64,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: nanoseconds)
                throw YamiboError.underlying(L10n.string("manga.chapter_load_timeout"))
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    public func makeWebFallbackContext(currentURL: URL, initialPage: Int) -> MangaWebContext {
        MangaWebContext(
            currentURL: currentURL,
            originalThreadURL: context.originalThreadURL,
            source: context.source,
            initialPage: initialPage,
            autoOpenNative: false,
            waitingForNativeReturn: false
        )
    }

    private func persistSettings(
        mangaSettings: MangaReaderSettings? = nil,
        applePencilPageTurnSettings: ApplePencilPageTurnSettings? = nil
    ) async {
        var appSettings = await appContext.settingsStore.load()
        appSettings.manga = mangaSettings ?? settings
        if let applePencilPageTurnSettings {
            appSettings.applePencilPageTurn = applePencilPageTurnSettings
        }
        try? await appContext.settingsStore.save(appSettings)
    }

    private func shouldAutoUpdateDirectory(_ directory: MangaDirectory) -> Bool {
        directory.strategy == .tag && directory.lastUpdatedAt == nil
    }

    private func handleDirectoryUpdateSuccess(
        result: MangaDirectoryUpdateResult,
        isForcedSearch: Bool
    ) {
        if isForcedSearch || result.searchPerformed {
            startDirectoryCooldown(seconds: 20)
        } else if result.directory.strategy == .tag {
            showForceSearchShortcut(duration: 5)
        }
    }

    private func handleDirectoryUpdateFailure(_ error: Error) {
        switch error {
        case let YamiboError.searchCooldown(seconds):
            startDirectoryCooldown(seconds: seconds)
        default:
            startDirectoryCooldown(seconds: 5)
        }
    }

    private func startDirectoryCooldown(seconds: Int) {
        directoryCooldownTask?.cancel()
        clearDirectoryShortcutState()
        directoryCooldownRemaining = max(0, seconds)
        guard seconds > 0 else { return }

        directoryCooldownTask = Task {
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                directoryCooldownRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
            if !Task.isCancelled {
                directoryCooldownRemaining = 0
            }
        }
    }

    private func showForceSearchShortcut(duration: Int) {
        forceSearchShortcutTask?.cancel()
        directoryCooldownTask?.cancel()
        directoryCooldownRemaining = 0
        showsForceSearchShortcut = true
        forceSearchShortcutRemaining = max(0, duration)
        guard duration > 0 else { return }

        forceSearchShortcutTask = Task {
            var remaining = duration
            while remaining > 0, !Task.isCancelled {
                showsForceSearchShortcut = true
                forceSearchShortcutRemaining = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
            if !Task.isCancelled {
                clearDirectoryShortcutState()
            }
        }
    }

    private func clearDirectoryShortcutState() {
        forceSearchShortcutTask?.cancel()
        showsForceSearchShortcut = false
        forceSearchShortcutRemaining = 0
    }

    public func makeDirectoryEditDraft() -> MangaDirectoryEditDraft {
        let title = currentDirectoryTitle
        let primaryKeyword = resolvedPrimaryDirectoryKeyword()
        return MangaDirectoryEditDraft(
            title: title,
            primaryKeyword: primaryKeyword,
            secondaryKeyword: ""
        )
    }

    private func resolvedPrimaryDirectoryKeyword() -> String {
        guard let currentDirectory else { return "" }
        if let searchKeyword = currentDirectory.searchKeyword?.trimmingCharacters(in: .whitespacesAndNewlines),
           !searchKeyword.isEmpty
        {
            let strippedKeyword = searchKeyword
                .replacingOccurrences(
                    of: currentDirectory.cleanBookName,
                    with: "",
                    options: [.caseInsensitive]
                )
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !strippedKeyword.isEmpty, strippedKeyword != searchKeyword {
                return strippedKeyword
            }
        }

        let seedTitle = currentDirectory.chapters.first(where: { $0.tid == currentPage?.tid })?.rawTitle
            ?? currentDirectory.chapters.last?.rawTitle
            ?? currentDirectory.cleanBookName
        return MangaTitleCleaner.extractAuthorPrefix(seedTitle)
    }

    private func webViewPage(from url: URL) -> Int {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "page" })?
            .value
            .flatMap(Int.init) ?? 1
    }
}

private struct MangaProgressSnapshot: Equatable {
    let chapterURL: URL
    let chapterTitle: String
    let pageIndex: Int
}

public struct MangaDirectoryEditDraft: Equatable, Sendable {
    public var title: String
    public var primaryKeyword: String
    public var secondaryKeyword: String

    public init(title: String, primaryKeyword: String, secondaryKeyword: String) {
        self.title = title
        self.primaryKeyword = primaryKeyword
        self.secondaryKeyword = secondaryKeyword
    }
}
