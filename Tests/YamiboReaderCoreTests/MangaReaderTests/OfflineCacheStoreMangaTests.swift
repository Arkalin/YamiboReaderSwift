import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Store")
struct MangaReaderTestsOfflineCacheStore {
    @Test func savesMembershipWithOwnerAndChapterIdentityAcrossStoreInstances() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=900&page=3"))
        let imageURL = try #require(URL(string: "https://img.example.com/page-1.jpg"))

        let writingStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        try await writingStore.saveMembership(
            MangaOfflineCacheMembership(
                ownerName: "作品",
                tid: "900",
                chapterTitle: "第1话",
                chapterURL: chapterURL,
                imageURLs: [imageURL]
            )
        )

        let readingStore = try makeTestOfflineCacheStore(rootDirectory: directory)
        let loaded = await readingStore.membership(ownerName: "作品", tid: "900")

        #expect(loaded?.id == MangaOfflineCacheMembershipID(ownerName: "作品", tid: "900"))
        #expect(loaded?.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=900")
        #expect(loaded?.chapterTitle == "第1话")
        #expect(loaded?.imageURLs == [imageURL])
    }

    @Test func usageReportsStoredOfflineImagesByOwner() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = try makeTestOfflineCacheStore(rootDirectory: directory)
        let firstImage = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/second.jpg"))

        try await store.saveOfflineImageData(Data(repeating: 1, count: 3), for: firstImage)
        try await store.saveOfflineImageData(Data(repeating: 2, count: 5), for: secondImage)
        try await store.saveMembership(makeOfflineMembership(ownerName: "作品A", tid: "1", imageURLs: [firstImage]))
        try await store.saveMembership(makeOfflineMembership(ownerName: "作品B", tid: "2", imageURLs: [firstImage, secondImage]))

        let usage = await store.diskUsageByOwner()

        #expect(usage == [
            MangaOfflineCacheOwnerUsage(ownerName: "作品A", byteCount: 3),
            MangaOfflineCacheOwnerUsage(ownerName: "作品B", byteCount: 8)
        ])
    }

    @Test func usageIncludesMembershipOwnerWhenReferencedImagesAreMissing() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheDirectory())
        let missingImage = try #require(URL(string: "https://img.example.com/missing.jpg"))

        try await store.saveMembership(makeOfflineMembership(ownerName: "作品A", tid: "1", imageURLs: [missingImage]))

        #expect(await store.diskUsageByOwner() == [
            MangaOfflineCacheOwnerUsage(ownerName: "作品A", byteCount: 0)
        ])
    }

    @Test func usageIncludesUnfinishedWorkOwnerAndStoredWorkImages() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryOfflineCacheDirectory())
        let completedImage = try #require(URL(string: "https://img.example.com/work-complete.jpg"))
        let missingImage = try #require(URL(string: "https://img.example.com/work-missing.jpg"))

        try await store.saveOfflineImageData(Data(repeating: 4, count: 6), for: completedImage)
        _ = try await store.enqueueOfflineCacheWork(
            makeOfflineWorkRequest(
                ownerName: "作品Work",
                tid: "40",
                targetImageURLs: [completedImage, missingImage]
            )
        )
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "作品Work",
            tid: "40",
            targetImageURLs: [completedImage, missingImage],
            completedImageURLs: [completedImage],
            currentBytesPerSecond: nil
        )

        #expect(await store.diskUsageByOwner() == [
            MangaOfflineCacheOwnerUsage(ownerName: "作品Work", byteCount: 6)
        ])
    }

    @Test func renameOwnerMovesMembershipsAndQueueWorksWithoutDroppingImages() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = try makeTestOfflineCacheStore(rootDirectory: directory)
        let cachedImage = try #require(URL(string: "https://img.example.com/rename-cached.jpg"))
        let workImage = try #require(URL(string: "https://img.example.com/rename-work.jpg"))

        try await store.saveOfflineImageData(Data([1, 2, 3]), for: cachedImage)
        try await store.saveOfflineImageData(Data([4, 5]), for: workImage)
        try await store.saveMembership(makeOfflineMembership(ownerName: "旧作品名", tid: "1", imageURLs: [cachedImage]))
        _ = try await store.enqueueOfflineCacheWork(makeOfflineWorkRequest(ownerName: "旧作品名", tid: "2", targetImageURLs: [workImage]))
        try await store.updateOfflineCacheWorkProgress(
            ownerName: "旧作品名",
            tid: "2",
            targetImageURLs: [workImage],
            completedImageURLs: [workImage],
            currentBytesPerSecond: 128
        )

        try await store.renameOwner(from: "旧作品名", to: "新作品名")

        #expect(await store.membership(ownerName: "旧作品名", tid: "1") == nil)
        #expect(await store.offlineCacheWork(ownerName: "旧作品名", tid: "2") == nil)
        #expect(await store.membership(ownerName: "新作品名", tid: "1")?.ownerName == "新作品名")
        #expect(await store.offlineCacheWork(ownerName: "新作品名", tid: "2")?.ownerName == "新作品名")
        #expect(await store.offlineImageData(for: cachedImage) == Data([1, 2, 3]))
        #expect(await store.offlineImageData(for: workImage) == Data([4, 5]))
        #expect(await store.diskUsageByOwner() == [
            MangaOfflineCacheOwnerUsage(ownerName: "新作品名", byteCount: 5)
        ])
    }

    @Test func deletingMembershipPreservesImagesReferencedByRemainingMemberships() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = try makeTestOfflineCacheStore(rootDirectory: directory)
        let sharedImage = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let firstOnlyImage = try #require(URL(string: "https://img.example.com/first-only.jpg"))

        try await store.saveOfflineImageData(Data([1, 2, 3]), for: sharedImage)
        try await store.saveOfflineImageData(Data([4, 5]), for: firstOnlyImage)
        try await store.saveMembership(makeOfflineMembership(ownerName: "作品A", tid: "1", imageURLs: [sharedImage, firstOnlyImage]))
        try await store.saveMembership(makeOfflineMembership(ownerName: "作品A", tid: "2", imageURLs: [sharedImage]))

        try await store.removeMembership(ownerName: "作品A", tid: "1")

        #expect(await store.membership(ownerName: "作品A", tid: "1") == nil)
        #expect(await store.offlineImageData(for: sharedImage) == Data([1, 2, 3]))
        #expect(await store.offlineImageData(for: firstOnlyImage) == nil)
        #expect(await store.diskUsageByOwner() == [
            MangaOfflineCacheOwnerUsage(ownerName: "作品A", byteCount: 3)
        ])
    }

    @Test func deletingOfflineMembershipDoesNotClearMangaIndexCaches() async throws {
        let root = try makeTemporaryOfflineCacheDirectory()
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: root)
        let directoryStore = try makeTestMangaDirectoryStore(rootDirectory: root)
        let projectionStore = try makeTestMangaReaderProjectionStore(rootDirectory: root)
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100"))
        let imageURL = try #require(URL(string: "https://img.example.com/offline.jpg"))
        let sourceIdentity = MangaReaderProjectionSourceIdentity(
            tid: "100",
            authorID: "42",
            contentSource: .authorFilteredPage,
            view: 1
        )

        try await directoryStore.saveDirectory(
            MangaDirectory(
                cleanBookName: "透明目录",
                strategy: .tag,
                sourceKey: "tag:1",
                chapters: [
                    MangaChapter(
                        tid: "100",
                        rawTitle: "第1话",
                        chapterNumber: 1,
                        url: chapterURL
                    )
                ]
            )
        )
        try await projectionStore.save(
            MangaReaderProjection(
                tid: "100",
                ownerAuthorID: "42",
                chapterTitle: "第1话",
                chapterURL: chapterURL,
                imageURLs: [imageURL],
                sourceIdentity: sourceIdentity,
                sourceFingerprint: "source"
            )
        )
        try await offlineStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await offlineStore.saveMembership(makeOfflineMembership(ownerName: "透明目录", tid: "100", imageURLs: [imageURL]))

        try await offlineStore.removeMembership(ownerName: "透明目录", tid: "100")

        #expect(try await directoryStore.directory(named: "透明目录")?.chapters.map(\.tid) == ["100"])
        #expect(await projectionStore.projection(for: sourceIdentity)?.tid == "100")
        #expect(await offlineStore.offlineImageData(for: imageURL) == nil)
    }

    @Test func clearAllRemovesMembershipAndRetainedOfflineImages() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = try makeTestOfflineCacheStore(rootDirectory: directory)
        let imageURL = try #require(URL(string: "https://img.example.com/clear.jpg"))

        try await store.saveOfflineImageData(Data([7]), for: imageURL)
        try await store.saveMembership(makeOfflineMembership(ownerName: "作品A", tid: "1", imageURLs: [imageURL]))

        try await store.clearAll()

        #expect(await store.membership(ownerName: "作品A", tid: "1") == nil)
        #expect(await store.offlineImageData(for: imageURL) == nil)
        #expect(await store.diskUsageByOwner().isEmpty)
    }
}

private func makeOfflineMembership(
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

private func makeOfflineWorkRequest(
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

private func makeTemporaryOfflineCacheDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
