import Foundation
import YamiboReaderCore

/// Filter and sort inputs for the favorites library. Any change to this value
/// triggers one full re-derivation of `LocalFavoriteDerivedState`.
struct LocalFavoriteFilterState: Equatable {
    var selectedSourceFilters: Set<LocalFavoriteSourceFilter> = []
    var selectedTagIDs: Set<String> = []
    var sortOrder: LocalFavoriteLibrarySortOrder = .organization
    var sortDescending = false
    var searchText = ""

    /// Whether a source-group or tag filter is narrowing the library view.
    var hasActiveFilters: Bool {
        !selectedSourceFilters.isEmpty || !selectedTagIDs.isEmpty
    }
}

/// Persisted display preferences for the favorites screen.
struct FavoriteLibraryDisplayState: Equatable {
    var layoutMode: FavoriteLibraryLayoutMode = .rowCard
    var showsCategoryCounts = true
}

/// One slot of a collection's 4-tile preview mosaic: a member's own cover
/// (when it has one) or its own title for a text-fallback tile — never
/// silently dropped just because it has no image.
struct LocalFavoriteCollectionPreviewTile: Equatable {
    let coverURL: URL?
    let title: String
}

/// Everything the favorites UI renders that is computed from the library
/// document plus filter state. Produced only by `LocalFavoriteLibraryDerivation`.
struct LocalFavoriteDerivedState: Equatable {
    var cards: [FavoriteCardProjection] = []
    var visibleCollections: [LocalFavoriteCollection] = []
    /// Collections and cards merged into the order the list/grid renders —
    /// collections pinned first only in manual sort order, interleaved with
    /// cards under every other sort order (see
    /// `LocalFavoriteLibraryProjection.mixedEntries`).
    var mixedEntries: [FavoriteMixedEntry] = []
    var categoryEntryCounts: [String: Int] = [:]
    var collectionEntryCounts: [String: Int] = [:]
    var sourceFilterEntryCounts: [LocalFavoriteSourceFilter: Int] = [:]
    /// Up to four preview tiles per visible collection for the preview
    /// mosaic, resolved from the collection's own members (not the filtered
    /// cards).
    var collectionPreviewTiles: [String: [LocalFavoriteCollectionPreviewTile]] = [:]
}

/// Pure computation: (document, navigation, filter, progress, covers) -> derived state.
/// This is the single data flow for card rebuilding; there are no incremental
/// update paths.
enum LocalFavoriteLibraryDerivation {
    struct Inputs {
        var document: FavoriteLibraryDocument
        var selectedCategoryID: String
        var selectedCollectionID: String?
        var filter: LocalFavoriteFilterState
        var readingProgress: [ReadingProgressRecord]
        var contentCoverURLsByTargetID: [String: URL]
        var textCoverForcedTargetIDs: Set<String>
    }

    static func derive(_ inputs: Inputs) -> LocalFavoriteDerivedState {
        let cards = resolvedCards(
            in: inputs.document,
            query: LocalFavoriteLibraryQuery(
                categoryID: inputs.selectedCategoryID,
                collectionID: inputs.selectedCollectionID,
                selectedSourceFilters: inputs.filter.selectedSourceFilters,
                selectedTagIDs: inputs.filter.selectedTagIDs,
                sortOrder: inputs.filter.sortOrder,
                sortsDescending: inputs.filter.sortDescending,
                searchText: inputs.filter.searchText
            ),
            inputs: inputs
        )
        let aggregates = collectionAggregates(inputs)
        let collectionCounts = aggregates.mapValues(\.entryCount)
        let collections = visibleCollections(
            in: inputs.document,
            categoryID: inputs.selectedCategoryID,
            filter: inputs.filter,
            collectionEntryCounts: collectionCounts
        )
        return LocalFavoriteDerivedState(
            cards: cards,
            visibleCollections: collections,
            mixedEntries: LocalFavoriteLibraryProjection.mixedEntries(
                cards: cards,
                // No nested collections in the domain model: a collection's
                // own detail page never shows sibling collections.
                collections: inputs.selectedCollectionID == nil ? collections : [],
                collectionSummaries: aggregates.mapValues(\.sortSummary),
                sortOrder: inputs.filter.sortOrder,
                descending: inputs.filter.sortDescending
            ),
            categoryEntryCounts: categoryEntryCounts(inputs, collectionEntryCounts: collectionCounts),
            collectionEntryCounts: collectionCounts,
            sourceFilterEntryCounts: sourceFilterEntryCounts(inputs),
            collectionPreviewTiles: collectionPreviewTiles(inputs)
        )
    }

    // MARK: - Cards

    private static func resolvedCards(
        in document: FavoriteLibraryDocument,
        query: LocalFavoriteLibraryQuery,
        inputs: Inputs
    ) -> [FavoriteCardProjection] {
        LocalFavoriteLibraryProjection.cards(
            in: document,
            query: query,
            readingProgress: inputs.readingProgress
        )
        .map { card in
            var card = card
            card.coverURL = inputs.contentCoverURLsByTargetID[card.item.target.id]
            card.textCoverForced = inputs.textCoverForcedTargetIDs.contains(card.item.target.id)
            return card
        }
    }

    // MARK: - Counts

    private static func categoryEntryCounts(
        _ inputs: Inputs,
        collectionEntryCounts: [String: Int]
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: inputs.document.categories.map { category in
            let cards = resolvedCards(
                in: inputs.document,
                query: LocalFavoriteLibraryQuery(
                    categoryID: category.id,
                    selectedSourceFilters: inputs.filter.selectedSourceFilters,
                    selectedTagIDs: inputs.filter.selectedTagIDs,
                    sortOrder: .organization,
                    searchText: inputs.filter.searchText
                ),
                inputs: inputs
            )
            let collections = visibleCollections(
                in: inputs.document,
                categoryID: category.id,
                filter: inputs.filter,
                collectionEntryCounts: collectionEntryCounts
            )
            return (category.id, cards.count + collections.count)
        })
    }

    private struct CollectionAggregate {
        var entryCount: Int
        var sortSummary: FavoriteCollectionSortSummary
    }

    private static func collectionAggregates(_ inputs: Inputs) -> [String: CollectionAggregate] {
        Dictionary(uniqueKeysWithValues: inputs.document.collections.map { collection in
            let cards = resolvedCards(
                in: inputs.document,
                query: LocalFavoriteLibraryQuery(
                    categoryID: collection.categoryID,
                    collectionID: collection.id,
                    selectedSourceFilters: inputs.filter.selectedSourceFilters,
                    selectedTagIDs: inputs.filter.selectedTagIDs,
                    sortOrder: .organization,
                    searchText: inputs.filter.searchText
                ),
                inputs: inputs
            )
            return (collection.id, CollectionAggregate(entryCount: cards.count, sortSummary: .summarizing(cards)))
        })
    }

    private static func collectionPreviewTiles(_ inputs: Inputs) -> [String: [LocalFavoriteCollectionPreviewTile]] {
        Dictionary(uniqueKeysWithValues: inputs.document.collections.map { collection in
            let location = FavoriteLocation.collection(categoryID: collection.categoryID, collectionID: collection.id)
            // Every member gets a tile — image-backed when a cover resolves,
            // otherwise the member's own title for a text-fallback tile.
            // Members without a cover must not be silently dropped here, or
            // the mosaic shows fewer/blank tiles instead of that member's
            // text cover.
            let tiles = inputs.document.items
                .filter { $0.locations.contains(location) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(4)
                .map { item in
                    LocalFavoriteCollectionPreviewTile(
                        coverURL: inputs.contentCoverURLsByTargetID[item.target.id],
                        title: item.resolvedDisplayTitle
                    )
                }
            return (collection.id, Array(tiles))
        })
    }

    private static func sourceFilterEntryCounts(_ inputs: Inputs) -> [LocalFavoriteSourceFilter: Int] {
        let allCards = resolvedCards(
            in: inputs.document,
            query: LocalFavoriteLibraryQuery(
                categoryID: inputs.selectedCategoryID,
                collectionID: inputs.selectedCollectionID,
                selectedSourceFilters: [],
                selectedTagIDs: inputs.filter.selectedTagIDs,
                sortOrder: .organization,
                searchText: inputs.filter.searchText
            ),
            inputs: inputs
        )
        return Dictionary(grouping: allCards) { card in
            LocalFavoriteSourceFilter.key(for: card.item)
        }
        .mapValues(\.count)
    }

    // MARK: - Collections

    private static func visibleCollections(
        in document: FavoriteLibraryDocument,
        categoryID: String,
        filter: LocalFavoriteFilterState,
        collectionEntryCounts: [String: Int]
    ) -> [LocalFavoriteCollection] {
        let trimmedSearch = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonSearchFiltersAreActive = !filter.selectedSourceFilters.isEmpty || !filter.selectedTagIDs.isEmpty
        let filtersAreActive = nonSearchFiltersAreActive || !trimmedSearch.isEmpty
        return document.collections
            .filter { collection in
                guard collection.categoryID == categoryID else { return false }
                guard filtersAreActive else { return true }
                // Filter match judged in the collection's own scope: members
                // usually carry only the collection location, so the
                // category-scope card list cannot see them.
                let hasMatchingMember = (collectionEntryCounts[collection.id] ?? 0) > 0
                if !trimmedSearch.isEmpty,
                   collection.name.localizedCaseInsensitiveContains(trimmedSearch) {
                    return !nonSearchFiltersAreActive || hasMatchingMember
                }
                return hasMatchingMember
            }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }
}
