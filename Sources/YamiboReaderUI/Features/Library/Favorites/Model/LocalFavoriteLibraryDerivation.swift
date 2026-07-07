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

/// Everything the favorites UI renders that is computed from the library
/// document plus filter state. Produced only by `LocalFavoriteLibraryDerivation`.
struct LocalFavoriteDerivedState: Equatable {
    var cards: [FavoriteCardProjection] = []
    var visibleCollections: [LocalFavoriteCollection] = []
    var categoryEntryCounts: [String: Int] = [:]
    var collectionEntryCounts: [String: Int] = [:]
    var sourceFilterEntryCounts: [LocalFavoriteSourceFilter: Int] = [:]
    /// Up to four cover URLs per visible collection for the preview mosaic,
    /// resolved from the collection's own members (not the filtered cards).
    var collectionPreviewCoverURLs: [String: [URL]] = [:]
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
        let collectionCounts = collectionEntryCounts(inputs)
        return LocalFavoriteDerivedState(
            cards: cards,
            visibleCollections: visibleCollections(
                in: inputs.document,
                categoryID: inputs.selectedCategoryID,
                filter: inputs.filter,
                collectionEntryCounts: collectionCounts
            ),
            categoryEntryCounts: categoryEntryCounts(inputs, collectionEntryCounts: collectionCounts),
            collectionEntryCounts: collectionCounts,
            sourceFilterEntryCounts: sourceFilterEntryCounts(inputs),
            collectionPreviewCoverURLs: collectionPreviewCoverURLs(inputs)
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

    private static func collectionEntryCounts(_ inputs: Inputs) -> [String: Int] {
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
            return (collection.id, cards.count)
        })
    }

    private static func collectionPreviewCoverURLs(_ inputs: Inputs) -> [String: [URL]] {
        Dictionary(uniqueKeysWithValues: inputs.document.collections.map { collection in
            let location = FavoriteLocation.collection(categoryID: collection.categoryID, collectionID: collection.id)
            let urls = inputs.document.items
                .filter { $0.locations.contains(location) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .compactMap { inputs.contentCoverURLsByTargetID[$0.target.id] }
                .prefix(4)
            return (collection.id, Array(urls))
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
