import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Queue")
struct MangaReaderTestsMangaOfflineCacheQueue {
    @Test func enqueuePersistsQueueWorkWithOwnerMetadataAndInsertionOrder() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let firstStore = FileMangaOfflineCacheStore(baseDirectory: directory)

        let result = try await firstStore.enqueueOfflineCacheWork(
            makeOfflineCacheWorkRequest(
                favoriteID: " favorite-a ",
                tid: " 100 ",
                targetImageURLs: [
                    try #require(URL(string: "https://img.example.com/100-1.jpg")),
                    try #require(URL(string: "https://img.example.com/100-2.jpg"))
                ]
            )
        )

        let enqueued = try #require(result.enqueuedWork)
        #expect(enqueued.favoriteID == "favorite-a")
        #expect(enqueued.tid == "100")
        #expect(enqueued.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=100")
        #expect(enqueued.insertionIndex == 1)
        #expect(enqueued.state == .paused)

        let secondStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        let persisted = await secondStore.allOfflineCacheWorks()

        #expect(persisted == [enqueued])
    }

    @Test func enqueueIsIdempotentForExistingQueueWorkAndCachedMembership() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let firstRequest = try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "100")
        let secondRequest = try makeOfflineCacheWorkRequest(
            favoriteID: "favorite-a",
            tid: "200",
            targetImageURLs: [try #require(URL(string: "https://img.example.com/cached.jpg"))]
        )

        let firstResult = try await store.enqueueOfflineCacheWork(firstRequest)
        let secondResult = try await store.enqueueOfflineCacheWork(firstRequest)

        let firstWork = try #require(firstResult.enqueuedWork)
        #expect(secondResult == .alreadyQueued(firstWork))
        #expect(await store.allOfflineCacheWorks() == [firstWork])

        let cachedMembership = try makeOfflineCacheMembership(favoriteID: "favorite-a", tid: "200", imageURLs: secondRequest.targetImageURLs)
        try await store.saveOfflineImageData(Data([1, 2, 3]), for: secondRequest.targetImageURLs[0])
        try await store.saveMembership(cachedMembership)

        let cachedResult = try await store.enqueueOfflineCacheWork(secondRequest)

        #expect(cachedResult == .alreadyCached(cachedMembership))
        #expect(await store.allOfflineCacheWorks() == [firstWork])
    }

    @Test func failedQueueWorkPersistsUntilCanceledAndProjectsAsCaching() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let writingStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        let request = try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "100")

        _ = try await writingStore.enqueueOfflineCacheWork(request)
        try await writingStore.markOfflineCacheWorkFailed(
            favoriteID: "favorite-a",
            tid: "100",
            message: "Network unavailable"
        )

        let readingStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        let failedWork = try #require(await readingStore.offlineCacheWork(favoriteID: "favorite-a", tid: "100"))

        #expect(failedWork.state == .failed)
        #expect(failedWork.failureMessage == "Network unavailable")
        #expect(await readingStore.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .caching)

        try await readingStore.cancelOfflineCacheWork(favoriteID: "favorite-a", tid: "100")

        #expect(await readingStore.offlineCacheWork(favoriteID: "favorite-a", tid: "100") == nil)
        #expect(await readingStore.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .uncached)
    }

    @Test func progressSnapshotsPersistAcrossStoreInstances() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let writingStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        let firstImage = try #require(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/100-2.jpg"))
        let thirdImage = try #require(URL(string: "https://img.example.com/100-3.jpg"))

        _ = try await writingStore.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(
                favoriteID: "favorite-a",
                tid: "100",
                targetImageURLs: [firstImage]
            )
        )
        try await writingStore.updateOfflineCacheWorkProgress(
            favoriteID: "favorite-a",
            tid: "100",
            targetImageURLs: [firstImage, secondImage, thirdImage],
            completedImageURLs: [firstImage, secondImage]
        )

        let readingStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        let work = try #require(await readingStore.offlineCacheWork(favoriteID: "favorite-a", tid: "100"))

        #expect(work.targetImageURLs == [firstImage, secondImage, thirdImage])
        #expect(work.completedImageURLs == [firstImage, secondImage])
        #expect(work.progress == MangaOfflineCacheProgress(completedImageCount: 2, targetImageCount: 3))
    }

    @Test func membershipDeletionCancelsQueueWorkEvenWithoutCachedImages() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let imageURL = try #require(URL(string: "https://img.example.com/100-1.jpg"))

        _ = try await store.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "100", targetImageURLs: [imageURL])
        )
        try await store.saveMembership(
            try makeOfflineCacheMembership(favoriteID: "favorite-a", tid: "100", imageURLs: [imageURL])
        )

        try await store.removeMembership(favoriteID: "favorite-a", tid: "100")

        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .uncached)
    }

    @Test func completedMembershipLeavesQueueWhenAllOfflineImagesArePresent() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let firstImage = try #require(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/100-2.jpg"))

        _ = try await store.enqueueOfflineCacheWork(
            try makeOfflineCacheWorkRequest(
                favoriteID: "favorite-a",
                tid: "100",
                targetImageURLs: [firstImage, secondImage]
            )
        )
        try await store.saveMembership(
            try makeOfflineCacheMembership(
                favoriteID: "favorite-a",
                tid: "100",
                imageURLs: [firstImage, secondImage]
            )
        )
        try await store.saveOfflineImageData(Data([1]), for: firstImage)

        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .caching)

        try await store.saveOfflineImageData(Data([2]), for: secondImage)

        #expect(await store.offlineCacheWork(favoriteID: "favorite-a", tid: "100") == nil)
        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .cached)
    }

    @Test func queueProjectionGroupsByFavoriteAndOrdersChaptersByDirectoryWhenAvailable() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        _ = try await store.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(favoriteID: "favorite-b", favoriteTitle: "作品B", tid: "300"))
        _ = try await store.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", favoriteTitle: "作品A", tid: "200"))
        _ = try await store.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", favoriteTitle: "作品A", tid: "100"))

        let projection = MangaOfflineCacheQueueProjection.project(
            works: await store.allOfflineCacheWorks(),
            directoriesByFavoriteID: [
                "favorite-a": MangaDirectory(
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
        #expect(projection.groups.map(\.favoriteID) == ["favorite-b", "favorite-a"])
        #expect(projection.groups[0].works.map(\.tid) == ["300"])
        #expect(projection.groups[1].works.map(\.tid) == ["100", "200"])
    }

    @Test func restartRecoveryPausesRunningQueueWithoutDroppingFailedWork() async throws {
        let directory = try makeTemporaryOfflineCacheQueueDirectory()
        let writingStore = FileMangaOfflineCacheStore(baseDirectory: directory)

        _ = try await writingStore.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "100"))
        _ = try await writingStore.enqueueOfflineCacheWork(try makeOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "200"))
        try await writingStore.markOfflineCacheWorkFailed(favoriteID: "favorite-a", tid: "200", message: "Timeout")
        try await writingStore.setOfflineCacheQueueRunState(.running)

        let readingStore = FileMangaOfflineCacheStore(baseDirectory: directory)

        #expect(await readingStore.offlineCacheQueueRunState() == .paused)
        #expect(await readingStore.offlineCacheWork(favoriteID: "favorite-a", tid: "100")?.state == .paused)
        #expect(await readingStore.offlineCacheWork(favoriteID: "favorite-a", tid: "200")?.state == .failed)
    }

    @Test func readerFacingCacheStateRequiresMembershipAndAllOfflineImages() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryOfflineCacheQueueDirectory())
        let firstImage = try #require(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/100-2.jpg"))

        try await store.saveMembership(
            try makeOfflineCacheMembership(
                favoriteID: "favorite-a",
                tid: "100",
                imageURLs: [firstImage, secondImage]
            )
        )
        try await store.saveOfflineImageData(Data([1]), for: firstImage)

        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .uncached)

        try await store.saveOfflineImageData(Data([2]), for: secondImage)

        #expect(await store.offlineCacheState(favoriteID: "favorite-a", tid: "100") == .cached)
    }
}

private func makeOfflineCacheWorkRequest(
    favoriteID: String,
    favoriteTitle: String = "作品",
    tid: String,
    targetImageURLs: [URL] = []
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        favoriteID: favoriteID,
        favoriteTitle: favoriteTitle,
        favoriteURL: try #require(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html")),
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        targetImageURLs: targetImageURLs
    )
}

private func makeOfflineCacheMembership(
    favoriteID: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        favoriteID: favoriteID,
        favoriteTitle: "作品",
        favoriteURL: try #require(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html")),
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
