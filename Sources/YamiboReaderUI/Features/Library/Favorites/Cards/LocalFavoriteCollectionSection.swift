import SwiftUI
import YamiboReaderCore

/// List section showing the visible collections of the current category.
struct LocalFavoriteCollectionSection: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes

    var body: some View {
        if !organizer.derived.visibleCollections.isEmpty {
            Section {
                ForEach(organizer.derived.visibleCollections) { collection in
                    LocalFavoriteCollectionRow(
                        collection: collection,
                        itemCount: organizer.derived.collectionEntryCounts[collection.id] ?? 0,
                        categories: organizer.categories,
                        isSelectionMode: selection.isSelectionMode,
                        isSelected: selection.selectedCollectionIDs.contains(collection.id),
                        previewCoverURLs: organizer.derived.cards.previewCoverURLs(for: collection),
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
            } header: {
                Text(L10n.string("favorites.collections"))
            }
        }
    }
}

/// Horizontally scrolling collection cards for the grid layouts.
struct LocalFavoriteCollectionGridSection: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes

    var body: some View {
        if !organizer.derived.visibleCollections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("favorites.collections"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(organizer.derived.visibleCollections) { collection in
                            LocalFavoriteCollectionCard(
                                collection: collection,
                                itemCount: organizer.derived.collectionEntryCounts[collection.id] ?? 0,
                                categories: organizer.categories,
                                isSelectionMode: selection.isSelectionMode,
                                isSelected: selection.selectedCollectionIDs.contains(collection.id),
                                previewCoverURLs: organizer.derived.cards.previewCoverURLs(for: collection),
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
                            .frame(width: 190, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

extension [FavoriteCardProjection] {
    /// Up to four cover URLs of cards contained in `collection`, used as the
    /// collection's preview mosaic.
    func previewCoverURLs(for collection: LocalFavoriteCollection) -> [URL] {
        filter { card in
            card.item.locations.contains(
                .collection(categoryID: collection.categoryID, collectionID: collection.id)
            )
        }
        .compactMap(\.coverURL)
        .prefix(4)
        .map { $0 }
    }
}
