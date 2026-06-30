import Foundation
import Testing
@testable import YamiboReaderCore

@Test func forumCacheStoreReturnsHomeWithinTTL() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 100)
    let store = ForumCacheStore(baseDirectory: directory, now: { now })
    let home = ForumHomePage(
        categories: [
            ForumCategory(
                id: "main",
                title: "分区",
                boards: [
                    ForumBoardSummary(
                        fid: "5",
                        name: "動漫區",
                        url: ForumRouteResolver.boardURL(fid: "5")
                    )
                ]
            )
        ],
        fetchedAt: now
    )

    try await store.saveHome(home)
    now = Date(timeIntervalSince1970: 100 + ForumCacheStore.homeTTL - 1)

    let loaded = await ForumCacheStore(baseDirectory: directory, now: { now }).loadHome()
    #expect(loaded?.categories.first?.boards.first?.fid == "5")
}

@Test func forumCacheStoreExpiresHomeAfterTTL() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 100)
    let store = ForumCacheStore(baseDirectory: directory, now: { now })
    let home = ForumHomePage(categories: [], fetchedAt: now)

    try await store.saveHome(home)
    now = Date(timeIntervalSince1970: 100 + ForumCacheStore.homeTTL + 1)

    #expect(await store.loadHome() == nil)
    #expect(await store.loadHome(allowExpired: true) != nil)
}

@Test func forumCacheStoreCachesThreadPagesByThreadPageAndAuthor() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 100)
    let store = ForumCacheStore(baseDirectory: directory, now: { now })
    let thread = try makeCacheTestThread(tid: "900")

    try await store.saveThreadPage(
        makeCacheTestThreadPage(thread: thread, title: "全部第一页"),
        thread: thread,
        pageNumber: 1,
        authorID: nil
    )
    try await store.saveThreadPage(
        makeCacheTestThreadPage(thread: thread, title: "全部第二页"),
        thread: thread,
        pageNumber: 2,
        authorID: nil
    )
    try await store.saveThreadPage(
        makeCacheTestThreadPage(thread: thread, title: "作者第一页"),
        thread: thread,
        pageNumber: 1,
        authorID: "42"
    )

    now = Date(timeIntervalSince1970: 100 + ForumCacheStore.threadPageTTL - 1)

    #expect(await store.loadThreadPage(thread: thread, page: 1, authorID: nil)?.title == "全部第一页")
    #expect(await store.loadThreadPage(thread: thread, page: 2, authorID: nil)?.title == "全部第二页")
    #expect(await store.loadThreadPage(thread: thread, page: 1, authorID: "42")?.title == "作者第一页")
}

@Test func forumCacheStoreExpiresThreadPagesAfterTTL() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 100)
    let store = ForumCacheStore(baseDirectory: directory, now: { now })
    let thread = try makeCacheTestThread(tid: "901")

    try await store.saveThreadPage(
        makeCacheTestThreadPage(thread: thread, title: "缓存页"),
        thread: thread,
        pageNumber: 1,
        authorID: nil
    )
    now = Date(timeIntervalSince1970: 100 + ForumCacheStore.threadPageTTL + 1)

    #expect(await store.loadThreadPage(thread: thread, page: 1, authorID: nil) == nil)
    #expect(await store.loadThreadPage(thread: thread, page: 1, authorID: nil, allowExpired: true)?.title == "缓存页")
}

@Test func forumCacheStorePrunesThreadPagesToMostRecentFiftyEntries() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    nonisolated(unsafe) var now = Date(timeIntervalSince1970: 100)
    let store = ForumCacheStore(baseDirectory: directory, now: { now })
    let thread = try makeCacheTestThread(tid: "902")

    for page in 1...51 {
        now = Date(timeIntervalSince1970: 100 + TimeInterval(page))
        try await store.saveThreadPage(
            makeCacheTestThreadPage(thread: thread, title: "第\(page)页"),
            thread: thread,
            pageNumber: page,
            authorID: nil
        )
    }

    #expect(await store.loadThreadPage(thread: thread, page: 1, authorID: nil, allowExpired: true) == nil)
    #expect(await store.loadThreadPage(thread: thread, page: 2, authorID: nil)?.title == "第2页")
    #expect(await store.loadThreadPage(thread: thread, page: 51, authorID: nil)?.title == "第51页")
}

@Test func forumCacheStoreClearThreadPagesPreservesOtherForumCache() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = ForumCacheStore(baseDirectory: directory)
    let firstThread = try makeCacheTestThread(tid: "903")
    let secondThread = try makeCacheTestThread(tid: "904")
    let home = ForumHomePage(categories: [], fetchedAt: Date(timeIntervalSince1970: 100))
    let board = ForumBoardPage(
        board: ForumBoardSummary(
            fid: "49",
            name: "百合小说",
            url: ForumRouteResolver.boardURL(fid: "49")
        ),
        fetchedAt: Date(timeIntervalSince1970: 100)
    )

    try await store.saveHome(home)
    try await store.saveBoard(board, fid: "49")
    try await store.saveThreadPage(
        makeCacheTestThreadPage(thread: firstThread, title: "目标线程"),
        thread: firstThread,
        pageNumber: 1,
        authorID: nil
    )
    try await store.saveThreadPage(
        makeCacheTestThreadPage(thread: secondThread, title: "其他线程"),
        thread: secondThread,
        pageNumber: 1,
        authorID: nil
    )

    try await store.clearThreadPages(thread: firstThread)

    #expect(await store.loadThreadPage(thread: firstThread, page: 1, authorID: nil, allowExpired: true) == nil)
    #expect(await store.loadThreadPage(thread: secondThread, page: 1, authorID: nil, allowExpired: true)?.title == "其他线程")
    #expect(await store.loadHome(allowExpired: true) != nil)
    #expect(await store.loadBoard(fid: "49", allowExpired: true)?.board.fid == "49")
}

private func makeCacheTestThread(tid: String) throws -> ThreadIdentity {
    ThreadIdentity(
        tid: tid,
        canonicalURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    )
}

private func makeCacheTestThreadPage(thread: ThreadIdentity, title: String) -> ForumThreadPage {
    ForumThreadPage(
        thread: thread,
        title: title,
        posts: [
            ForumThreadPost(
                postID: "p-\(title)",
                author: BlogReaderUser(uid: "42", name: "楼主"),
                contentHTML: "",
                contentText: title
            )
        ]
    )
}
