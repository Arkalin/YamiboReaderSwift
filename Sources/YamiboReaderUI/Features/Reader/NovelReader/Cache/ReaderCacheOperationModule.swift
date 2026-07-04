import Foundation
import YamiboReaderCore

public struct ReaderCacheOperationContext: Equatable, Sendable {
    public var ownerTitle: String
    public var threadID: String
    public var authorID: String?
    public var contentSource: ReaderContentSource?

    public init(ownerTitle: String = "", threadID: String, authorID: String?, contentSource: ReaderContentSource?) {
        self.ownerTitle = ownerTitle
        self.threadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authorID = authorID
        self.contentSource = contentSource
    }
}

public struct ReaderCacheOperationSnapshot: Equatable, Sendable {
    public var cacheableViews: Set<Int>
    public var cachedViews: Set<Int>
    public var cachingViews: Set<Int>
    public var updateTimesByView: [Int: Date]
    public var context: ReaderCacheOperationContext

    public init(
        cacheableViews: Set<Int>,
        cachedViews: Set<Int>,
        cachingViews: Set<Int> = [],
        updateTimesByView: [Int: Date] = [:],
        context: ReaderCacheOperationContext
    ) {
        self.cacheableViews = cacheableViews
        self.cachedViews = cachedViews
        self.cachingViews = cachingViews
        self.updateTimesByView = updateTimesByView
        self.context = context
    }
}

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
    public var cachingSelectedViews: Set<Int>
    public var updatableSelectedViews: Set<Int>
    public var uncachedSelectedViews: Set<Int>
    public var canCache: Bool
    public var canUpdate: Bool
    public var canDelete: Bool
    public var isAllSelected: Bool

    public init(
        selectedViews: Set<Int>,
        cachedSelectedViews: Set<Int>,
        cachingSelectedViews: Set<Int> = [],
        updatableSelectedViews: Set<Int>? = nil,
        uncachedSelectedViews: Set<Int>,
        canCache: Bool,
        canUpdate: Bool,
        canDelete: Bool,
        isAllSelected: Bool
    ) {
        self.selectedViews = selectedViews
        self.cachedSelectedViews = cachedSelectedViews
        self.cachingSelectedViews = cachingSelectedViews
        self.updatableSelectedViews = updatableSelectedViews ?? cachedSelectedViews.subtracting(cachingSelectedViews)
        self.uncachedSelectedViews = uncachedSelectedViews
        self.canCache = canCache
        self.canUpdate = canUpdate
        self.canDelete = canDelete
        self.isAllSelected = isAllSelected
    }
}

public enum ReaderCacheOperationMode: Sendable {
    case cache
    case update
}

public protocol ReaderCacheOperationRepository: Sendable {
    func cacheState(for context: ReaderCacheOperationContext) async -> NovelOfflineCacheViewsSnapshot
    func cachedViews(for context: ReaderCacheOperationContext) async -> Set<Int>

    func deleteCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext
    ) async throws

    func cacheViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult

    func updateCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult
}

@MainActor
public final class ReaderCacheOperationModule {
    public private(set) var cachedViews: Set<Int> = []
    public private(set) var cachingViews: Set<Int> = []
    public private(set) var cachedViewUpdateTimes: [Int: Date] = [:]
    public private(set) var state = ReaderCacheOperationState()
    public var onChange: (@MainActor (NovelOfflineCacheViewsSnapshot, ReaderCacheOperationState) -> Void)?

    private var operationTask: Task<Void, Never>?

    public init() {}

    deinit {
        operationTask?.cancel()
    }

    public func syncCachedViews(_ views: Set<Int>) {
        syncCacheState(NovelOfflineCacheViewsSnapshot(cachedViews: views))
    }

    public func syncCacheState(_ snapshot: NovelOfflineCacheViewsSnapshot) {
        cachedViews = snapshot.cachedViews
        cachingViews = snapshot.cachingViews
        cachedViewUpdateTimes = snapshot.updateTimesByView
        state.cachedViews = snapshot.cachedViews
        emitChange()
    }

    public func selectionState(
        for selectedViews: Set<Int>,
        snapshot: ReaderCacheOperationSnapshot
    ) -> ReaderCacheSelectionState {
        let validSelections = selectedViews.intersection(snapshot.cacheableViews)
        let cachedSelectedViews = validSelections.intersection(snapshot.cachedViews)
        let cachingSelectedViews = validSelections.intersection(snapshot.cachingViews)
        let updatableSelectedViews = cachedSelectedViews.subtracting(snapshot.cachingViews)
        let uncachedSelectedViews = validSelections
            .subtracting(snapshot.cachedViews)
            .subtracting(snapshot.cachingViews)
        return ReaderCacheSelectionState(
            selectedViews: validSelections,
            cachedSelectedViews: cachedSelectedViews,
            cachingSelectedViews: cachingSelectedViews,
            updatableSelectedViews: updatableSelectedViews,
            uncachedSelectedViews: uncachedSelectedViews,
            canCache: !uncachedSelectedViews.isEmpty,
            canUpdate: !updatableSelectedViews.isEmpty,
            canDelete: !cachedSelectedViews.isEmpty,
            isAllSelected: !snapshot.cacheableViews.isEmpty && validSelections.count == snapshot.cacheableViews.count
        )
    }

    public func startCaching(
        views: Set<Int>,
        snapshot: ReaderCacheOperationSnapshot,
        repository: ReaderCacheOperationRepository,
        summary: @escaping @MainActor (ReaderCacheOperationMode, ReaderCacheBatchResult) -> String
    ) {
        guard !state.isRunning else { return }
        let selection = selectionState(for: views, snapshot: snapshot)
        guard !selection.uncachedSelectedViews.isEmpty else { return }
        startOperation(
            mode: .cache,
            views: selection.uncachedSelectedViews,
            snapshot: snapshot,
            repository: repository,
            summary: summary
        )
    }

    public func updateCachedViews(
        _ views: Set<Int>,
        snapshot: ReaderCacheOperationSnapshot,
        repository: ReaderCacheOperationRepository,
        summary: @escaping @MainActor (ReaderCacheOperationMode, ReaderCacheBatchResult) -> String,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        guard !state.isRunning else { return }
        let selection = selectionState(for: views, snapshot: snapshot)
        guard !selection.updatableSelectedViews.isEmpty else { return }
        startOperation(
            mode: .update,
            views: selection.updatableSelectedViews,
            snapshot: snapshot,
            repository: repository,
            summary: summary
        )
    }

    public func deleteCachedViews(
        _ views: Set<Int>,
        snapshot: ReaderCacheOperationSnapshot,
        repository: ReaderCacheOperationRepository
    ) async throws {
        guard !state.isRunning else { return }
        let selection = selectionState(for: views, snapshot: snapshot)
        guard !selection.cachedSelectedViews.isEmpty else { return }

        try await repository.deleteCachedViews(
            selection.cachedSelectedViews,
            for: snapshot.context
        )
        syncCacheState(await repository.cacheState(for: snapshot.context))
    }

    public func showProgressIfRunning() {
        guard state.hasSession else { return }
        state.isProgressHidden = false
        emitChange()
    }

    public func hideProgress() {
        guard state.hasSession else { return }
        state.isProgressHidden = true
        emitChange()
    }

    public func dismissProgress() {
        operationTask = nil
        reset()
    }

    public func stopCaching() {
        guard state.isRunning else { return }
        operationTask?.cancel()
    }

    private func reset() {
        state = ReaderCacheOperationState(cachedViews: cachedViews)
        emitChange()
    }

    private func startOperation(
        mode: ReaderCacheOperationMode,
        views: Set<Int>,
        snapshot: ReaderCacheOperationSnapshot,
        repository: ReaderCacheOperationRepository,
        summary: @escaping @MainActor (ReaderCacheOperationMode, ReaderCacheBatchResult) -> String
    ) {
        let targets = views.sorted()
        guard !targets.isEmpty else { return }

        state = ReaderCacheOperationState(
            cachedViews: cachedViews,
            queuedViews: targets,
            totalCount: targets.count,
            status: .running
        )
        emitChange()

        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            let result = if mode == .update {
                await repository.updateCachedViews(
                    Set(targets),
                    for: snapshot.context
                ) { [weak self] progress in
                    await self?.apply(progress: progress, allTargets: targets)
                }
            } else {
                await repository.cacheViews(
                    Set(targets),
                    for: snapshot.context
                ) { [weak self] progress in
                    await self?.apply(progress: progress, allTargets: targets)
                }
            }
            await self.finalize(result: result, mode: mode, snapshot: snapshot, repository: repository, summary: summary)
        }
    }

    private func apply(progress: ReaderCacheBatchProgress, allTargets: [Int]) {
        state.totalCount = progress.totalCount
        state.completedCount = progress.completedCount
        state.currentView = progress.currentView
        state.completedViews = progress.completedViews
        state.failedViews = progress.failedViews
        state.status = progress.status == .cancelled ? .cancelled : .running

        let completed = Set(progress.completedViews)
        let failed = Set(progress.failedViews)
        state.queuedViews = allTargets.filter { !completed.contains($0) && !failed.contains($0) }
        syncCachedViews(cachedViews.union(completed))
    }

    private func finalize(
        result: ReaderCacheBatchResult,
        mode: ReaderCacheOperationMode,
        snapshot: ReaderCacheOperationSnapshot,
        repository: ReaderCacheOperationRepository,
        summary: @MainActor (ReaderCacheOperationMode, ReaderCacheBatchResult) -> String
    ) async {
        operationTask = nil
        let refreshedState = await repository.cacheState(for: snapshot.context)
        syncCacheState(refreshedState)

        state.cachedViews = cachedViews
        state.queuedViews = result.wasCancelled ? state.queuedViews : []
        state.completedViews = result.completedViews
        state.failedViews = result.failedViews
        state.totalCount = result.totalCount
        state.completedCount = result.completedViews.count
        state.currentView = nil
        state.status = result.wasCancelled ? .cancelled : .completed
        state.summaryMessage = summary(mode, result)
        state.isProgressHidden = false
        emitChange()
    }

    private func emitChange() {
        onChange?(
            NovelOfflineCacheViewsSnapshot(
                cachedViews: cachedViews,
                cachingViews: cachingViews,
                updateTimesByView: cachedViewUpdateTimes
            ),
            state
        )
    }
}
