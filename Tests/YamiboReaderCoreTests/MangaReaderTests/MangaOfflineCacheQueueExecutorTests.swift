import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Queue Executor")
struct MangaReaderTestsMangaOfflineCacheQueueExecutor {
    @Test func continueProcessesOneChapterAtATimeWithThreeImageTransferLimit() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let firstChapterImages = try makeImageURLs(tid: "100", count: 4)
        let secondChapterImages = try makeImageURLs(tid: "200", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "100", targetImageURLs: firstChapterImages)
        )
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "200", targetImageURLs: secondChapterImages)
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
        #expect(await store.offlineCacheWork(ownerName: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineCacheWork(ownerName: "favorite-a", tid: "200") == nil)
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "100") == .cached)
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "200") == .cached)
    }

    @Test func continueLoadsChapterDocumentBeforeImageCountProgressAndRebuildsChapterURLFromTid() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "300", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            MangaOfflineCacheWorkRequest(
                ownerName: "favorite-a",
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
        let completedWork = await store.offlineCacheWork(ownerName: "favorite-a", tid: "300")
        #expect(completedWork == nil)
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "300") == .cached)
    }

    @Test func cacheCompletionDoesNotUpdateReadingProgressResumeRouteOrRecentReading() async throws {
        let suiteName = "manga-offline-cache-no-progress-side-effects-\(UUID().uuidString)"
        try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let favoriteStore = FavoriteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "favorites")
        let resumeRouteStore = ReaderResumeRouteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "resume-route")
        let ownerURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=350&mobile=2"))
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=350&page=2&mobile=2"))
        let favorite = Favorite(
            id: "favorite-progress",
            title: "阅读进度漫画",
            url: ownerURL,
            mangaPageIndex: 5,
            lastChapter: "既有章节",
            type: .manga,
            lastMangaURL: chapterURL,
            lastReadAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let resumeRoute = ReaderResumeRoute.manga(.native(MangaLaunchContext(
            originalThreadURL: ownerURL,
            chapterURL: chapterURL,
            displayTitle: "阅读进度漫画",
            source: .resume,
            initialPage: 5
        )))
        let imageURLs = try makeImageURLs(tid: "350", count: 2)
        try await favoriteStore.saveFavorites([favorite])
        try await resumeRouteStore.save(resumeRoute)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: favorite.id, tid: "350", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheState(ownerName: favorite.id, tid: "350") == .cached)
        #expect(await favoriteStore.favorite(id: favorite.id) == favorite)
        #expect(await resumeRouteStore.load() == .manga(.native(MangaLaunchContext(
            originalThreadURL: try #require(MangaReaderDataSupport.chapterURL(forTID: "350")),
            chapterURL: try #require(MangaReaderDataSupport.chapterURL(forTID: "350")),
            displayTitle: "阅读进度漫画",
            source: .resume,
            initialPage: 5
        ))))
    }

    @Test func pauseCancelsInFlightTransfersAndPreservesCompletedProgress() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "400", count: 4)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "400", targetImageURLs: imageURLs)
        )
        let acquirer = FirstImageOnlyImmediateAcquirer(firstImageURL: imageURLs[0])
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        try await waitUntil {
            await store.offlineCacheWork(ownerName: "favorite-a", tid: "400")?.completedImageURLs == [imageURLs[0]]
        }
        try await executor.pauseQueue()
        await executor.waitForIdle()

        let work = try #require(await store.offlineCacheWork(ownerName: "favorite-a", tid: "400"))
        #expect(work.completedImageURLs == [imageURLs[0]])
        #expect(work.progress == MangaOfflineCacheProgress(completedImageCount: 1, targetImageCount: 4))
        #expect(work.currentBytesPerSecond == 0)
        #expect(await store.offlineCacheQueueRunState() == .paused)
        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([1]))
        #expect(await store.offlineImageData(for: imageURLs[1]) == nil)
    }

    @Test func failedWorkRemainsQueuedAndContinueRetriesFromRetainedProgress() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "500", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "500", targetImageURLs: imageURLs)
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

        let failedWork = try #require(await store.offlineCacheWork(ownerName: "favorite-a", tid: "500"))
        #expect(failedWork.state == .failed)
        #expect(failedWork.completedImageURLs == [imageURLs[0]])
        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([1]))

        await acquirer.allowRetry()
        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheWork(ownerName: "favorite-a", tid: "500") == nil)
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "500") == .cached)
        #expect(await acquirer.requestedURLs == [imageURLs[1]])
    }

    @Test func emptyImageDataFailsWorkWithoutAdvancingProgress() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "550", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "550", targetImageURLs: imageURLs)
        )
        let acquirer = EmptyImageThenFailingAcquirer(emptyImageURL: imageURLs[0])
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer,
            maxConcurrentImageTransfers: 1
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let failedWork = try #require(await store.offlineCacheWork(ownerName: "favorite-a", tid: "550"))
        #expect(failedWork.state == .failed)
        #expect(failedWork.completedImageURLs.isEmpty)
        #expect(failedWork.progress == MangaOfflineCacheProgress(completedImageCount: 0, targetImageCount: 2))
        #expect(await store.offlineImageData(for: imageURLs[0]) == nil)
        #expect(await acquirer.requestedURLs == [imageURLs[0]])
    }

    @Test func continueReconcilesPersistedProgressAgainstOfflineImageStorage() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "600", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "600", targetImageURLs: imageURLs)
        )
        try await store.saveOfflineImageData(Data([1]), for: imageURLs[0])
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "favorite-a",
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
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "600") == .cached)
    }

    @Test func transparentCacheHitsAreCopiedToOfflineStorageAndNetworkMissesAreFetched() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let transparentCache = FileMangaImageDataCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "700", count: 2)
        try await transparentCache.save(Data([7]), for: imageURLs[0])
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "700", targetImageURLs: imageURLs)
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

    @Test func transparentCacheMissesUseBackgroundTransport() async throws {
        let transparentCache = FileMangaImageDataCacheStore(baseDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "710", count: 2)
        try await transparentCache.save(Data([7]), for: imageURLs[0])
        let transport = RecordingImageTransport(dataByURL: [imageURLs[1]: Data([8])])
        let networkLoader = RecordingNetworkImageLoader(dataByURL: [:])
        let acquirer = MangaOfflineCacheImageAcquirer(
            transparentCache: transparentCache,
            networkLoader: networkLoader,
            backgroundTransport: transport
        )
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=710"))

        let cacheHit = try await acquirer.acquireImageData(for: imageURLs[0], refererURL: refererURL)
        let miss = try await acquirer.acquireImageData(for: imageURLs[1], refererURL: refererURL)

        #expect(cacheHit == MangaOfflineCacheImageAcquisition(data: Data([7]), source: .transparentCache))
        #expect(miss == MangaOfflineCacheImageAcquisition(data: Data([8]), source: .network))
        #expect(await transport.requests == [ImageTransportRequest(imageURL: imageURLs[1], refererURL: refererURL)])
        #expect(await networkLoader.requestedURLs.isEmpty)
    }

    @Test func observerReceivesSubmissionProgressAndSuccessfulFinish() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "720", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "720", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let observer = RecordingQueueRunObserver()
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer,
            runObserver: observer,
            maxConcurrentImageTransfers: 1
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await observer.submissionCount == 1)
        #expect(await observer.progressUpdates == [
            MangaOfflineCacheProgress(completedImageCount: 0, targetImageCount: 2),
            MangaOfflineCacheProgress(completedImageCount: 1, targetImageCount: 2),
            MangaOfflineCacheProgress(completedImageCount: 2, targetImageCount: 2)
        ])
        #expect(await observer.finishResults == [true])
    }

    @Test func observerIsNotResubmittedForSystemContinuedProcessingLaunch() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "730", count: 1)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "730", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let observer = RecordingQueueRunObserver()
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer,
            runObserver: observer
        )

        try await executor.continueQueue(submitsUserInitiatedRun: false)
        await executor.waitForIdle()

        #expect(await observer.submissionCount == 0)
        #expect(await observer.finishResults == [true])
    }

    @Test func continueWhileAlreadyRunningDoesNotSubmitAnotherContinuedProcessingRun() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "735", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "735", targetImageURLs: imageURLs)
        )
        let acquirer = FirstImageOnlyImmediateAcquirer(firstImageURL: imageURLs[0])
        let observer = RecordingQueueRunObserver()
        let executor = MangaOfflineCacheQueueExecutor(
            store: store,
            chapterDocumentLoader: RecordingChapterDocumentLoader(),
            imageAcquirer: acquirer,
            runObserver: observer
        )

        try await executor.continueQueue()
        try await waitUntil {
            await store.offlineCacheWork(ownerName: "favorite-a", tid: "735")?.completedImageURLs == [imageURLs[0]]
        }
        try await executor.continueQueue()
        try await executor.pauseQueue()
        await executor.waitForIdle()

        #expect(await observer.submissionCount == 1)
    }

    @Test func urlSessionDownloadTransportReturnsDownloadedDataAndReferer() async throws {
        let harness = MangaReaderDataTestHarness()
        defer { harness.reset() }
        let imageURL = try #require(URL(string: "https://img.example.com/740-1.jpg"))
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=740"))
        harness.setHandler { request in
            #expect(request.url == imageURL)
            #expect(request.value(forHTTPHeaderField: "Referer") == refererURL.absoluteString)
            return MangaReaderDataTestResponse(data: Data([7, 4, 0]))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderDataTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Manga-Test-ID": harness.testID]
        let transport = MangaOfflineCacheBackgroundDownloadTransport(configuration: configuration)

        let data = try await transport.downloadImageData(for: imageURL, refererURL: refererURL)

        #expect(data == Data([7, 4, 0]))
        #expect(harness.requests.count == 1)
    }

    @Test func chapterCancellationRemovesPartialOfflineBytesForCanceledWork() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "800", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "作品A", tid: "800", targetImageURLs: imageURLs)
        )
        try await store.saveOfflineImageData(Data([1]), for: imageURLs[0])
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
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

        try await executor.cancelChapter(ownerName: "作品A", tid: "800")

        #expect(await store.offlineCacheWork(ownerName: "作品A", tid: "800") == nil)
        #expect(await store.offlineImageData(for: imageURLs[0]) == nil)
    }

    @Test func ownerGroupCancellationRemovesPartialOfflineBytesForCanceledWorkOnly() async throws {
        let store = try makeTestGRDBMangaOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let canceledImages = try makeImageURLs(tid: "900", count: 1)
        let retainedImages = try makeImageURLs(tid: "901", count: 1)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "作品A", tid: "900", targetImageURLs: canceledImages)
        )
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "作品B", tid: "901", targetImageURLs: retainedImages)
        )
        try await store.saveOfflineImageData(Data([9]), for: canceledImages[0])
        try await store.saveOfflineImageData(Data([1]), for: retainedImages[0])
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "900",
            targetImageURLs: canceledImages,
            completedImageURLs: canceledImages,
            currentBytesPerSecond: nil
        )
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "作品B",
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

        try await executor.cancelOwnerGroup(ownerName: "作品A")

        #expect(await store.offlineCacheWork(ownerName: "作品A", tid: "900") == nil)
        #expect(await store.offlineCacheWork(ownerName: "作品B", tid: "901") != nil)
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

private actor EmptyImageThenFailingAcquirer: MangaOfflineCacheImageAcquiring {
    private(set) var requestedURLs: [URL] = []
    private let emptyImageURL: URL

    init(emptyImageURL: URL) {
        self.emptyImageURL = emptyImageURL
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> MangaOfflineCacheImageAcquisition {
        requestedURLs.append(imageURL)
        if imageURL == emptyImageURL {
            return MangaOfflineCacheImageAcquisition(data: Data(), source: .network)
        }
        throw YamiboError.offline
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

private struct ImageTransportRequest: Hashable, Sendable {
    var imageURL: URL
    var refererURL: URL?
}

private actor RecordingImageTransport: MangaOfflineCacheImageTransporting {
    private(set) var requests: [ImageTransportRequest] = []
    private let dataByURL: [URL: Data]

    init(dataByURL: [URL: Data]) {
        self.dataByURL = dataByURL
    }

    func downloadImageData(for imageURL: URL, refererURL: URL?) async throws -> Data {
        requests.append(ImageTransportRequest(imageURL: imageURL, refererURL: refererURL))
        guard let data = dataByURL[imageURL] else {
            throw YamiboError.invalidResponse(statusCode: 404)
        }
        return data
    }
}

private actor RecordingQueueRunObserver: MangaOfflineCacheQueueRunObserving {
    private(set) var submissionCount = 0
    private(set) var progressUpdates: [MangaOfflineCacheProgress] = []
    private(set) var finishResults: [Bool] = []

    func submitUserInitiatedRun() async {
        submissionCount += 1
    }

    func queueRunDidUpdateProgress(completedImageCount: Int, targetImageCount: Int) async {
        progressUpdates.append(
            MangaOfflineCacheProgress(
                completedImageCount: completedImageCount,
                targetImageCount: targetImageCount
            )
        )
    }

    func queueRunDidFinish(success: Bool) async {
        finishResults.append(success)
    }

    func queueRunDidCancel() async {
        finishResults.append(false)
    }
}

private func makeExecutorWorkRequest(
    ownerName: String,
    tid: String,
    targetImageURLs: [URL]
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: ownerName,
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
