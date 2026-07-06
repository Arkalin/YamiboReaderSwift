import SwiftUI
import YamiboReaderCore

/// Row-card layout for the favorites screen.
struct LocalFavoriteListContent: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let showsCover: Bool
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    var body: some View {
        List {
            if let selectedCollection = organizer.selectedCollection {
                LocalFavoriteCollectionScopeSection(
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
            } else {
                Section {
                    LocalFavoriteCategoryTabBar(organizer: organizer, routes: routes)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if organizer.filter.hasActiveFilters {
                    Section {
                        LocalFavoriteActiveFilterStrip(organizer: organizer)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                LocalFavoriteCollectionSection(
                    organizer: organizer,
                    selection: selection,
                    routes: routes
                )
            }
            LocalFavoriteItemSection(
                cards: organizer.derived.cards,
                showsCover: showsCover,
                showsCount: organizer.showsCategoryBadges,
                selection: selection,
                routes: routes,
                onOpen: onOpen
            )
        }
        .listStyle(.insetGrouped)
    }
}
