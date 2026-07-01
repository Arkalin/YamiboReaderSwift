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
