import Foundation

public enum FavoriteLibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all

    public static let allCases: [FavoriteLibraryFilter] = [.all]

    public var id: String { rawValue }

    func matches(_ favorite: Favorite) -> Bool {
        switch self {
        case .all:
            true
        }
    }
}

public enum FavoriteLibrarySortOrder: String, CaseIterable, Identifiable, Sendable {
    case manual
    case title
    case recentRead

    public static let allCases: [FavoriteLibrarySortOrder] = [.manual, .title, .recentRead]

    public var id: String { rawValue }
}

public enum FavoriteLibraryTagSortOrder: String, CaseIterable, Identifiable, Sendable {
    case manual
    case name
    case nameDescending
    case updatedAt
    case updatedAtDescending
    case associationCount
    case associationCountDescending

    public var id: String { rawValue }
}

public enum FavoriteLibraryScope: Hashable, Sendable {
    case root
    case collection(FavoriteCollection)

    var collection: FavoriteCollection? {
        if case let .collection(collection) = self {
            return collection
        }
        return nil
    }
}

public struct FavoriteLibraryQuery: Equatable, Sendable {
    public var scope: FavoriteLibraryScope
    public var filter: FavoriteLibraryFilter
    public var sortOrder: FavoriteLibrarySortOrder
    public var searchText: String
    public var selectedTagIDs: Set<String>

    public init(
        scope: FavoriteLibraryScope = .root,
        filter: FavoriteLibraryFilter = .all,
        sortOrder: FavoriteLibrarySortOrder = .manual,
        searchText: String = "",
        selectedTagIDs: Set<String> = []
    ) {
        self.scope = scope
        self.filter = filter
        self.sortOrder = sortOrder
        self.searchText = searchText
        self.selectedTagIDs = selectedTagIDs
    }
}

public enum FavoriteLibraryEntry: Identifiable, Hashable, Sendable {
    case collection(FavoriteCollection)
    case favorite(Favorite)

    public var id: String {
        switch self {
        case let .collection(collection):
            "collection:\(collection.id)"
        case let .favorite(favorite):
            "favorite:\(favorite.id)"
        }
    }
}

public struct FavoriteLibraryCollectionSummary: Equatable, Sendable {
    public let itemCount: Int

    public init(itemCount: Int) {
        self.itemCount = itemCount
    }
}

public struct FavoriteLibraryTagChipSummary: Equatable, Sendable {
    public let chips: [FavoriteTag]
    public let overflowCount: Int

    public init(chips: [FavoriteTag], overflowCount: Int) {
        self.chips = chips
        self.overflowCount = overflowCount
    }
}

public struct FavoriteLibrarySelectionActionState: Equatable, Sendable {
    public let canTag: Bool
    public let canCreateCollection: Bool
    public let canMove: Bool
    public let canDelete: Bool

    public init(canTag: Bool, canCreateCollection: Bool, canMove: Bool, canDelete: Bool) {
        self.canTag = canTag
        self.canCreateCollection = canCreateCollection
        self.canMove = canMove
        self.canDelete = canDelete
    }
}

public struct FavoriteLibraryBatchTagSelectionState: Equatable, Sendable {
    public let initialTagIDs: Set<String>
    public let showsOverwriteWarning: Bool

    public init(initialTagIDs: Set<String>, showsOverwriteWarning: Bool) {
        self.initialTagIDs = initialTagIDs
        self.showsOverwriteWarning = showsOverwriteWarning
    }
}

public enum FavoriteLibraryProjection {
    public static func entries(
        in snapshot: FavoriteLibrarySnapshot,
        query: FavoriteLibraryQuery
    ) -> [FavoriteLibraryEntry] {
        switch query.scope {
        case .root:
            let rootFavorites = favorites(in: snapshot, query: query)
            let visibleCollections = orderedCollections(snapshot.collections).filter { collection in
                rootCollectionMatches(collection, snapshot: snapshot, query: query)
            }
            let entries = visibleCollections.map(FavoriteLibraryEntry.collection) + rootFavorites.map(FavoriteLibraryEntry.favorite)
            switch query.sortOrder {
            case .manual:
                return entries.sorted { lhs, rhs in
                    if entryManualOrder(lhs) != entryManualOrder(rhs) {
                        return entryManualOrder(lhs) < entryManualOrder(rhs)
                    }
                    return lhs.id < rhs.id
                }
            case .recentRead:
                return entries.sorted { lhs, rhs in
                    compareRecentReadEntries(lhs, rhs, snapshot: snapshot, query: query)
                }
            case .title:
                return visibleCollections.map(FavoriteLibraryEntry.collection) + rootFavorites.map(FavoriteLibraryEntry.favorite)
            }
        case .collection:
            return favorites(in: snapshot, query: query).map(FavoriteLibraryEntry.favorite)
        }
    }

    public static func favorites(
        in snapshot: FavoriteLibrarySnapshot,
        query: FavoriteLibraryQuery
    ) -> [Favorite] {
        let trimmedSearchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentCollectionID = query.scope.collection?.id
        let filtered = snapshot.favorites
            .filter { $0.parentCollectionID == parentCollectionID }
            .filter { query.filter.matches($0) }
            .filter { favorite in
                query.selectedTagIDs.isEmpty || query.selectedTagIDs.isSubset(of: Set(favorite.tagIDs))
            }
            .filter { favorite in
                guard !trimmedSearchText.isEmpty else { return true }
                return favorite.resolvedDisplayTitle.localizedCaseInsensitiveContains(trimmedSearchText)
            }

        switch query.sortOrder {
        case .manual:
            return filtered.sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
        case .title:
            return filtered.sorted { lhs, rhs in
                lhs.resolvedDisplayTitle.localizedCompare(rhs.resolvedDisplayTitle) == .orderedAscending
            }
        case .recentRead:
            return filtered.sorted(by: compareRecentReadFavorites)
        }
    }

    public static func collectionSummary(
        for collection: FavoriteCollection,
        in snapshot: FavoriteLibrarySnapshot,
        query: FavoriteLibraryQuery
    ) -> FavoriteLibraryCollectionSummary {
        let allItems = snapshot.favorites.filter { $0.parentCollectionID == collection.id }

        guard case .root = query.scope else {
            return FavoriteLibraryCollectionSummary(
                itemCount: allItems.count
            )
        }

        let trimmedSearchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.selectedTagIDs.isEmpty,
           query.filter == .all,
           trimmedSearchText.isEmpty || collection.name.localizedCaseInsensitiveContains(trimmedSearchText) {
            return FavoriteLibraryCollectionSummary(
                itemCount: allItems.count
            )
        }

        var containedQuery = query
        containedQuery.scope = .collection(collection)
        containedQuery.sortOrder = .manual
        containedQuery.searchText = favoriteSearchTextForCollectionMatch(collection, query: query)
        let matchingItems = favorites(in: snapshot, query: containedQuery)
        return FavoriteLibraryCollectionSummary(
            itemCount: matchingItems.count
        )
    }

    public static func filteredTags(_ tags: [FavoriteTag], searchText: String) -> [FavoriteTag] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else { return tags }

        return tags.filter { tag in
            tag.name.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    public static func canReorderTags(sortOrder: FavoriteLibraryTagSortOrder, searchText: String) -> Bool {
        sortOrder == .manual && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func canReorderEntries(
        sortOrder: FavoriteLibrarySortOrder,
        searchText: String,
        selectedTagIDs: Set<String> = []
    ) -> Bool {
        sortOrder == .manual &&
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            selectedTagIDs.isEmpty
    }

    public static func sortedTags(
        _ tags: [FavoriteTag],
        favorites: [Favorite],
        sortOrder: FavoriteLibraryTagSortOrder
    ) -> [FavoriteTag] {
        let associationCounts = tagAssociationCounts(from: favorites)
        return tags.sorted { lhs, rhs in
            switch sortOrder {
            case .manual:
                break
            case .name:
                let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if result != .orderedSame {
                    return result == .orderedAscending
                }
            case .nameDescending:
                let result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if result != .orderedSame {
                    return result == .orderedDescending
                }
            case .updatedAt:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
            case .updatedAtDescending:
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
            case .associationCount:
                let lhsCount = associationCounts[lhs.id, default: 0]
                let rhsCount = associationCounts[rhs.id, default: 0]
                if lhsCount != rhsCount {
                    return lhsCount < rhsCount
                }
            case .associationCountDescending:
                let lhsCount = associationCounts[lhs.id, default: 0]
                let rhsCount = associationCounts[rhs.id, default: 0]
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
            }

            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    public static func tagAssociationCounts(from favorites: [Favorite]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for favorite in favorites {
            for tagID in Set(favorite.tagIDs) {
                counts[tagID, default: 0] += 1
            }
        }
        return counts
    }

    public static func tagChipSummary(
        for favorite: Favorite,
        tags: [FavoriteTag],
        searchText: String,
        prioritizedTagIDs: Set<String> = []
    ) -> FavoriteLibraryTagChipSummary {
        let tagIDs = Set(favorite.tagIDs)
        guard !tagIDs.isEmpty else {
            return FavoriteLibraryTagChipSummary(chips: [], overflowCount: 0)
        }

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let favoriteTags = tags
            .filter { tagIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsIsPrioritized = prioritizedTagIDs.contains(lhs.id) ||
                    (!trimmedSearchText.isEmpty && lhs.name.localizedCaseInsensitiveContains(trimmedSearchText))
                let rhsIsPrioritized = prioritizedTagIDs.contains(rhs.id) ||
                    (!trimmedSearchText.isEmpty && rhs.name.localizedCaseInsensitiveContains(trimmedSearchText))
                if lhsIsPrioritized != rhsIsPrioritized {
                    return lhsIsPrioritized
                }
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
        let chips = Array(favoriteTags.prefix(3))
        return FavoriteLibraryTagChipSummary(
            chips: chips,
            overflowCount: max(0, favoriteTags.count - chips.count)
        )
    }

    public static func selectionActionState(
        scope: FavoriteLibraryScope,
        selectedFavoriteCount: Int,
        selectedCollectionCount: Int
    ) -> FavoriteLibrarySelectionActionState {
        let hasFavorites = selectedFavoriteCount > 0
        let hasCollections = selectedCollectionCount > 0
        let hasSelection = hasFavorites || hasCollections

        switch scope {
        case .root:
            return FavoriteLibrarySelectionActionState(
                canTag: hasFavorites && !hasCollections,
                canCreateCollection: hasFavorites && !hasCollections,
                canMove: hasFavorites && !hasCollections,
                canDelete: hasSelection
            )
        case .collection:
            return FavoriteLibrarySelectionActionState(
                canTag: hasFavorites,
                canCreateCollection: false,
                canMove: hasFavorites,
                canDelete: hasFavorites
            )
        }
    }

    public static func batchTagSelectionState(
        favorites: [Favorite],
        selectedFavoriteIDs: Set<String>
    ) -> FavoriteLibraryBatchTagSelectionState {
        let selectedFavorites = favorites.filter { selectedFavoriteIDs.contains($0.id) }
        guard let firstFavorite = selectedFavorites.first else {
            return FavoriteLibraryBatchTagSelectionState(initialTagIDs: [], showsOverwriteWarning: false)
        }

        let firstTagIDs = Set(firstFavorite.tagIDs)
        let hasDivergentTags = selectedFavorites.dropFirst().contains { Set($0.tagIDs) != firstTagIDs }
        return FavoriteLibraryBatchTagSelectionState(
            initialTagIDs: hasDivergentTags ? [] : firstTagIDs,
            showsOverwriteWarning: hasDivergentTags
        )
    }

    private static func rootCollectionMatches(
        _ collection: FavoriteCollection,
        snapshot: FavoriteLibrarySnapshot,
        query: FavoriteLibraryQuery
    ) -> Bool {
        let trimmedSearchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var containedQuery = query
        containedQuery.scope = .collection(collection)
        containedQuery.sortOrder = .manual
        containedQuery.searchText = favoriteSearchTextForCollectionMatch(collection, query: query)
        let matchedFavorites = favorites(in: snapshot, query: containedQuery)

        guard query.filter == .all, query.selectedTagIDs.isEmpty else {
            return !matchedFavorites.isEmpty
        }

        guard !trimmedSearchText.isEmpty else {
            return true
        }

        return collection.name.localizedCaseInsensitiveContains(trimmedSearchText) || !matchedFavorites.isEmpty
    }

    private static func favoriteSearchTextForCollectionMatch(
        _ collection: FavoriteCollection,
        query: FavoriteLibraryQuery
    ) -> String {
        let trimmedSearchText = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.selectedTagIDs.isEmpty,
              query.filter == .all,
              !trimmedSearchText.isEmpty,
              collection.name.localizedCaseInsensitiveContains(trimmedSearchText) else {
            return query.searchText
        }
        return ""
    }

    private static func compareRecentReadFavorites(_ lhs: Favorite, _ rhs: Favorite) -> Bool {
        switch (lhs.lastReadAt, rhs.lastReadAt) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private static func compareRecentReadEntries(
        _ lhs: FavoriteLibraryEntry,
        _ rhs: FavoriteLibraryEntry,
        snapshot: FavoriteLibrarySnapshot,
        query: FavoriteLibraryQuery
    ) -> Bool {
        switch (
            entryLastReadAt(lhs, snapshot: snapshot, query: query),
            entryLastReadAt(rhs, snapshot: snapshot, query: query)
        ) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if entryManualOrder(lhs) != entryManualOrder(rhs) {
                return entryManualOrder(lhs) < entryManualOrder(rhs)
            }
            return lhs.id < rhs.id
        }
    }

    private static func entryLastReadAt(
        _ entry: FavoriteLibraryEntry,
        snapshot: FavoriteLibrarySnapshot,
        query: FavoriteLibraryQuery
    ) -> Date? {
        switch entry {
        case let .favorite(favorite):
            return favorite.lastReadAt
        case let .collection(collection):
            var containedQuery = query
            containedQuery.scope = .collection(collection)
            containedQuery.sortOrder = .recentRead
            containedQuery.searchText = favoriteSearchTextForCollectionMatch(collection, query: query)
            return favorites(in: snapshot, query: containedQuery)
                .compactMap(\.lastReadAt)
                .max()
        }
    }

    private static func orderedCollections(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
        collections.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private static func entryManualOrder(_ entry: FavoriteLibraryEntry) -> Int {
        switch entry {
        case let .collection(collection):
            collection.manualOrder
        case let .favorite(favorite):
            favorite.manualOrder
        }
    }
}
