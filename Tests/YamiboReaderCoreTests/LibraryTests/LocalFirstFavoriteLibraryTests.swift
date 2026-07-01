import Foundation
import Testing
@testable import YamiboReaderCore

@Test func localFirstFavoriteLibraryInitializesWithDefaultFavoriteCategory() {
    let document = FavoriteLibraryDocument()

    #expect(document.categories.count == 1)
    #expect(document.defaultCategory.isDefault)
    #expect(document.defaultCategory.id == FavoriteCategory.defaultID)
    #expect(document.items.isEmpty)
}

@Test func favoriteItemIdentityComesFromStableContentTarget() throws {
    let firstURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=319&page=4&mobile=2"))
    let secondURL = try #require(URL(string: "https://bbs.yamibo.com/thread-319-1-1.html"))
    let normal = FavoriteContentTarget(kind: .normalThread, threadURL: firstURL)
    let sameNormal = FavoriteContentTarget(kind: .normalThread, threadURL: secondURL)
    let novel = FavoriteContentTarget(kind: .novelThread, threadURL: secondURL)
    let manga = FavoriteContentTarget(mangaCleanBookName: "Clean Manga")

    #expect(normal.id == sameNormal.id)
    #expect(normal.id != novel.id)
    #expect(manga.id == "manga-title:Clean Manga")
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

@Test func localFirstFavoriteLibraryRebuildsFromLegacyWithoutHiddenArchiveSemantics() async throws {
    let suite = try #require(UserDefaults(suiteName: "LocalFirstFavoriteLibraryTests.\(UUID().uuidString)"))
    let store = LocalFirstFavoriteLibraryStore(defaults: suite, key: "library")
    let favoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=322"))
    let archivedURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=323"))
    let legacyTag = FavoriteTag(id: "tag", name: "旧标签", color: .green)
    let snapshot = FavoriteLibrarySnapshot(
        favorites: [
            Favorite(
                title: "旧收藏",
                displayName: "旧本地名",
                url: favoriteURL,
                remoteFavoriteID: "remote-322",
                isHidden: true,
                type: .novel,
                tagIDs: [legacyTag.id]
            )
        ],
        collections: [FavoriteCollection(id: "legacy-collection", name: "旧合集", isHidden: true)],
        tags: [legacyTag],
        archivedMetadata: [
            FavoriteMetadataArchiveEntry(
                canonicalThreadURL: archivedURL,
                displayName: "归档名",
                mangaPageIndex: 2,
                lastView: 3,
                lastChapter: "归档章",
                authorID: nil,
                novelResumePoint: nil,
                isHidden: true,
                type: .novel,
                lastMangaURL: nil,
                parentCollectionID: "legacy-collection",
                manualOrder: 0,
                lastReadAt: nil,
                tagIDs: [legacyTag.id]
            )
        ]
    )

    let document = try await store.rebuildFromLegacy(snapshot, date: Date(timeIntervalSince1970: 100))

    #expect(document.categories.map(\.id) == [FavoriteCategory.defaultID])
    #expect(document.collections.isEmpty)
    #expect(document.items.count == 1)
    let item = try #require(document.items.first)
    #expect(item.target.kind == .novelThread)
    #expect(item.locations == [.category(FavoriteCategory.defaultID)])
    #expect(item.remoteMapping?.yamiboFavoriteID == "remote-322")
    #expect(item.tagIDs == [legacyTag.id])
    #expect(document.tags == [legacyTag])
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
