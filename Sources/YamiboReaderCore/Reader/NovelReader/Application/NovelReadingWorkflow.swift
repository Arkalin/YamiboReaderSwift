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

extension NovelReaderRepository: NovelReadingPageRepository {}

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

package struct NovelChapterAnchor: Hashable, Sendable {
    fileprivate let resumePoint: ReaderResumePoint
}

package struct NovelChapterDirectoryEntry: Hashable, Sendable {
    package let chapter: ReaderChapter
    package let anchor: NovelChapterAnchor?
}

public struct NovelReadingWorkflowState: Equatable, Sendable {
    package var snapshot: NovelReadingSnapshot
    public var presentation: NovelReaderPresentation?
    public var cachedViews: Set<Int>

    package init(
        snapshot: NovelReadingSnapshot,
        presentation: NovelReaderPresentation? = nil,
        cachedViews: Set<Int> = []
    ) {
        self.snapshot = snapshot
        self.presentation = presentation
        self.cachedViews = cachedViews
    }
}

public struct NovelReadingWorkflowRuntimeUpdate: Equatable, Sendable {
    public var settings: ReaderAppearanceSettings
    public var layout: ReaderContainerLayout
    public var usesPadPresentation: Bool

    public init(
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool
    ) {
        self.settings = settings
        self.layout = layout
        self.usesPadPresentation = usesPadPresentation
    }
}

package struct NovelReadingWorkflowDebugState: Equatable, Sendable {
    package var viewportSurfaces: [NovelTextViewportIndexSurface]
    package var fingerprints: NovelTextLayoutFingerprints?
    package var runtime: NovelTextViewportRuntimeDiagnostics
    package var transactions: NovelTextViewportRuntimeTransactionDiagnostics
}

public typealias NovelReadingWorkflowRuntimeUpdatePreparation = @Sendable (
    _ update: NovelReadingWorkflowRuntimeUpdate
) async throws -> NovelReadingWorkflowRuntimeUpdate

@MainActor
private struct NovelReadingPreparedTransaction {
    let runtime: NovelTextViewportRuntimeTransaction
    let session: NovelReadingSession
    let state: NovelReadingWorkflowState
    let settings: ReaderAppearanceSettings
    let layout: ReaderContainerLayout
    let usesPadPresentation: Bool
    let currentDocument: ReaderPageDocument
    let prefetchedDocument: ReaderPageDocument?
    let currentAuthorID: String?
    let currentDocumentSurfaceCount: Int
}

@MainActor
public final class NovelReadingWorkflow {
    public private(set) var state: NovelReadingWorkflowState?
    public private(set) var runtimeUpdateRequestSequence: UInt64 = 0

    private let context: ReaderLaunchContext
    private var settings: ReaderAppearanceSettings
    private var layout: ReaderContainerLayout
    private let repository: any NovelReadingPageRepository
    private var session: NovelReadingSession?
    private var currentDocument: ReaderPageDocument?
    private var prefetchedDocument: ReaderPageDocument?
    private var currentAuthorID: String?
    private var currentDocumentSurfaceCount = 0
    private var usesPadPresentation: Bool
    private let viewportRuntime: NovelTextViewportRuntimeOwner
    private var pendingRuntimeUpdateTask: Task<NovelReadingWorkflowState?, Error>?

    package var runtimeDiagnostics: NovelTextViewportRuntimeDiagnostics {
        viewportRuntime.diagnostics
    }

    package var runtimeTransactionDiagnostics: NovelTextViewportRuntimeTransactionDiagnostics {
        viewportRuntime.runtimeTransactionDiagnostics
    }

    package var debugState: NovelReadingWorkflowDebugState {
        NovelReadingWorkflowDebugState(
            viewportSurfaces: viewportRuntime.currentResult?.viewportIndex.surfaces ?? [],
            fingerprints: viewportRuntime.currentResult?.fingerprints,
            runtime: viewportRuntime.diagnostics,
            transactions: viewportRuntime.runtimeTransactionDiagnostics
        )
    }

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
        viewportRuntime = NovelTextViewportRuntimeOwner()
    }

    package init(
        context: ReaderLaunchContext,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        repository: any NovelReadingPageRepository,
        usesPadPresentation: Bool = false,
        runtimeAdapter: any NovelTextLayoutRuntimeAdapter
    ) {
        self.context = context
        self.settings = settings
        self.layout = layout
        self.repository = repository
        self.usesPadPresentation = usesPadPresentation
        viewportRuntime = NovelTextViewportRuntimeOwner(adapter: runtimeAdapter)
    }

    @discardableResult
    public func start(initial: NovelReadingInitialPosition) async throws -> NovelReadingWorkflowState {
        let resumePoint = initial.resumePoint
        let initialView = resumePoint?.view ?? context.initialView ?? 1
        currentAuthorID = resumePoint?.authorID ?? initial.favoriteAuthorID ?? context.authorID
        return try await load(
            view: initialView,
            preferredSurfaceOrdinal: 0,
            preferredResumePoint: resumePoint,
            forceRefresh: false
        )
    }

    @discardableResult
    public func loadCurrent(
        preferredSurfaceOrdinal: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async throws -> NovelReadingWorkflowState {
        let view = state?.snapshot.currentView ?? context.initialView ?? 1
        return try await loadView(
            view,
            preferredSurfaceOrdinal: preferredSurfaceOrdinal,
            preferredResumePoint: preferredResumePoint,
            forceRefresh: forceRefresh
        )
    }

    @discardableResult
    public func loadView(
        _ view: Int,
        preferredSurfaceOrdinal: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async throws -> NovelReadingWorkflowState {
        return try await load(
            view: view,
            preferredSurfaceOrdinal: preferredSurfaceOrdinal,
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

    public func canPromotePrefetchedDocument(forView view: Int) -> Bool {
        prefetchedDocument?.view == max(1, view)
    }

    package func previewChapterDirectory(view: Int) async throws -> [NovelChapterDirectoryEntry] {
        let request = ReaderPageRequest(
            threadURL: context.threadURL,
            view: view,
            authorID: cacheContext(forView: view).authorID
        )
        return try await repository.loadPage(request)
            .previewChapterDirectoryEntries(readingMode: settings.readingMode)
    }

    package func loadChapter(_ anchor: NovelChapterAnchor) async throws -> NovelReadingWorkflowState {
        try await load(
            view: anchor.resumePoint.view,
            preferredSurfaceOrdinal: 0,
            preferredResumePoint: anchor.resumePoint,
            forceRefresh: false
        )
    }

    @discardableResult
    public func commitSurfaceAppearance(_ settings: ReaderAppearanceSettings) -> NovelReadingWorkflowState? {
        guard let state,
              let session,
              state.presentation?.generation == viewportRuntime.currentGeneration else {
            self.settings = settings
            return nil
        }
        self.settings = settings
        let revision = (state.presentation?.revision ?? 0) + 1
        let nextState = NovelReadingWorkflowState(
            snapshot: session.snapshot,
            presentation: makePresentation(
                snapshot: session.snapshot,
                layoutResult: viewportRuntime.currentResult,
                generation: viewportRuntime.currentGeneration,
                revision: revision,
                settings: settings,
                usesTwoPageSpread: usesPagedSpread(
                    settings: settings,
                    layout: layout,
                    usesPadPresentation: usesPadPresentation
                )
            ),
            cachedViews: state.cachedViews
        )
        self.state = nextState
        return nextState
    }

    @discardableResult
    public func requestRuntimeUpdate(
        _ update: NovelReadingWorkflowRuntimeUpdate,
        preparation: @escaping NovelReadingWorkflowRuntimeUpdatePreparation = { $0 }
    ) async throws -> NovelReadingWorkflowState? {
        runtimeUpdateRequestSequence &+= 1
        pendingRuntimeUpdateTask?.cancel()
        pendingRuntimeUpdateTask = nil
        let requestSequence = runtimeUpdateRequestSequence
        let task = Task { [weak self] () throws -> NovelReadingWorkflowState? in
            let preparedUpdate = try await preparation(update)
            try Task.checkCancellation()
            guard let self,
                  let document = self.currentDocument else {
                return nil
            }
            let paginationLayout = preparedUpdate.layout.novelTextBoxLayout(
                settings: preparedUpdate.settings,
                usesPadPresentation: preparedUpdate.usesPadPresentation
            )
            let semanticInput = try await Task.detached(priority: .userInitiated) {
                try NovelTextLayout.prepareInput(
                    document: document,
                    settings: preparedUpdate.settings,
                    layout: paginationLayout
                )
            }.value
            try Task.checkCancellation()
            return try self.commitRuntimeUpdateRequest(
                preparedUpdate,
                semanticInput: semanticInput,
                requestSequence: requestSequence
            )
        }
        pendingRuntimeUpdateTask = task
        do {
            let result = try await task.value
            if runtimeUpdateRequestSequence == requestSequence {
                pendingRuntimeUpdateTask = nil
            }
            return result
        } catch {
            if runtimeUpdateRequestSequence == requestSequence {
                pendingRuntimeUpdateTask = nil
            }
            throw error
        }
    }

    private func commitRuntimeUpdateRequest(
        _ update: NovelReadingWorkflowRuntimeUpdate,
        semanticInput: NovelTextLayoutPreparedInput,
        requestSequence: UInt64
    ) throws -> NovelReadingWorkflowState? {
        guard requestSequence == runtimeUpdateRequestSequence,
              !Task.isCancelled,
              var candidateSession = session,
              state != nil,
              currentDocument == semanticInput.document else {
            return nil
        }
        let resumePoint = candidateSession.captureNovelReadingPosition()
        let transaction = try viewportRuntime.prepareTransaction(
            preparedInput: semanticInput
        )
        candidateSession.consumeCommittedLayoutResult(
            transaction.result,
            preferredSurfaceOrdinal: candidateSession.snapshot.selectedSurfaceOrdinal,
            preferredResumePoint: resumePoint,
            usesPagedSpread: usesPagedSpread(
                settings: update.settings,
                layout: update.layout,
                usesPadPresentation: update.usesPadPresentation
            )
        )
        guard requestSequence == runtimeUpdateRequestSequence,
              !Task.isCancelled else {
            return nil
        }
        return try commitRuntimeTransaction(
            transaction: transaction,
            candidateSession: candidateSession,
            settings: update.settings,
            layout: update.layout,
            usesPadPresentation: update.usesPadPresentation
        )
    }

    private func supersedePendingRuntimeUpdate() {
        guard pendingRuntimeUpdateTask != nil else { return }
        runtimeUpdateRequestSequence &+= 1
        pendingRuntimeUpdateTask?.cancel()
        pendingRuntimeUpdateTask = nil
    }

    private func commitRuntimeTransaction(
        transaction: NovelTextViewportRuntimeTransaction,
        candidateSession: NovelReadingSession,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool
    ) throws -> NovelReadingWorkflowState? {
        guard let currentDocument else { return nil }
        let preparedTransaction = try makePreparedTransaction(
            runtime: transaction,
            session: candidateSession,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation,
            currentDocument: currentDocument,
            prefetchedDocument: prefetchedDocument,
            currentAuthorID: candidateSession.snapshot.currentAuthorID ?? currentAuthorID,
            cachedViews: state?.cachedViews ?? []
        )
        return commit(preparedTransaction)
    }

    private func makePreparedTransaction(
        runtime: NovelTextViewportRuntimeTransaction,
        session: NovelReadingSession,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool,
        currentDocument: ReaderPageDocument,
        prefetchedDocument: ReaderPageDocument?,
        currentAuthorID: String?,
        cachedViews: Set<Int>
    ) throws -> NovelReadingPreparedTransaction {
        let snapshot = session.snapshot
        try viewportRuntime.prepareInitialViewport(
            for: runtime,
            around: snapshot.selectedSurfaceOrdinal
        )
        let state = NovelReadingWorkflowState(
            snapshot: snapshot,
            presentation: makePresentation(
                snapshot: snapshot,
                layoutResult: runtime.result,
                generation: runtime.generation,
                revision: 0,
                settings: settings,
                usesTwoPageSpread: usesPagedSpread(
                    settings: settings,
                    layout: layout,
                    usesPadPresentation: usesPadPresentation
                )
            ),
            cachedViews: cachedViews
        )
        return NovelReadingPreparedTransaction(
            runtime: runtime,
            session: session,
            state: state,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation,
            currentDocument: currentDocument,
            prefetchedDocument: prefetchedDocument,
            currentAuthorID: currentAuthorID,
            currentDocumentSurfaceCount: session.surfaceCount(in: snapshot.currentView)
        )
    }

    private func commit(
        _ transaction: NovelReadingPreparedTransaction
    ) -> NovelReadingWorkflowState? {
        guard viewportRuntime.commit(transaction.runtime) else { return nil }
        settings = transaction.settings
        layout = transaction.layout
        usesPadPresentation = transaction.usesPadPresentation
        session = transaction.session
        currentDocument = transaction.currentDocument
        prefetchedDocument = transaction.prefetchedDocument
        currentAuthorID = transaction.currentAuthorID
        currentDocumentSurfaceCount = transaction.currentDocumentSurfaceCount
        state = transaction.state
        return transaction.state
    }

    public func selectSurface(
        _ surfaceIdentity: NovelReaderSurfaceIdentity,
        presentationRevision: UInt64
    ) -> NovelReadingWorkflowState? {
        guard let presentation = state?.presentation,
              presentation.generation == surfaceIdentity.generation,
              presentation.revision == presentationRevision,
              presentation.surfaces.contains(where: { $0.identity == surfaceIdentity }) else {
            return nil
        }
        let previousSnapshot = session?.snapshot
        session?.selectSurface(surfaceIdentity.ordinal)
        guard session?.snapshot != previousSnapshot else { return nil }
        return try? updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    public func updateVerticalViewportPosition(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        intraSurfaceProgress: Double,
        presentationRevision: UInt64
    ) -> NovelReadingWorkflowState? {
        guard let presentation = state?.presentation,
              presentation.generation == surfaceIdentity.generation,
              presentation.revision == presentationRevision,
              presentation.surfaces.contains(where: { $0.identity == surfaceIdentity }) else {
            return nil
        }
        let previousSnapshot = session?.snapshot
        session?.updateVerticalViewportPosition(
            surfaceOrdinal: surfaceIdentity.ordinal,
            intraSurfaceProgress: intraSurfaceProgress
        )
        guard session?.snapshot != previousSnapshot else { return nil }
        return try? updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    @discardableResult
    package func updateVerticalViewportPosition(
        sample: NovelTextViewportSample
    ) -> NovelReadingWorkflowState? {
        let previousSnapshot = session?.snapshot
        session?.updateVerticalViewportPosition(sample: sample)
        guard session?.snapshot != previousSnapshot else { return nil }
        return try? updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    @discardableResult
    package func updateVerticalViewportPosition(
        sample: NovelTextViewportSample,
        presentationRevision: UInt64
    ) -> NovelReadingWorkflowState? {
        guard let presentation = state?.presentation,
              presentation.generation == sample.surfaceIdentity.generation,
              presentation.revision == presentationRevision else {
            return nil
        }
        let previousSnapshot = session?.snapshot
        session?.updateVerticalViewportPosition(sample: sample)
        guard session?.snapshot != previousSnapshot else { return nil }
        return try? updateStateFromSession(cachedViews: state?.cachedViews ?? [])
    }

    @discardableResult
    package func jumpRelativeSurface(_ delta: Int) -> (state: NovelReadingWorkflowState, request: NovelReadingNavigationRequest?)? {
        guard session != nil else { return nil }
        var request = session?.jumpRelativeSurface(delta)
        if case let .loadView(view, preferredSurfaceOrdinal, resumePoint) = request,
           prefetchedDocument?.view == view {
            request = .promotePrefetched(
                preferredSurfaceOrdinal: preferredSurfaceOrdinal,
                resumePoint: resumePoint
            )
        }
        guard let state = try? updateStateFromSession(cachedViews: state?.cachedViews ?? []) else { return nil }
        return (state, request)
    }

    public func captureNovelReadingPosition() -> ReaderResumePoint? {
        session?.captureNovelReadingPosition()
    }

    public func currentProgressPosition() -> NovelReadingPosition {
        let resumePoint = captureNovelReadingPosition()
        let snapshot = state?.snapshot
        let progressProjection = state?.presentation?.progressProjection
        let documentSurfaceProgressPercent = progressProjection.map { projection in
            guard projection.displayedPageCount > 1 else { return 0 }
            let fraction = Double(projection.displayedPageIndex) / Double(projection.displayedPageCount - 1)
            return Int((min(max(fraction, 0), 1) * 100).rounded())
        }
        let surfaces = viewportRuntime.currentResult?.viewportIndex.surfaces ?? []
        let view = currentDisplayedView(in: snapshot, surfaces: surfaces) ?? resumePoint?.view ?? context.initialView ?? 1
        return NovelReadingPosition(
            threadURL: context.threadURL,
            view: view,
            maxView: snapshot?.maxView,
            chapterTitle: resumePoint?.chapterTitle ?? snapshot?.currentChapterTitle,
            authorID: resumePoint?.authorID ?? snapshot?.currentAuthorID ?? currentAuthorID ?? context.authorID,
            resumePoint: resumePoint,
            documentSurfaceProgressPercent: documentSurfaceProgressPercent
        )
    }

    public func currentPreviewSourceText() -> String {
        session?.currentPreviewSourceText() ?? ""
    }

    public func displayReference(for surfaceIdentity: NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference? {
        viewportRuntime.displayReference(for: surfaceIdentity)
    }

    public func updateVisibleSurfaceIdentities(_ surfaceIdentities: [NovelReaderSurfaceIdentity]) {
        viewportRuntime.updateVisibleSurfaceIdentities(surfaceIdentities)
    }

    public func handleMemoryPressure() {
        viewportRuntime.handleMemoryPressure()
    }

    public func close() {
        supersedePendingRuntimeUpdate()
        viewportRuntime.release()
        session = nil
        currentDocument = nil
        prefetchedDocument = nil
        currentAuthorID = nil
        currentDocumentSurfaceCount = 0
        state = nil
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

    private func currentDisplayedView(
        in snapshot: NovelReadingSnapshot?,
        surfaces: [NovelTextViewportIndexSurface]
    ) -> Int? {
        guard let snapshot else { return nil }
        let normalizedIndex = selectedSurfaceOrdinal(in: snapshot, surfaces: surfaces)
        guard surfaces.indices.contains(normalizedIndex) else {
            return snapshot.currentView
        }
        return surfaces[normalizedIndex].documentView
    }

    private func selectedSurfaceOrdinal(
        in snapshot: NovelReadingSnapshot,
        surfaces: [NovelTextViewportIndexSurface]
    ) -> Int {
        max(0, min(snapshot.selectedSurfaceOrdinal, max(surfaces.count - 1, 0)))
    }

    @discardableResult
    public func prefetchIfNeeded(near surfaceIdentity: NovelReaderSurfaceIdentity) async -> NovelReadingWorkflowState? {
        guard let currentDocument else { return nil }
        guard surfaceIdentity.generation == viewportRuntime.currentGeneration,
              viewportRuntime.currentResult?.viewportIndex.surfaces.contains(where: {
                  $0.surfaceOrdinal == surfaceIdentity.ordinal
              }) == true else {
            return nil
        }
        guard currentDocument.view < currentDocument.maxView else { return nil }
        let thresholdIndex = max(currentDocumentSurfaceCount - 2, 0)
        guard surfaceIdentity.ordinal >= thresholdIndex else { return nil }
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
        if nextDocument.maxView > (session?.snapshot.maxView ?? 0) {
            session?.updateMaximumView(nextDocument.maxView)
        }
        return try? await updateStateFromSession(refreshCachedViews: false)
    }

    @discardableResult
    public func promotePrefetchedDocument(
        preferredSurfaceOrdinal: Int,
        resumePoint: ReaderResumePoint?
    ) async throws -> NovelReadingWorkflowState? {
        supersedePendingRuntimeUpdate()
        guard let nextDocument = prefetchedDocument,
              var candidateSession = session else {
            return nil
        }
        let effectiveResumePoint = resumePoint?.view == nextDocument.view ? resumePoint : nil
        let transaction = try prepareRuntimeTransaction(
            document: nextDocument,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation
        )
        try candidateSession.promotePrefetchedDocument(
            document: nextDocument,
            layoutResult: transaction.result,
            preferredSurfaceOrdinal: preferredSurfaceOrdinal,
            resumePoint: effectiveResumePoint,
            usesPagedSpread: usesPagedSpread(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            )
        )
        let nextAuthorID = nextDocument.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        let preparedTransaction = try makePreparedTransaction(
            runtime: transaction,
            session: candidateSession,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation,
            currentDocument: nextDocument,
            prefetchedDocument: nil,
            currentAuthorID: candidateSession.snapshot.currentAuthorID ?? nextAuthorID,
            cachedViews: state?.cachedViews ?? [],
        )
        return commit(preparedTransaction)
    }

    private func load(
        view: Int,
        preferredSurfaceOrdinal: Int,
        preferredResumePoint: ReaderResumePoint?,
        forceRefresh: Bool
    ) async throws -> NovelReadingWorkflowState {
        supersedePendingRuntimeUpdate()
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
        let preservedResumePoint = preferredResumePoint ?? captureNovelReadingPosition()
        let nextAuthorID = document.resolvedAuthorID ?? currentAuthorID ?? context.authorID
        let transaction = try prepareRuntimeTransaction(
            document: document,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation
        )
        let candidateSession = try NovelReadingSession(
            validating: document,
            layoutResult: transaction.result,
            preferredSurfaceOrdinal: preferredSurfaceOrdinal,
            resumePoint: preservedResumePoint,
            currentAuthorID: nextAuthorID,
            usesPagedSpread: usesPagedSpread(
                settings: settings,
                layout: layout,
                usesPadPresentation: usesPadPresentation
            )
        )
        let documentCacheContext = cacheContext(for: document)
        let cachedViews = await repository.cachedViews(
            for: context.threadURL,
            authorID: documentCacheContext.authorID,
            contentSource: documentCacheContext.contentSource
        )
        let preparedTransaction = try makePreparedTransaction(
            runtime: transaction,
            session: candidateSession,
            settings: settings,
            layout: layout,
            usesPadPresentation: usesPadPresentation,
            currentDocument: document,
            prefetchedDocument: nil,
            currentAuthorID: candidateSession.snapshot.currentAuthorID ?? nextAuthorID,
            cachedViews: cachedViews,
        )
        guard let nextState = commit(preparedTransaction) else {
            throw NovelTextLayoutFailure.textKitIndexing
        }
        return nextState
    }

    private func updateStateFromSession(refreshCachedViews: Bool) async throws -> NovelReadingWorkflowState {
        guard let snapshot = session?.snapshot,
              currentDocument != nil else {
            preconditionFailure("Novel reading workflow has no active session")
        }
        currentAuthorID = snapshot.currentAuthorID ?? currentAuthorID
        currentDocumentSurfaceCount = session?.surfaceCount(in: snapshot.currentView) ?? 0
        let cachedViews = if refreshCachedViews {
            await repository.cachedViews(
                for: context.threadURL,
                authorID: cacheContext(forView: snapshot.currentView).authorID,
                contentSource: cacheContext(forView: snapshot.currentView).contentSource
            )
        } else {
            state?.cachedViews ?? []
        }
        guard let nextState = try updateStateFromSession(cachedViews: cachedViews) else {
            preconditionFailure("Novel reading workflow has no active session")
        }
        return nextState
    }

    private func updateStateFromSession(cachedViews: Set<Int>) throws -> NovelReadingWorkflowState? {
        guard let snapshot = session?.snapshot else {
            return nil
        }
        currentAuthorID = snapshot.currentAuthorID ?? currentAuthorID
        currentDocumentSurfaceCount = session?.surfaceCount(in: snapshot.currentView) ?? 0
        let generation = viewportRuntime.currentGeneration
        let previousPresentation = state?.presentation
        let revision = previousPresentation?.generation == generation
            ? (previousPresentation?.revision ?? 0) + 1
            : 0
        let nextState = NovelReadingWorkflowState(
            snapshot: snapshot,
            presentation: makePresentation(
                snapshot: snapshot,
                layoutResult: viewportRuntime.currentResult,
                generation: generation,
                revision: revision,
                settings: settings,
                usesTwoPageSpread: usesPagedSpread(
                    settings: settings,
                    layout: layout,
                    usesPadPresentation: usesPadPresentation
                )
            ),
            cachedViews: cachedViews
        )
        state = nextState
        return nextState
    }

    private func makePresentation(
        snapshot: NovelReadingSnapshot,
        layoutResult: NovelTextLayoutResult?,
        generation: UInt64,
        revision: UInt64,
        settings: ReaderAppearanceSettings,
        usesTwoPageSpread: Bool
    ) -> NovelReaderPresentation {
        let readableSize = layoutResult?.viewportContext.identity.layout.readableFrame.size ?? layout.readableFrame.size
        let indexSurfaces = (layoutResult?.viewportIndex.surfaces ?? []).sorted { lhs, rhs in
            lhs.surfaceOrdinal < rhs.surfaceOrdinal
        }
        let surfaces = indexSurfaces.enumerated().map { index, surface in
            let presentationHeight = layoutResult?.layoutMetrics.surfaceHeight(for: surface.surfaceOrdinal) ?? readableSize.height
            let nextSurface = indexSurfaces.indices.contains(index + 1) ? indexSurfaces[index + 1] : nil
            let spacingAfter: CGFloat = {
                guard let nextSurface else { return 0 }
                return surface.externalBlocks.isEmpty && nextSurface.externalBlocks.isEmpty ? 0 : 14
            }()
            return NovelReaderSurface(
                identity: NovelReaderSurfaceIdentity(
                    generation: generation,
                    ordinal: surface.surfaceOrdinal
                ),
                presentationIndex: index,
                kind: surface.externalBlocks.isEmpty ? .text : .externalBlock,
                documentView: surface.documentView,
                chapterTitle: surface.chapterTitle,
                presentationSize: CGSize(width: readableSize.width, height: presentationHeight),
                presentationSpacingAfter: spacingAfter,
                externalBlocks: surface.externalBlocks.map {
                    NovelReaderExternalBlock(
                        url: $0.url,
                        frame: $0.frozenFrame.map {
                            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
                        }
                    )
                },
                chapterCommentTarget: surface.chapterCommentTarget
            )
        }
        let surfaceIdentityByOrdinal = Dictionary(
            uniqueKeysWithValues: surfaces.map { ($0.identity.ordinal, $0.identity) }
        )
        let surfaceIndexByOrdinal = Dictionary(
            uniqueKeysWithValues: surfaces.map { ($0.identity.ordinal, $0.presentationIndex) }
        )
        let spreads = makeSpreads(from: indexSurfaces).compactMap { spread -> NovelReaderPresentationSpread? in
            guard let leftIdentity = surfaceIdentityByOrdinal[spread.leftSurfaceIndex] else {
                return nil
            }
            return NovelReaderPresentationSpread(
                index: spread.index,
                leftSurfaceIndex: surfaceIndexByOrdinal[spread.leftSurfaceIndex] ?? spread.index,
                leftSurfaceIdentity: leftIdentity,
                rightSurfaceIndex: spread.rightSurfaceIndex.flatMap { surfaceIndexByOrdinal[$0] },
                rightSurfaceIdentity: spread.rightSurfaceIndex.flatMap { surfaceIdentityByOrdinal[$0] },
                chapterTitle: spread.chapterTitle
            )
        }
        let selectedSurfaceIndex = surfaceIndexByOrdinal[snapshot.selectedSurfaceOrdinal]
        let readingState = NovelReaderReadingState(
            currentView: snapshot.currentView,
            maxView: snapshot.maxView,
            currentChapterTitle: snapshot.currentChapterTitle,
            authorID: snapshot.currentAuthorID,
            currentSurfaceIntraProgress: snapshot.currentSurfaceIntraProgress
        )
        let progressProjection = NovelReaderProgressProjection(
            readingMode: settings.readingMode,
            usesTwoPageSpread: usesTwoPageSpread,
            surfaces: surfaces,
            selectedSurfaceIndex: selectedSurfaceIndex ?? 0,
            spreads: spreads,
            readingState: readingState
        )
        return NovelReaderPresentation(
            generation: generation,
            revision: revision,
            surfaces: surfaces,
            selectedSurfaceIdentity: surfaceIdentityByOrdinal[snapshot.selectedSurfaceOrdinal],
            spreads: spreads,
            chapters: layoutResult?.viewportIndex.readerChapters ?? [],
            committedSettings: settings,
            readingState: readingState,
            currentContentSource: snapshot.currentContentSource,
            retainedChapterCount: snapshot.retainedChapterCount,
            filteredChapterCandidateCount: snapshot.filteredChapterCandidateCount,
            selectedSurfaceIndex: selectedSurfaceIndex,
            progressProjection: progressProjection,
            usesTwoPageSpread: usesTwoPageSpread
        )
    }

    private func makeSpreads(from surfaces: [NovelTextViewportIndexSurface]) -> [NovelReadingSpread] {
        guard !surfaces.isEmpty else { return [] }

        var spreads: [NovelReadingSpread] = []
        var surfaceCursor = 0

        while surfaceCursor < surfaces.count {
            let leftSurface = surfaces[surfaceCursor]
            let candidateRightIndex = surfaceCursor + 1
            let rightSurfaceIndex: Int? = if surfaces.indices.contains(candidateRightIndex),
                                          surfaces[candidateRightIndex].documentView == leftSurface.documentView {
                candidateRightIndex
            } else {
                nil
            }

            spreads.append(
                NovelReadingSpread(
                    index: spreads.count,
                    leftSurfaceIndex: leftSurface.surfaceOrdinal,
                    rightSurfaceIndex: rightSurfaceIndex,
                    chapterTitle: leftSurface.chapterTitle
                )
            )
            surfaceCursor += rightSurfaceIndex == nil ? 1 : 2
        }

        return spreads
    }

    private func prepareRuntimeTransaction(
        document: ReaderPageDocument,
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool
    ) throws -> NovelTextViewportRuntimeTransaction {
        let paginationLayout = layout.novelTextBoxLayout(
            settings: settings,
            usesPadPresentation: usesPadPresentation
        )
        return try viewportRuntime.prepareTransaction(
            preparedInput: try NovelTextLayout.prepareInput(
                document: document,
                settings: settings,
                layout: paginationLayout
            )
        )
    }

    private func usesPagedSpread(
        settings: ReaderAppearanceSettings,
        layout: ReaderContainerLayout,
        usesPadPresentation: Bool
    ) -> Bool {
        settings.readingMode == .paged &&
            settings.showsTwoPagesInLandscapeOnPad &&
            usesPadPresentation &&
            layout.width > layout.height
    }

    private func inferredContentSource(for authorID: String?) -> ReaderContentSource {
        let normalizedAuthorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalizedAuthorID.isEmpty ? .fallbackUnfilteredPage : .authorFilteredPage
    }
}

private extension ReaderPageDocument {
    func previewChapterDirectoryEntries(
        readingMode: ReaderReadingMode
    ) -> [NovelChapterDirectoryEntry] {
        var seenIdentities: Set<NovelChapterIdentity> = []
        return zip(segments, segmentSemantics).compactMap { segment, semantics in
            guard let semantics,
                  let chapterIdentity = semantics.chapterIdentity,
                  seenIdentities.insert(chapterIdentity).inserted else {
                return nil
            }
            let ordinal = seenIdentities.count - 1
            let title: String = switch segment {
            case let .text(_, chapterTitle), let .image(_, chapterTitle):
                chapterTitle ?? ""
            }
            let anchor = semantics.textSegmentIdentity.map {
                NovelChapterAnchor(
                    resumePoint: ReaderResumePoint(
                        view: view,
                        chapterIdentity: chapterIdentity,
                        textSegmentIdentity: $0,
                        displayedTextOffset: 0,
                        chapterOrdinal: ordinal,
                        chapterTitle: title,
                        segmentProgress: 0,
                        authorID: resolvedAuthorID,
                        readingModeHint: readingMode
                    )
                )
            }
            return NovelChapterDirectoryEntry(
                chapter: ReaderChapter(
                    ordinal: ordinal,
                    title: title,
                    startIndex: ordinal
                ),
                anchor: anchor
            )
        }
    }
}
