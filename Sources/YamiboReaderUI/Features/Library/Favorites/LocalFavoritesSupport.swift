import YamiboReaderCore

enum FavoriteLaunchMode: Sendable {
    case start
    case resume
}

func favoriteLaunchNeedsMangaProbeBlocker(_ favorite: Favorite) -> Bool {
    false
}

func shouldBlockFavoriteInteractions(openingMangaFavoriteID: String?) -> Bool {
    openingMangaFavoriteID != nil
}

enum FavoriteTagSortOrder: String, CaseIterable, Identifiable {
    case manual
    case name
    case nameDescending
    case updatedAt
    case updatedAtDescending
    case associationCount
    case associationCountDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: L10n.string("favorites.tag_sort.manual")
        case .name: L10n.string("favorites.tag_sort.name")
        case .nameDescending: L10n.string("favorites.tag_sort.name_desc")
        case .updatedAt: L10n.string("favorites.tag_sort.updated_at")
        case .updatedAtDescending: L10n.string("favorites.tag_sort.updated_at_desc")
        case .associationCount: L10n.string("favorites.tag_sort.association_count")
        case .associationCountDescending: L10n.string("favorites.tag_sort.association_count_desc")
        }
    }

    var libraryTagSortOrder: FavoriteLibraryTagSortOrder {
        switch self {
        case .manual: .manual
        case .name: .name
        case .nameDescending: .nameDescending
        case .updatedAt: .updatedAt
        case .updatedAtDescending: .updatedAtDescending
        case .associationCount: .associationCount
        case .associationCountDescending: .associationCountDescending
        }
    }
}

let favoriteTagSelectionLimit = 20

enum FavoriteTagSelectionDraftResult: Equatable {
    case changed
    case unchanged
    case selectionLimitExceeded(max: Int)
}

struct FavoriteTagSelectionDraft: Equatable {
    var selectedTagIDs: Set<String>

    mutating func toggle(_ tagID: String, limit: Int = favoriteTagSelectionLimit) -> FavoriteTagSelectionDraftResult {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
            return .changed
        }
        return select(tagID, limit: limit)
    }

    mutating func select(_ tagID: String, limit: Int = favoriteTagSelectionLimit) -> FavoriteTagSelectionDraftResult {
        guard !selectedTagIDs.contains(tagID) else { return .unchanged }
        guard selectedTagIDs.count < limit else {
            return .selectionLimitExceeded(max: limit)
        }
        selectedTagIDs.insert(tagID)
        return .changed
    }

    mutating func selectAll(visibleTagIDs: [String], limit: Int = favoriteTagSelectionLimit) -> FavoriteTagSelectionDraftResult {
        let updatedSelection = selectedTagIDs.union(visibleTagIDs)
        guard updatedSelection.count <= limit else {
            return .selectionLimitExceeded(max: limit)
        }
        guard updatedSelection != selectedTagIDs else { return .unchanged }
        selectedTagIDs = updatedSelection
        return .changed
    }

    mutating func deselectAll(visibleTagIDs: [String]) -> FavoriteTagSelectionDraftResult {
        let updatedSelection = selectedTagIDs.subtracting(visibleTagIDs)
        guard updatedSelection != selectedTagIDs else { return .unchanged }
        selectedTagIDs = updatedSelection
        return .changed
    }
}

struct FavoriteTagEditorDraft: Identifiable {
    let tag: FavoriteTag?
    var name: String
    var color: FavoriteTagColor

    var id: String { tag?.id ?? "new" }

    init(tag: FavoriteTag?, defaultColor: FavoriteTagColor) {
        self.tag = tag
        name = tag?.name ?? ""
        color = tag?.color ?? defaultColor
    }
}

func filteredFavoriteTags(_ tags: [FavoriteTag], searchText: String) -> [FavoriteTag] {
    FavoriteLibraryProjection.filteredTags(tags, searchText: searchText)
}

func canReorderFavoriteTags(sortOrder: FavoriteTagSortOrder, searchText: String) -> Bool {
    FavoriteLibraryProjection.canReorderTags(sortOrder: sortOrder.libraryTagSortOrder, searchText: searchText)
}

func sortedFavoriteTags(
    _ tags: [FavoriteTag],
    favorites: [Favorite],
    sortOrder: FavoriteTagSortOrder
) -> [FavoriteTag] {
    FavoriteLibraryProjection.sortedTags(tags, favorites: favorites, sortOrder: sortOrder.libraryTagSortOrder)
}
