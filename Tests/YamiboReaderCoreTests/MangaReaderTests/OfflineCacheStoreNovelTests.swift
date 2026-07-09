import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Novel Offline Cache Store")
struct MangaReaderTestsNovelOfflineCacheStore {
    @Test func sourcePageSaveMakesViewCachedAndPersistsUpdateTime() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let request = try makeNovelWorkRequest(tid: "7001", view: 2)
        let sourcePage = try makeNovelSourcePage(tid: "7001", view: 2, totalPages: 4)
        let updatedAt = Date(timeIntervalSince1970: 12_345)

        #expect(await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            authorID: request.authorID
        ).cachedViews.isEmpty)

        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            updatedAt: updatedAt
        )

        let snapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            authorID: request.authorID
        )
        let loadedSource = await store.novelOfflineSourcePage(
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            view: request.view,
            authorID: request.authorID
        )
        let expectedBytes = try JSONEncoder().encode(sourcePage).count

        #expect(snapshot.cachedViews == [2])
        #expect(snapshot.cachingViews.isEmpty)
        #expect(snapshot.updateTimesByView[2] == updatedAt)
        #expect(snapshot.state(for: 2).status == .cached)
        #expect(loadedSource == sourcePage)
        #expect(await store.totalDiskUsageBytes() == expectedBytes)
    }

    @Test func sourcePageSaveDoesNotCreateNovelProjectionPayloadDirectory() async throws {
        let root = try makeTemporaryNovelOfflineCacheDirectory()
        let baseDirectory = root.appendingPathComponent("offline", isDirectory: true)
        let store = try makeTestOfflineCacheStore(rootDirectory: root, baseDirectory: baseDirectory)
        let request = try makeNovelWorkRequest(tid: "7002", view: 1)
        let sourcePage = try makeNovelSourcePage(tid: "7002", view: 1, totalPages: 1)

        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            updatedAt: Date(timeIntervalSince1970: 22_000)
        )

        let snapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            authorID: request.authorID
        )

        #expect(snapshot.cachedViews == [1])
        #expect(!FileManager.default.fileExists(atPath: baseDirectory.appendingPathComponent("novel-projections", isDirectory: true).path))
    }

    @Test func queuedNovelWorkProjectsAsCachingWithoutCachedSourcePage() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let request = try makeNovelWorkRequest(tid: "7003", view: 3)

        _ = try await store.enqueueNovelOfflineCacheWork(request)

        let snapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            authorID: request.authorID
        )

        #expect(snapshot.cachedViews.isEmpty)
        #expect(snapshot.cachingViews == [3])
        #expect(snapshot.updateTimesByView.isEmpty)
        #expect(snapshot.state(for: 3).status == .caching)
    }

    @Test func sourcePageIdentityIgnoresOwnerTitleChanges() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let originalRequest = try makeNovelWorkRequest(tid: "7010", view: 1, ownerTitle: "旧标题7010")
        let renamedRequest = try makeNovelWorkRequest(tid: "7010", view: 1, ownerTitle: "新标题7010")
        let sourcePage = try makeNovelSourcePage(tid: "7010", view: 1, totalPages: 1)

        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: originalRequest,
            updatedAt: Date(timeIntervalSince1970: 70_100)
        )

        let renamedSnapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: renamedRequest.ownerTitle,
            threadID: renamedRequest.threadID,
            authorID: renamedRequest.authorID
        )
        let loadedSource = await store.novelOfflineSourcePage(
            ownerTitle: renamedRequest.ownerTitle,
            threadID: renamedRequest.threadID,
            view: renamedRequest.view,
            authorID: renamedRequest.authorID
        )

        #expect(renamedSnapshot.cachedViews == [1])
        #expect(loadedSource == sourcePage)

        try await store.removeNovelOfflineCacheViews(
            [1],
            ownerTitle: renamedRequest.ownerTitle,
            threadID: renamedRequest.threadID,
            authorID: renamedRequest.authorID
        )

        #expect(await store.novelOfflineSourcePage(
            ownerTitle: originalRequest.ownerTitle,
            threadID: originalRequest.threadID,
            view: originalRequest.view,
            authorID: originalRequest.authorID
        ) == nil)
        #expect(await store.allNovelOfflineCacheEntries().isEmpty)
    }

    @Test func queuedNovelWorkIdentityIgnoresOwnerTitleAndUpdatesDisplayTitle() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let originalRequest = try makeNovelWorkRequest(tid: "7011", view: 2, ownerTitle: "旧标题7011")
        let renamedRequest = try makeNovelWorkRequest(tid: "7011", view: 2, ownerTitle: "新标题7011")

        _ = try await store.enqueueNovelOfflineCacheWork(originalRequest)
        let secondResult = try await store.enqueueNovelOfflineCacheWork(renamedRequest)

        guard case let .alreadyQueued(projectedWork) = secondResult else {
            Issue.record("Second enqueue should return the existing novel work")
            return
        }
        let works = await store.offlineCacheQueueWorks()
        let expectedGroupKey = NovelOfflineCacheEntry.groupKey(
            threadID: renamedRequest.threadID,
            authorID: renamedRequest.authorID
        )

        #expect(works.count == 1)
        #expect(projectedWork.groupID.ownerKey == expectedGroupKey)
        #expect(projectedWork.ownerTitle == "新标题7011")
        #expect(works.first?.ownerTitle == "新标题7011")
    }

    @Test func savingSameNovelViewWithNewOwnerTitleUpdatesManagementGroupWithoutDuplicate() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let originalRequest = try makeNovelWorkRequest(tid: "7012", view: 1, ownerTitle: "旧标题7012")
        let renamedRequest = try makeNovelWorkRequest(tid: "7012", view: 1, ownerTitle: "新标题7012")
        let sourcePage = try makeNovelSourcePage(tid: "7012", view: 1, totalPages: 1)

        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: originalRequest,
            updatedAt: Date(timeIntervalSince1970: 70_120)
        )
        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: renamedRequest,
            updatedAt: Date(timeIntervalSince1970: 70_121)
        )

        let snapshot = await store.offlineCacheManagementSnapshot()
        let group = try #require(snapshot.groups.first)
        let expectedGroupKey = NovelOfflineCacheEntry.groupKey(
            threadID: renamedRequest.threadID,
            authorID: renamedRequest.authorID
        )

        #expect(snapshot.groups.count == 1)
        #expect(group.id.ownerKey == expectedGroupKey)
        #expect(group.title == "新标题7012")
        #expect(group.cachedCount == 1)
        #expect(group.entries.count == 1)
    }

    @Test func novelOfflineImageDataMatchesCanonicalRefererAndReferencedImage() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let sharedImageURL = try #require(URL(string: "https://img.example.com/shared-inline.jpg"))
        let matchingRequest = try NovelOfflineCacheWorkRequest(
            ownerTitle: "小说7013",
            title: "第1页",
            threadID: "7013",
            view: 1,
            authorID: "42",
            targetImageURLs: [sharedImageURL],
            retainsInlineImages: true
        )
        let otherRequest = try makeNovelWorkRequest(tid: "7014", view: 1)
        let matchingSourcePage = try makeNovelSourcePage(tid: "7013", view: 1, totalPages: 1)
        let otherSourcePage = try makeNovelSourcePage(tid: "7014", view: 1, totalPages: 1)

        try await store.saveNovelOfflineSourcePage(
            matchingSourcePage,
            request: matchingRequest,
            updatedAt: Date(timeIntervalSince1970: 70_130)
        )
        try await store.saveNovelOfflineSourcePage(
            otherSourcePage,
            request: otherRequest,
            updatedAt: Date(timeIntervalSince1970: 70_140)
        )
        try await store.saveOfflineImageData(Data([1, 3]), for: sharedImageURL)

        #expect(await store.novelOfflineImageData(for: sharedImageURL, threadID: "7013") == Data([1, 3]))
        #expect(await store.novelOfflineImageData(for: sharedImageURL, threadID: "7014") == nil)
    }

    @Test func deletingNovelOfflineEntryPreservesTransparentThreadPageAndProjectionCaches() async throws {
        let root = try makeTemporaryNovelOfflineCacheDirectory()
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: root)
        let novelReaderCacheStore = NovelReaderProjectionStore(baseDirectory: root.appendingPathComponent("reader-cache", isDirectory: true))
        let forumCacheStore = ForumCacheStore(baseDirectory: root.appendingPathComponent("forum-cache", isDirectory: true))
        let request = try makeNovelWorkRequest(tid: "7004", view: 1)
        let sourcePage = try makeNovelSourcePage(tid: "7004", view: 1, totalPages: 2)
        let projection = try makeNovelDocument(tid: "7004", view: 1, maxView: 2)
        let thread = sourcePage.thread

        try await forumCacheStore.saveThreadPage(sourcePage, thread: thread, pageNumber: 1, authorID: "42")
        try await novelReaderCacheStore.save(projection)
        try await offlineStore.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            updatedAt: Date(timeIntervalSince1970: 33_000)
        )
        _ = try await offlineStore.enqueueNovelOfflineCacheUpdateWork(request)

        try await offlineStore.removeNovelOfflineCacheViews(
            [1],
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            authorID: request.authorID
        )

        #expect(await offlineStore.novelOfflineSourcePage(
            ownerTitle: request.ownerTitle,
            threadID: request.threadID,
            view: 1,
            authorID: request.authorID
        ) == nil)
        #expect(await offlineStore.offlineCacheQueueWorks().isEmpty)
        #expect(await forumCacheStore.loadThreadPage(thread: thread, page: 1, authorID: "42") == sourcePage)
        let retainedProjection = await novelReaderCacheStore.loadProjection(
            for: NovelPageRequest(threadID: request.threadID, view: 1, authorID: "42")
        )
        #expect(retainedProjection?.view == projection.view)
        #expect(retainedProjection?.segments == projection.segments)
    }

    @Test func sourcePageUpdateWithImageRetentionDisabledPreservesExistingImageAssets() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let imageURL = try #require(URL(string: "https://img.example.com/7005-inline.jpg"))
        let sourcePage = try makeNovelSourcePage(tid: "7005", view: 1, totalPages: 1)
        let initialRequest = NovelOfflineCacheWorkRequest(
            ownerTitle: "小说7005",
            title: "第1页",
            threadID: "7005",
            view: 1,
            authorID: "42",
            targetImageURLs: [imageURL],
            retainsInlineImages: true
        )
        let disabledRequest = NovelOfflineCacheWorkRequest(
            ownerTitle: initialRequest.ownerTitle,
            title: initialRequest.title,
            threadID: initialRequest.threadID,
            view: initialRequest.view,
            authorID: initialRequest.authorID,
            retainsInlineImages: false
        )

        try await store.saveOfflineImageData(Data([7, 5]), for: imageURL)
        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: initialRequest,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: disabledRequest,
            updatedAt: Date(timeIntervalSince1970: 11),
            preservesExistingImageReferencesWhenEmpty: true
        )

        let entry = await store.novelOfflineCacheEntry(id: OfflineCacheEntryID(
            readerKind: .novel,
            ownerKey: initialRequest.groupKey,
            entryKey: initialRequest.entryKey
        ))
        #expect(entry?.imageURLs == [imageURL])
        #expect(await store.offlineImageData(for: imageURL) == Data([7, 5]))
    }
}

private func makeNovelWorkRequest(
    tid: String,
    view: Int,
    ownerTitle: String? = nil
) throws -> NovelOfflineCacheWorkRequest {
    NovelOfflineCacheWorkRequest(
        ownerTitle: ownerTitle ?? "小说\(tid)",
        title: "第\(view)页",
        threadID: tid,
        view: view,
        authorID: "42"
    )
}

private func makeNovelSourcePage(tid: String, view: Int, totalPages: Int) throws -> ForumThreadPage {
    return ForumThreadPage(
        thread: ThreadIdentity(tid: tid),
        title: "小说\(tid)",
        posts: [
            ForumThreadPost(
                postID: "\(tid)-\(view)",
                author: BlogReaderUser(uid: "42", name: "楼主"),
                contentHTML: "<strong>第\(view)章</strong><br>正文\(view)",
                contentText: "正文\(view)"
            )
        ],
        pageNavigation: ForumPageNavigation(currentPage: view, totalPages: totalPages)
    )
}

private func makeNovelDocument(tid: String, view: Int, maxView: Int) throws -> NovelReaderProjection {
    return NovelReaderProjection(
        threadID: tid,
        view: view,
        maxView: maxView,
        resolvedAuthorID: "42",
        segments: [.text("正文\(view)", chapterTitle: "第\(view)章")],
        projectionSourceFingerprint: "source-\(view)",
        projectionSchemaVersion: 1
    )
}

private func makeTemporaryNovelOfflineCacheDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
