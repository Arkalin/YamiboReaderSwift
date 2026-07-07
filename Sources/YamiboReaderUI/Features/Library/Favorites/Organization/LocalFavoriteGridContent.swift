import SwiftUI
import YamiboReaderCore

/// Fixed-grid and staggered layouts for the favorites screen. Collections
/// and favorite items share one grid — collections as a contiguous block
/// first (Android parity). Column counts adapt to the available width with
/// two columns on iPhone.
struct LocalFavoriteGridContent: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let isStaggered: Bool
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .top)
    ]

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    LocalFavoriteBrowseChrome(organizer: organizer, routes: routes)
                    if organizer.showsCategoryBadges {
                        Text(L10n.string("favorites.items_count", organizer.derived.cards.count))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    if isStaggered {
                        LocalFavoriteStaggeredCards(
                            entries: gridEntries,
                            columnCount: staggeredColumnCount(for: proxy.size.width),
                            organizer: organizer,
                            selection: selection,
                            routes: routes,
                            actions: cardActions
                        )
                        .padding(.horizontal)
                    } else {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                            ForEach(gridEntries) { entry in
                                LocalFavoriteGridEntryCell(
                                    entry: entry,
                                    organizer: organizer,
                                    selection: selection,
                                    routes: routes,
                                    actions: cardActions
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

    /// Collections first, then items — one grid (Android gridEntries parity).
    private var gridEntries: [LocalFavoriteGridEntry] {
        var entries: [LocalFavoriteGridEntry] = []
        if organizer.selectedCollection == nil {
            entries.append(contentsOf: organizer.derived.visibleCollections.map(LocalFavoriteGridEntry.collection))
        }
        entries.append(contentsOf: organizer.derived.cards.map(LocalFavoriteGridEntry.item))
        return entries
    }

    /// Two waterfall columns on iPhone widths, more as the width grows.
    private func staggeredColumnCount(for width: CGFloat) -> Int {
        max(2, Int((width - 32 + 12) / (170 + 12)))
    }

    private var cardActions: LocalFavoriteCardActions {
        .standard(organizer: organizer, selection: selection, routes: routes, onOpen: onOpen)
    }
}

/// One entry of the mixed favorites grid.
enum LocalFavoriteGridEntry: Identifiable {
    case collection(LocalFavoriteCollection)
    case item(FavoriteCardProjection)

    var id: String {
        switch self {
        case let .collection(collection):
            "collection-\(collection.id)"
        case let .item(card):
            "item-\(card.id)"
        }
    }
}

/// Renders one mixed-grid entry as either a collection cell or an item card.
struct LocalFavoriteGridEntryCell: View {
    let entry: LocalFavoriteGridEntry
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let actions: LocalFavoriteCardActions

    var body: some View {
        switch entry {
        case let .collection(collection):
            LocalFavoriteCollectionGridCard(
                collection: collection,
                itemCount: organizer.derived.collectionEntryCounts[collection.id] ?? 0,
                categories: organizer.categories,
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
        case let .item(card):
            LocalFavoriteGridCard(
                card: card,
                selection: selection,
                actions: actions
            )
        }
    }
}

/// Waterfall arrangement distributing mixed entries round-robin per column.
struct LocalFavoriteStaggeredCards: View {
    let entries: [LocalFavoriteGridEntry]
    let columnCount: Int
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let actions: LocalFavoriteCardActions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<max(1, columnCount), id: \.self) { column in
                LazyVStack(spacing: 12) {
                    ForEach(columnEntries(column)) { entry in
                        LocalFavoriteGridEntryCell(
                            entry: entry,
                            organizer: organizer,
                            selection: selection,
                            routes: routes,
                            actions: actions
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func columnEntries(_ column: Int) -> [LocalFavoriteGridEntry] {
        entries.enumerated().compactMap { index, entry in
            index % max(1, columnCount) == column ? entry : nil
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
