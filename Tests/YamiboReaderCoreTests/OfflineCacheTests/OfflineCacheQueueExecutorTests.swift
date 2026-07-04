import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("OfflineCacheTests: Offline Cache Queue Executor")
struct OfflineCacheTestsQueueExecutor {
    @Test func continueProcessesOneChapterAtATimeWithThreeImageTransferLimit() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
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
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "100", imageURLs: firstChapterImages),
                try makeDocument(tid: "200", imageURLs: secondChapterImages)
            ]),
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

    @Test func continueLoadsReaderProjectionBeforeImageCountProgressAndRebuildsChapterURLFromTid() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
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
        let projectionLoader = RecordingReaderProjectionLoader()
        await projectionLoader.setDocument(
            try makeDocument(tid: "300", imageURLs: imageURLs),
            forAnyRequest: true
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: projectionLoader,
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let requestedURL = try #require(await projectionLoader.requestedURLs.first)
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
        #expect(await store.membership(ownerName: "favorite-a", tid: "300")?.sourcePage.thread == ThreadIdentity(tid: "300"))
    }

    @Test func continueLoadsSnapshotEvenWhenWorkAlreadyHasTargetImages() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let staleImages = try makeImageURLs(tid: "310", count: 1)
        let projectionImages = try makeImageURLs(tid: "311", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "310", targetImageURLs: staleImages)
        )
        let projectionLoader = RecordingReaderProjectionLoader(documents: [
            try makeDocument(tid: "310", imageURLs: projectionImages)
        ])
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: projectionImages)
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: projectionLoader,
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await projectionLoader.requestedURLs.count == 1)
        #expect(await acquirer.requestedURLs == projectionImages)
        let membership = try #require(await store.membership(ownerName: "favorite-a", tid: "310"))
        #expect(membership.imageURLs == projectionImages)
        #expect(membership.sourcePage.thread == ThreadIdentity(tid: "310"))
    }

    @Test func snapshotLoadFailureFailsWorkWithoutCreatingMembership() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "320", count: 1)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "320", targetImageURLs: imageURLs)
        )
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let failedWork = try #require(await store.offlineCacheWork(ownerName: "favorite-a", tid: "320"))
        #expect(failedWork.state == .failed)
        #expect(await store.membership(ownerName: "favorite-a", tid: "320") == nil)
    }

    @Test func emptyProjectionImageListFailsWorkWithoutCreatingMembership() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "330", targetImageURLs: [])
        )
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "330", imageURLs: [])
            ]),
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let failedWork = try #require(await store.offlineCacheWork(ownerName: "favorite-a", tid: "330"))
        #expect(failedWork.state == .failed)
        #expect(await store.membership(ownerName: "favorite-a", tid: "330") == nil)
    }

    @Test func cacheCompletionDoesNotUpdateReadingProgressResumeRouteOrRecentReading() async throws {
        let suiteName = "manga-offline-cache-no-progress-side-effects-\(UUID().uuidString)"
        try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try #require(UserDefaults(suiteName: suiteName)),
            key: "local-favorites"
        )
        let resumeRouteStore = ReaderResumeRouteStore(defaults: try #require(UserDefaults(suiteName: suiteName)), key: "resume-route")
        let ownerURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=350&mobile=2"))
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=350&page=2&mobile=2"))
        var favoriteLibrary = FavoriteLibraryDocument()
        let favorite = try FavoriteItem(
            target: FavoriteContentTarget(kind: .normalThread, threadURL: ownerURL),
            title: "阅读进度漫画",
            locations: [.category(favoriteLibrary.defaultCategory.id)]
        )
        favoriteLibrary.addItem(favorite)
        let resumeRoute = ReaderResumeRoute.manga(.native(MangaLaunchContext(
            originalThreadURL: ownerURL,
            chapterURL: chapterURL,
            displayTitle: "阅读进度漫画",
            source: .resume,
            initialPage: 5
        )))
        let imageURLs = try makeImageURLs(tid: "350", count: 2)
        try await localFavoriteLibraryStore.save(favoriteLibrary)
        try await resumeRouteStore.save(resumeRoute)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: favorite.id, tid: "350", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "350", imageURLs: imageURLs)
            ]),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheState(ownerName: favorite.id, tid: "350") == .cached)
        #expect(await localFavoriteLibraryStore.load() == favoriteLibrary)
        #expect(await resumeRouteStore.load() == .manga(.native(MangaLaunchContext(
            originalThreadURL: try #require(YamiboRoute.chapterURL(forTID: "350")),
            chapterURL: try #require(YamiboRoute.chapterURL(forTID: "350")),
            displayTitle: "阅读进度漫画",
            source: .resume,
            initialPage: 5
        ))))
    }

    @Test func pauseCancelsInFlightTransfersAndPreservesCompletedProgress() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "400", count: 4)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "400", targetImageURLs: imageURLs)
        )
        let acquirer = FirstImageOnlyImmediateAcquirer(firstImageURL: imageURLs[0])
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "400", imageURLs: imageURLs)
            ]),
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
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "500", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "500", targetImageURLs: imageURLs)
        )
        let acquirer = RetryOfflineImageAcquirer(failingImageURL: imageURLs[1])
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "500", imageURLs: imageURLs)
            ]),
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
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "550", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "550", targetImageURLs: imageURLs)
        )
        let acquirer = EmptyImageThenFailingAcquirer(emptyImageURL: imageURLs[0])
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "550", imageURLs: imageURLs)
            ]),
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
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
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
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "600", imageURLs: imageURLs)
            ]),
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await acquirer.requestedURLs == [imageURLs[1]])
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "600") == .cached)
    }

    @Test func queueWritesNetworkAcquiredBytesToOfflineStorage() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "700", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "700", targetImageURLs: imageURLs)
        )
        let networkLoader = RecordingNetworkImageLoader(dataByURL: [
            imageURLs[0]: Data([7]),
            imageURLs[1]: Data([8])
        ])
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "700", imageURLs: imageURLs)
            ]),
            imageAcquirer: OfflineCacheImageAcquirer(
                networkLoader: networkLoader
            )
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([7]))
        #expect(await store.offlineImageData(for: imageURLs[1]) == Data([8]))
        #expect(await networkLoader.requestedURLs == imageURLs)
    }

    @Test func imageAcquirerUsesBackgroundTransportInsteadOfNetworkLoader() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/710-1.jpg"))
        let transport = RecordingImageTransport(dataByURL: [imageURL: Data([8])])
        let networkLoader = RecordingNetworkImageLoader(dataByURL: [:])
        let acquirer = OfflineCacheImageAcquirer(
            networkLoader: networkLoader,
            backgroundTransport: transport
        )
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=710"))

        let acquisition = try await acquirer.acquireImageData(for: imageURL, refererURL: refererURL)

        #expect(acquisition == OfflineCacheImageAcquisition(data: Data([8]), source: .network))
        #expect(await transport.requests == [ImageTransportRequest(imageURL: imageURL, refererURL: refererURL)])
        #expect(await networkLoader.requestedURLs.isEmpty)
    }

    @Test func observerReceivesSubmissionProgressAndSuccessfulFinish() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "720", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "720", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let observer = RecordingQueueRunObserver()
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "720", imageURLs: imageURLs)
            ]),
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
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "730", count: 1)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "730", targetImageURLs: imageURLs)
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let observer = RecordingQueueRunObserver()
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "730", imageURLs: imageURLs)
            ]),
            imageAcquirer: acquirer,
            runObserver: observer
        )

        try await executor.continueQueue(submitsUserInitiatedRun: false)
        await executor.waitForIdle()

        #expect(await observer.submissionCount == 0)
        #expect(await observer.finishResults == [true])
    }

    @Test func continueWhileAlreadyRunningDoesNotSubmitAnotherContinuedProcessingRun() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "735", count: 2)
        _ = try await store.enqueueOfflineCacheWork(
            try makeExecutorWorkRequest(ownerName: "favorite-a", tid: "735", targetImageURLs: imageURLs)
        )
        let acquirer = FirstImageOnlyImmediateAcquirer(firstImageURL: imageURLs[0])
        let observer = RecordingQueueRunObserver()
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(documents: [
                try makeDocument(tid: "735", imageURLs: imageURLs)
            ]),
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
        let transport = OfflineCacheBackgroundDownloadTransport(configuration: configuration)

        let data = try await transport.downloadImageData(for: imageURL, refererURL: refererURL)

        #expect(data == Data([7, 4, 0]))
        #expect(harness.requests.count == 1)
    }

    @Test func chapterCancellationRemovesPartialOfflineBytesForCanceledWork() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
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
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.cancelChapter(ownerName: "作品A", tid: "800")

        #expect(await store.offlineCacheWork(ownerName: "作品A", tid: "800") == nil)
        #expect(await store.offlineImageData(for: imageURLs[0]) == nil)
    }

    @Test func ownerGroupCancellationRemovesPartialOfflineBytesForCanceledWorkOnly() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
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
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.cancelOwnerGroup(ownerName: "作品A")

        #expect(await store.offlineCacheWork(ownerName: "作品A", tid: "900") == nil)
        #expect(await store.offlineCacheWork(ownerName: "作品B", tid: "901") != nil)
        #expect(await store.offlineImageData(for: canceledImages[0]) == nil)
        #expect(await store.offlineImageData(for: retainedImages[0]) == Data([1]))
    }

    @Test func continueProcessesNovelWorkWithoutImagesWhenRetentionFlagDisabled() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "1100", count: 2)
        let request = try makeNovelExecutorWorkRequest(tid: "1100", view: 1, retainsInlineImages: false)
        _ = try await store.enqueueNovelOfflineCacheWork(request)
        let sourceLoader = RecordingNovelOfflineSourcePageLoader()
        await sourceLoader.setPreparedPage(
            try makeNovelExecutorPreparedSourcePage(tid: "1100", view: 1, imageURLs: imageURLs),
            for: request
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            novelSourcePageLoader: sourceLoader,
            imageAcquirer: acquirer
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheQueueWorks().isEmpty)
        #expect(await acquirer.requestedURLs.isEmpty)
        #expect(await store.offlineImageData(for: imageURLs[0]) == nil)
        let entry = await store.novelOfflineCacheEntry(id: OfflineCacheEntryID(
            readerKind: .novel,
            ownerKey: request.groupKey,
            entryKey: request.entryKey
        ))
        #expect(entry?.imageURLs.isEmpty == true)
        #expect(entry?.document.segments.contains { segment in
            guard case let .text(text, _) = segment else { return false }
            return text.contains("正文1")
        } == true)
    }

    @Test func continueProcessesNovelInlineImagesWhenRetentionFlagEnabled() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "1110", count: 2)
        let request = try makeNovelExecutorWorkRequest(tid: "1110", view: 1, retainsInlineImages: true)
        _ = try await store.enqueueNovelOfflineCacheWork(request)
        let sourceLoader = RecordingNovelOfflineSourcePageLoader()
        await sourceLoader.setPreparedPage(
            try makeNovelExecutorPreparedSourcePage(tid: "1110", view: 1, imageURLs: imageURLs),
            for: request
        )
        let acquirer = RecordingOfflineImageAcquirer()
        await acquirer.setData(for: imageURLs)
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            novelSourcePageLoader: sourceLoader,
            imageAcquirer: acquirer,
            maxConcurrentImageTransfers: 1
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheQueueWorks().isEmpty)
        #expect(await acquirer.requestedURLs == imageURLs)
        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([1]))
        #expect(await store.offlineImageData(for: imageURLs[1]) == Data([2]))
        let entry = await store.novelOfflineCacheEntry(id: OfflineCacheEntryID(
            readerKind: .novel,
            ownerKey: request.groupKey,
            entryKey: request.entryKey
        ))
        #expect(entry?.imageURLs == imageURLs)
    }

    @Test func failedNovelImageAcquisitionPreservesRefreshedSourcePageAndFailedWork() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let imageURLs = try makeImageURLs(tid: "1120", count: 2)
        let request = try makeNovelExecutorWorkRequest(tid: "1120", view: 2, retainsInlineImages: true)
        _ = try await store.enqueueNovelOfflineCacheWork(request)
        let sourceLoader = RecordingNovelOfflineSourcePageLoader()
        let preparedPage = try makeNovelExecutorPreparedSourcePage(tid: "1120", view: 2, imageURLs: imageURLs)
        await sourceLoader.setPreparedPage(preparedPage, for: request)
        let acquirer = RetryOfflineImageAcquirer(failingImageURL: imageURLs[1])
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            novelSourcePageLoader: sourceLoader,
            imageAcquirer: acquirer,
            maxConcurrentImageTransfers: 1
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        let failedWork = try #require(await store.offlineCacheQueueWorks().first)
        #expect(failedWork.state == .failed)
        #expect(failedWork.progress == OfflineCacheProgress(completedUnitCount: 1, targetUnitCount: 2))
        #expect(await store.offlineImageData(for: imageURLs[0]) == Data([1]))
        #expect(await store.offlineImageData(for: imageURLs[1]) == nil)
        let sourceSnapshot = await store.novelOfflineSourcePageSnapshot(
            threadURL: request.threadURL,
            view: request.view,
            authorID: request.authorID,
            contentSource: request.contentSource
        )
        #expect(sourceSnapshot?.sourcePage == preparedPage.sourcePage)
        let entry = await store.novelOfflineCacheEntry(id: OfflineCacheEntryID(
            readerKind: .novel,
            ownerKey: request.groupKey,
            entryKey: request.entryKey
        ))
        #expect(entry?.imageURLs == imageURLs)
    }

    @Test func continueProcessesNovelWorkAfterOwnerTitleChanges() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryExecutorDirectory())
        let originalRequest = try makeNovelExecutorWorkRequest(
            tid: "1130",
            view: 1,
            retainsInlineImages: false,
            ownerTitle: "旧标题1130"
        )
        let renamedRequest = try makeNovelExecutorWorkRequest(
            tid: "1130",
            view: 1,
            retainsInlineImages: false,
            ownerTitle: "新标题1130"
        )
        _ = try await store.enqueueNovelOfflineCacheWork(originalRequest)
        _ = try await store.enqueueNovelOfflineCacheWork(renamedRequest)
        let sourceLoader = RecordingNovelOfflineSourcePageLoader()
        await sourceLoader.setPreparedPage(
            try makeNovelExecutorPreparedSourcePage(tid: "1130", view: 1, imageURLs: []),
            for: renamedRequest
        )
        let executor = OfflineCacheQueueExecutor(
            store: store,
            readerProjectionLoader: RecordingReaderProjectionLoader(),
            novelSourcePageLoader: sourceLoader,
            imageAcquirer: RecordingOfflineImageAcquirer()
        )

        try await executor.continueQueue()
        await executor.waitForIdle()

        #expect(await store.offlineCacheQueueWorks().isEmpty)
        #expect(await sourceLoader.requests.map(\.ownerTitle) == ["新标题1130"])
        let entry = await store.novelOfflineCacheEntry(id: OfflineCacheEntryID(
            readerKind: .novel,
            ownerKey: renamedRequest.groupKey,
            entryKey: renamedRequest.entryKey
        ))
        #expect(entry?.ownerTitle == "新标题1130")
    }
}

private actor RecordingReaderProjectionLoader: MangaReaderProjectionSnapshotLoading {
    private(set) var requestedURLs: [URL] = []
    private var documentByURL: [String: MangaReaderProjection] = [:]
    private var documentByTID: [String: MangaReaderProjection] = [:]
    private var anyDocument: MangaReaderProjection?

    init(documents: [MangaReaderProjection] = []) {
        self.documentByTID = Dictionary(uniqueKeysWithValues: documents.map { ($0.tid, $0) })
    }

    func setDocument(_ document: MangaReaderProjection, forAnyRequest: Bool = false) {
        if forAnyRequest {
            anyDocument = document
        } else {
            documentByURL[document.chapterURL.absoluteString] = document
            documentByTID[document.tid] = document
        }
    }

    func loadReaderProjection(at url: URL) async throws -> MangaReaderProjection {
        requestedURLs.append(url)
        let tid = MangaTitleCleaner.extractTid(from: url.absoluteString)
        if let document = documentByURL[url.absoluteString]
            ?? tid.flatMap({ documentByTID[$0] })
            ?? anyDocument {
            return document
        }
        throw YamiboError.parsingFailed(context: "Missing test Manga Chapter Document")
    }

    func loadReaderProjectionSnapshot(at url: URL) async throws -> MangaReaderProjectionSnapshot {
        let projection = try await loadReaderProjection(at: url)
        return MangaReaderProjectionSnapshot(
            projection: projection,
            sourcePage: makeSourcePage(projection: projection)
        )
    }

    private func makeSourcePage(projection: MangaReaderProjection) -> ForumThreadPage {
        ForumThreadPage(
            thread: ThreadIdentity(tid: projection.tid),
            title: projection.chapterTitle,
            posts: [
                ForumThreadPost(
                    postID: projection.ownerPostID,
                    author: BlogReaderUser(uid: projection.ownerAuthorID, name: projection.ownerAuthorName ?? "作者"),
                    contentHTML: "",
                    contentText: "",
                    images: projection.imageURLs.map { ForumThreadPostImage(url: $0.absoluteString) }
                )
            ]
        )
    }
}

private actor RecordingOfflineImageAcquirer: OfflineCacheImageAcquiring {
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

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> OfflineCacheImageAcquisition {
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
        return OfflineCacheImageAcquisition(data: data, source: .network)
    }
}

private actor FirstImageOnlyImmediateAcquirer: OfflineCacheImageAcquiring {
    private let firstImageURL: URL

    init(firstImageURL: URL) {
        self.firstImageURL = firstImageURL
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> OfflineCacheImageAcquisition {
        if imageURL == firstImageURL {
            return OfflineCacheImageAcquisition(data: Data([1]), source: .network)
        }
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return OfflineCacheImageAcquisition(data: Data([2]), source: .network)
    }
}

private actor RetryOfflineImageAcquirer: OfflineCacheImageAcquiring {
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

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> OfflineCacheImageAcquisition {
        requestedURLs.append(imageURL)
        if imageURL == failingImageURL, shouldFail {
            throw YamiboError.offline
        }
        return OfflineCacheImageAcquisition(data: imageURL == failingImageURL ? Data([2]) : Data([1]), source: .network)
    }
}

private actor EmptyImageThenFailingAcquirer: OfflineCacheImageAcquiring {
    private(set) var requestedURLs: [URL] = []
    private let emptyImageURL: URL

    init(emptyImageURL: URL) {
        self.emptyImageURL = emptyImageURL
    }

    func acquireImageData(for imageURL: URL, refererURL: URL?) async throws -> OfflineCacheImageAcquisition {
        requestedURLs.append(imageURL)
        if imageURL == emptyImageURL {
            return OfflineCacheImageAcquisition(data: Data(), source: .network)
        }
        throw YamiboError.offline
    }
}

private actor RecordingNetworkImageLoader: YamiboImageDataLoading {
    private(set) var requestedRequests: [YamiboImageRequest] = []
    private let dataByURL: [URL: Data]

    init(dataByURL: [URL: Data]) {
        self.dataByURL = dataByURL
    }

    var requestedURLs: [URL] {
        requestedRequests.map(\.url)
    }

    func imageData(for request: YamiboImageRequest) async throws -> Data {
        requestedRequests.append(request)
        guard let data = dataByURL[request.url] else {
            throw YamiboError.invalidResponse(statusCode: 404)
        }
        return data
    }
}

private struct ImageTransportRequest: Hashable, Sendable {
    var imageURL: URL
    var refererURL: URL?
}

private actor RecordingImageTransport: OfflineCacheImageTransporting {
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

private actor RecordingQueueRunObserver: OfflineCacheQueueRunObserving {
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

private actor RecordingNovelOfflineSourcePageLoader: NovelOfflineCacheSourcePageLoading {
    private(set) var requests: [NovelOfflineCacheWorkRequest] = []
    private var preparedPagesByEntryKey: [String: NovelOfflineCachePreparedSourcePage] = [:]

    func setPreparedPage(
        _ preparedPage: NovelOfflineCachePreparedSourcePage,
        for request: NovelOfflineCacheWorkRequest
    ) {
        preparedPagesByEntryKey[request.entryKey] = preparedPage
    }

    func loadNovelOfflineCacheSourcePage(
        _ request: NovelOfflineCacheWorkRequest
    ) async throws -> NovelOfflineCachePreparedSourcePage {
        requests.append(request)
        guard let preparedPage = preparedPagesByEntryKey[request.entryKey] else {
            throw YamiboError.parsingFailed(context: "Missing test novel offline source page")
        }
        return preparedPage
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

private func makeNovelExecutorWorkRequest(
    tid: String,
    view: Int,
    retainsInlineImages: Bool,
    ownerTitle: String? = nil
) throws -> NovelOfflineCacheWorkRequest {
    NovelOfflineCacheWorkRequest(
        ownerTitle: ownerTitle ?? "小说\(tid)",
        title: "第\(view)页",
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")),
        view: view,
        authorID: "42",
        contentSource: .authorFilteredPage,
        retainsInlineImages: retainsInlineImages
    )
}

private func makeNovelExecutorPreparedSourcePage(
    tid: String,
    view: Int,
    imageURLs: [URL]
) throws -> NovelOfflineCachePreparedSourcePage {
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    let canonicalURL = ReaderCacheIdentity.canonicalThreadURL(from: threadURL)
    let segments = [.text("正文\(view)", chapterTitle: "第\(view)章")]
        + imageURLs.map { ReaderSegment.image($0, chapterTitle: nil) }
    let sourcePage = ForumThreadPage(
        thread: ThreadIdentity(tid: tid, canonicalURL: canonicalURL),
        title: "小说\(tid)",
        posts: [
            ForumThreadPost(
                postID: "\(tid)-\(view)",
                author: BlogReaderUser(uid: "42", name: "楼主"),
                contentHTML: "<strong>第\(view)章</strong><br>正文\(view)",
                contentText: "正文\(view)",
                images: imageURLs.map { ForumThreadPostImage(url: $0.absoluteString) }
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: view, totalPages: max(2, view))
    )
    let document = ReaderPageDocument(
        threadURL: canonicalURL,
        view: view,
        maxView: max(2, view),
        resolvedAuthorID: "42",
        contentSource: .authorFilteredPage,
        segments: segments,
        projectionSourceFingerprint: "novel-\(tid)-\(view)",
        projectionSchemaVersion: 1
    )
    return NovelOfflineCachePreparedSourcePage(sourcePage: sourcePage, document: document)
}

private func makeDocument(tid: String, imageURLs: [URL]) throws -> MangaReaderProjection {
    MangaReaderProjection(
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
