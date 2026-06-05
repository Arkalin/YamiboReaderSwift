import Foundation

public protocol NovelReadingPageRepository: Sendable {
    func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument
    func loadPageIgnoringCache(_ request: ReaderPageRequest) async throws -> ReaderPageDocument
    func cachedViews(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> Set<Int>
    func deleteCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws
}

extension ReaderRepository: NovelReadingPageRepository {}

public struct NovelReadingInitialPosition: Equatable, Sendable {
    public var resumePoint: ReaderResumePoint?
    public var favoriteAuthorID: String?

    public init(resumePoint: ReaderResumePoint? = nil, favoriteAuthorID: String? = nil) {
        self.resumePoint = resumePoint
        self.favoriteAuthorID = favoriteAuthorID
    }
}

public struct NovelReadingCacheContext: Equatable, Sendable {
    public var authorID: String?
    public var contentSource: ReaderContentSource?

    public init(authorID: String?, contentSource: ReaderContentSource?) {
        self.authorID = authorID
        self.contentSource = contentSource
    }
}

public struct NovelReadingWorkflowState: Equatable, Sendable {
    public var snapshot: NovelReadingSnapshot
    public var currentAuthorID: String?
    public var cachedViews: Set<Int>
    public var currentDocument: ReaderPageDocument
    public var prefetchedDocument: ReaderPageDocument?

    public init(
        snapshot: NovelReadingSnapshot,
        currentAuthorID: String?,
        cachedViews: Set<Int> = [],
        currentDocument: ReaderPageDocument,
        prefetchedDocument: ReaderPageDocument? = nil
    ) {
        self.snapshot = snapshot
        self.currentAuthorID = currentAuthorID
        self.cachedViews = cachedViews
        self.currentDocument = currentDocument
        self.prefetchedDocument = prefetchedDocument
    }
}

@MainActor
public final class NovelReadingWorkflow {
    public private(set) var state: NovelReadingWorkflowState?

    private let context: ReaderLaunchContext
    private var settings: ReaderAppearanceSettings
    private var layout: ReaderContainerLayout
    private let repository: any NovelReadingPageRepository
    private var session: NovelReadingSession?
    private var currentDocument: ReaderPageDocument?
    private var prefetchedDocument: ReaderPageDocument?
    private var currentAuthorID: String?
    private var currentDocumentPageCount = 0
    private var usesPadPresentation: Bool
    private let pagination: NovelTextPagination
    private let viewportRuntime = NovelTextViewportRuntimeOwner()

    public var runtimeDiagnostics: NovelTextViewportRuntimeDiagnostics {
        viewportRuntime.diagnostics
    }

    public init(
        context: ReaderLaunchContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        repository: any NovelReadingPageRepository,
        usesPadPresentation: Bool = false,
        pagination: @escaping NovelTextPagination = NovelTextLayout.layout
    ) {
        self.context = context
        self.settings = settings
        self.layout = layout
        self.repository = repository
        self.usesPadPresentation = usesPadPresentation
        self.pagination = pagination
    }

    @discardableResult
    public func start(initial: NovelReadingInitialPosition) async throws -> NovelReadingWorkflowState {
        let resumePoint = initial.resumePoint
        let initialView = resumePoint?.view ?? context.initialView ?? 1
        let preferredPage = resumePoint == nil ? max(0, context.initialPage ?? 0) : 0
        currentAuthorID = resumePoint?.authorID ?? initial.favoriteAuthorID ?? context.authorID
        return try await load(
            view: initialView,
            preferredPage: preferredPage,
            preferredResumePoint: resumePoint,
            forceRefresh: false
        )
    }

    @discardableResult
    public func loadCurrent(
        preferredPage: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async throws -> NovelReadingWorkflowState {
        let view = state?.snapshot.currentView ?? context.initialView ?? 1
        return try await loadView(
            view,
            preferredPage: preferredPage,
            preferredResumePoint: preferredResumePoint,
            forceRefresh: forceRefresh
        )
    }

    @discardableResult
    public func loadView(
        _ view: Int,
        preferredPage: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async throws -> NovelReadingWorkflowState {
        return try await load(
            view: view,
            preferredPage: preferredPage,
            preferredResumePoint: preferredResumePoint,
            forceRefresh: forceRefresh
        )
    }

    public func cacheContext(forView view: Int) -> NovelReadingCacheContext {
        if let currentDocument, currentDocument.view == view {
            return cacheContext(for: currentDocument)
        }

        if let prefetchedDocument, prefetchedDocument.view == view {
            return cacheContext(for: prefetchedDocument)
        }

        let authorID = currentAuthorID ?? context.authorID
        let contentSource = state?.snapshot.currentContentSource
        return NovelReadingCacheContext(
            authorID: authorID,
            contentSource: contentSource == .allPostsPage ? inferredContentSource(for: authorID) : contentSource
        )
    }

    @discardableResult
    public func updateSettings(_ settings: ReaderAppearanceSettings) throws -> NovelReadingWorkflowState? {
        let oldSettings = self.settings
        self.settings = settings
        do {
            try session?.applySettings(settings)
            return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
        } catch {
            self.settings = oldSettings
            throw error
        }
    }

    @discardableResult
    public func updateLayout(_ layout: ReaderContainerLayout) throws -> NovelReadingWorkflowState? {
        let oldLayout = self.layout
        self.layout = layout
        do {
            try session?.updateLayout(layout)
            return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
        } catch {
            self.layout = oldLayout
            throw error
        }
    }

    @discardableResult
    public func updatePagedPresentationEnvironment(isPad: Bool) throws -> NovelReadingWorkflowState? {
        let oldUsesPadPresentation = usesPadPresentation
        usesPadPresentation = isPad
        do {
            try session?.updatePagedPresentationEnvironment(isPad: isPad)
            return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
        } catch {
            usesPadPresentation = oldUsesPadPresentation
            throw error
        }
    }

    @discardableResult
    public func jumpToRenderedPage(_ pageIndex: Int) -> NovelReadingWorkflowState? {
        session?.jumpToRenderedPage(pageIndex)
        return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    @discardableResult
    public func updateVerticalViewportPosition(
        pageIndex: Int,
        intraPageProgress: Double
    ) -> NovelReadingWorkflowState? {
        session?.updateVerticalViewportPosition(
            pageIndex: pageIndex,
            intraPageProgress: intraPageProgress
        )
        return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    @discardableResult
    public func updateVerticalViewportPosition(
        sample: NovelTextViewportSample
    ) -> NovelReadingWorkflowState? {
        session?.updateVerticalViewportPosition(sample: sample)
        return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    @discardableResult
    public func jumpRelativePage(_ delta: Int) -> (state: NovelReadingWorkflowState, request: NovelReadingNavigationRequest?)? {
        guard session != nil else { return nil }
        let request = session?.jumpRelativePage(delta)
        guard let state = updateStateFromSession(cachedViews: state?.cachedViews ?? []) else { return nil }
        return (state, request)
    }

    public func captureNovelReadingPosition() -> ReaderResumePoint? {
        session?.captureNovelReadingPosition()
    }

    public func currentProgressPosition() -> NovelReadingPosition {
        let resumePoint = captureNovelReadingPosition()
        let snapshot = state?.snapshot
        let view = currentDisplayedView(in: snapshot) ?? resumePoint?.view ?? context.initialView ?? 1
        return NovelReadingPosition(
            threadURL: context.threadURL,
            view: view,
            page: currentDisplayedPageIndex(in: snapshot, view: view),
            chapterTitle: resumePoint?.chapterTitle ?? snapshot?.currentChapterTitle,
            authorID: resumePoint?.authorID ?? snapshot?.currentAuthorID ?? currentAuthorID ?? context.authorID,
            resumePoint: resumePoint
        )
    }

    public func currentPreviewSourceText() -> String {
        session?.currentPreviewSourceText() ?? ""
    }

    public func displayReference(for pageIdentity: Int) -> NovelTextViewportDisplayReference? {
        viewportRuntime.displayReference(for: pageIdentity)
    }

    private func cacheContext(for document: ReaderPageDocument) -> NovelReadingCacheContext {
        switch document.contentSource {
        case .authorFilteredPage:
            let authorID = document.resolvedAuthorID ?? currentAuthorID ?? context.authorID
            return NovelReadingCacheContext(authorID: authorID, contentSource: .authorFilteredPage)
        case .fallbackUnfilteredPage:
            return NovelReadingCacheContext(authorID: nil, contentSource: .fallbackUnfilteredPage)
        case .allPostsPage:
            let authorID = document.resolvedAuthorID ?? currentAuthorID ?? context.authorID
            return NovelReadingCacheContext(
                authorID: authorID,
                contentSource: inferredContentSource(for: authorID)
            )
        }
    }

    private func currentDisplayedView(in snapshot: NovelReadingSnapshot?) -> Int? {
        guard let snapshot else { return nil }
        let normalizedIndex = currentPageIndex(in: snapshot)
        guard snapshot.pages.indices.contains(normalizedIndex) else {
            return snapshot.currentView
        }
        return snapshot.pages[normalizedIndex].documentView
    }

    private func currentDisplayedPageIndex(in snapshot: NovelReadingSnapshot?, view: Int) -> Int {
        guard let snapshot else { return max(context.initialPage ?? 0, 0) }
        let normalizedIndex = currentPageIndex(in: snapshot)
        guard let firstIndex = snapshot.pages.firstIndex(where: { $0.documentView == view }) else {
            return max(normalizedIndex, 0)
        }
        return max(normalizedIndex - firstIndex, 0)
    }

    private func currentPageIndex(in snapshot: NovelReadingSnapshot) -> Int {
        max(0, min(snapshot.currentPageIndex, max(snapshot.pages.count - 1, 0)))
    }

    @discardableResult
    public func prefetchIfNeeded(forPageIndex pageIndex: Int) async -> NovelReadingWorkflowState? {
        guard let currentDocument else { return nil }
        guard currentDocument.view < currentDocument.maxView else { return nil }
        let thresholdIndex = max(currentDocumentPageCount - 2, 0)
        guard pageIndex >= thresholdIndex else { return nil }
        if let prefetchedDocument, prefetchedDocument.view == currentDocument.view + 1 {
            return nil
        }

        let nextRequest = ReaderPageRequest(
            threadURL: context.threadURL,
            view: currentDocument.view + 1,
            authorID: currentAuthorID ?? currentDocument.resolvedAuthorID ?? context.authorID
        )
        guard let nextDocument = try? await repository.loadPage(nextRequest) else { return nil }

        prefetchedDocument = nextDocument
        currentAuthorID = nextDocument.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        session?.acceptPrefetchedDocument(nextDocument)
        return await updateStateFromSession(refreshCachedViews: false)
    }

    @discardableResult
    public func promotePrefetchedDocument(
        preferredPage: Int,
        resumePoint: ReaderResumePoint?
    ) async throws -> NovelReadingWorkflowState? {
        guard let nextDocument = prefetchedDocument else { return nil }
        let previousDocument = currentDocument
        let previousPrefetchedDocument = prefetchedDocument
        let previousAuthorID = currentAuthorID
        currentDocument = nextDocument
        prefetchedDocument = nil
        currentAuthorID = nextDocument.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        let resumePoint = resumePoint?.view == nextDocument.view ? resumePoint : nil
        do {
            try session?.promotePrefetchedDocument(preferredPage: preferredPage, resumePoint: resumePoint)
            return updateStateFromSession(cachedViews: state?.cachedViews ?? [])
        } catch {
            currentDocument = previousDocument
            prefetchedDocument = previousPrefetchedDocument
            currentAuthorID = previousAuthorID
            throw error
        }
    }

    private func load(
        view: Int,
        preferredPage: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async throws -> NovelReadingWorkflowState {
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
        let preservedResumePoint = preferredResumePoint ?? captureNovelReadingPosition()
        session = try NovelReadingSession(
            validating: document,
            settings: settings,
            layout: layout,
            preferredPage: preferredPage,
            resumePoint: preservedResumePoint,
            usesPadPresentation: usesPadPresentation,
            currentAuthorID: currentAuthorID,
            pagination: pagination
        )
        return await updateStateFromSession(refreshCachedViews: true)
    }

    private func updateStateFromSession(refreshCachedViews: Bool) async -> NovelReadingWorkflowState {
        guard let snapshot = session?.snapshot,
              currentDocument != nil else {
            preconditionFailure("Novel reading workflow has no active session")
        }
        currentAuthorID = snapshot.currentAuthorID ?? currentAuthorID
        currentDocumentPageCount = snapshot.pages.filter { $0.documentView == snapshot.currentView }.count
        let cachedViews = if refreshCachedViews {
            await repository.cachedViews(
                for: context.threadURL,
                authorID: cacheContext(forView: snapshot.currentView).authorID,
                contentSource: cacheContext(forView: snapshot.currentView).contentSource
            )
        } else {
            state?.cachedViews ?? []
        }
        guard let nextState = updateStateFromSession(cachedViews: cachedViews) else {
            preconditionFailure("Novel reading workflow has no active session")
        }
        return nextState
    }

    private func updateStateFromSession(cachedViews: Set<Int>) -> NovelReadingWorkflowState? {
        guard let snapshot = session?.snapshot,
              let currentDocument else {
            return nil
        }
        if let viewportContext = snapshot.viewportContext,
           let viewportIndex = snapshot.viewportIndex {
            viewportRuntime.commit(
                result: NovelTextLayoutResult(
                    viewportContext: viewportContext,
                    viewportIndex: viewportIndex,
                    layoutMetrics: snapshot.viewportLayoutMetrics ?? NovelTextViewportLayoutMetrics()
                ),
                settings: settings,
                layout: layout
            )
        }
        currentAuthorID = snapshot.currentAuthorID ?? currentAuthorID
        currentDocumentPageCount = snapshot.pages.filter { $0.documentView == snapshot.currentView }.count
        let nextState = NovelReadingWorkflowState(
            snapshot: snapshot,
            currentAuthorID: currentAuthorID,
            cachedViews: cachedViews,
            currentDocument: currentDocument,
            prefetchedDocument: prefetchedDocument
        )
        state = nextState
        return nextState
    }

    private func inferredContentSource(for authorID: String?) -> ReaderContentSource {
        let normalizedAuthorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedAuthorID.isEmpty ? .fallbackUnfilteredPage : .authorFilteredPage
    }
}
