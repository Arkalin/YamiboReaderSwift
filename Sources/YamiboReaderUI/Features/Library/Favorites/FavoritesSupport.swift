import SwiftUI
import UniformTypeIdentifiers
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#endif

public enum FavoriteFilter: String, CaseIterable, Identifiable, Sendable {
    case all

    public static let allCases: [FavoriteFilter] = [.all]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: L10n.string("favorites.filter.all")
        }
    }

    func matches(_ favorite: Favorite) -> Bool {
        switch self {
        case .all:
            true
        }
    }

    var libraryFilter: FavoriteLibraryFilter {
        switch self {
        case .all: .all
        }
    }
}

public enum FavoriteSortOrder: String, CaseIterable, Identifiable, Sendable {
    case manual
    case title
    case recentRead

    public static let allCases: [FavoriteSortOrder] = [.manual, .title, .recentRead]

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: L10n.string("favorites.sort.manual")
        case .title: L10n.string("favorites.sort.title")
        case .recentRead: L10n.string("favorites.sort.recent_read")
        }
    }

    var librarySortOrder: FavoriteLibrarySortOrder {
        switch self {
        case .manual: .manual
        case .title: .title
        case .recentRead: .recentRead
        }
    }
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

public enum FavoriteScope: Hashable, Sendable {
    case root
    case collection(FavoriteCollection)

    var collection: FavoriteCollection? {
        if case let .collection(collection) = self {
            return collection
        }
        return nil
    }

    var libraryScope: FavoriteLibraryScope {
        switch self {
        case .root:
            .root
        case let .collection(collection):
            .collection(collection)
        }
    }
}

public enum FavoriteListEntry: Identifiable, Hashable, Sendable {
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

    var moveKey: String { id }
}

extension FavoriteLibraryEntry {
    var favoriteListEntry: FavoriteListEntry {
        switch self {
        case let .collection(collection):
            .collection(collection)
        case let .favorite(favorite):
            .favorite(favorite)
        }
    }
}

struct FavoriteSelectionActionState: Equatable {
    let canTag: Bool
    let canCreateCollection: Bool
    let canMove: Bool
    let canDelete: Bool
}

func favoriteLaunchNeedsMangaProbeBlocker(_ favorite: Favorite) -> Bool {
    false
}

func shouldBlockFavoriteInteractions(openingMangaFavoriteID: String?) -> Bool {
    openingMangaFavoriteID != nil
}

enum FavoriteLaunchMode: Sendable {
    case start
    case resume
}


public enum FavoriteOpenTarget: Sendable {
    case reader(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case web(Favorite)
}

struct FavoriteDisplayNameDraft {
    let favoriteID: String
    let originalTitle: String
    var displayName: String

    init(favorite: Favorite) {
        favoriteID = favorite.id
        originalTitle = favorite.title
        displayName = favorite.displayName ?? favorite.resolvedDisplayTitle
    }
}

struct FavoriteCollectionNameDraft {
    let collectionID: String
    var name: String

    init(collection: FavoriteCollection) {
        collectionID = collection.id
        name = collection.name
    }
}

struct FavoriteTagPickerContext: Identifiable {
    let favoriteIDs: [String]
    let initialTagIDs: Set<String>
    let showsOverwriteWarning: Bool
    let exitsSelectionModeOnConfirm: Bool
    let isFilter: Bool

    var id: String {
        isFilter ? "filter" : favoriteIDs.sorted().joined(separator: ",")
    }

    init(favoriteID: String, initialTagIDs: Set<String>) {
        favoriteIDs = [favoriteID]
        self.initialTagIDs = initialTagIDs
        showsOverwriteWarning = false
        exitsSelectionModeOnConfirm = false
        isFilter = false
    }

    init(filterTagIDs: Set<String>) {
        favoriteIDs = []
        initialTagIDs = filterTagIDs
        showsOverwriteWarning = false
        exitsSelectionModeOnConfirm = false
        isFilter = true
    }

    init(
        favoriteIDs: [String],
        initialTagIDs: Set<String>,
        showsOverwriteWarning: Bool,
        exitsSelectionModeOnConfirm: Bool
    ) {
        self.favoriteIDs = favoriteIDs
        self.initialTagIDs = initialTagIDs
        self.showsOverwriteWarning = showsOverwriteWarning
        self.exitsSelectionModeOnConfirm = exitsSelectionModeOnConfirm
        isFilter = false
    }
}

struct FavoriteBatchTagSelectionState: Equatable {
    let initialTagIDs: Set<String>
    let showsOverwriteWarning: Bool
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

        guard selectedTagIDs.count < limit else {
            return .selectionLimitExceeded(max: limit)
        }

        selectedTagIDs.insert(tagID)
        return .changed
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

struct FavoriteTagChipSummary: Equatable {
    let chips: [FavoriteTag]
    let overflowCount: Int
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

struct FavoriteCollectionSummary: Equatable {
    let itemCount: Int
    let hiddenCount: Int
}

enum FavoriteListColumn {
    case left
    case right
}

enum FavoriteDropPosition {
    case before
    case after
}

struct FavoriteVisibleOrderMove: Equatable {
    let fromOffsets: IndexSet
    let toOffset: Int
}

func splitAlternatingColumns<Element>(_ items: [Element]) -> (left: [Element], right: [Element]) {
    var left: [Element] = []
    var right: [Element] = []

    for (index, item) in items.enumerated() {
        if index.isMultiple(of: 2) {
            left.append(item)
        } else {
            right.append(item)
        }
    }

    return (left: left, right: right)
}

func reorderedItemsAfterDrop<Element: Equatable>(
    _ items: [Element],
    draggedItem: Element,
    targetItem: Element,
    position: FavoriteDropPosition
) -> [Element] {
    guard draggedItem != targetItem,
          let draggedIndex = items.firstIndex(of: draggedItem),
          items.contains(targetItem) else {
        return items
    }

    var reordered = items
    reordered.remove(at: draggedIndex)
    guard let targetIndex = reordered.firstIndex(of: targetItem) else { return items }

    let insertionIndex: Int
    switch position {
    case .before:
        insertionIndex = targetIndex
    case .after:
        insertionIndex = targetIndex + 1
    }

    reordered.insert(draggedItem, at: min(insertionIndex, reordered.count))
    return reordered
}

func reorderedItemsAfterDroppingAtColumnBottom<Element: Equatable>(
    _ items: [Element],
    draggedItem: Element,
    column: FavoriteListColumn
) -> [Element] {
    guard items.contains(draggedItem) else { return items }

    let columns = splitAlternatingColumns(items)
    let targetColumn = switch column {
    case .left: columns.left
    case .right: columns.right
    }

    if let lastItem = targetColumn.last {
        return reorderedItemsAfterDrop(items, draggedItem: draggedItem, targetItem: lastItem, position: .after)
    }

    var reordered = items
    guard let draggedIndex = reordered.firstIndex(of: draggedItem) else { return items }
    reordered.remove(at: draggedIndex)

    switch column {
    case .left:
        reordered.insert(draggedItem, at: 0)
    case .right:
        reordered.append(draggedItem)
    }

    return reordered
}

func makeVisibleOrderMovesToTransform<Element: Equatable>(
    from original: [Element],
    to target: [Element]
) -> [FavoriteVisibleOrderMove] {
    guard original.count == target.count else { return [] }

    var working = original
    var moves: [FavoriteVisibleOrderMove] = []

    for targetIndex in target.indices {
        guard working[targetIndex] != target[targetIndex],
              let sourceIndex = working[targetIndex...].firstIndex(of: target[targetIndex]) else {
            continue
        }

        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        let move = FavoriteVisibleOrderMove(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        working.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
        moves.append(move)
    }

    return working == target ? moves : []
}

func applyingVisibleOrderMoves<Element>(
    _ items: [Element],
    moves: [FavoriteVisibleOrderMove]
) -> [Element] {
    var working = items
    for move in moves {
        working.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
    }
    return working
}
