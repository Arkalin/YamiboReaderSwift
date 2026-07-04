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
    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> OfflineCacheImageAcquisition
}

public protocol OfflineCacheImageTransporting: Sendable {
    func downloadImageData(for imageURL: URL, refererURL: URL?) async throws -> Data
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

    public func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> OfflineCacheImageAcquisition {
        let request = YamiboImageRequest(
            url: imageURL,
            refererURL: refererURL
        )

        let data: Data
        if let backgroundTransport {
            data = try await backgroundTransport.downloadImageData(for: imageURL, refererURL: refererURL)
        } else {
            data = try await networkLoader.imageData(for: request)
        }
        return OfflineCacheImageAcquisition(data: data, source: .network)
    }
}

public actor OfflineCacheQueueExecutor {
    private let store: any OfflineCacheStoring
    private let readerProjectionLoader: any MangaReaderProjectionSnapshotLoading
    private let novelSourcePageLoader: (any NovelOfflineCacheSourcePageLoading)?
    private let imageAcquirer: any OfflineCacheImageAcquiring
    private let runObserver: (any OfflineCacheQueueRunObserving)?
    private let maxConcurrentImageTransfers: Int
    private var runTask: Task<Void, Never>?
    private var runGeneration = 0

    public init(
        store: any OfflineCacheStoring,
        readerProjectionLoader: any MangaReaderProjectionSnapshotLoading,
        novelSourcePageLoader: (any NovelOfflineCacheSourcePageLoading)? = nil,
        imageAcquirer: any OfflineCacheImageAcquiring,
        runObserver: (any OfflineCacheQueueRunObserving)? = nil,
        maxConcurrentImageTransfers: Int = 3
    ) {
        self.store = store
        self.readerProjectionLoader = readerProjectionLoader
        self.novelSourcePageLoader = novelSourcePageLoader
        self.imageAcquirer = imageAcquirer
        self.runObserver = runObserver
        self.maxConcurrentImageTransfers = max(1, maxConcurrentImageTransfers)
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
        try await store.cancelOfflineCacheWork(ownerName: ownerName, tid: tid)
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
        try await store.cancelOfflineCacheWorks(forOwnerName: ownerName)
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
            try await processManga(work)
        case .novel:
            try await processNovel(work)
        }
    }

    private func processManga(_ work: OfflineCacheProcessingWork) async throws {
        let mangaWork = MangaOfflineCacheWork(
            workID: work.id.rawValue,
            ownerName: work.entryID.ownerKey,
            tid: work.entryID.entryKey,
            chapterTitle: work.title,
            chapterURL: Self.rebuiltChapterURL(tid: work.entryID.entryKey),
            targetImageURLs: work.targetImageURLs,
            completedImageURLs: work.completedImageURLs,
            state: MangaOfflineCacheWorkState(rawValue: work.state.rawValue) ?? .paused,
            failureMessage: work.failureMessage,
            currentBytesPerSecond: work.currentBytesPerSecond,
            insertionIndex: work.insertionIndex,
            createdAt: work.createdAt,
            updatedAt: work.updatedAt
        )
        try await process(mangaWork)
    }

    private func process(_ work: MangaOfflineCacheWork) async throws {
        try Task.checkCancellation()
        let workID = OfflineCacheWorkID(readerKind: .manga, rawValue: work.workID)
        guard await store.offlineCacheProcessingWork(id: workID) != nil else {
            throw CancellationError()
        }

        let projectionBacked = try await workWithReaderProjection(work)
        let projectionBackedWork = projectionBacked.work
        let targetImageURLs = projectionBackedWork.targetImageURLs
        guard !targetImageURLs.isEmpty else {
            throw YamiboError.parsingFailed(context: "Manga Offline Cache")
        }

        var completedImageURLs = await reconciledCompletedImageURLs(targetImageURLs)
        try await store.prepareOfflineCacheWorkForRun(
            id: workID,
            targetImageURLs: targetImageURLs,
            completedImageURLs: completedImageURLs
        )
        await runObserver?.queueRunDidUpdateProgress(
            completedImageCount: completedImageURLs.count,
            targetImageCount: targetImageURLs.count
        )

        if completedImageURLs.count < targetImageURLs.count {
            completedImageURLs = try await transferMissingImages(
                workID: workID,
                refererURL: projectionBackedWork.chapterURL,
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs
            )
        }

        try Task.checkCancellation()
        try await store.saveMembership(
            MangaOfflineCacheMembership(
                ownerName: projectionBackedWork.ownerName,
                tid: projectionBackedWork.tid,
                chapterTitle: projectionBackedWork.chapterTitle,
                chapterURL: projectionBackedWork.chapterURL,
                imageURLs: targetImageURLs,
                sourcePage: projectionBacked.sourcePage
            )
        )
    }

    private func processNovel(_ work: OfflineCacheProcessingWork) async throws {
        try Task.checkCancellation()
        guard await store.offlineCacheProcessingWork(id: work.id) != nil else {
            throw CancellationError()
        }
        guard let novelSourcePageLoader else {
            throw YamiboError.parsingFailed(context: "Novel Offline Cache")
        }

        let request = try novelWorkRequest(from: work)
        let prepared = try await novelSourcePageLoader.loadNovelOfflineCacheSourcePage(request)
        let targetImageURLs = work.retainsInlineImages
            ? Self.inlineImageURLs(in: prepared.document)
            : work.targetImageURLs
        var sourcePageRequest = request
        sourcePageRequest.targetImageURLs = targetImageURLs
        try await store.saveNovelOfflineSourcePage(
            prepared.sourcePage,
            request: sourcePageRequest,
            projectionPrewarm: prepared.document,
            updatedAt: .now,
            completesMatchingWork: targetImageURLs.isEmpty,
            preservesExistingImageReferencesWhenEmpty: targetImageURLs.isEmpty && !work.retainsInlineImages
        )

        guard !targetImageURLs.isEmpty else { return }

        var completedImageURLs = await reconciledCompletedImageURLs(targetImageURLs)
        try await store.prepareOfflineCacheWorkForRun(
            id: work.id,
            targetImageURLs: targetImageURLs,
            completedImageURLs: completedImageURLs
        )
        await runObserver?.queueRunDidUpdateProgress(
            completedImageCount: completedImageURLs.count,
            targetImageCount: targetImageURLs.count
        )

        if completedImageURLs.count < targetImageURLs.count {
            completedImageURLs = try await transferMissingImages(
                workID: work.id,
                refererURL: request.threadURL,
                targetImageURLs: targetImageURLs,
                completedImageURLs: completedImageURLs
            )
        }

        try Task.checkCancellation()
        guard await store.offlineCacheProcessingWork(id: work.id) != nil else {
            throw CancellationError()
        }
        try await store.finishOfflineCacheWork(id: work.id)
    }

    private func workWithReaderProjection(_ work: MangaOfflineCacheWork) async throws -> MangaOfflineCacheProjectionBackedWork {
        let recoveryURL = Self.rebuiltChapterURL(tid: work.tid)
        let snapshot = try await readerProjectionLoader.loadReaderProjectionSnapshot(at: recoveryURL)

        return MangaOfflineCacheProjectionBackedWork(
            work: work.preparingForRun(
                targetImageURLs: snapshot.projection.imageURLs,
                completedImageURLs: []
            ),
            sourcePage: snapshot.sourcePage
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
        workID: OfflineCacheWorkID,
        refererURL: URL,
        targetImageURLs: [URL],
        completedImageURLs: [URL]
    ) async throws -> [URL] {
        var completedKeys = Set(completedImageURLs.map(\.absoluteString))
        var completed = targetImageURLs.filter { completedKeys.contains($0.absoluteString) }
        let pending = targetImageURLs.filter { !completedKeys.contains($0.absoluteString) }

        try await withThrowingTaskGroup(of: OfflineCacheImageTransferResult.self) { group in
            var pendingIterator = pending.makeIterator()
            var activeCount = 0

            func submitNext() {
                guard activeCount < maxConcurrentImageTransfers, let imageURL = pendingIterator.next() else {
                    return
                }
                activeCount += 1
                group.addTask { [store, imageAcquirer] in
                    try Task.checkCancellation()
                    guard await store.offlineCacheProcessingWork(id: workID) != nil else {
                        throw CancellationError()
                    }
                    let startedAt = Date()
                    let acquisition = try await imageAcquirer.acquireImageData(for: imageURL, refererURL: refererURL)
                    guard !acquisition.data.isEmpty else {
                        throw YamiboError.invalidResponse(statusCode: nil)
                    }
                    try Task.checkCancellation()
                    guard await store.offlineCacheProcessingWork(id: workID) != nil else {
                        throw CancellationError()
                    }
                    try await store.saveOfflineImageData(acquisition.data, for: imageURL)
                    return OfflineCacheImageTransferResult(
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
                    id: workID,
                    targetImageURLs: targetImageURLs,
                    completedImageURLs: completed,
                    currentBytesPerSecond: result.bytesPerSecond
                )
                await runObserver?.queueRunDidUpdateProgress(
                    completedImageCount: completed.count,
                    targetImageCount: targetImageURLs.count
                )
                submitNext()
            }
        }

        return completed
    }

    private func novelWorkRequest(from work: OfflineCacheProcessingWork) throws -> NovelOfflineCacheWorkRequest {
        guard work.entryID.readerKind == .novel,
              let components = OfflineCacheStore.novelEntryKeyComponents(from: work.entryID.entryKey) else {
            throw YamiboError.parsingFailed(context: "Novel Offline Cache")
        }
        return NovelOfflineCacheWorkRequest(
            ownerTitle: work.entryID.ownerKey,
            title: work.title,
            threadURL: Self.rebuiltChapterURL(tid: components.threadID),
            view: components.view,
            authorID: components.authorID,
            contentSource: components.contentSource,
            targetImageURLs: work.targetImageURLs,
            retainsInlineImages: work.retainsInlineImages
        )
    }

    private static func inlineImageURLs(in document: ReaderPageDocument) -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []
        for segment in document.segments {
            guard case let .image(url, _) = segment else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
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

private struct OfflineCacheImageTransferResult: Sendable {
    var imageURL: URL
    var bytesPerSecond: Int
}

private struct MangaOfflineCacheProjectionBackedWork: Sendable {
    var work: MangaOfflineCacheWork
    var sourcePage: ForumThreadPage
}
