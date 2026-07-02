import Foundation
import Testing
@preconcurrency import GRDB
@testable import YamiboReaderCore

@Test func localFirstFavoriteLibraryInitializesWithDefaultFavoriteCategory() {
    let document = FavoriteLibraryDocument()

    #expect(document.categories.count == 1)
    #expect(document.defaultCategory.isDefault)
    #expect(document.defaultCategory.id == FavoriteCategory.defaultID)
    #expect(document.defaultCategory.name == FavoriteCategory.defaultStorageName)
    #expect(document.defaultCategory.displayName == L10n.string("favorites.default_category"))
    #expect(document.items.isEmpty)
}

@Test func localFirstFavoriteLibraryNormalizesLegacyLocalizedDefaultCategoryName() {
    let legacyDefault = FavoriteCategory(
        id: FavoriteCategory.defaultID,
        name: "默认",
        manualOrder: 99,
        isDefault: true
    )
    let document = FavoriteLibraryDocument(categories: [legacyDefault])

    #expect(document.categories.count == 1)
    #expect(document.defaultCategory.id == FavoriteCategory.defaultID)
    #expect(document.defaultCategory.isDefault)
    #expect(document.defaultCategory.name == FavoriteCategory.defaultStorageName)
    #expect(document.defaultCategory.displayName == L10n.string("favorites.default_category"))
}

@Test func favoriteItemIdentityComesFromStableContentTarget() throws {
    let firstURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=319&page=4&mobile=2"))
    let secondURL = try #require(URL(string: "https://bbs.yamibo.com/thread-319-1-1.html"))
    let normal = FavoriteContentTarget(kind: .normalThread, threadURL: firstURL)
    let sameNormal = FavoriteContentTarget(kind: .normalThread, threadURL: secondURL)
    let novel = FavoriteContentTarget(kind: .novelThread, threadURL: secondURL)
    let manga = FavoriteContentTarget(mangaCleanBookName: "Clean Manga")
    let stableManga = FavoriteContentTarget(mangaID: "links:9001", mangaCleanBookName: "Clean Manga")

    #expect(normal.id == sameNormal.id)
    #expect(normal.id != novel.id)
    #expect(manga.id == "manga-title:Clean Manga")
    #expect(stableManga.id == "manga-title:links:9001")
    #expect(stableManga.mangaCleanBookName == "Clean Manga")
}

@Test func favoriteItemIdentityDecodesLegacyMangaTitlePayloads() throws {
    let decoder = JSONDecoder()
    let targetData = Data(#"{"kind":"mangaTitle","cleanBookName":"Legacy Manga"}"#.utf8)
    let sourceGroupData = Data(#"{"mangaTitle":{"cleanBookName":"Legacy Manga"}}"#.utf8)

    let target = try decoder.decode(FavoriteContentTarget.self, from: targetData)
    let sourceGroup = try decoder.decode(FavoriteSourceGroup.self, from: sourceGroupData)

    #expect(target == FavoriteContentTarget(mangaCleanBookName: "Legacy Manga"))
    #expect(target.mangaCleanBookName == "Legacy Manga")
    #expect(sourceGroup == .mangaTitle(cleanBookName: "Legacy Manga"))
}

@Test func favoriteItemRequiresAtLeastOneFavoriteLocation() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=320"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)

    #expect(throws: YamiboError.self) {
        _ = try FavoriteItem(target: target, title: "No location", locations: [])
    }
}

@Test func localFirstFavoriteLibraryPersistsItemMetadataLocationsTagsAndRemoteMapping() async throws {
    let suiteName = "LocalFirstFavoriteLibraryTests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: suiteName))
    let store = FavoriteLibraryStore(defaults: suite, key: "library")
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=321"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    let coverURL = try #require(URL(string: "https://img.example.test/cover.jpg"))
    var document = FavoriteLibraryDocument()
    let category = document.defaultCategory
    let tag = document.createTag(name: "本地标签", color: .blue)
    let item = try FavoriteItem(
        target: target,
        title: "远端标题",
        displayName: " 本地名 ",
        sourceGroup: .forumBoard(id: "fid-1", label: "版块"),
        coverURL: coverURL,
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-321", yamiboRemoteOrder: 7),
        locations: [.category(category.id)],
        tagIDs: [tag.id, tag.id]
    )
    document.addItem(item)

    try await store.save(document)

    let loaded = await store.load()
    let loadedItem = try #require(loaded.items.first)
    #expect(loaded.defaultCategory.id == FavoriteCategory.defaultID)
    #expect(loadedItem.id == target.id)
    #expect(loadedItem.resolvedDisplayTitle == "本地名")
    #expect(loadedItem.coverURL == coverURL)
    #expect(loadedItem.remoteMapping?.yamiboFavoriteID == "remote-321")
    #expect(loadedItem.locations == [.category(category.id)])
    #expect(loadedItem.tagIDs == [tag.id])
}

@Test func remoteFavoriteMappingDoesNotDecideLocalItemExistence() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=324"))
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: url)
    var document = FavoriteLibraryDocument()
    let item = try FavoriteItem(
        target: target,
        title: "本地收藏",
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-324"),
        locations: [.category(document.defaultCategory.id)]
    )
    document.addItem(item)

    document.markRemoteMappingMissing(for: target, date: Date(timeIntervalSince1970: 200))

    let remaining = try #require(document.items.first)
    #expect(remaining.id == target.id)
    #expect(remaining.remoteMapping?.yamiboFavoriteID == "remote-324")
    #expect(remaining.remoteMapping?.isMarkedRemoteMissing == true)
}

@Test func grdbFavoriteLibraryPersistsStructuredTidFirstLibraryAndIgnoresLegacyJSON() async throws {
    let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let database = try YamiboDatabase.openPool(rootDirectory: rootDirectory)
    let suiteName = "GRDBFavoriteLibraryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let legacyData = Data(#"{"items":[{"id":"legacy"}]}"#.utf8)
    defaults.set(legacyData, forKey: "library")
    let store = FavoriteLibraryStore(defaults: defaults, key: "library", databasePool: database)

    let fresh = await store.load()
    #expect(fresh.defaultCategory.id == FavoriteCategory.defaultID)
    #expect(fresh.items.isEmpty)
    #expect(await store.hasStoredDocument() == false)
    let legacyDefaultsAfterLoad = try #require(UserDefaults(suiteName: suiteName))
    #expect(legacyDefaultsAfterLoad.data(forKey: "library") == legacyData)

    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "阅读")
    let collection = document.createCollection(categoryID: category.id, name: "合集", color: .blue)
    let tag = document.createTag(name: "标签", color: .green, date: Date(timeIntervalSince1970: 10))
    let target = FavoriteContentTarget(
        kind: .novelThread,
        threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=321&page=4&mobile=2"))
    )
    let item = try FavoriteItem(
        target: target,
        title: "小说",
        displayName: "本地小说",
        sourceGroup: .forumBoard(id: "fid-1", label: "版块"),
        remoteMapping: FavoriteRemoteMapping(
            yamiboFavoriteID: "remote-321",
            yamiboRemoteOrder: 3,
            lastSeenAt: Date(timeIntervalSince1970: 20)
        ),
        locations: [
            .category(category.id),
            .collection(categoryID: category.id, collectionID: collection.id),
        ],
        tagIDs: [tag.id]
    )
    document.addItem(item)

    try await store.save(document)

    let loaded = await store.load()
    let loadedItem = try #require(loaded.items.first)
    #expect(loadedItem.id == "thread:novel:321")
    #expect(loadedItem.target.threadID == "321")
    #expect(loadedItem.target.canonicalURL?.absoluteString == "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=321")
    #expect(loadedItem.locations == [.category(category.id), .collection(categoryID: category.id, collectionID: collection.id)])
    #expect(loadedItem.tagIDs == [tag.id])
    #expect(loadedItem.remoteMapping?.yamiboFavoriteID == "remote-321")
    #expect(await store.hasStoredDocument())

    let databaseRows = try await database.read { db in
        let itemRow = try Row.fetchOne(
            db,
            sql: "SELECT id, target_kind, thread_id, item_json FROM favorite_items WHERE id = ?",
            arguments: [loadedItem.id]
        )
        let locationRows = try Row.fetchAll(
            db,
            sql: "SELECT category_id, collection_id FROM favorite_locations WHERE item_id = ? ORDER BY manual_order",
            arguments: [loadedItem.id]
        )
        let remoteID = try String.fetchOne(
            db,
            sql: "SELECT yamibo_favorite_id FROM favorite_remote_mappings WHERE item_id = ?",
            arguments: [loadedItem.id]
        )
        let tagID = try String.fetchOne(
            db,
            sql: "SELECT tag_id FROM favorite_item_tags WHERE item_id = ?",
            arguments: [loadedItem.id]
        )
        return (
            itemID: itemRow?["id"] as String?,
            targetKind: itemRow?["target_kind"] as String?,
            threadID: itemRow?["thread_id"] as String?,
            itemJSON: itemRow?["item_json"] as String?,
            locationCategoryIDs: locationRows.map { $0["category_id"] as String },
            locationCollectionIDs: locationRows.map { $0["collection_id"] as String? },
            remoteID: remoteID,
            tagID: tagID
        )
    }

    #expect(databaseRows.itemID == "thread:novel:321")
    #expect(databaseRows.targetKind == FavoriteContentTargetKind.novelThread.rawValue)
    #expect(databaseRows.threadID == "321")
    #expect(databaseRows.itemJSON?.contains("canonicalURL") == false)
    #expect(databaseRows.locationCategoryIDs == [category.id, category.id])
    #expect(databaseRows.locationCollectionIDs == [nil, collection.id])
    #expect(databaseRows.remoteID == "remote-321")
    #expect(databaseRows.tagID == tag.id)
}
