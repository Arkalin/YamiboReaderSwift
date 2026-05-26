import Foundation
import Testing
@testable import YamiboReaderCore

@Test func favoriteLibraryArchivesRemovedRemoteMetadataWithOnlyValidTags() throws {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=934&mobile=2"))
    let tag = FavoriteTag(id: "tag-valid", name: "有效标签", color: .blue)
    let favorite = Favorite(
        title: "远端消失收藏",
        url: url,
        remoteFavoriteID: "remote-934",
        isHidden: true,
        tagIDs: [tag.id, "missing-tag"]
    )
    var library = FavoriteLibrary(snapshot: FavoriteLibrarySnapshot(
        favorites: [favorite],
        collections: [],
        tags: [tag]
    ))

    library.reconcileRemoteFavorites([])

    #expect(library.favorites.isEmpty)
    let archive = try #require(library.archivedMetadata.first)
    #expect(archive.canonicalThreadURL == ReaderCacheIdentity.canonicalThreadURL(from: url))
    #expect(archive.isHidden)
    #expect(archive.tagIDs == [tag.id])
}

@Test func favoriteLibraryRestoresArchivedMetadataByCanonicalURLUsingRemoteFavoriteFields() throws {
    let archivedURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=935&mobile=2&page=4"))
    let returningURL = try #require(URL(string: "https://bbs.yamibo.com/thread-935-1-1.html"))
    let tag = FavoriteTag(id: "tag-valid", name: "有效标签", color: .green)
    let archive = FavoriteMetadataArchiveEntry(
        canonicalThreadURL: ReaderCacheIdentity.canonicalThreadURL(from: archivedURL),
        displayName: "恢复名",
        lastPage: 6,
        lastView: 2,
        lastChapter: "第二章",
        authorID: "author-935",
        novelResumePoint: nil,
        isHidden: true,
        type: .novel,
        lastMangaURL: nil,
        parentCollectionID: "missing-collection",
        manualOrder: 9,
        lastReadAt: Date(timeIntervalSince1970: 1_800_000_001),
        tagIDs: [tag.id, "missing-tag"]
    )
    var library = FavoriteLibrary(snapshot: FavoriteLibrarySnapshot(
        favorites: [],
        collections: [],
        tags: [tag],
        archivedMetadata: [archive]
    ))

    library.reconcileRemoteFavorites([
        Favorite(title: "远端新标题", url: returningURL, remoteFavoriteID: "remote-new")
    ])

    let restored = try #require(library.favorites.first)
    #expect(restored.title == "远端新标题")
    #expect(restored.url == returningURL)
    #expect(restored.remoteFavoriteID == "remote-new")
    #expect(restored.displayName == "恢复名")
    #expect(restored.isHidden)
    #expect(restored.parentCollectionID == nil)
    #expect(restored.type == .novel)
    #expect(restored.lastPage == 6)
    #expect(restored.lastView == 2)
    #expect(restored.lastChapter == "第二章")
    #expect(restored.authorID == "author-935")
    #expect(restored.lastReadAt == Date(timeIntervalSince1970: 1_800_000_001))
    #expect(restored.tagIDs == [tag.id])
    #expect(library.archivedMetadata.isEmpty)
}
