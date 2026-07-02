import Foundation
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
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSearchText.isEmpty else { return tags }

    return tags.filter { tag in
        tag.name.localizedCaseInsensitiveContains(trimmedSearchText)
    }
}

func canReorderFavoriteTags(sortOrder: FavoriteTagSortOrder, searchText: String) -> Bool {
    sortOrder == .manual && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

func sortedFavoriteTags(
    _ tags: [FavoriteTag],
    favorites: [Favorite],
    sortOrder: FavoriteTagSortOrder
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

private func tagAssociationCounts(from favorites: [Favorite]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for favorite in favorites {
        for tagID in Set(favorite.tagIDs) {
            counts[tagID, default: 0] += 1
        }
    }
    return counts
}
