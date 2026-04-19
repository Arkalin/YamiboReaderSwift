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

@MainActor
public final class MangaReaderModel: ObservableObject {
    @Published public private(set) var pages: [MangaPage] = []
    @Published public private(set) var currentDirectory: MangaDirectory?
    @Published public private(set) var isLoading = false
    @Published public var errorMessage: String?
    @Published public var settings = MangaReaderSettings()
    @Published public var currentPageIndex = 0
    @Published public private(set) var viewportRequest: MangaViewportRequest?
    @Published public private(set) var isUpdatingDirectory = false
    @Published public private(set) var directoryCooldownRemaining = 0
    @Published public private(set) var showsForceSearchShortcut = false
    @Published public private(set) var forceSearchShortcutRemaining = 0
    @Published public private(set) var chapterTransitionState: MangaChapterTransitionState = .idle
    @Published public private(set) var navigationRequest: MangaReaderNavigationRequest?

    public let context: MangaLaunchContext

    private let appContext: YamiboAppContext
    private let imageRepository: MangaImageRepository
    private let chapterProbe: @MainActor (MangaLaunchContext) async -> MangaProbeOutcome
    private var repository: MangaRepository?
    private var loadedDocuments: [MangaChapterDocument] = []
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

    public var progressLabelText: String {
        currentPageText
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
        guard let currentPage else { return "第 1 / 1 页" }
        let clampedIndex = clampedLocalPageIndex(for: localIndex)
        return "第 \(clampedIndex + 1) / \(max(1, currentPage.chapterTotalPages)) 页"
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
        return "最新: 第\(MangaChapterDisplayFormatter.displayNumber(for: latestChapter))话"
    }

    public var directoryUpdateButtonTitle: String {
        if isUpdatingDirectory {
            return "更新中"
        }
        if directoryCooldownRemaining > 0 {
            return "\(directoryCooldownRemaining)s"
        }
        if showsForceSearchShortcut {
            return forceSearchShortcutRemaining > 0
                ? "全局搜索 \(forceSearchShortcutRemaining)s"
                : "全局搜索"
        }
        if currentDirectory?.strategy != .tag {
            return "全局搜索"
        }
        return "更新"
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
        settings = await appContext.settingsStore.load().manga
        await loadInitialChapter()
    }

    public func retryCurrentChapter() async {
        errorMessage = nil
        await loadInitialChapter()
    }

    public func consumeNavigationRequest() {
        navigationRequest = nil
    }

    public func clearTransitionFailureIfNeeded() {
        if case .failed = chapterTransitionState {
            chapterTransitionState = .idle
        }
    }

    public func updateCurrentPage(_ index: Int) {
        guard !pages.isEmpty else { return }
        currentPageIndex = max(0, min(index, pages.count - 1))
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

    public func requestCurrentChapterPage(_ localIndex: Int, animated: Bool = true) {
        guard let currentPage else { return }
        let clampedLocalIndex = max(0, min(localIndex, max(0, currentPage.chapterTotalPages - 1)))
        guard let targetIndex = pages.firstIndex(where: {
            $0.chapterURL == currentPage.chapterURL && $0.localIndex == clampedLocalIndex
        }) else {
            return
        }
        currentPageIndex = targetIndex
        emitViewportRequest(targetIndex: targetIndex, animated: animated, resetRevision: false)
        scheduleImagePrefetch()
        Task {
            await prefetchIfNeeded(for: targetIndex)
        }
    }

    public func saveProgress() async {
        guard let currentPage else { return }
        _ = try? await appContext.favoriteStore.updateMangaProgress(
            for: context.originalThreadURL,
            chapterURL: currentPage.chapterURL,
            chapterTitle: currentPage.chapterTitle,
            pageIndex: currentPage.localIndex
        )
        await persistSettings()
    }

    public func applySettings(_ newSettings: MangaReaderSettings) {
        settings = newSettings
        Task {
            await persistSettings()
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
            chapterTransitionState = .failed(message: "当前章节状态异常，请重试")
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
            reorderDocumentsToMatchDirectory()
            rebuildPages(focus: currentFocusKey, animated: false, resetRevision: false)
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
            reorderDocumentsToMatchDirectory()
            rebuildPages(focus: currentFocusKey, animated: false, resetRevision: false)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var currentFocusKey: MangaFocusKey? {
        guard let currentPage else { return nil }
        return MangaFocusKey(chapterURL: currentPage.chapterURL, localIndex: currentPage.localIndex)
    }

    private func loadInitialChapter() async {
        chapterJumpTask?.cancel()
        chapterTransitionState = .idle
        navigationRequest = nil
        do {
            let document = try await loadDocument(for: context.chapterURL, htmlOverride: nil)
            loadedDocuments = [document]
            let directory = try await resolveDirectory(from: document)
            currentDirectory = directory
            reorderDocumentsToMatchDirectory()
            let initialLocalPage = max(0, context.initialPage)
            rebuildPages(
                focus: MangaFocusKey(chapterURL: document.chapterURL, localIndex: initialLocalPage),
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
            throw YamiboError.underlying("漫画仓储未初始化")
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
        guard let chapter = adjacentChapterForLoadedRange(delta: delta) else { return }
        guard firstPageIndex(for: chapter.url) == nil else { return }
        do {
            let focus = currentFocusKey
            let preservedTID = focus.map { MangaTitleCleaner.extractTid(from: $0.chapterURL.absoluteString) ?? $0.chapterURL.absoluteString }
            let document = try await loadDocument(for: chapter.url, htmlOverride: nil)
            if delta < 0 {
                loadedDocuments.insert(document, at: 0)
                trimLoadedDocumentsIfNeeded(
                    preferredRemoval: .back,
                    preservingTID: preservedTID ?? document.tid
                )
            } else {
                loadedDocuments.append(document)
                trimLoadedDocumentsIfNeeded(
                    preferredRemoval: .front,
                    preservingTID: preservedTID ?? document.tid
                )
            }
            reorderDocumentsToMatchDirectory()
            rebuildPages(focus: focus, animated: false, resetRevision: delta < 0)
        } catch {
            // Preload failures should not interrupt reading.
        }
    }

    private func reorderDocumentsToMatchDirectory() {
        guard let currentDirectory else { return }
        let order = Dictionary(uniqueKeysWithValues: currentDirectory.chapters.enumerated().map { ($1.tid, $0) })
        loadedDocuments.sort {
            (order[$0.tid] ?? .max) < (order[$1.tid] ?? .max)
        }
    }

    private func rebuildPages(
        focus: MangaFocusKey?,
        animated: Bool,
        resetRevision: Bool
    ) {
        var rebuilt: [MangaPage] = []
        rebuilt.reserveCapacity(loadedDocuments.reduce(0) { $0 + $1.pages.count })
        for document in loadedDocuments {
            for (localIndex, imageURL) in document.pages.enumerated() {
                rebuilt.append(
                    MangaPage(
                        tid: document.tid,
                        chapterTitle: document.chapterTitle,
                        imageURL: imageURL,
                        globalIndex: rebuilt.count,
                        localIndex: localIndex,
                        chapterTotalPages: document.pages.count,
                        chapterURL: document.chapterURL
                    )
                )
            }
        }
        let targetIndex: Int?
        if let focus {
            targetIndex = rebuilt.firstIndex(where: {
                $0.chapterURL == focus.chapterURL && $0.localIndex == focus.localIndex
            })
        } else {
            targetIndex = nil
        }

        pages = rebuilt

        guard !rebuilt.isEmpty else {
            currentPageIndex = 0
            viewportRequest = nil
            return
        }

        if let targetIndex {
            currentPageIndex = targetIndex
            emitViewportRequest(targetIndex: targetIndex, animated: animated, resetRevision: resetRevision)
        } else {
            currentPageIndex = max(0, min(currentPageIndex, rebuilt.count - 1))
            emitViewportRequest(
                targetIndex: currentPageIndex,
                animated: animated,
                resetRevision: resetRevision
            )
        }
        scheduleImagePrefetch()
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
        guard let currentPage, let currentDirectory else { return nil }
        guard let index = currentDirectory.chapters.firstIndex(where: { $0.tid == currentPage.tid }) else { return nil }
        let target = index + delta
        guard currentDirectory.chapters.indices.contains(target) else { return nil }
        return currentDirectory.chapters[target]
    }

    private func adjacentChapterForLoadedRange(delta: Int) -> MangaChapter? {
        guard let currentDirectory else { return nil }
        guard let anchorTID = delta < 0 ? loadedDocuments.first?.tid : loadedDocuments.last?.tid else { return nil }
        guard let index = currentDirectory.chapters.firstIndex(where: { $0.tid == anchorTID }) else { return nil }
        let target = index + delta
        guard currentDirectory.chapters.indices.contains(target) else { return nil }
        return currentDirectory.chapters[target]
    }

    private func shouldResetLoadedDocuments(for document: MangaChapterDocument) -> Bool {
        guard let currentDirectory,
              let targetIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == document.tid }),
              let currentPage,
              let currentIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == currentPage.tid }) else {
            return true
        }
        return abs(targetIndex - currentIndex) > 1
    }

    private func shouldInsertBeforeCurrent(_ document: MangaChapterDocument) -> Bool {
        guard let currentDirectory,
              let targetIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == document.tid }),
              let firstLoadedTID = loadedDocuments.first?.tid,
              let firstLoadedIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == firstLoadedTID }) else {
            return false
        }
        return targetIndex < firstLoadedIndex
    }

    private func firstPageIndex(for chapterURL: URL) -> Int? {
        pages.firstIndex(where: { $0.chapterURL == chapterURL && $0.localIndex == 0 })
    }

    private func trimLoadedDocumentsIfNeeded(
        preferredRemoval: LoadedDocumentRemovalSide,
        preservingTID: String
    ) {
        while loadedDocuments.count > maxLoadedDocuments {
            switch preferredRemoval {
            case .front:
                if loadedDocuments.first?.tid != preservingTID {
                    loadedDocuments.removeFirst()
                } else if loadedDocuments.last?.tid != preservingTID {
                    loadedDocuments.removeLast()
                } else {
                    return
                }
            case .back:
                if loadedDocuments.last?.tid != preservingTID {
                    loadedDocuments.removeLast()
                } else if loadedDocuments.first?.tid != preservingTID {
                    loadedDocuments.removeFirst()
                } else {
                    return
                }
            }
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

            insertLoadedDocument(document)
            rebuildPages(
                focus: MangaFocusKey(chapterURL: document.chapterURL, localIndex: 0),
                animated: false,
                resetRevision: true
            )
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

    private func insertLoadedDocument(_ document: MangaChapterDocument) {
        if shouldResetLoadedDocuments(for: document) {
            loadedDocuments = [document]
        } else if shouldInsertBeforeCurrent(document) {
            loadedDocuments.insert(document, at: 0)
            trimLoadedDocumentsIfNeeded(
                preferredRemoval: .back,
                preservingTID: document.tid
            )
        } else {
            loadedDocuments.append(document)
            trimLoadedDocumentsIfNeeded(
                preferredRemoval: .front,
                preservingTID: document.tid
            )
        }
    }

    private func loadDocumentViaProbe(for chapter: MangaChapter) async throws -> MangaChapterDocument {
        let outcome = await chapterProbe(makeNativeLaunchContext(for: chapter))
        switch outcome {
        case let .success(payload):
            guard !payload.images.isEmpty else {
                throw YamiboError.parsingFailed(context: "漫画图片")
            }
            let title = MangaTitleCleaner.cleanThreadTitle(
                payload.title.isEmpty ? chapter.rawTitle : payload.title
            )
            return MangaChapterDocument(
                tid: chapter.tid,
                chapterTitle: title,
                chapterURL: YamiboRoute.thread(url: chapter.url, page: 1, authorID: nil).url,
                pages: payload.images,
                html: payload.html ?? ""
            )
        case let .fallback(reason, _):
            switch reason {
            case .retryableNetwork:
                throw YamiboError.underlying("章节加载超时，请稍后重试")
            case .timeout:
                throw YamiboError.underlying("章节加载超时，请稍后重试")
            case .notManga:
                throw YamiboError.parsingFailed(context: "当前页面不是漫画章节")
            case .noImages:
                throw YamiboError.parsingFailed(context: "漫画图片")
            case .webProcessTerminated:
                throw YamiboError.underlying("章节探测失败，请切换网页模式重试")
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
                throw YamiboError.underlying("章节加载超时，请稍后重试")
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

    private func persistSettings() async {
        var appSettings = await appContext.settingsStore.load()
        appSettings.manga = settings
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

private struct MangaFocusKey {
    var chapterURL: URL
    var localIndex: Int
}

private enum LoadedDocumentRemovalSide {
    case front
    case back
}
