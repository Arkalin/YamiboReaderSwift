import Foundation

public enum MangaOfflineCacheImageAcquisitionSource: Hashable, Sendable {
    case transparentCache
    case network
}

public struct MangaOfflineCacheImageAcquisition: Hashable, Sendable {
    public var data: Data
    public var source: MangaOfflineCacheImageAcquisitionSource

    public init(data: Data, source: MangaOfflineCacheImageAcquisitionSource) {
        self.data = data
        self.source = source
    }
}

public protocol MangaOfflineCacheImageAcquiring: Sendable {
    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition
}

public actor MangaOfflineCacheImageAcquirer: MangaOfflineCacheImageAcquiring {
    private let transparentCache: any MangaImageDataCaching
    private let networkLoader: any MangaImageDataLoading

    public init(
        transparentCache: any MangaImageDataCaching,
        networkLoader: any MangaImageDataLoading
    ) {
        self.transparentCache = transparentCache
        self.networkLoader = networkLoader
    }

    public func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition {
        if let cached = await transparentCache.data(for: imageURL) {
            return MangaOfflineCacheImageAcquisition(data: cached, source: .transparentCache)
        }

        let data = try await networkLoader.imageData(for: imageURL, refererURL: refererURL)
        return MangaOfflineCacheImageAcquisition(data: data, source: .network)
    }
}

public actor MangaOfflineCacheQueueExecutor {
    private let store: any MangaOfflineCacheStoring
    private let chapterDocumentLoader: any MangaChapterDocumentLoading
    private let imageAcquirer: any MangaOfflineCacheImageAcquiring
    private let maxConcurrentImageTransfers: Int
    private var runTask: Task<Void, Never>?
    private var runGeneration = 0

    public init(
        store: any MangaOfflineCacheStoring,
        chapterDocumentLoader: any MangaChapterDocumentLoading,
        imageAcquirer: any MangaOfflineCacheImageAcquiring,
        maxConcurrentImageTransfers: Int = 3
    ) {
        self.store = store
        self.chapterDocumentLoader = chapterDocumentLoader
        self.imageAcquirer = imageAcquirer
        self.maxConcurrentImageTransfers = max(1, maxConcurrentImageTransfers)
    }

    public func continueQueue() async throws {
        try await store.setOfflineCacheQueueRunState(.running)
        if let runTask, !runTask.isCancelled {
            return
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
    }

    public func cancelChapter(favoriteID: String, tid: String) async throws {
        let wasRunning = await store.offlineCacheQueueRunState() == .running
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        try await store.cancelOfflineCacheWork(favoriteID: favoriteID, tid: tid)
        if wasRunning {
            try await continueQueue()
        }
    }

    public func cancelFavoriteGroup(favoriteID: String) async throws {
        let wasRunning = await store.offlineCacheQueueRunState() == .running
        runGeneration += 1
        runTask?.cancel()
        runTask = nil
        try await store.cancelOfflineCacheWorks(forFavoriteID: favoriteID)
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
                await finishRun(generation: generation, pauseQueue: false)
                return
            }

            guard let work = await store.allOfflineCacheWorks().first else {
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
                    favoriteID: work.favoriteID,
                    tid: work.tid,
                    message: Self.failureMessage(from: error)
                )
                await finishRun(generation: generation, pauseQueue: true)
                return
            }
        }

        await finishRun(generation: generation, pauseQueue: false)
    }

    private func finishRun(generation: Int, pauseQueue: Bool) async {
        guard runGeneration == generation else { return }
        if pauseQueue {
            try? await store.setOfflineCacheQueueRunState(.paused)
        }
        runTask = nil
    }

    private func process(_ work: MangaOfflineCacheWork) async throws {
        try Task.checkCancellation()
        guard await store.offlineCacheWork(favoriteID: work.favoriteID, tid: work.tid) != nil else {
            throw CancellationError()
        }

        let documentBackedWork = try await workWithChapterDocument(work)
        let targetImageURLs = documentBackedWork.targetImageURLs
        guard !targetImageURLs.isEmpty else {
            throw YamiboError.parsingFailed(context: "Manga Offline Cache")
        }

        var completedImageURLs = await reconciledCompletedImageURLs(targetImageURLs)
        try await store.prepareOfflineCacheWorkForRun(
            favoriteID: documentBackedWork.favoriteID,
            tid: documentBackedWork.tid,
            targetImageURLs: targetImageURLs,
            completedImageURLs: completedImageURLs
        )

        if completedImageURLs.count < targetImageURLs.count {
            completedImageURLs = try await transferMissingImages(
                for: documentBackedWork,
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs
            )
        }

        try Task.checkCancellation()
        try await store.saveMembership(
            MangaOfflineCacheMembership(
                favoriteID: documentBackedWork.favoriteID,
                favoriteTitle: documentBackedWork.favoriteTitle,
                favoriteURL: documentBackedWork.favoriteURL,
                tid: documentBackedWork.tid,
                chapterTitle: documentBackedWork.chapterTitle,
                chapterURL: documentBackedWork.chapterURL,
                imageURLs: targetImageURLs
            )
        )
    }

    private func workWithChapterDocument(_ work: MangaOfflineCacheWork) async throws -> MangaOfflineCacheWork {
        guard work.targetImageURLs.isEmpty else {
            return work
        }

        let recoveryURL = Self.rebuiltChapterURL(tid: work.tid)
        let document = try await chapterDocumentLoader.loadChapterDocument(at: recoveryURL)
        return work.preparingForRun(
            targetImageURLs: document.imageURLs,
            completedImageURLs: []
        )
    }

    private func reconciledCompletedImageURLs(_ targetImageURLs: [URL]) async -> [URL] {
        var completed: [URL] = []
        for imageURL in targetImageURLs {
            if await store.offlineImageData(for: imageURL) != nil {
                completed.append(imageURL)
            }
        }
        return completed
    }

    private func transferMissingImages(
        for work: MangaOfflineCacheWork,
        targetImageURLs: [URL],
        completedImageURLs: [URL]
    ) async throws -> [URL] {
        var completedKeys = Set(completedImageURLs.map(\.absoluteString))
        var completed = targetImageURLs.filter { completedKeys.contains($0.absoluteString) }
        let pending = targetImageURLs.filter { !completedKeys.contains($0.absoluteString) }

        try await withThrowingTaskGroup(of: MangaOfflineCacheImageTransferResult.self) { group in
            var pendingIterator = pending.makeIterator()
            var activeCount = 0

            func submitNext() {
                guard activeCount < maxConcurrentImageTransfers, let imageURL = pendingIterator.next() else {
                    return
                }
                activeCount += 1
                group.addTask { [store, imageAcquirer] in
                    try Task.checkCancellation()
                    guard await store.offlineCacheWork(favoriteID: work.favoriteID, tid: work.tid) != nil else {
                        throw CancellationError()
                    }
                    let startedAt = Date()
                    let acquisition = try await imageAcquirer.acquireImageData(for: imageURL, refererURL: work.chapterURL)
                    try Task.checkCancellation()
                    guard await store.offlineCacheWork(favoriteID: work.favoriteID, tid: work.tid) != nil else {
                        throw CancellationError()
                    }
                    try await store.saveOfflineImageData(acquisition.data, for: imageURL)
                    return MangaOfflineCacheImageTransferResult(
                        imageURL: imageURL,
                        bytesPerSecond: Self.bytesPerSecond(byteCount: acquisition.data.count, startedAt: startedAt)
                    )
                }
            }

            for _ in 0..<maxConcurrentImageTransfers {
                submitNext()
            }

            while let result = try await group.next() {
                activeCount -= 1
                completedKeys.insert(result.imageURL.absoluteString)
                completed = targetImageURLs.filter { completedKeys.contains($0.absoluteString) }
                try await store.updateOfflineCacheWorkProgress(
                    favoriteID: work.favoriteID,
                    tid: work.tid,
                    targetImageURLs: targetImageURLs,
                    completedImageURLs: completed,
                    currentBytesPerSecond: result.bytesPerSecond
                )
                submitNext()
            }
        }

        return completed
    }

    private static func rebuiltChapterURL(tid: String) -> URL {
        var components = URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/forum.php"
        components.queryItems = [
            URLQueryItem(name: "mobile", value: "2"),
            URLQueryItem(name: "mod", value: "viewthread"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "tid", value: tid.trimmingCharacters(in: .whitespacesAndNewlines))
        ]
        return components.url!
    }

    private static func failureMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription?.mangaReaderTrimmedNonEmpty {
            return description
        }
        return error.localizedDescription
    }

    private static func bytesPerSecond(byteCount: Int, startedAt: Date) -> Int {
        let elapsed = max(Date().timeIntervalSince(startedAt), 0.001)
        return max(0, Int(Double(byteCount) / elapsed))
    }
}

private struct MangaOfflineCacheImageTransferResult: Sendable {
    var imageURL: URL
    var bytesPerSecond: Int
}
