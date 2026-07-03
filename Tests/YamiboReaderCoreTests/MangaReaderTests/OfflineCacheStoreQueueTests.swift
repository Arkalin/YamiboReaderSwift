import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Queue")
struct MangaReaderTestsMangaOfflineCacheQueue {
    @Test func enqueuePersistsQueueWorkWithOwnerMetadataAndInsertionOrder() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let firstStore = try makeTestOfflineCacheStore(rootDirectory: directory)

        let result = try await firstStore.enqueueOfflineCacheWork(
            makeOfflineCacheWorkRequest(
                ownerName: " favorite-a ",
                tid: " 100 ",
                targetImageURLs: [
                    try #require(URL(string: "https://img.example.com/100-1.jpg")),
                    try #require(URL(string: "https://img.example.com/100-2.jpg"))
                ]
            )
        )

        let enqueued = try #require(result.enqueuedWork)
        #expect(enqueued.ownerName == "favorite-a")
        #expect(enqueued.tid == "100")
        #expect(enqueued.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=100")
        #expect(enqueued.insertionIndex == 1)
        #expect(enqueued.state == .queued)

        let secondStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        let persisted = await secondStore.allOfflineCacheWorks()

        #expect(persisted == [enqueued])
    }

    @Test func enqueueIsIdempotentForExistingQueueWorkAndCachedMembership() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let firstRequest = try makeOfflineCacheWorkRequest(ownerName: "favorite-a", tid: "100")
        let secondRequest = try makeOfflineCacheWorkRequest(
            ownerName: "favorite-a",
            tid: "200",
            targetImageURLs: [try #require(URL(string: "https://img.example.com/cached.jpg"))]
        )

        let firstResult = try await store.enqueueOfflineCacheWork(firstRequest)
        let secondResult = try await store.enqueueOfflineCacheWork(firstRequest)

        let firstWork = try #require(firstResult.enqueuedWork)
        #expect(secondResult == .alreadyQueued(firstWork))
        #expect(await store.allOfflineCacheWorks() == [firstWork])

        let cachedMembership = try makeOfflineCacheMembership(ownerName: "favorite-a", tid: "200", imageURLs: secondRequest.targetImageURLs)
        try await store.saveOfflineImageData(Data([1, 2, 3]), for: secondRequest.targetImageURLs[0])
        try await store.saveMembership(cachedMembership)

        let cachedResult = try await store.enqueueOfflineCacheWork(secondRequest)

        guard case let .alreadyCached(loadedMembership) = cachedResult else {
            Issue.record("Expected existing cached membership")
            return
        }
        #expect(loadedMembership.id == cachedMembership.id)
        #expect(loadedMembership.chapterTitle == cachedMembership.chapterTitle)
        #expect(loadedMembership.chapterURL == cachedMembership.chapterURL)
        #expect(loadedMembership.imageURLs == cachedMembership.imageURLs)
        #expect(await store.allOfflineCacheWorks() == [firstWork])
    }

    @Test func failedQueueWorkPersistsUntilCanceledAndProjectsAsCaching() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let writingStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        let request = try makeOfflineCacheWorkRequest(ownerName: "favorite-a", tid: "100")

        _ = try await writingStore.enqueueOfflineCacheWork(request)
        try await writingStore.markOfflineCacheWorkFailed(
            ownerName: "favorite-a",
            tid: "100",
            message: "Network unavailable"
        )

        let readingStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        let failedWork = try #require(await readingStore.offlineCacheWork(ownerName: "favorite-a", tid: "100"))

        #expect(failedWork.state == .failed)
        #expect(failedWork.failureMessage == "Network unavailable")
        #expect(await readingStore.offlineCacheState(ownerName: "favorite-a", tid: "100") == .caching)

        try await readingStore.cancelOfflineCacheWork(ownerName: "favorite-a", tid: "100")

        #expect(await readingStore.offlineCacheWork(ownerName: "favorite-a", tid: "100") == nil)
        #expect(await readingStore.offlineCacheState(ownerName: "favorite-a", tid: "100") == .uncached)
    }

    @Test func progressSnapshotsPersistAcrossStoreInstances() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let writingStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        let firstImage = try #require(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/100-2.jpg"))
        let thirdImage = try #require(URL(string: "https://img.example.com/100-3.jpg"))

        _ = try await writingStore.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(
                ownerName: "favorite-a",
                tid: "100",
                targetImageURLs: [firstImage]
            )
        )
        try await writingStore.updateOfflineCacheWorkProgress(
            ownerName: "favorite-a",
            tid: "100",
            targetImageURLs: [firstImage, secondImage, thirdImage],
            completedImageURLs: [firstImage, secondImage],
            currentBytesPerSecond: nil
        )

        let readingStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        let work = try #require(await readingStore.offlineCacheWork(ownerName: "favorite-a", tid: "100"))

        #expect(work.targetImageURLs == [firstImage, secondImage, thirdImage])
        #expect(work.completedImageURLs == [firstImage, secondImage])
        #expect(work.progress == MangaOfflineCacheProgress(completedImageCount: 2, targetImageCount: 3))
    }

    @Test func membershipDeletionCancelsQueueWorkEvenWithoutCachedImages() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let imageURL = try #require(URL(string: "https://img.example.com/100-1.jpg"))

        _ = try await store.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(ownerName: "favorite-a", tid: "100", targetImageURLs: [imageURL])
        )
        try await store.saveMembership(
            try makeOfflineCacheMembership(ownerName: "favorite-a", tid: "100", imageURLs: [imageURL])
        )

        try await store.removeMembership(ownerName: "favorite-a", tid: "100")

        #expect(await store.offlineCacheWork(ownerName: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "100") == .uncached)
    }

    @Test func membershipDeletionRemovesPartialOfflineBytesForCanceledQueueWork() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let imageURL = try #require(URL(string: "https://img.example.com/100-1.jpg"))

        _ = try await store.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(ownerName: "favorite-a", tid: "100", targetImageURLs: [imageURL])
        )
        try await store.saveOfflineImageData(Data([1]), for: imageURL)
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "favorite-a",
            tid: "100",
            targetImageURLs: [imageURL],
            completedImageURLs: [imageURL],
            currentBytesPerSecond: nil
        )

        try await store.removeMembership(ownerName: "favorite-a", tid: "100")

        #expect(await store.offlineCacheWork(ownerName: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineImageData(for: imageURL) == nil)
    }

    @Test func completedMembershipLeavesQueueWhenAllOfflineImagesArePresent() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let firstImage = try #require(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/100-2.jpg"))

        _ = try await store.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(
                ownerName: "favorite-a",
                tid: "100",
                targetImageURLs: [firstImage, secondImage]
            )
        )
        try await store.saveMembership(
            try makeOfflineCacheMembership(
                ownerName: "favorite-a",
                tid: "100",
                imageURLs: [firstImage, secondImage]
            )
        )
        try await store.saveOfflineImageData(Data([1]), for: firstImage)

        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "100") == .caching)

        try await store.saveOfflineImageData(Data([2]), for: secondImage)

        #expect(await store.offlineCacheWork(ownerName: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "100") == .cached)
    }

    @Test func queueProjectionGroupsByOwnerAndOrdersChaptersByDirectoryWhenAvailable() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        _ = try await store.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(ownerName: "作品B", tid: "300"))
        _ = try await store.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(ownerName: "作品A", tid: "200"))
        _ = try await store.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(ownerName: "作品A", tid: "100"))

        let projection = MangaOfflineCacheQueueProjection.project(
            works: await store.allOfflineCacheWorks(),
            directoriesByOwnerName: [
                "作品A": MangaDirectory(
                    cleanBookName: "作品A",
                    strategy: .tag,
                    sourceKey: "tag:1",
                    chapters: [
                        try makeDirectoryChapter(tid: "100", chapterNumber: 1),
                        try makeDirectoryChapter(tid: "200", chapterNumber: 2)
                    ]
                )
            ]
        )

        #expect(projection.unfinishedCount == 3)
        #expect(projection.groups.map(\.ownerName) == ["作品B", "作品A"])
        #expect(projection.groups[0].works.map(\.tid) == ["300"])
        #expect(projection.groups[1].works.map(\.tid) == ["100", "200"])
    }

    @Test func restartRecoveryPausesRunningQueueWithoutDroppingFailedWork() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let writingStore = try makeTestOfflineCacheStore(rootDirectory: directory)

        _ = try await writingStore.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(ownerName: "favorite-a", tid: "100"))
        _ = try await writingStore.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(ownerName: "favorite-a", tid: "200"))
        try await writingStore.markOfflineCacheWorkFailed(ownerName: "favorite-a", tid: "200", message: "Timeout")
        try await writingStore.prepareOfflineCacheWorkForRun(
            ownerName: "favorite-a",
            tid: "100",
            targetImageURLs: nil,
            completedImageURLs: []
        )
        try await writingStore.setOfflineCacheQueueRunState(.running)

        let readingStore = try makeTestOfflineCacheStore(rootDirectory: directory)

        #expect(await readingStore.offlineCacheQueueRunState() == .paused)
        #expect(await readingStore.offlineCacheWork(ownerName: "favorite-a", tid: "100")?.state == .paused)
        #expect(await readingStore.offlineCacheWork(ownerName: "favorite-a", tid: "200")?.state == .failed)
    }

    @Test func readerFacingCacheStateRequiresMembershipAndAllOfflineImages() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let firstImage = try #require(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/100-2.jpg"))

        try await store.saveMembership(
            try makeOfflineCacheMembership(
                ownerName: "favorite-a",
                tid: "100",
                imageURLs: [firstImage, secondImage]
            )
        )
        try await store.saveOfflineImageData(Data([1]), for: firstImage)

        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "100") == .uncached)

        try await store.saveOfflineImageData(Data([2]), for: secondImage)

        #expect(await store.offlineCacheState(ownerName: "favorite-a", tid: "100") == .cached)
    }
}

private func makeOfflineCacheWorkRequest(
    ownerName: String,
    tid: String,
    targetImageURLs: [URL] = []
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        targetImageURLs: targetImageURLs
    )
}

private func makeOfflineCacheMembership(
    ownerName: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        imageURLs: imageURLs
    )
}

private func makeDirectoryChapter(tid: String, chapterNumber: Double) throws -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: "第\(tid)话",
        chapterNumber: chapterNumber,
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)"))
    )
}

private func makeTemporaryOfflineCacheQueueDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
