import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Manga Offline Cache Store")
struct MangaReaderTestsMangaOfflineCacheStore {
    @Test func savesMembershipWithFavoriteAndChapterIdentityAcrossStoreInstances() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=900&page=3"))
        let imageURL = try #require(URL(string: "https://img.example.com/page-1.jpg"))

        let writingStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        try await writingStore.saveMembership(
            MangaOfflineCacheMembership(
                favoriteID: "favorite-1",
                favoriteTitle: "作品",
                favoriteURL: try #require(URL(string: "https://bbs.yamibo.com/thread-900-1-1.html")),
                tid: "900",
                chapterTitle: "第1话",
                chapterURL: chapterURL,
                imageURLs: [imageURL]
            )
        )

        let readingStore = FileMangaOfflineCacheStore(baseDirectory: directory)
        let loaded = await readingStore.membership(favoriteID: "favorite-1", tid: "900")

        #expect(loaded?.id == MangaOfflineCacheMembershipID(favoriteID: "favorite-1", tid: "900"))
        #expect(loaded?.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=900")
        #expect(loaded?.favoriteTitle == "作品")
        #expect(loaded?.chapterTitle == "第1话")
        #expect(loaded?.imageURLs == [imageURL])
    }

    @Test func usageReportsStoredOfflineImagesByOwningFavorite() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = FileMangaOfflineCacheStore(baseDirectory: directory)
        let firstImage = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let secondImage = try #require(URL(string: "https://img.example.com/second.jpg"))

        try await store.saveOfflineImageData(Data(repeating: 1, count: 3), for: firstImage)
        try await store.saveOfflineImageData(Data(repeating: 2, count: 5), for: secondImage)
        try await store.saveMembership(makeOfflineMembership(favoriteID: "favorite-a", tid: "1", imageURLs: [firstImage]))
        try await store.saveMembership(makeOfflineMembership(favoriteID: "favorite-b", tid: "2", imageURLs: [firstImage, secondImage]))

        let usage = await store.diskUsageByFavorite()

        #expect(usage == [
            MangaOfflineCacheFavoriteUsage(favoriteID: "favorite-a", byteCount: 3),
            MangaOfflineCacheFavoriteUsage(favoriteID: "favorite-b", byteCount: 8)
        ])
    }

    @Test func usageIncludesMembershipOwnerWhenReferencedImagesAreMissing() async throws {
        let store = FileMangaOfflineCacheStore(baseDirectory: try makeTemporaryOfflineCacheDirectory())
        let missingImage = try #require(URL(string: "https://img.example.com/missing.jpg"))

        try await store.saveMembership(makeOfflineMembership(favoriteID: "favorite-a", tid: "1", imageURLs: [missingImage]))

        #expect(await store.diskUsageByFavorite() == [
            MangaOfflineCacheFavoriteUsage(favoriteID: "favorite-a", byteCount: 0)
        ])
    }

    @Test func deletingMembershipPreservesImagesReferencedByRemainingMemberships() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = FileMangaOfflineCacheStore(baseDirectory: directory)
        let sharedImage = try #require(URL(string: "https://img.example.com/shared.jpg"))
        let firstOnlyImage = try #require(URL(string: "https://img.example.com/first-only.jpg"))

        try await store.saveOfflineImageData(Data([1, 2, 3]), for: sharedImage)
        try await store.saveOfflineImageData(Data([4, 5]), for: firstOnlyImage)
        try await store.saveMembership(makeOfflineMembership(favoriteID: "favorite-a", tid: "1", imageURLs: [sharedImage, firstOnlyImage]))
        try await store.saveMembership(makeOfflineMembership(favoriteID: "favorite-a", tid: "2", imageURLs: [sharedImage]))

        try await store.removeMembership(favoriteID: "favorite-a", tid: "1")

        #expect(await store.membership(favoriteID: "favorite-a", tid: "1") == nil)
        #expect(await store.offlineImageData(for: sharedImage) == Data([1, 2, 3]))
        #expect(await store.offlineImageData(for: firstOnlyImage) == nil)
        #expect(await store.diskUsageByFavorite() == [
            MangaOfflineCacheFavoriteUsage(favoriteID: "favorite-a", byteCount: 3)
        ])
    }

    @Test func deletingOfflineMembershipDoesNotClearTransparentMangaCaches() async throws {
        let root = try makeTemporaryOfflineCacheDirectory()
        let offlineStore = FileMangaOfflineCacheStore(baseDirectory: root.appendingPathComponent("offline", isDirectory: true))
        let directoryStore = FileMangaDirectoryStore(baseDirectory: root.appendingPathComponent("directories", isDirectory: true))
        let documentStore = FileMangaChapterDocumentStore(baseDirectory: root.appendingPathComponent("documents", isDirectory: true))
        let imageCacheStore = FileMangaImageDataCacheStore(baseDirectory: root.appendingPathComponent("transparent-images", isDirectory: true))
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100"))
        let imageURL = try #require(URL(string: "https://img.example.com/transparent.jpg"))

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
        try await documentStore.save(
            MangaChapterDocument(
                tid: "100",
                chapterTitle: "第1话",
                chapterURL: chapterURL,
                imageURLs: [imageURL]
            ),
            for: chapterURL
        )
        try await imageCacheStore.save(Data([9, 9]), for: imageURL)
        try await offlineStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await offlineStore.saveMembership(makeOfflineMembership(favoriteID: "favorite-a", tid: "100", imageURLs: [imageURL]))

        try await offlineStore.removeMembership(favoriteID: "favorite-a", tid: "100")

        #expect(try await directoryStore.directory(named: "透明目录")?.chapters.map(\.tid) == ["100"])
        #expect(await documentStore.document(for: chapterURL)?.tid == "100")
        #expect(await imageCacheStore.data(for: imageURL) == Data([9, 9]))
        #expect(await offlineStore.offlineImageData(for: imageURL) == nil)
    }

    @Test func clearAllRemovesMembershipAndRetainedOfflineImages() async throws {
        let directory = try makeTemporaryOfflineCacheDirectory()
        let store = FileMangaOfflineCacheStore(baseDirectory: directory)
        let imageURL = try #require(URL(string: "https://img.example.com/clear.jpg"))

        try await store.saveOfflineImageData(Data([7]), for: imageURL)
        try await store.saveMembership(makeOfflineMembership(favoriteID: "favorite-a", tid: "1", imageURLs: [imageURL]))

        try await store.clearAll()

        #expect(await store.membership(favoriteID: "favorite-a", tid: "1") == nil)
        #expect(await store.offlineImageData(for: imageURL) == nil)
        #expect(await store.diskUsageByFavorite().isEmpty)
    }
}

private func makeOfflineMembership(
    favoriteID: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        favoriteID: favoriteID,
        favoriteTitle: "作品 \(favoriteID)",
        favoriteURL: try #require(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html")),
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=5")),
        imageURLs: imageURLs
    )
}

private func makeTemporaryOfflineCacheDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
