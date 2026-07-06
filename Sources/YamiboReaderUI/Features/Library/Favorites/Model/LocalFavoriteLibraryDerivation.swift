import Foundation
import YamiboReaderCore

/// Filter and sort inputs for the favorites library. Any change to this value
/// triggers one full re-derivation of `LocalFavoriteDerivedState`.
struct LocalFavoriteFilterState: Equatable {
    var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter = .all
    var selectedTagIDs: Set<String> = []
    var sortOrder: LocalFavoriteLibrarySortOrder = .organization
    var sortDescending = false
    var searchText = ""

    /// Whether a source-group or tag filter is narrowing the library view.
    var hasActiveFilters: Bool {
        if case .group = sourceGroupFilter { return true }
        return !selectedTagIDs.isEmpty
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
    var sourceGroupEntryCounts: [FavoriteSourceGroup: Int] = [:]
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
                sourceGroupFilter: inputs.filter.sourceGroupFilter,
                selectedTagIDs: inputs.filter.selectedTagIDs,
                sortOrder: inputs.filter.sortOrder,
                sortsDescending: inputs.filter.sortDescending,
                searchText: inputs.filter.searchText
            ),
            inputs: inputs
        )
        return LocalFavoriteDerivedState(
            cards: cards,
            visibleCollections: visibleCollections(
                in: inputs.document,
                categoryID: inputs.selectedCategoryID,
                filter: inputs.filter,
                filteredCards: cards
            ),
            categoryEntryCounts: categoryEntryCounts(inputs),
            collectionEntryCounts: collectionEntryCounts(inputs),
            sourceGroupEntryCounts: sourceGroupEntryCounts(inputs)
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
            card.coverURL = inputs.contentCoverURLsByTargetID[card.item.target.id] ?? card.coverURL
            return card
        }
    }

    // MARK: - Counts

    private static func categoryEntryCounts(_ inputs: Inputs) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: inputs.document.categories.map { category in
            let cards = resolvedCards(
                in: inputs.document,
                query: LocalFavoriteLibraryQuery(
                    categoryID: category.id,
                    sourceGroupFilter: inputs.filter.sourceGroupFilter,
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
                filteredCards: cards
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
                    sourceGroupFilter: inputs.filter.sourceGroupFilter,
                    selectedTagIDs: inputs.filter.selectedTagIDs,
                    sortOrder: .organization,
                    searchText: inputs.filter.searchText
                ),
                inputs: inputs
            )
            return (collection.id, cards.count)
        })
    }

    private static func sourceGroupEntryCounts(_ inputs: Inputs) -> [FavoriteSourceGroup: Int] {
        let allCards = resolvedCards(
            in: inputs.document,
            query: LocalFavoriteLibraryQuery(
                categoryID: inputs.selectedCategoryID,
                collectionID: inputs.selectedCollectionID,
                sourceGroupFilter: .all,
                selectedTagIDs: inputs.filter.selectedTagIDs,
                sortOrder: .organization,
                searchText: inputs.filter.searchText
            ),
            inputs: inputs
        )
        return Dictionary(grouping: allCards) { card in
            canonicalSourceGroup(for: card.item)
        }
        .mapValues(\.count)
    }

    private static func canonicalSourceGroup(for item: FavoriteItem) -> FavoriteSourceGroup {
        guard let forumID = item.forumID ?? item.sourceGroup.forumID else {
            return item.sourceGroup
        }
        return .forumBoard(id: forumID, label: item.forumName ?? item.sourceGroup.forumName ?? forumID)
    }

    // MARK: - Collections

    private static func visibleCollections(
        in document: FavoriteLibraryDocument,
        categoryID: String,
        filter: LocalFavoriteFilterState,
        filteredCards: [FavoriteCardProjection]
    ) -> [LocalFavoriteCollection] {
        let trimmedSearch = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonSearchFiltersAreActive = filter.sourceGroupFilter != .all || !filter.selectedTagIDs.isEmpty
        let filtersAreActive = nonSearchFiltersAreActive || !trimmedSearch.isEmpty
        return document.collections
            .filter { collection in
                guard collection.categoryID == categoryID else { return false }
                guard filtersAreActive else { return true }
                let hasMatchingFilteredCard = filteredCards.contains { card in
                    card.item.locations.contains(
                        .collection(categoryID: collection.categoryID, collectionID: collection.id)
                    )
                }
                if !trimmedSearch.isEmpty,
                   collection.name.localizedCaseInsensitiveContains(trimmedSearch) {
                    return !nonSearchFiltersAreActive || hasMatchingFilteredCard
                }
                return hasMatchingFilteredCard
            }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }
}
