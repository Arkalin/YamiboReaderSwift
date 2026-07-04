import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Cached Manga Image Data Loader", .serialized)
struct MangaReaderTestsCachedMangaImageDataLoader {
    @Test func matchingOfflineMembershipReadsRetainedBytesBeforeImageDataLoader() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/offline.jpg"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryCachedMangaImageLoaderDirectory())
        try await offlineStore.saveOfflineImageData(Data([7]), for: imageURL)
        try await offlineStore.saveMembership(makeCachedMangaImageLoaderMembership(imageURLs: [imageURL]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(imageDataLoader: upstream, offlineCacheStore: offlineStore)

        let data = try await loader.imageData(
            for: imageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([7]))
        #expect(await upstream.callCount == 0)
    }

    @Test func missingOfflineBytesForMatchingMembershipFallsBackToImageDataLoader() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/fallback.jpg"))
        let refererURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=100"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryCachedMangaImageLoaderDirectory())
        try await offlineStore.saveMembership(makeCachedMangaImageLoaderMembership(imageURLs: [imageURL]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([9]))])
        let loader = CachedMangaImageDataLoader(imageDataLoader: upstream, offlineCacheStore: offlineStore)

        let data = try await loader.imageData(
            for: imageURL,
            refererURL: refererURL,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([9]))
        #expect(await upstream.callCount == 1)
        #expect(await upstream.requestedRequests == [YamiboImageRequest(url: imageURL, refererURL: refererURL)])
    }

    @Test func nonMemberImageDoesNotUseOfflineBytesForSameURL() async throws {
        let memberImageURL = try #require(URL(string: "https://img.example.com/member.jpg"))
        let requestedImageURL = try #require(URL(string: "https://img.example.com/non-member.jpg"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryCachedMangaImageLoaderDirectory())
        try await offlineStore.saveOfflineImageData(Data([7]), for: requestedImageURL)
        try await offlineStore.saveMembership(makeCachedMangaImageLoaderMembership(imageURLs: [memberImageURL]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([3]))])
        let loader = CachedMangaImageDataLoader(imageDataLoader: upstream, offlineCacheStore: offlineStore)

        let data = try await loader.imageData(
            for: requestedImageURL,
            refererURL: nil,
            offlineCacheContext: MangaImageOfflineCacheContext(ownerName: "favorite-a", tid: "100")
        )

        #expect(data == Data([3]))
        #expect(await upstream.callCount == 1)
    }

    @Test func noOfflineContextDelegatesToImageDataLoader() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/no-context.jpg"))
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryCachedMangaImageLoaderDirectory())
        try await offlineStore.saveOfflineImageData(Data([7]), for: imageURL)
        try await offlineStore.saveMembership(makeCachedMangaImageLoaderMembership(imageURLs: [imageURL]))
        let upstream = RecordingYamiboImageDataLoader(results: [.success(Data([4]))])
        let loader = CachedMangaImageDataLoader(imageDataLoader: upstream, offlineCacheStore: offlineStore)

        let data = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(data == Data([4]))
        #expect(await upstream.callCount == 1)
    }

    @Test func loaderDoesNotPersistOrdinaryBytesBetweenMisses() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/ordinary.jpg"))
        let upstream = RecordingYamiboImageDataLoader(results: [
            .success(Data([1])),
            .success(Data([2])),
        ])
        let loader = CachedMangaImageDataLoader(imageDataLoader: upstream)

        let first = try await loader.imageData(for: imageURL, refererURL: nil)
        let second = try await loader.imageData(for: imageURL, refererURL: nil)

        #expect(first == Data([1]))
        #expect(second == Data([2]))
        #expect(await upstream.callCount == 2)
    }

    @Test func upstreamFailureIsNotMaskedByOfflineMiss() async throws {
        let imageURL = try #require(URL(string: "https://img.example.com/fail.jpg"))
        let upstream = RecordingYamiboImageDataLoader(results: [.failure(YamiboError.offline)])
        let loader = CachedMangaImageDataLoader(imageDataLoader: upstream)

        await #expect(throws: YamiboError.offline) {
            _ = try await loader.imageData(for: imageURL, refererURL: nil)
        }

        #expect(await upstream.callCount == 1)
    }
}

private actor RecordingYamiboImageDataLoader: YamiboImageDataLoading {
    private var results: [Result<Data, Error>]
    private(set) var requestedRequests: [YamiboImageRequest] = []
    private(set) var callCount = 0

    init(results: [Result<Data, Error>]) {
        self.results = results
    }

    func imageData(for request: YamiboImageRequest) async throws -> Data {
        callCount += 1
        requestedRequests.append(request)
        let result = results.isEmpty ? Result<Data, Error>.failure(YamiboError.unreadableBody) : results.removeFirst()
        return try result.get()
    }
}

private func makeCachedMangaImageLoaderMembership(imageURLs: [URL]) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: "favorite-a",
        tid: "100",
        chapterTitle: "第100话",
        imageURLs: imageURLs,
        sourcePage: ForumThreadPage(
            thread: ThreadIdentity(tid: "100"),
            title: "第100话",
            posts: [
                ForumThreadPost(
                    postID: "p-100",
                    author: BlogReaderUser(uid: "author-100", name: "作者"),
                    contentHTML: "",
                    contentText: ""
                )
            ]
        )
    )
}

private func makeTemporaryCachedMangaImageLoaderDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
