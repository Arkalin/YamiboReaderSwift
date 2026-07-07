import SwiftUI
import YamiboReaderCore

/// Row-card layout for the favorites screen. Collections and favorite items
/// share one list section — collections as a contiguous block first
/// (Android parity).
struct LocalFavoriteListContent: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let showsCover: Bool
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    var body: some View {
        List {
            Section {
                LocalFavoriteBrowseChrome(organizer: organizer, routes: routes)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    // The chrome is one plain content block, not a list row:
                    // suppress the row/section separator lines List draws
                    // around it by default (grid mode has no such line).
                    .listRowSeparator(.hidden)
                    .listSectionSeparator(.hidden)
            }
            Section {
                if organizer.selectedCollection == nil {
                    ForEach(organizer.derived.visibleCollections) { collection in
                        LocalFavoriteCollectionRow(
                            collection: collection,
                            itemCount: organizer.derived.collectionEntryCounts[collection.id] ?? 0,
                            categories: organizer.categories,
                            showsCover: showsCover,
                            isSelectionMode: selection.isSelectionMode,
                            isSelected: selection.selectedCollectionIDs.contains(collection.id),
                            previewCoverURLs: organizer.derived.collectionPreviewCoverURLs[collection.id] ?? [],
                            onOpen: { organizer.openCollection(id: collection.id) },
                            onToggleSelection: { organizer.toggleCollectionSelection(id: collection.id) },
                            onEdit: { routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(collection: collection)) },
                            onDissolve: { routes.dialog = .dissolveCollection(collection) },
                            onMove: { direction in
                                await organizer.moveCollection(id: collection.id, direction: direction)
                            },
                            onMoveToCategory: { categoryID in
                                await organizer.moveCollection(id: collection.id, toCategoryID: categoryID)
                            }
                        )
                    }
                }
                ForEach(organizer.derived.cards) { card in
                    LocalFavoriteItemRow(
                        card: card,
                        showsCover: showsCover,
                        isSelectionMode: selection.isSelectionMode,
                        isSelected: selection.selectedFavoriteIDs.contains(card.id),
                        onToggleSelection: { selection.toggleFavoriteSelection(id: card.id) },
                        actions: .standard(organizer: organizer, selection: selection, routes: routes, onOpen: onOpen)
                    )
                }
            }
        }
        // Grid mode is a plain `ScrollView` whose LazyVStack has an explicit
        // 12pt top inset (`.padding(.vertical, 12)`). List's own implicit top
        // inset above the first section doesn't match that value, so pin it
        // explicitly instead of relying on List's default.
        .listStyle(.plain)
        .listSectionSpacing(12)
        .contentMargins(.top, 12, for: .scrollContent)
    }
}
