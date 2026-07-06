import SwiftUI
import YamiboReaderCore

/// Fixed-grid and staggered layouts for the favorites screen.
struct LocalFavoriteGridContent: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let isStaggered: Bool
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 158), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let selectedCollection = organizer.selectedCollection {
                    LocalFavoriteCollectionScopeHeader(
                        collection: selectedCollection,
                        itemCount: organizer.derived.collectionEntryCounts[selectedCollection.id] ?? organizer.derived.cards.count,
                        categories: organizer.categories,
                        onBack: { organizer.closeCollection() },
                        onEdit: { routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(collection: selectedCollection)) },
                        onDissolve: { routes.dialog = .dissolveCollection(selectedCollection) },
                        onMoveToCategory: { categoryID in
                            await organizer.moveCollection(id: selectedCollection.id, toCategoryID: categoryID)
                        }
                    )
                    .padding(.horizontal)
                } else {
                    LocalFavoriteCategoryTabBar(organizer: organizer, routes: routes)
                    LocalFavoriteActiveFilterStrip(organizer: organizer)
                        .padding(.horizontal)
                    LocalFavoriteCollectionGridSection(
                        organizer: organizer,
                        selection: selection,
                        routes: routes
                    )
                }
                if organizer.showsCategoryBadges {
                    Text(L10n.string("favorites.items_count", organizer.derived.cards.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                if isStaggered {
                    LocalFavoriteStaggeredCards(
                        cards: organizer.derived.cards,
                        selection: selection,
                        routes: routes,
                        onOpen: onOpen
                    )
                    .padding(.horizontal)
                } else {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                        ForEach(organizer.derived.cards) { card in
                            LocalFavoriteGridCard(
                                card: card,
                                fixedHeight: 236,
                                selection: selection,
                                routes: routes,
                                onOpen: onOpen
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

extension FavoriteLibraryOrganizer {
    /// Category count badges stay visible while a search is active even when
    /// the user has hidden them, so result counts remain visible.
    var showsCategoryBadges: Bool {
        display.showsCategoryCounts || !filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
