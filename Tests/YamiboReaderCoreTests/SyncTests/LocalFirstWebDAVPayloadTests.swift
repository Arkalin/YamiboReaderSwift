import Foundation
import Testing
@testable import YamiboReaderCore

@Test func favoriteLibraryWebDAVPayloadExcludesProgressAuthLogsAndCoverBytes() throws {
    let payload = FavoriteLibraryWebDAVPayload(
        updatedAt: Date(timeIntervalSince1970: 1),
        accountUID: "uid",
        library: FavoriteLibraryDocument()
    )

    let data = try JSONEncoder().encode(payload)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["library"] != nil)
    #expect(object["readingProgress"] == nil)
    #expect(object["auth"] == nil)
    #expect(object["logs"] == nil)
    #expect(object["coverBytes"] == nil)
}

@Test func favoriteLibraryWebDAVMergePreservesIndependentLocationsAndTagsWithTombstones() throws {
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1001")))
    let baseDate = Date(timeIntervalSince1970: 10)
    var localDocument = FavoriteLibraryDocument()
    let category = localDocument.createCategory(name: "分类")
    let collection = localDocument.createCollection(categoryID: category.id, name: "合集")
    let tag = localDocument.createTag(name: "标签", color: .blue)
    var localItem = try FavoriteItem(target: target, title: "主题", locations: [.category(category.id)], tagIDs: [tag.id], updatedAt: baseDate)
    localDocument.addItem(localItem)

    var remoteDocument = localDocument
    localItem.locations = [.collection(categoryID: category.id, collectionID: collection.id)]
    localItem.tagIDs = []
    remoteDocument.items = [localItem]

    let merged = FavoriteLibraryWebDAVMerger().merge(
        local: FavoriteLibraryWebDAVPayload(updatedAt: baseDate, library: localDocument),
        remote: FavoriteLibraryWebDAVPayload(
            updatedAt: baseDate.addingTimeInterval(1),
            library: remoteDocument,
            tombstones: FavoriteLibraryWebDAVTombstones(removedTagIDsByTargetID: [target.id: [tag.id]])
        ),
        updatedAt: baseDate.addingTimeInterval(2)
    )

    let item = try #require(merged.library.items.first)
    #expect(Set(item.locations) == [.category(category.id), .collection(categoryID: category.id, collectionID: collection.id)])
    #expect(item.tagIDs.isEmpty)
}

@Test func favoriteLibraryWebDAVMergeUsesFieldDomainClocks() throws {
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1002")))
    let localClock = Date(timeIntervalSince1970: 20)
    let remoteClock = Date(timeIntervalSince1970: 30)
    let localItem = try FavoriteItem(
        target: target,
        title: "主题",
        displayName: "本地名",
        coverURL: URL(string: "https://example.com/local.jpg"),
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "local"),
        locations: [.category(FavoriteCategory.defaultID)]
    )
    var remoteItem = localItem
    remoteItem.displayName = "远端名"
    remoteItem.coverURL = URL(string: "https://example.com/remote.jpg")
    remoteItem.remoteMapping = FavoriteRemoteMapping(yamiboFavoriteID: "remote")

    let merged = FavoriteLibraryWebDAVMerger().merge(
        local: FavoriteLibraryWebDAVPayload(
            updatedAt: localClock,
            library: FavoriteLibraryDocument(items: [localItem]),
            clocks: FavoriteLibraryWebDAVClocks(
                displayNameUpdatedAtByTargetID: [target.id: remoteClock],
                coverUpdatedAtByTargetID: [target.id: localClock],
                remoteMappingUpdatedAtByTargetID: [target.id: localClock]
            )
        ),
        remote: FavoriteLibraryWebDAVPayload(
            updatedAt: remoteClock,
            library: FavoriteLibraryDocument(items: [remoteItem]),
            clocks: FavoriteLibraryWebDAVClocks(
                displayNameUpdatedAtByTargetID: [target.id: localClock],
                coverUpdatedAtByTargetID: [target.id: remoteClock],
                remoteMappingUpdatedAtByTargetID: [target.id: remoteClock]
            )
        ),
        updatedAt: remoteClock.addingTimeInterval(1)
    )

    let item = try #require(merged.library.items.first)
    #expect(item.displayName == "本地名")
    #expect(item.coverURL?.absoluteString == "https://example.com/remote.jpg")
    #expect(item.remoteMapping?.yamiboFavoriteID == "remote")
}

@Test func readingProgressWebDAVMergeUsesStableTargetIdentityAndNewestRecord() throws {
    let target = FavoriteContentTarget(mangaCleanBookName: "清理后的书名")
    let older = ReadingProgressRecord(
        contentTarget: target,
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1101")),
        kind: .manga,
        updatedAt: Date(timeIntervalSince1970: 10),
        manga: MangaReadingProgressRecord(
            lastMangaURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1101")),
            lastChapter: "第一话",
            mangaPageIndex: 1
        )
    )
    var newer = older
    newer.updatedAt = Date(timeIntervalSince1970: 20)
    newer.manga = MangaReadingProgressRecord(lastMangaURL: older.threadURL, lastChapter: "第一话", mangaPageIndex: 7)

    let merged = ReadingProgressWebDAVMerger().merge(
        local: ReadingProgressWebDAVPayload(updatedAt: older.updatedAt, records: [older]),
        remote: ReadingProgressWebDAVPayload(updatedAt: newer.updatedAt, records: [newer]),
        updatedAt: Date(timeIntervalSince1970: 30)
    )

    let record = try #require(merged.records.first)
    #expect(record.id == target.id)
    #expect(record.manga?.mangaPageIndex == 7)
}
