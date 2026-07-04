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
            threadURL: request.threadURL,
            authorID: request.authorID,
            contentSource: request.contentSource
        ).cachedViews.isEmpty)

        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            projectionPrewarm: nil,
            updatedAt: updatedAt
        )

        let snapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            authorID: request.authorID,
            contentSource: request.contentSource
        )
        let loadedSource = await store.novelOfflineSourcePage(
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            view: request.view,
            authorID: request.authorID,
            contentSource: request.contentSource
        )

        #expect(snapshot.cachedViews == [2])
        #expect(snapshot.cachingViews.isEmpty)
        #expect(snapshot.updateTimesByView[2] == updatedAt)
        #expect(snapshot.state(for: 2).status == .cached)
        #expect(loadedSource == sourcePage)
    }

    @Test func projectionPrewarmFailureDoesNotFailSourcePageSave() async throws {
        let root = try makeTemporaryNovelOfflineCacheDirectory()
        let baseDirectory = root.appendingPathComponent("offline", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try Data([1]).write(to: baseDirectory.appendingPathComponent("novel-projections", isDirectory: false))
        let store = try makeTestOfflineCacheStore(rootDirectory: root, baseDirectory: baseDirectory)
        let request = try makeNovelWorkRequest(tid: "7002", view: 1)
        let sourcePage = try makeNovelSourcePage(tid: "7002", view: 1, totalPages: 1)
        let projection = try makeNovelDocument(tid: "7002", view: 1, maxView: 1)

        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            projectionPrewarm: projection,
            updatedAt: Date(timeIntervalSince1970: 22_000)
        )

        let snapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            authorID: request.authorID,
            contentSource: request.contentSource
        )
        let prewarm = await store.novelOfflineProjectionPrewarm(
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            view: request.view,
            authorID: request.authorID,
            contentSource: request.contentSource
        )

        #expect(snapshot.cachedViews == [1])
        #expect(prewarm == nil)
    }

    @Test func queuedNovelWorkProjectsAsCachingWithoutCachedSourcePage() async throws {
        let store = try makeTestOfflineCacheStore(rootDirectory: try makeTemporaryNovelOfflineCacheDirectory())
        let request = try makeNovelWorkRequest(tid: "7003", view: 3)

        _ = try await store.enqueueNovelOfflineCacheWork(request)

        let snapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            authorID: request.authorID,
            contentSource: request.contentSource
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
            projectionPrewarm: nil,
            updatedAt: Date(timeIntervalSince1970: 70_100)
        )

        let renamedSnapshot = await store.novelOfflineCacheViewsSnapshot(
            ownerTitle: renamedRequest.ownerTitle,
            threadURL: renamedRequest.threadURL,
            authorID: renamedRequest.authorID,
            contentSource: renamedRequest.contentSource
        )
        let loadedSource = await store.novelOfflineSourcePage(
            ownerTitle: renamedRequest.ownerTitle,
            threadURL: renamedRequest.threadURL,
            view: renamedRequest.view,
            authorID: renamedRequest.authorID,
            contentSource: renamedRequest.contentSource
        )

        #expect(renamedSnapshot.cachedViews == [1])
        #expect(loadedSource == sourcePage)

        try await store.removeNovelOfflineCacheViews(
            [1],
            ownerTitle: renamedRequest.ownerTitle,
            threadURL: renamedRequest.threadURL,
            authorID: renamedRequest.authorID,
            contentSource: renamedRequest.contentSource
        )

        #expect(await store.novelOfflineSourcePage(
            ownerTitle: originalRequest.ownerTitle,
            threadURL: originalRequest.threadURL,
            view: originalRequest.view,
            authorID: originalRequest.authorID,
            contentSource: originalRequest.contentSource
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
            threadURL: renamedRequest.threadURL,
            authorID: renamedRequest.authorID,
            contentSource: renamedRequest.contentSource
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
            projectionPrewarm: nil,
            updatedAt: Date(timeIntervalSince1970: 70_120)
        )
        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: renamedRequest,
            projectionPrewarm: nil,
            updatedAt: Date(timeIntervalSince1970: 70_121)
        )

        let snapshot = await store.offlineCacheManagementSnapshot()
        let group = try #require(snapshot.groups.first)
        let expectedGroupKey = NovelOfflineCacheEntry.groupKey(
            threadURL: renamedRequest.threadURL,
            authorID: renamedRequest.authorID,
            contentSource: renamedRequest.contentSource
        )

        #expect(snapshot.groups.count == 1)
        #expect(group.id.ownerKey == expectedGroupKey)
        #expect(group.title == "新标题7012")
        #expect(group.cachedCount == 1)
        #expect(group.entries.count == 1)
    }

    @Test func deletingNovelOfflineEntryPreservesTransparentThreadPageAndProjectionCaches() async throws {
        let root = try makeTemporaryNovelOfflineCacheDirectory()
        let offlineStore = try makeTestOfflineCacheStore(rootDirectory: root)
        let readerCacheStore = ReaderCacheStore(baseDirectory: root.appendingPathComponent("reader-cache", isDirectory: true))
        let forumCacheStore = ForumCacheStore(baseDirectory: root.appendingPathComponent("forum-cache", isDirectory: true))
        let request = try makeNovelWorkRequest(tid: "7004", view: 1)
        let sourcePage = try makeNovelSourcePage(tid: "7004", view: 1, totalPages: 2)
        let projection = try makeNovelDocument(tid: "7004", view: 1, maxView: 2)
        let thread = sourcePage.thread

        try await forumCacheStore.saveThreadPage(sourcePage, thread: thread, pageNumber: 1, authorID: "42")
        try await readerCacheStore.save(projection)
        try await offlineStore.saveNovelOfflineSourcePage(
            sourcePage,
            request: request,
            projectionPrewarm: projection,
            updatedAt: Date(timeIntervalSince1970: 33_000)
        )
        _ = try await offlineStore.enqueueNovelOfflineCacheUpdateWork(request)

        try await offlineStore.removeNovelOfflineCacheViews(
            [1],
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            authorID: request.authorID,
            contentSource: request.contentSource
        )

        #expect(await offlineStore.novelOfflineSourcePage(
            ownerTitle: request.ownerTitle,
            threadURL: request.threadURL,
            view: 1,
            authorID: request.authorID,
            contentSource: request.contentSource
        ) == nil)
        #expect(await offlineStore.offlineCacheQueueWorks().isEmpty)
        #expect(await forumCacheStore.loadThreadPage(thread: thread, page: 1, authorID: "42") == sourcePage)
        let retainedProjection = await readerCacheStore.loadDocument(
            for: ReaderPageRequest(threadURL: request.threadURL, view: 1, authorID: "42"),
            contentSource: .authorFilteredPage
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
            threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7005&mobile=2")),
            view: 1,
            authorID: "42",
            contentSource: .authorFilteredPage,
            targetImageURLs: [imageURL],
            retainsInlineImages: true
        )
        let disabledRequest = NovelOfflineCacheWorkRequest(
            ownerTitle: initialRequest.ownerTitle,
            title: initialRequest.title,
            threadURL: initialRequest.threadURL,
            view: initialRequest.view,
            authorID: initialRequest.authorID,
            contentSource: initialRequest.contentSource,
            retainsInlineImages: false
        )

        try await store.saveOfflineImageData(Data([7, 5]), for: imageURL)
        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: initialRequest,
            projectionPrewarm: nil,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        try await store.saveNovelOfflineSourcePage(
            sourcePage,
            request: disabledRequest,
            projectionPrewarm: nil,
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
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")),
        view: view,
        authorID: "42",
        contentSource: .authorFilteredPage
    )
}

private func makeNovelSourcePage(tid: String, view: Int, totalPages: Int) throws -> ForumThreadPage {
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    let thread = ThreadIdentity(tid: tid, canonicalURL: ReaderCacheIdentity.canonicalThreadURL(from: threadURL))
    return ForumThreadPage(
        thread: thread,
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

private func makeNovelDocument(tid: String, view: Int, maxView: Int) throws -> ReaderPageDocument {
    let threadURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    return ReaderPageDocument(
        threadURL: ReaderCacheIdentity.canonicalThreadURL(from: threadURL),
        view: view,
        maxView: maxView,
        resolvedAuthorID: "42",
        contentSource: .authorFilteredPage,
        segments: [.text("正文\(view)", chapterTitle: "第\(view)章")],
        projectionSourceFingerprint: "source-\(view)",
        projectionSchemaVersion: 1
    )
}

private func makeTemporaryNovelOfflineCacheDirectory() throws -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
