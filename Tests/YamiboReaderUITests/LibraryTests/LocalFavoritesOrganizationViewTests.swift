import SwiftUI
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
@Test func localFavoritesOrganizationViewIsConstructibleWithNativeOrganizationData() throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "分类")
    let collection = document.createCollection(categoryID: category.id, name: "合集", color: .blue)
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=801")))
    let item = try FavoriteItem(
        target: target,
        title: "主题",
        sourceGroup: .forumBoard(id: "fid", label: "版块"),
        locations: [.category(category.id), .collection(categoryID: category.id, collectionID: collection.id)]
    )
    document.addItem(item)
    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(categoryID: category.id)
    )

    let view = LocalFavoritesOrganizationView(
        categories: document.categories,
        collections: document.collections,
        cards: cards,
        selectedCategoryID: .constant(category.id)
    )

    _ = view
    #expect(cards.map(\.id) == [item.id])
}

@MainActor
@Test func localFavoritesOrganizationViewRendersCoverLayoutsAndOrganizationControls() throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "分类")
    let collection = document.createCollection(categoryID: category.id, name: "合集", color: .orange)
    let tag = document.createTag(name: "待读", color: .pink)
    let firstTarget = FavoriteContentTarget(kind: .normalThread, threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=831")))
    let secondTarget = FavoriteContentTarget(kind: .normalThread, threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=832")))
    document.addItem(try FavoriteItem(
        target: firstTarget,
        title: "带封面主题一",
        sourceGroup: .forumBoard(id: "fid", label: "版块"),
        coverURL: URL(string: "https://img.example.test/cover-a.jpg"),
        locations: [.category(category.id), .collection(categoryID: category.id, collectionID: collection.id)],
        tagIDs: [tag.id]
    ))
    document.addItem(try FavoriteItem(
        target: secondTarget,
        title: "带封面主题二",
        sourceGroup: .forumBoard(id: "fid", label: "版块"),
        coverURL: URL(string: "https://img.example.test/cover-b.jpg"),
        locations: [.category(category.id)],
        tagIDs: [tag.id]
    ))
    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(categoryID: category.id, selectedTagIDs: [tag.id])
    )
    let selectionState = LocalFavoriteSelectionState(
        isActive: true,
        selectedFavoriteIDs: [firstTarget.id],
        selectedCollectionIDs: [collection.id],
        selectedFavoriteCount: 1,
        selectedCollectionCount: 1,
        selectedEntryCount: 2,
        canCreateCollection: true,
        editableCollection: collection
    )

    for layoutMode in FavoriteLibraryLayoutMode.allCases {
        let view = LocalFavoritesOrganizationView(
            categories: document.categories,
            collections: document.collections,
            tags: document.tags,
            cards: cards,
            categoryEntryCounts: [category.id: cards.count],
            collectionEntryCounts: [collection.id: 1],
            selectionState: selectionState,
            selectedCategoryID: .constant(category.id),
            sourceGroupFilter: .constant(.group(.forumBoard(id: "fid", label: "版块"))),
            selectedTagIDs: .constant([tag.id]),
            layoutMode: .constant(layoutMode)
        )
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 720))

        #expect(renderer.cgImage != nil)
    }
    #expect(cards.compactMap(\.coverURL).count == 2)
}

@MainActor
@Test func localFavoritesOrganizationViewRendersAllLayoutsWithoutCollections() throws {
    var document = FavoriteLibraryDocument()
    let category = document.createCategory(name: "分类")
    let target = FavoriteContentTarget(kind: .normalThread, threadURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=833")))
    document.addItem(try FavoriteItem(
        target: target,
        title: "无合集主题",
        sourceGroup: .forumBoard(id: "fid", label: "版块"),
        locations: [.category(category.id)]
    ))
    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(categoryID: category.id)
    )

    for layoutMode in FavoriteLibraryLayoutMode.allCases {
        let view = LocalFavoritesOrganizationView(
            categories: document.categories,
            collections: document.collections,
            cards: cards,
            categoryEntryCounts: [category.id: cards.count],
            selectedCategoryID: .constant(category.id),
            layoutMode: .constant(layoutMode)
        )
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 720))

        #expect(renderer.cgImage != nil)
    }
    #expect(document.collections.isEmpty)
}
