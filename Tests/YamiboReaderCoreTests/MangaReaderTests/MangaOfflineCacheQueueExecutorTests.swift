import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Queue Executor")
struct MangaReaderTestsMangaOfflineCacheQueueExecutor {
    @Test func continueProcessesOneChapterAtATimeWithThreeImageTransferLimit() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let firstChapterImages = try makeImageURLs(tid: "100", count: 4)
        let secondChapterImages = try makeImageURLs(tid: "200", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "100", targetImageURLs: firstChapterImages)
        )
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "200", targetImageURLs: secondChapterImages)
        )
        let acquirer = RecordingOfflineImageAcquirer(delayNanoseconds: 20_000_000)
        await acquirer.setData(for: firstChapterImages + secondChapterImages)
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let requestedURLs = await acquirer.requestedURLs
        let firstSecondChapterIndex = try #require(requestedURLs.firstIndex(of: secondChapterImages[0]))
        let lastFirstChapterIndex = try #require(firstChapterImages.compactMap { requestedURLs.firstIndex(of: $0) }.max())
        #expect(lastFirstChapterIndex < firstSecondChapterIndex)
        #expect(await acquirer.maxActiveCount <= 3)
        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "200") == nil)
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .cached)
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "200") == .cached)
    }

    @Test func continueLoadsChapterDocumentBeforeImageCountProgressAndRebuildsChapterURLFromTid() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "300", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            MangaOfflineCacheWorkRequest(
                favoriteID: "favorite-a",
                favoriteTitle: "作品",
                favoriteURL: try #require(URL(string: "https://bbs.yamibo.com/thread-300-1-1.html")),
                tid: "300",
                chapterTitle: "第300话",
                chapterURL: try #require(URL(string: "https://stale.example.com/old/path?x=1")),
                targetImageURLs: []
            )
        )
        let documentLoader = RecordingChapterDocumentLoader()
        await documentLoader.setDocument(
            try makeDocument(tid: "300", imageURLs: imageURLs),
            forAnyRequest: true
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: documentLoader,
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let requestedURL = try #require(await documentLoader.requestedURLs.first)
        let components = try #require(URLComponents(url: requestedURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(components.host == "bbs.yamibo.com")
        #expect(components.path == "/forum.php")
        #expect(queryItems["tid"] == "300")
        let completedWork = await store.offlineCacheWork(favoriteID: "favorite-a", tid: "300")
        #expect(completedWork == nil)
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "300") == .cached)
    }

    @Test func pauseCancelsInFlightTransfersAndPreservesCompletedProgress() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "400", count: 4)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "400", targetImageURLs: imageURLs)
        )
        let acquirer = FirstImageOnlyImmediateAcquirer(firstImageURL: imageURLs[0])
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        try await waitUntil {
            await store.offlineCacheWork(favoriteID: "favorite-a", tid: "400")?.completedImageURLs == [imageURLs[0]]
        }
        try await executor.pauseQueue()
        await executor.waitForIdle()

        let work = try #require(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "400"))
        #expect(work.completedImageURLs == [imageURLs[0]])
        #expect(work.progress == MangaOfflineCacheProgress(completedImageCount: 1, targetImageCount: 4))
        #expect(work.currentBytesPerSecond == 0)
        #expect(await store.offlineCacheQueueRunState() == .paused)
        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([1]))
        #expect(await store.offlineImageData(for: imageURLs[1]) == nil)
    }

    @Test func failedWorkRemainsQueuedAndContinueRetriesFromRetainedProgress() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "500", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "500", targetImageURLs: imageURLs)
        )
        let acquirer = RetryOfflineImageAcquirer(failingImageURL: imageURLs[1])
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer,
            maxConcurrentImageTransfers: 1
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let failedWork = try #require(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "500"))
        #expect(failedWork.state == .failed)
        #expect(failedWork.completedImageURLs == [imageURLs[0]])
        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([1]))

        await acquirer.allowRetry()
        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "500") == nil)
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "500") == .cached)
        #expect(await acquirer.requestedURLs == [imageURLs[1]])
    }

    @Test func continueReconcilesPersistedProgressAgainstOfflineImageStorage() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "600", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "600", targetImageURLs: imageURLs)
        )
        try await store.saveOfflineImageData(Data([1]), for: imageURLs[0])
        try await store.updateOfflineCacheWorkProgress(
            favoriteID: "favorite-a",
            tid: "600",
            targetImageURLs: imageURLs,
            completedImageURLs: imageURLs,
            currentBytesPerSecond: nil
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: [imageURLs[1]])
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await acquirer.requestedURLs == [imageURLs[1]])
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "600") == .cached)
    }

    @Test func transparentCacheHitsAreCopiedToOfflineStorageAndNetworkMissesAreFetched() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let transparentCache = FileMangaImageDataCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "700", count: 2)
        try await transparentCache.save(Data([7]), for: imageURLs[0])
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "700", targetImageURLs: imageURLs)
        )
        let networkLoader = RecordingNetworkImageLoader(dataByURL: [imageURLs[1]: Data([8])])
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: MangaOfflineCacheImageAcquirer(
                transparentCache: transparentCache,
                networkLoader: networkLoader
            )
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([7]))
        #expect(await store.offlineImageData(for: imageURLs[1]) == Data([8]))
        #expect(await transparentCache.data(for: imageURLs[0]) == Data([7]))
        #expect(await networkLoader.requestedURLs == [imageURLs[1]])
    }

    @Test func chapterCancellationRemovesPartialOfflineBytesForCanceledWork() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "800", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "800", targetImageURLs: imageURLs)
        )
        try await store.saveOfflineImageData(Data([1]), for: imageURLs[0])
        try await store.updateOfflineCacheWorkProgress(
            favoriteID: "favorite-a",
            tid: "800",
            targetImageURLs: imageURLs,
            completedImageURLs: [imageURLs[0]],
            currentBytesPerSecond: nil
        )
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.cancelChapter(favoriteID: "favorite-a", tid: "800")

        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "800") == nil)
        #expect(await store.offlineImageData(for: imageURLs[0]) == nil)
    }

    @Test func favoriteGroupCancellationRemovesPartialOfflineBytesForCanceledWorkOnly() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let canceledImages = try makeImageURLs(tid: "900", count: 1)
        let retainedImages = try makeImageURLs(tid: "901", count: 1)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-a", tid: "900", targetImageURLs: canceledImages)
        )
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(favoriteID: "favorite-b", tid: "901", targetImageURLs: retainedImages)
        )
        try await store.saveOfflineImageData(Data([9]), for: canceledImages[0])
        try await store.saveOfflineImageData(Data([1]), for: retainedImages[0])
        try await store.updateOfflineCacheWorkProgress(
            favoriteID: "favorite-a",
            tid: "900",
            targetImageURLs: canceledImages,
            completedImageURLs: canceledImages,
            currentBytesPerSecond: nil
        )
        try await store.updateOfflineCacheWorkProgress(
            favoriteID: "favorite-b",
            tid: "901",
            targetImageURLs: retainedImages,
            completedImageURLs: retainedImages,
            currentBytesPerSecond: nil
        )
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.cancelFavoriteGroup(favoriteID: "favorite-a")

        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "900") == nil)
        #expect(await store.offlineCacheWork(favoriteID: "favorite-b", tid: "901") != nil)
        #expect(await store.offlineImageData(for: canceledImages[0]) == nil)
        #expect(await store.offlineImageData(for: retainedImages[0]) == Data([1]))
    }
}

private actor RecordingChapterDocumentLoader: MangaChapterDocumentLoading {
    private(set) var requestedURLs: [URL] = []
    private var documentByURL: [String: MangaChapterDocument] = [:]
    private var anyDocument: MangaChapterDocument?

    func setDocument(_ document: MangaChapterDocument, forAnyRequest: Bool = false) {
        if forAnyRequest {
            anyDocument = document
        } else {
            documentByURL[document.chapterURL.absoluteString] = document
        }
    }

    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        requestedURLs.append(url)
        if let document = documentByURL[url.absoluteString] ?? anyDocument {
            return document
        }
        throw YamiboError.parsingFailed(context: "Missing test Manga Chapter Document")
    }
}

private actor RecordingOfflineImageAcquirer: MangaOfflineCacheImageAcquiring {
    private(set) var requestedURLs: [URL] = []
    private(set) var maxActiveCount = 0
    private let delayNanoseconds: UInt64
    private var activeCount = 0
    private var dataByURL: [URL: Data] = [:]

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func setData(for imageURLs: [URL]) {
        for (index, imageURL) in imageURLs.enumerated() {
            dataByURL[imageURL] = Data([UInt8((index % 200) + 1)])
        }
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition {
        requestedURLs.append(imageURL)
        activeCount += 1
        maxActiveCount = max(maxActiveCount, activeCount)
        defer { activeCount -= 1 }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard let data = dataByURL[imageURL] else {
            throw YamiboError.invalidResponse(statusCode: 404)
        }
        return MangaOfflineCacheImageAcquisition(data: data, source: .network)
    }
}

private actor FirstImageOnlyImmediateAcquirer: MangaOfflineCacheImageAcquiring {
    private let firstImageURL: URL

    init(firstImageURL: URL) {
        self.firstImageURL = firstImageURL
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition {
        if imageURL == firstImageURL {
            return MangaOfflineCacheImageAcquisition(data: Data([1]), source: .network)
        }
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return MangaOfflineCacheImageAcquisition(data: Data([2]), source: .network)
    }
}

private actor RetryOfflineImageAcquirer: MangaOfflineCacheImageAcquiring {
    private(set) var requestedURLs: [URL] = []
    private let failingImageURL: URL
    private var shouldFail = true

    init(failingImageURL: URL) {
        self.failingImageURL = failingImageURL
    }

    func allowRetry() {
        shouldFail = false
        requestedURLs.removeAll()
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition {
        requestedURLs.append(imageURL)
        if imageURL == failingImageURL, shouldFail {
            throw YamiboError.offline
        }
        return MangaOfflineCacheImageAcquisition(data: imageURL == failingImageURL ? Data([2]) : Data([1]), source: .network)
    }
}

private actor RecordingNetworkImageLoader: MangaImageDataLoading {
    private(set) var requestedURLs: [URL] = []
    private let dataByURL: [URL: Data]

    init(dataByURL: [URL: Data]) {
        self.dataByURL = dataByURL
    }

    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        requestedURLs.append(url)
        guard let data = dataByURL[url] else {
            throw YamiboError.invalidResponse(statusCode: 404)
        }
        return data
    }
}

private func makeExecutorWorkRequest(
    favoriteID: String,
    tid: String,
    targetImageURLs: [URL]
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        favoriteID: favoriteID,
        favoriteTitle: "作品",
        favoriteURL: try #require(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html")),
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        targetImageURLs: targetImageURLs
    )
}

private func makeDocument(tid: String, imageURLs: [URL]) throws -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1")),
        imageURLs: imageURLs
    )
}

private func makeImageURLs(tid: String, count: Int) throws -> [URL] {
    try (1...count).map { index in
        try #require(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
    }
}

private func makeTemporaryExecutorDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping () async -> Bool
) async throws {
    let start = ContinuousClock.now
    while await condition() == false {
        if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
            throw YamiboError.underlying("Timed out waiting for condition")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
