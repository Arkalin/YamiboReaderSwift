import Foundation

public enum OfflineCacheImageAcquisitionSource: Hashable, Sendable {
    case network
}

public struct OfflineCacheImageAcquisition: Hashable, Sendable {
    public var data: Data
    public var source: OfflineCacheImageAcquisitionSource

    public init(data: Data, source: OfflineCacheImageAcquisitionSource) {
        self.data = data
        self.source = source
    }
}

public protocol OfflineCacheImageAcquiring: Sendable {
    func acquireImageData(for request: YamiboImageRequest) async throws -> OfflineCacheImageAcquisition
}

public protocol OfflineCacheImageTransporting: Sendable {
    func downloadImageData(for request: YamiboImageRequest) async throws -> Data
}

public protocol OfflineCacheQueueRunObserving: Sendable {
    func submitUserInitiatedRun() async
    func queueRunDidUpdateProgress(completedImageCount: Int, targetImageCount: Int) async
    func queueRunDidFinish(success: Bool) async
    func queueRunDidCancel() async
}

public actor OfflineCacheImageAcquirer: OfflineCacheImageAcquiring {
    private let networkLoader: any YamiboImageDataLoading
    private let backgroundTransport: (any OfflineCacheImageTransporting)?

    public init(
        networkLoader: any YamiboImageDataLoading,
        backgroundTransport: (any OfflineCacheImageTransporting)? = nil
    ) {
        self.networkLoader = networkLoader
        self.backgroundTransport = backgroundTransport
    }

    public func acquireImageData(for request: YamiboImageRequest) async throws -> OfflineCacheImageAcquisition {
        let data: Data
        if let backgroundTransport {
            data = try await backgroundTransport.downloadImageData(for: request)
        } else {
            data = try await networkLoader.imageData(for: request)
        }
        return OfflineCacheImageAcquisition(data: data, source: .network)
    }
}

public actor OfflineCacheQueueExecutor {
    private let store: any OfflineCacheQueueStoring & OfflineCacheImageAssetStoring
    private let runObserver: (any OfflineCacheQueueRunObserving)?
    private let mangaWorkProcessor: OfflineCacheWorkProcessor<MangaOfflineCacheWorkProcessingStrategy>
    private let novelWorkProcessor: OfflineCacheWorkProcessor<NovelOfflineCacheWorkProcessingStrategy>?
    private var runTask: Task<Void, Never>?
    private var runGeneration = 0

    public init(
        store: any OfflineCacheQueueStoring & OfflineCacheImageAssetStoring,
        mangaCacheStore: any MangaOfflineCacheStoring,
        novelCacheStore: (any NovelOfflineCacheStoring)? = nil,
        readerProjectionLoader: any MangaReaderProjectionSnapshotLoading,
        novelSourcePageLoader: (any NovelOfflineCacheSourcePageLoading)? = nil,
        imageAcquirer: any OfflineCacheImageAcquiring,
        runObserver: (any OfflineCacheQueueRunObserving)? = nil,
        maxConcurrentImageTransfers: Int = 3
    ) {
        self.store = store
        self.runObserver = runObserver
        let transferLimit = max(1, maxConcurrentImageTransfers)
        self.mangaWorkProcessor = OfflineCacheWorkProcessor(
            store: store,
            imageAcquirer: imageAcquirer,
            runObserver: runObserver,
            maxConcurrentImageTransfers: transferLimit,
            strategy: MangaOfflineCacheWorkProcessingStrategy(
                store: mangaCacheStore,
                readerProjectionLoader: readerProjectionLoader
            )
        )
        if let novelSourcePageLoader, let novelCacheStore {
            self.novelWorkProcessor = OfflineCacheWorkProcessor(
                store: store,
                imageAcquirer: imageAcquirer,
                runObserver: runObserver,
                maxConcurrentImageTransfers: transferLimit,
                strategy: NovelOfflineCacheWorkProcessingStrategy(
                    store: novelCacheStore,
                    sourcePageLoader: novelSourcePageLoader
                )
            )
        } else {
            self.novelWorkProcessor = nil
        }
    }

    public func continueQueue() async throws {
        try await continueQueue(submitsUserInitiatedRun: true)
    }

    public func continueQueue(submitsUserInitiatedRun: Bool) async throws {
        try await store.retryFailedOfflineCacheWorks()
        try await store.setOfflineCacheQueueRunState(.running)
        if let runTask, !runTask.isCancelled {
            return
        }

        if submitsUserInitiatedRun {
            await runObserver?.submitUserInitiatedRun()
        }
        runGeneration += 1
        let generation = runGeneration
        runTask = Task { [weak self] in
            await self?.runQueue(generation: generation)
        }
    }

    public func pauseQueue() async throws {
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        try await store.setOfflineCacheQueueRunState(.paused)
        await runObserver?.queueRunDidCancel()
    }

    public func cancelChapter(ownerName: String, tid: String) async throws {
        let wasRunning = await store.offlineCacheQueueRunState() == .running
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        await runObserver?.queueRunDidCancel()
        try await store.cancelOfflineCacheEntry(
            OfflineCacheEntryID(readerKind: .manga, ownerKey: ownerName, entryKey: tid)
        )
        if wasRunning {
            try await continueQueue()
        }
    }

    public func cancelOwnerGroup(ownerName: String) async throws {
        let wasRunning = await store.offlineCacheQueueRunState() == .running
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        await runObserver?.queueRunDidCancel()
        try await store.cancelOfflineCacheGroup(
            OfflineCacheGroupID(readerKind: .manga, ownerKey: ownerName)
        )
        if wasRunning {
            try await continueQueue()
        }
    }

    public func cancelWork(id: OfflineCacheWorkID) async throws {
        let wasRunning = await store.offlineCacheQueueRunState() == .running
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        await runObserver?.queueRunDidCancel()
        try await store.cancelOfflineCacheWork(id: id)
        if wasRunning {
            try await continueQueue()
        }
    }

    public func cancelGroup(id: OfflineCacheGroupID) async throws {
        let wasRunning = await store.offlineCacheQueueRunState() == .running
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        await runObserver?.queueRunDidCancel()
        try await store.cancelOfflineCacheGroup(id)
        if wasRunning {
            try await continueQueue()
        }
    }

    public func waitForIdle() async {
        let task = runTask
        await task?.value
    }

    private func runQueue(generation: Int) async {
        while !Task.isCancelled {
            guard await store.offlineCacheQueueRunState() == .running else {
                await runObserver?.queueRunDidFinish(success: false)
                await finishRun(generation: generation, pauseQueue: false)
                return
            }

            guard let work = await store.nextOfflineCacheProcessingWork() else {
                await runObserver?.queueRunDidFinish(success: true)
                await finishRun(generation: generation, pauseQueue: true)
                return
            }

            do {
                try await process(work)
            } catch is CancellationError {
                await finishRun(generation: generation, pauseQueue: false)
                return
            } catch {
                try? await store.markOfflineCacheWorkFailed(
                    id: work.id,
                    message: Self.failureMessage(from: error)
                )
                await runObserver?.queueRunDidFinish(success: false)
                await finishRun(generation: generation, pauseQueue: true)
                return
            }
        }

        await runObserver?.queueRunDidFinish(success: false)
        await finishRun(generation: generation, pauseQueue: false)
    }

    private func finishRun(generation: Int, pauseQueue: Bool) async {
        guard runGeneration == generation else { return }
        if pauseQueue {
            try? await store.setOfflineCacheQueueRunState(.paused)
        }
        runTask = nil
    }

    private func process(_ work: OfflineCacheProcessingWork) async throws {
        switch work.id.readerKind {
        case .manga:
            try await mangaWorkProcessor.process(work)
        case .novel:
            guard let novelWorkProcessor else {
                throw YamiboError.parsingFailed(context: "Novel Offline Cache")
            }
            try await novelWorkProcessor.process(work)
        }
    }

    private static func failureMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.mangaReaderTrimmedNonEmpty {
            return description
        }
        return error.localizedDescription
    }
}
