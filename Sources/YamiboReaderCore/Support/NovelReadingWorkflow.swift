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

    public init(
        snapshot: NovelReadingSnapshot,
        currentAuthorID: String?,
        cachedViews: Set<Int> = []
    ) {
        self.snapshot = snapshot
        self.currentAuthorID = currentAuthorID
        self.cachedViews = cachedViews
    }
}

public actor NovelReadingWorkflow {
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

    public init(
        context: ReaderLaunchContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        repository: any NovelReadingPageRepository,
        usesPadPresentation: Bool = false
    ) {
        self.context = context
        self.settings = settings
        self.layout = layout
        self.repository = repository
        self.usesPadPresentation = usesPadPresentation
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
        session = NovelReadingSession(
            document: document,
            settings: settings,
            layout: layout,
            preferredPage: preferredPage,
            resumePoint: preferredResumePoint,
            usesPadPresentation: usesPadPresentation,
            currentAuthorID: currentAuthorID
        )
        return await updateStateFromSession(refreshCachedViews: true)
    }

    private func updateStateFromSession(refreshCachedViews: Bool) async -> NovelReadingWorkflowState {
        guard let snapshot = session?.snapshot else {
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
        let nextState = NovelReadingWorkflowState(
            snapshot: snapshot,
            currentAuthorID: currentAuthorID,
            cachedViews: cachedViews
        )
        state = nextState
        return nextState
    }

    private func inferredContentSource(for authorID: String?) -> ReaderContentSource {
        let normalizedAuthorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedAuthorID.isEmpty ? .fallbackUnfilteredPage : .authorFilteredPage
    }
}
