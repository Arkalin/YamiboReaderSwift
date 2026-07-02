import Foundation
import Testing
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
    let store = LocalFirstFavoriteLibraryStore(defaults: suite, key: "library")
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
