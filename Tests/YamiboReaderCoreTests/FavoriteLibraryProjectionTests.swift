import Foundation
import Testing
@testable import YamiboReaderCore

@Test func favoriteLibraryProjectionRootEntriesMixCollectionsAndFavoritesInManualOrder() throws {
    let rootFavorite = Favorite(
        title: "根页收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=860&mobile=2")),
        manualOrder: 1
    )
    let collectionFavorite = Favorite(
        title: "合集内收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=861&mobile=2")),
        parentCollectionID: "collection-1",
        manualOrder: 0
    )
    let collection = FavoriteCollection(id: "collection-1", name: "合集A", manualOrder: 0)
    let snapshot = FavoriteLibrarySnapshot(
        favorites: [rootFavorite, collectionFavorite],
        collections: [collection]
    )

    let entries = FavoriteLibraryProjection.entries(
        in: snapshot,
        query: FavoriteLibraryQuery(scope: .root, showsHidden: false)
    )

    #expect(entries.map(\.id) == ["collection:collection-1", "favorite:\(rootFavorite.id)"])
}

@Test func favoriteLibraryProjectionAppliesTagFilterWithAndSemantics() throws {
    let first = Favorite(
        title: "百合短篇",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=856&mobile=2")),
        type: .novel,
        tagIDs: ["love", "short"]
    )
    let missingOne = Favorite(
        title: "百合长篇",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=857&mobile=2")),
        type: .novel,
        tagIDs: ["love"]
    )
    let hiddenMatch = Favorite(
        title: "隐藏短篇",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=858&mobile=2")),
        isHidden: true,
        type: .novel,
        tagIDs: ["love", "short"]
    )
    let mangaMatch = Favorite(
        title: "漫画短篇",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=859&mobile=2")),
        type: .manga,
        tagIDs: ["love", "short"]
    )
    let snapshot = FavoriteLibrarySnapshot(favorites: [first, missingOne, hiddenMatch, mangaMatch], collections: [])

    let hiddenOff = FavoriteLibraryProjection.favorites(
        in: snapshot,
        query: FavoriteLibraryQuery(
            showsHidden: false,
            filter: .novel,
            searchText: "短篇",
            selectedTagIDs: ["love", "short"]
        )
    )
    let hiddenOn = FavoriteLibraryProjection.favorites(
        in: snapshot,
        query: FavoriteLibraryQuery(
            showsHidden: true,
            filter: .novel,
            searchText: "短篇",
            selectedTagIDs: ["love", "short"]
        )
    )

    #expect(hiddenOff.map(\.id) == [first.id])
    #expect(hiddenOn.map(\.id) == [first.id, hiddenMatch.id])
}

@Test func favoriteLibraryProjectionRootSearchMatchesCollectionFavoriteTitlesAndTaggedCollectionNameRequiresTaggedChild() throws {
    let taggedCollection = FavoriteCollection(id: "collection-tagged", name: "标签合集", manualOrder: 0)
    let untaggedCollection = FavoriteCollection(id: "collection-untagged", name: "标签合集空", manualOrder: 1)
    let titleMatchedCollection = FavoriteCollection(id: "collection-title", name: "普通合集名", manualOrder: 2)
    let taggedFavorite = Favorite(
        title: "普通收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=876&mobile=2")),
        parentCollectionID: taggedCollection.id,
        tagIDs: ["love"]
    )
    let untaggedFavorite = Favorite(
        title: "普通收藏二",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=877&mobile=2")),
        parentCollectionID: untaggedCollection.id,
        tagIDs: ["short"]
    )
    let titleMatchedFavorite = Favorite(
        title: "会被搜索命中的收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=865&mobile=2")),
        parentCollectionID: titleMatchedCollection.id
    )
    let snapshot = FavoriteLibrarySnapshot(
        favorites: [taggedFavorite, untaggedFavorite, titleMatchedFavorite],
        collections: [taggedCollection, untaggedCollection, titleMatchedCollection]
    )

    let titleSearchEntries = FavoriteLibraryProjection.entries(
        in: snapshot,
        query: FavoriteLibraryQuery(scope: .root, showsHidden: false, searchText: "搜索命中")
    )
    let taggedEntries = FavoriteLibraryProjection.entries(
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: .root,
            showsHidden: false,
            searchText: "标签合集",
            selectedTagIDs: ["love"]
        )
    )
    let summary = FavoriteLibraryProjection.collectionSummary(
        for: taggedCollection,
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: .root,
            showsHidden: false,
            searchText: "标签合集",
            selectedTagIDs: ["love"]
        )
    )

    #expect(titleSearchEntries.map(\.id) == ["collection:collection-title"])
    #expect(taggedEntries.map(\.id) == ["collection:collection-tagged"])
    #expect(summary == FavoriteLibraryCollectionSummary(itemCount: 1, hiddenCount: 0))
}

@Test func favoriteLibraryProjectionRecentReadSortUsesCollectionMatchingChildren() throws {
    let oldReadAt = Date(timeIntervalSince1970: 1_700_000_000)
    let newReadAt = Date(timeIntervalSince1970: 1_700_000_500)
    let rootFavorite = Favorite(
        title: "根页收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=873&mobile=2")),
        manualOrder: 0,
        lastReadAt: oldReadAt
    )
    let collectionFavorite = Favorite(
        title: "合集最近阅读",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=874&mobile=2")),
        parentCollectionID: "collection-8",
        manualOrder: 0,
        lastReadAt: newReadAt
    )
    let unreadCollectionFavorite = Favorite(
        title: "未阅读合集收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=875&mobile=2")),
        parentCollectionID: "collection-9"
    )
    let recentCollection = FavoriteCollection(id: "collection-8", name: "最近合集", manualOrder: 1)
    let unreadCollection = FavoriteCollection(id: "collection-9", name: "未读合集", manualOrder: 2)
    let snapshot = FavoriteLibrarySnapshot(
        favorites: [rootFavorite, collectionFavorite, unreadCollectionFavorite],
        collections: [recentCollection, unreadCollection]
    )

    let entries = FavoriteLibraryProjection.entries(
        in: snapshot,
        query: FavoriteLibraryQuery(scope: .root, showsHidden: false, sortOrder: .recentRead)
    )

    #expect(entries.map(\.id) == ["collection:collection-8", "favorite:\(rootFavorite.id)", "collection:collection-9"])
}

@Test func favoriteLibraryProjectionSortsTagsAndBuildsChipsWithOverflowAndPriority() throws {
    let baseDate = Date(timeIntervalSince1970: 100)
    let old = FavoriteTag(id: "old", name: "Zeta", color: .gray, manualOrder: 0, updatedAt: baseDate)
    let sameCountEarlier = FavoriteTag(id: "same-a", name: "Beta", color: .blue, manualOrder: 1, updatedAt: baseDate.addingTimeInterval(10))
    let sameCountLater = FavoriteTag(id: "same-b", name: "Alpha", color: .red, manualOrder: 2, updatedAt: baseDate.addingTimeInterval(20))
    let popular = FavoriteTag(id: "popular", name: "Gamma", color: .green, manualOrder: 3, updatedAt: baseDate.addingTimeInterval(30))
    let tags = [popular, sameCountLater, sameCountEarlier, old]
    let favorites = [
        Favorite(title: "A", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=850&mobile=2")), tagIDs: [popular.id]),
        Favorite(title: "B", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=851&mobile=2")), isHidden: true, tagIDs: [popular.id]),
        Favorite(title: "C", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=852&mobile=2")), tagIDs: [sameCountLater.id]),
        Favorite(title: "D", url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=853&mobile=2")), tagIDs: [sameCountEarlier.id])
    ]
    let chipFavorite = Favorite(
        title: "带标签收藏",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=854&mobile=2")),
        tagIDs: ["old", "popular", "same-b", "same-a"]
    )

    #expect(FavoriteLibraryProjection.sortedTags(tags, favorites: favorites, sortOrder: .manual).map(\.id) == ["old", "same-a", "same-b", "popular"])
    #expect(FavoriteLibraryProjection.sortedTags(tags, favorites: favorites, sortOrder: .name).map(\.id) == ["same-b", "same-a", "popular", "old"])
    #expect(FavoriteLibraryProjection.sortedTags(tags, favorites: favorites, sortOrder: .associationCountDescending).map(\.id) == ["popular", "same-a", "same-b", "old"])

    let summary = FavoriteLibraryProjection.tagChipSummary(for: chipFavorite, tags: tags, searchText: "alp")
    #expect(summary.chips.map(\.id) == ["same-b", "old", "same-a"])
    #expect(summary.overflowCount == 1)
}

@Test func favoriteLibraryProjectionReportsReorderSelectionAndBatchTagStates() throws {
    let first = Favorite(
        title: "A",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=840&mobile=2")),
        tagIDs: ["one", "two"]
    )
    let matching = Favorite(
        title: "B",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=841&mobile=2")),
        tagIDs: ["one", "two"]
    )
    let divergent = Favorite(
        title: "C",
        url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=842&mobile=2")),
        tagIDs: ["one"]
    )

    #expect(FavoriteLibraryProjection.canReorderEntries(sortOrder: .manual, searchText: "", selectedTagIDs: []))
    #expect(!FavoriteLibraryProjection.canReorderEntries(sortOrder: .manual, searchText: "", selectedTagIDs: ["love"]))
    #expect(!FavoriteLibraryProjection.canReorderEntries(sortOrder: .manual, searchText: "百合", selectedTagIDs: []))
    #expect(FavoriteLibraryProjection.selectionActionState(scope: .root, selectedFavoriteCount: 1, selectedCollectionCount: 1) == FavoriteLibrarySelectionActionState(canTag: false, canCreateCollection: false, canMove: false, canDelete: true))
    #expect(FavoriteLibraryProjection.selectionActionState(scope: .collection(FavoriteCollection(id: "collection-3", name: "合集C")), selectedFavoriteCount: 1, selectedCollectionCount: 0) == FavoriteLibrarySelectionActionState(canTag: true, canCreateCollection: false, canMove: true, canDelete: true))
    #expect(FavoriteLibraryProjection.batchTagSelectionState(favorites: [first, matching], selectedFavoriteIDs: [first.id, matching.id]) == FavoriteLibraryBatchTagSelectionState(initialTagIDs: ["one", "two"], showsOverwriteWarning: false))
    #expect(FavoriteLibraryProjection.batchTagSelectionState(favorites: [first, divergent], selectedFavoriteIDs: [first.id, divergent.id]) == FavoriteLibraryBatchTagSelectionState(initialTagIDs: [], showsOverwriteWarning: true))
}
