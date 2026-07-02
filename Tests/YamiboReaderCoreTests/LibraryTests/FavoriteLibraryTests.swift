import Foundation
import Testing
@testable import YamiboReaderCore

@Test func favoriteLibrarySetsDisplayNameAndClearsBlankDisplayName() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=933&mobile=2"))
    let favorite = Favorite(
        title: "原标题",
        url: url,
        remoteFavoriteID: "remote-933",
        parentCollectionID: "collection-a",
        manualOrder: 7,
        tagIDs: ["tag-a"]
    )
    var library = FavoriteLibrary(snapshot: FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        tags: [FavoriteTag(id: "tag-a", name: "标签", color: .blue)]
    ))

    library.setDisplayName("  自定义名称  ", for: favorite.id)

    let renamed = try #require(library.favorites.first)
    #expect(renamed.displayName == "自定义名称")
    #expect(renamed.resolvedDisplayTitle == "自定义名称")
    #expect(renamed.title == favorite.title)
    #expect(renamed.url == favorite.url)
    #expect(renamed.remoteFavoriteID == favorite.remoteFavoriteID)
    #expect(renamed.parentCollectionID == favorite.parentCollectionID)
    #expect(renamed.manualOrder == favorite.manualOrder)
    #expect(renamed.tagIDs == favorite.tagIDs)

    library.setDisplayName("   ", for: favorite.id)

    let cleared = try #require(library.favorites.first)
    #expect(cleared.displayName == nil)
    #expect(cleared.resolvedDisplayTitle == "原标题")
}

@Test func favoriteLibraryRemoteRefreshPreservesLocalItemsWithoutArchive() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=934&mobile=2"))
    let tag = FavoriteTag(id: "tag-valid", name: "有效标签", color: .blue)
    let favorite = Favorite(
        title: "远端消失收藏",
        url: url,
        remoteFavoriteID: "remote-934",
        tagIDs: [tag.id, "missing-tag"]
    )
    var library = FavoriteLibrary(snapshot: FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        tags: [tag]
    ))

    library.reconcileRemoteFavorites([])

    let preserved = try #require(library.favorites.first)
    #expect(preserved.url == url)
    #expect(preserved.remoteFavoriteID == nil)
    #expect(preserved.tagIDs == [tag.id, "missing-tag"])
}

@Test func favoriteLibraryReturningRemoteFavoriteCreatesFreshItemWithoutArchiveMetadata() throws {
    let returningURL = try #require(URL(string: "https://bbs.yamibo.com/thread-935-1-1.html"))
    let tag = FavoriteTag(id: "tag-valid", name: "有效标签", color: .green)
    var library = FavoriteLibrary(snapshot: FavoriteLibrarySnapshot(
        favorites: [],
        collections: [],
        tags: [tag]
    ))

    library.reconcileRemoteFavorites([
        Favorite(title: "远端新标题", url: returningURL, remoteFavoriteID: "remote-new")
    ])

    let restored = try #require(library.favorites.first)
    #expect(restored.title == "远端新标题")
    #expect(restored.url == returningURL)
    #expect(restored.remoteFavoriteID == "remote-new")
    #expect(restored.displayName == nil)
    #expect(restored.parentCollectionID == nil)
    #expect(restored.type == .unknown)
    #expect(restored.mangaPageIndex == 0)
    #expect(restored.lastView == 1)
    #expect(restored.lastChapter == nil)
    #expect(restored.authorID == nil)
    #expect(restored.lastReadAt == nil)
    #expect(restored.tagIDs == [])
}

@Test func favoriteLibraryCanonicalKeysUseReaderCacheIdentityCanonicalizer() throws {
    let favoriteURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mobile=2&page=4&authorid=42&tid=936&mod=viewthread&extra=page%3D1"))
    let expectedKey = ReaderCacheIdentity.canonicalThreadURL(from: favoriteURL).absoluteString
    let snapshot = FavoriteLibrarySnapshot(
        favorites: [Favorite(title: "收藏", url: favoriteURL)],
        collections: []
    )

    #expect(snapshot.favoriteCanonicalURLKeys == [expectedKey])
    #expect(expectedKey == "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=936")
}
