import Foundation
import Testing
@preconcurrency import GRDB
@testable import YamiboReaderCore

@Test func likeWorkKeyDerivesFromFavoriteContentTargetAndExcludesNormalThreads() {
    #expect(LikeWorkKey(target: .novelThread(threadID: "500")) == LikeWorkKey.novel(threadID: "500"))
    #expect(
        LikeWorkKey(target: .mangaTitle(mangaID: "m1", cleanBookName: "书名"))
            == LikeWorkKey.mangaTitle(cleanBookName: "书名")
    )
    #expect(LikeWorkKey(target: .normalThread(threadID: "500")) == nil)
}

@Test func likeStoreUpsertsAndFetchesTextLike() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-basic"))
    let workKey = LikeWorkKey.novel(threadID: "100")
    let anchor = NovelTextLikeAnchor(
        chapterIdentity: NovelChapterIdentity(rawValue: "chapter-1"),
        textSegmentIdentity: NovelTextSegmentIdentity(rawValue: "chapter-1#text:0"),
        range: NovelCharacterRange(location: 0, length: 4)
    )

    let result = try await store.upsertTextLike(workKey: workKey, anchor: anchor, excerptText: "你好世界")

    #expect(result.replacedIDs.isEmpty)
    let likes = await store.likes(for: workKey)
    #expect(likes.count == 1)
    #expect(likes.first?.excerptText == "你好世界")
    #expect(likes.first?.kind == .text)
    guard case let .novelText(storedAnchor) = likes.first?.anchor else {
        Issue.record("expected a novelText anchor")
        return
    }
    #expect(storedAnchor == anchor)
}

@Test func likeStoreUpsertTextLikeMergesTouchingRange() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-merge-touch"))
    let workKey = LikeWorkKey.novel(threadID: "200")
    let chapter = NovelChapterIdentity(rawValue: "chapter-1")
    let segment = NovelTextSegmentIdentity(rawValue: "chapter-1#text:0")

    try await store.upsertTextLike(
        id: "first",
        workKey: workKey,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 10)),
        excerptText: "AAAAAAAAAA"
    )

    // The union of the existing [0,10) range and the newly liked [10,15)
    // range is [0,15): the caller re-captures the excerpt over that union
    // before calling upsertTextLike.
    let merged = try await store.upsertTextLike(
        id: "second",
        workKey: workKey,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 15)),
        excerptText: "AAAAAAAAAABBBBB"
    )

    #expect(merged.replacedIDs == ["first"])
    let likes = await store.likes(for: workKey)
    #expect(likes.count == 1)
    #expect(likes.first?.id == "second")
    #expect(likes.first?.excerptText == "AAAAAAAAAABBBBB")
}

@Test func likeStoreUpsertTextLikeMergesOverlappingRange() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-merge-overlap"))
    let workKey = LikeWorkKey.novel(threadID: "201")
    let chapter = NovelChapterIdentity(rawValue: "chapter-1")
    let segment = NovelTextSegmentIdentity(rawValue: "chapter-1#text:0")

    try await store.upsertTextLike(
        id: "first",
        workKey: workKey,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 10)),
        excerptText: "0123456789"
    )

    // The union of the existing [0,10) range and the newly liked [5,15)
    // range is [0,15).
    let merged = try await store.upsertTextLike(
        id: "second",
        workKey: workKey,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 15)),
        excerptText: "0123456789ABCDE"
    )

    #expect(merged.replacedIDs == ["first"])
    #expect(await store.likes(for: workKey).count == 1)
}

@Test func likeStoreUpsertTextLikeDoesNotMergeGappedRange() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-gap"))
    let workKey = LikeWorkKey.novel(threadID: "202")
    let chapter = NovelChapterIdentity(rawValue: "chapter-1")
    let segment = NovelTextSegmentIdentity(rawValue: "chapter-1#text:0")

    try await store.upsertTextLike(
        id: "first",
        workKey: workKey,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 5)),
        excerptText: "01234"
    )

    let result = try await store.upsertTextLike(
        id: "second",
        workKey: workKey,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 10, length: 5)),
        excerptText: "56789"
    )

    #expect(result.replacedIDs.isEmpty)
    #expect(await store.likes(for: workKey).count == 2)
}

@Test func likeStoreUpsertsAndDeletesImageLike() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-image"))
    let workKey = LikeWorkKey.mangaTitle(cleanBookName: "测试漫画")
    let anchor = LikeAnchorPayload.mangaImage(MangaImageLikeAnchor(chapterTID: "900", pageLocalIndex: 3))
    let sourceURL = try #require(URL(string: "https://img.example.com/page.jpg"))

    let item = try await store.upsertImageLike(id: "image-1", workKey: workKey, anchor: anchor, sourceImageURL: sourceURL)
    #expect(item.kind == .image)
    #expect(item.sourceImageURL == sourceURL)

    let fetched = await store.like(id: "image-1")
    #expect(fetched?.anchor == anchor)

    try await store.delete(id: "image-1")
    #expect(await store.like(id: "image-1") == nil)
}

@Test func likeStoreWorkSummariesOrderByMostRecentActivity() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-summaries"))
    let novelKey = LikeWorkKey.novel(threadID: "300")
    let mangaKey = LikeWorkKey.mangaTitle(cleanBookName: "老漫画")
    let earlier = Date(timeIntervalSince1970: 1_000)
    let later = Date(timeIntervalSince1970: 2_000)

    try await store.upsertTextLike(
        workKey: novelKey,
        anchor: NovelTextLikeAnchor(
            chapterIdentity: NovelChapterIdentity(rawValue: "chapter-a"),
            textSegmentIdentity: NovelTextSegmentIdentity(rawValue: "chapter-a#text:0"),
            range: NovelCharacterRange(location: 0, length: 2)
        ),
        excerptText: "旧的",
        date: earlier
    )
    try await store.upsertImageLike(
        workKey: mangaKey,
        anchor: .mangaImage(MangaImageLikeAnchor(chapterTID: "1", pageLocalIndex: 0)),
        sourceImageURL: nil,
        date: later
    )

    let summaries = await store.workSummaries()
    #expect(summaries.count == 2)
    #expect(summaries.first?.workKey == mangaKey)
    #expect(summaries.first?.itemCount == 1)
    #expect(summaries.last?.workKey == novelKey)
}

@Test func likeStoreDeleteAllRemovesOnlyThatWork() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-delete-all"))
    let keyA = LikeWorkKey.novel(threadID: "400")
    let keyB = LikeWorkKey.novel(threadID: "401")
    let chapter = NovelChapterIdentity(rawValue: "chapter-1")
    let segment = NovelTextSegmentIdentity(rawValue: "chapter-1#text:0")

    try await store.upsertTextLike(
        workKey: keyA,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 3)),
        excerptText: "A"
    )
    try await store.upsertTextLike(
        workKey: keyB,
        anchor: NovelTextLikeAnchor(chapterIdentity: chapter, textSegmentIdentity: segment, range: NovelCharacterRange(location: 0, length: 3)),
        excerptText: "B"
    )

    try await store.deleteAll(workKey: keyA)

    #expect(await store.likes(for: keyA).isEmpty)
    #expect(await store.likes(for: keyB).count == 1)
}

@Test func likeStoreDeleteSoftDeletesAndHidesFromReadsButKeepsInAllIncludingDeleted() async throws {
    let store = LikeStore(databasePool: try makeLikeStoreTestDatabasePool(prefix: "like-store-soft-delete"))
    let workKey = LikeWorkKey.mangaTitle(cleanBookName: "软删除测试")
    let anchor = LikeAnchorPayload.mangaImage(MangaImageLikeAnchor(chapterTID: "1", pageLocalIndex: 0))

    let item = try await store.upsertImageLike(workKey: workKey, anchor: anchor, sourceImageURL: nil)
    let deletedAt = Date(timeIntervalSince1970: 5_000)
    try await store.delete(id: item.id, date: deletedAt)

    #expect(await store.likes(for: workKey).isEmpty)
    #expect(await store.workSummaries().isEmpty)
    #expect(await store.like(id: item.id) == nil)

    let allIncludingDeleted = await store.allIncludingDeleted()
    let deletedItem = try #require(allIncludingDeleted.first { $0.id == item.id })
    #expect(deletedItem.deletedAt == deletedAt)
    #expect(deletedItem.updatedAt == deletedAt)
}

private func makeLikeStoreTestDatabasePool(prefix: String) throws -> DatabasePool {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    return try YamiboDatabase.openPool(rootDirectory: root)
}
