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
    private let novelOfflineCacheSettings: @Sendable () async -> NovelOfflineCacheSettings
    private let continueOfflineCacheQueue: (@Sendable () async throws -> Void)?

    public init(
        store: any OfflineCacheStoring,
        novelOfflineCacheSettings: @escaping @Sendable () async -> NovelOfflineCacheSettings = { .init() },
        continueOfflineCacheQueue: (@Sendable () async throws -> Void)? = nil
    ) {
        self.store = store
        self.novelOfflineCacheSettings = novelOfflineCacheSettings
        self.continueOfflineCacheQueue = continueOfflineCacheQueue
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
        var didEnqueueWork = false
        let settings = await novelOfflineCacheSettings()
        for view in views.sorted() {
            do {
                let request = NovelOfflineCacheWorkRequest(
                    ownerTitle: context.ownerTitle,
                    title: L10n.string("reader.page_number_spaced", view),
                    threadURL: context.threadURL,
                    view: view,
                    authorID: context.authorID,
                    contentSource: context.contentSource ?? .fallbackUnfilteredPage,
                    retainsInlineImages: settings.retainsInlineImages
                )
                let result = try await (isUpdate
                    ? store.enqueueNovelOfflineCacheUpdateWork(request)
                    : store.enqueueNovelOfflineCacheWork(request))
                switch result {
                case .alreadyCached:
                    break
                case .alreadyQueued:
                    submittedViews.append(view)
                case .enqueued:
                    submittedViews.append(view)
                    didEnqueueWork = true
                }
            } catch {
                failedViews.append(view)
            }
        }
        if didEnqueueWork {
            do {
                try await continueOfflineCacheQueueIfAllowed()
            } catch {
                failedViews.append(contentsOf: submittedViews.filter { !failedViews.contains($0) })
            }
        }
        let completedViews = submittedViews.filter { !failedViews.contains($0) }
        return ReaderCacheBatchResult(
            totalCount: views.count,
            completedViews: completedViews,
            failedViews: failedViews,
            wasCancelled: false
        )
    }

    private func continueOfflineCacheQueueIfAllowed() async throws {
        let works = await store.offlineCacheQueueWorks()
        guard works.allSatisfy({ $0.state != .failed }) else { return }
        try await continueOfflineCacheQueue?()
    }
}
