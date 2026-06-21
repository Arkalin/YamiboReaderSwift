import Foundation

public struct MangaAdjacentChapterPrefetchPolicy: Hashable, Sendable {
    public var nextTriggerDistanceFromEnd: Int
    public var previousTriggerMaximumIndex: Int

    public init(
        nextTriggerDistanceFromEnd: Int = 6,
        previousTriggerMaximumIndex: Int = 2
    ) {
        self.nextTriggerDistanceFromEnd = max(0, nextTriggerDistanceFromEnd)
        self.previousTriggerMaximumIndex = max(0, previousTriggerMaximumIndex)
    }

    public func triggeredDeltas(globalIndex: Int, pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }

        let normalizedIndex = min(max(globalIndex, 0), pageCount - 1)
        var deltas: [Int] = []
        if normalizedIndex >= pageCount - nextTriggerDistanceFromEnd {
            deltas.append(1)
        }
        if normalizedIndex <= previousTriggerMaximumIndex {
            deltas.append(-1)
        }
        return deltas
    }
}

@MainActor
public final class MangaReaderWorkflow {
    public private(set) var presentation: MangaReaderPresentation
    public private(set) var shouldAutoUpdateDirectoryAfterPrepare = false

    private let context: MangaLaunchContext
    private let documentLoader: any MangaChapterDocumentLoading
    private let directoryWorkflow: MangaDirectoryWorkflow
    private let adjacentPrefetchPolicy: MangaAdjacentChapterPrefetchPolicy
    private var window: MangaChapterWindow?
    private var settings: MangaReaderSettings
    private var directoryPanelCommandState = MangaDirectoryPanelCommandState()
    private var viewportPlacementRevision = 0
    private var currentViewportPlacement: MangaReaderViewportPlacement?

    public init(
        context: MangaLaunchContext,
        documentLoader: any MangaChapterDocumentLoading,
        directoryRepository: any MangaDirectoryRepository,
        directoryStore: any MangaDirectoryPersisting,
        settings: MangaReaderSettings = MangaReaderSettings(),
        directoryWorkflowConfiguration: MangaDirectoryWorkflowConfiguration = MangaDirectoryWorkflowConfiguration(),
        directorySearchCooldownState: MangaDirectorySearchCooldownState = MangaDirectorySearchCooldownState(),
        adjacentPrefetchPolicy: MangaAdjacentChapterPrefetchPolicy = MangaAdjacentChapterPrefetchPolicy()
    ) {
        self.context = context
        self.documentLoader = documentLoader
        self.adjacentPrefetchPolicy = adjacentPrefetchPolicy
        self.directoryWorkflow = MangaDirectoryWorkflow(
            repository: directoryRepository,
            store: directoryStore,
            configuration: directoryWorkflowConfiguration,
            searchCooldownState: directorySearchCooldownState
        )
        self.settings = settings
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context))),
            settings: settings
        )
    }

    @discardableResult
    public func prepare() async -> MangaReaderPresentation {
        window = nil
        shouldAutoUpdateDirectoryAfterPrepare = false
        directoryPanelCommandState = MangaDirectoryPanelCommandState()
        presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context))),
            settings: settings
        )

        do {
            let document = try await documentLoader.loadChapterDocument(at: context.chapterURL)
            let resolution = try await directoryWorkflow.resolveInitialDirectory(
                context: context,
                document: document
            )
            let directory = resolution.directory
            let requestedPosition = MangaReadingPosition(
                tid: document.tid,
                localIndex: context.initialPage
            )
            let window = MangaChapterWindow(
                directory: directory,
                initialDocument: document,
                position: requestedPosition
            )
            self.window = window
            shouldAutoUpdateDirectoryAfterPrepare = resolution.shouldAutoUpdateAfterInitialLoad
            presentation = loadedPresentation(from: window, placementPageIndex: MangaReaderPageProjection.resolvedPageIndex(for: window))
        } catch {
            window = nil
            presentation = MangaReaderPresentation(
                state: .failed(
                    MangaReaderErrorPresentation(
                        title: L10n.string("common.load_failed"),
                        message: error.localizedDescription
                    )
                ),
                settings: settings
            )
        }

        return presentation
    }

    @discardableResult
    public func moveToLoadedPage(at globalIndex: Int) -> MangaReaderPresentation {
        guard var window else { return presentation }
        _ = window.moveToLoadedPage(at: globalIndex)
        self.window = window
        presentation = loadedPresentation(from: window)
        return presentation
    }

    @discardableResult
    public func jumpToLoadedPage(at globalIndex: Int) -> MangaReaderPresentation {
        guard var window else { return presentation }
        _ = window.moveToLoadedPage(at: globalIndex)
        self.window = window
        presentation = loadedPresentation(
            from: window,
            placementPageIndex: MangaReaderPageProjection.resolvedPageIndex(for: window)
        )
        return presentation
    }

    @discardableResult
    public func prefetchAdjacentChaptersIfNeeded(around globalIndex: Int) async -> MangaReaderPresentation? {
        guard var window else { return nil }

        let pages = MangaReaderPageProjection.projections(from: window)
        let deltas = adjacentPrefetchPolicy.triggeredDeltas(
            globalIndex: globalIndex,
            pageCount: pages.count
        )
        guard !deltas.isEmpty else { return nil }

        let preservedPosition = window.resolvedPosition
        var didChange = false
        for delta in deltas {
            guard !Task.isCancelled else { return nil }
            guard let chapter = window.adjacentChapterForLoadedRange(delta: delta) else { continue }
            let document: MangaChapterDocument
            do {
                document = try await documentLoader.loadChapterDocument(at: chapter.url)
            } catch {
                guard !Task.isCancelled else { return nil }
                continue
            }
            guard !Task.isCancelled else { return nil }

            let result = window.insertAdjacentDocument(document, preserving: preservedPosition)
            if case .changed = result {
                didChange = true
            }
        }

        guard didChange else { return nil }

        self.window = window
        let currentIndex = MangaReaderPageProjection.resolvedPageIndex(for: window)
        presentation = loadedPresentation(from: window, placementPageIndex: currentIndex)
        return presentation
    }

    @discardableResult
    public func applySettings(_ settings: MangaReaderSettings) -> MangaReaderPresentation {
        self.settings = settings
        if let window {
            presentation = loadedPresentation(from: window)
        } else {
            presentation.settings = settings
        }
        return presentation
    }

    @discardableResult
    public func updateDirectoryPanelCommandState(
        _ state: MangaDirectoryPanelCommandState
    ) -> MangaReaderPresentation {
        directoryPanelCommandState = state
        if let window {
            presentation = loadedPresentation(from: window)
        }
        return presentation
    }

    @discardableResult
    public func updateDirectory(isForcedSearch: Bool = false) async throws -> MangaDirectoryUpdateResult {
        try Task.checkCancellation()

        guard var window else {
            throw YamiboError.underlying("Manga reader workflow is not prepared.")
        }
        let result = try await directoryWorkflow.updateDirectory(
            window.directory,
            currentTID: window.resolvedPosition?.tid,
            isForcedSearch: isForcedSearch
        )
        try Task.checkCancellation()

        let position = window.resolvedPosition
        _ = window.updateDirectory(result.directory, preserving: position)
        self.window = window
        presentation = loadedPresentation(from: window)
        return result
    }

    @discardableResult
    public func renameDirectory(
        cleanBookName: String,
        searchKeyword: String
    ) async throws -> MangaDirectory {
        guard var window else {
            throw YamiboError.underlying("Manga reader workflow is not prepared.")
        }
        let updated = try await directoryWorkflow.renameDirectory(
            window.directory,
            cleanBookName: cleanBookName,
            searchKeyword: searchKeyword
        )
        let position = window.resolvedPosition
        _ = window.updateDirectory(updated, preserving: position)
        self.window = window
        presentation = loadedPresentation(from: window)
        return updated
    }

    @discardableResult
    public func deleteDirectoryChapters(tids: Set<String>) async throws -> MangaReaderPresentation {
        try Task.checkCancellation()

        guard var window else {
            throw YamiboError.underlying("Manga reader workflow is not prepared.")
        }

        let targetTIDs = Set(tids.compactMap(Self.normalizedNonEmpty))
        guard !targetTIDs.isEmpty else { return presentation }
        if let currentTID = window.resolvedPosition?.tid,
           targetTIDs.contains(currentTID) {
            return presentation
        }

        let position = window.resolvedPosition
        let updated = try await directoryWorkflow.deleteChapters(window.directory, tids: targetTIDs)
        try Task.checkCancellation()

        _ = window.updateDirectory(updated, preserving: position)
        _ = window.removeLoadedDocuments(withTIDs: targetTIDs, preserving: position)
        self.window = window
        let currentIndex = MangaReaderPageProjection.resolvedPageIndex(for: window)
        presentation = loadedPresentation(from: window, placementPageIndex: currentIndex)
        return presentation
    }

    @discardableResult
    public func jumpToChapter(_ chapter: MangaChapter) async throws -> MangaReaderPresentation {
        try Task.checkCancellation()

        guard var window else {
            throw YamiboError.underlying("Manga reader workflow is not prepared.")
        }

        let pages = MangaReaderPageProjection.projections(from: window)
        if let loadedIndex = pages.firstIndex(where: { $0.tid == chapter.tid && $0.localIndex == 0 }) {
            _ = window.moveToLoadedPage(at: loadedIndex)
            self.window = window
            presentation = loadedPresentation(from: window, placementPageIndex: loadedIndex)
            return presentation
        }

        let document = try await documentLoader.loadChapterDocument(at: chapter.url)
        try Task.checkCancellation()

        let targetPosition = MangaReadingPosition(tid: document.tid, localIndex: 0)
        let result = window.insertAdjacentDocument(document, preserving: targetPosition)
        switch result {
        case .changed:
            break
        case let .unchanged(_, reason):
            if reason != .duplicateChapter {
                _ = window.reset(to: document, position: targetPosition)
            }
        }

        self.window = window
        let targetIndex = MangaReaderPageProjection.resolvedPageIndex(for: window)
        presentation = loadedPresentation(from: window, placementPageIndex: targetIndex)
        return presentation
    }

    public func currentDirectorySearchCooldownExpiresAt() async -> Date? {
        await directoryWorkflow.cooldownExpiresAt()
    }

    private func loadedPresentation(
        from window: MangaChapterWindow,
        placementPageIndex: Int? = nil
    ) -> MangaReaderPresentation {
        let pages = MangaReaderPageProjection.projections(from: window)
        let currentPageIndex = MangaReaderPageProjection.resolvedPageIndex(for: window)
        let currentPage = currentPageIndex.flatMap { index in
            pages.indices.contains(index) ? pages[index] : nil
        }
        let viewportPlacement = placementPageIndex.map { index in
            nextViewportPlacement(targetPageIndex: index)
        } ?? currentViewportPlacement

        return MangaReaderPresentation(
            state: .loaded(
                MangaReaderLoadedPresentation(
                    title: Self.presentationTitle(for: context),
                    directoryTitle: window.directory.cleanBookName,
                    pages: pages,
                    currentPage: currentPage,
                    currentPageIndex: currentPageIndex,
                    readingPosition: window.resolvedPosition,
                    directoryPanel: directoryPanelPresentation(from: window),
                    viewportPlacement: viewportPlacement
                )
            ),
            settings: settings
        )
    }

    private func directoryPanelPresentation(from window: MangaChapterWindow) -> MangaDirectoryPanelPresentation {
        let displayChapters: [MangaChapter] = switch settings.directorySortOrder {
        case .ascending:
            window.directory.chapters
        case .descending:
            Array(window.directory.chapters.reversed())
        }
        let latestChapterText = MangaChapterDisplayFormatter.latestChapter(in: window.directory.chapters).map {
            L10n.string("manga.latest_chapter", MangaChapterDisplayFormatter.displayNumber(for: $0))
        }
        let forcedRemaining = directoryPanelCommandState.forcedSearchShortcutRemaining
        let isSearchMode = forcedRemaining != nil || window.directory.strategy != .tag
        let updateTitle: String
        if directoryPanelCommandState.isUpdating {
            updateTitle = L10n.string("common.updating")
        } else if directoryPanelCommandState.cooldownRemaining > 0 {
            updateTitle = "\(directoryPanelCommandState.cooldownRemaining)s"
        } else if let forcedRemaining {
            updateTitle = forcedRemaining > 0
                ? L10n.string("manga.global_search_countdown", forcedRemaining)
                : L10n.string("manga.global_search")
        } else if window.directory.strategy != .tag {
            updateTitle = L10n.string("manga.global_search")
        } else {
            updateTitle = L10n.string("reader.cache_action.update")
        }

        return MangaDirectoryPanelPresentation(
            directoryTitle: window.directory.cleanBookName,
            displayChapters: displayChapters,
            currentChapterTID: window.resolvedPosition?.tid,
            latestChapterText: latestChapterText,
            sortOrder: settings.directorySortOrder,
            updateButtonTitle: updateTitle,
            isUpdateButtonEnabled: !directoryPanelCommandState.isUpdating && directoryPanelCommandState.cooldownRemaining <= 0,
            isSearchMode: isSearchMode,
            shouldForceSearchOnUpdate: forcedRemaining != nil,
            isUpdating: directoryPanelCommandState.isUpdating,
            editDraft: directoryWorkflow.editDraft(for: window.directory, currentTID: window.resolvedPosition?.tid),
            errorMessage: directoryPanelCommandState.errorMessage
        )
    }

    private func nextViewportPlacement(targetPageIndex: Int) -> MangaReaderViewportPlacement {
        viewportPlacementRevision += 1
        let placement = MangaReaderViewportPlacement(
            targetPageIndex: targetPageIndex,
            animated: false,
            revision: viewportPlacementRevision
        )
        currentViewportPlacement = placement
        return placement
    }

    private static func presentationTitle(for context: MangaLaunchContext) -> String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.string("manga.reader.title") : title
    }

    private static func normalizedNonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
