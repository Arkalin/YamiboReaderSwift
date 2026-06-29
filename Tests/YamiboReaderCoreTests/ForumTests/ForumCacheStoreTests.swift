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
