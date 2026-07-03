import Foundation
import YamiboReaderCore

public struct ReaderRepositoryCacheOperationAdapter: ReaderCacheOperationRepository {
    private let repository: NovelReaderRepository

    public init(repository: NovelReaderRepository) {
        self.repository = repository
    }

    public func cacheState(for context: ReaderCacheOperationContext) async -> NovelOfflineCacheViewsSnapshot {
        NovelOfflineCacheViewsSnapshot(cachedViews: await cachedViews(for: context))
    }

    public func cachedViews(for context: ReaderCacheOperationContext) async -> Set<Int> {
        await repository.cachedViews(
            for: context.threadURL,
            authorID: context.authorID,
            contentSource: context.contentSource
        )
    }

    public func deleteCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext
    ) async throws {
        try await repository.deleteCachedViews(
            views,
            for: context.threadURL,
            authorID: context.authorID,
            contentSource: context.contentSource
        )
    }

    public func cacheViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult {
        await repository.cacheViews(
            views,
            for: context.threadURL,
            authorID: context.authorID,
            contentSource: context.contentSource,
            progress: progress
        )
    }

    public func updateCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult {
        do {
            try await deleteCachedViews(views, for: context)
        } catch {
            return ReaderCacheBatchResult(totalCount: views.count, completedViews: [], failedViews: views.sorted(), wasCancelled: false)
        }
        return await cacheViews(views, for: context, progress: progress)
    }
}

public struct OfflineStoreReaderCacheOperationAdapter: ReaderCacheOperationRepository {
    private let store: any OfflineCacheStoring

    public init(store: any OfflineCacheStoring) {
        self.store = store
    }

    public func cacheState(for context: ReaderCacheOperationContext) async -> NovelOfflineCacheViewsSnapshot {
        await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: context.ownerTitle,
            threadURL: context.threadURL,
            authorID: context.authorID,
            contentSource: context.contentSource
        )
    }

    public func cachedViews(for context: ReaderCacheOperationContext) async -> Set<Int> {
        await cacheState(for: context).cachedViews
    }

    public func deleteCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext
    ) async throws {
        try await store.removeNovelOfflineCacheViews(
            views,
            ownerTitle: context.ownerTitle,
            threadURL: context.threadURL,
            authorID: context.authorID,
            contentSource: context.contentSource
        )
    }

    public func cacheViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress _: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult {
        await enqueue(views, for: context, isUpdate: false)
    }

    public func updateCachedViews(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        progress _: (@Sendable (ReaderCacheBatchProgress) async -> Void)?
    ) async -> ReaderCacheBatchResult {
        await enqueue(views, for: context, isUpdate: true)
    }

    private func enqueue(
        _ views: Set<Int>,
        for context: ReaderCacheOperationContext,
        isUpdate: Bool
    ) async -> ReaderCacheBatchResult {
        var submittedViews: [Int] = []
        var failedViews: [Int] = []
        for view in views.sorted() {
            do {
                let request = NovelOfflineCacheWorkRequest(
                    ownerTitle: context.ownerTitle,
                    title: L10n.string("reader.page_number_spaced", view),
                    threadURL: context.threadURL,
                    view: view,
                    authorID: context.authorID,
                    contentSource: context.contentSource ?? .fallbackUnfilteredPage
                )
                let result = try await (isUpdate
                    ? store.enqueueNovelOfflineCacheUpdateWork(request)
                    : store.enqueueNovelOfflineCacheWork(request))
                switch result {
                case .alreadyCached:
                    break
                case .alreadyQueued, .enqueued:
                    submittedViews.append(view)
                }
            } catch {
                failedViews.append(view)
            }
        }
        return ReaderCacheBatchResult(
            totalCount: views.count,
            completedViews: submittedViews,
            failedViews: failedViews,
            wasCancelled: false
        )
    }
}
