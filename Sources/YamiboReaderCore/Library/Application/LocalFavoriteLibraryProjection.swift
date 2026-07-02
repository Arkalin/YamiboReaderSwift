import Foundation

public enum LocalFavoriteLibrarySortOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case organization
    case contentUpdatedAt
    case yamiboRemoteOrder
    case displayTitle
    case sourceGroup
    case lastReadAt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .organization:
            L10n.string("favorites.sort.manual")
        case .contentUpdatedAt:
            L10n.string("favorites.sort.updated_at")
        case .yamiboRemoteOrder:
            L10n.string("favorites.sort.remote_order")
        case .displayTitle:
            L10n.string("favorites.sort.title")
        case .sourceGroup:
            L10n.string("favorites.source_group")
        case .lastReadAt:
            L10n.string("favorites.sort.recent_read")
        }
    }
}

public enum LocalFavoriteLibrarySourceGroupFilter: Hashable, Sendable {
    case all
    case group(FavoriteSourceGroup)
}

public struct LocalFavoriteLibraryQuery: Equatable, Sendable {
    public var categoryID: String?
    public var collectionID: String?
    public var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    public var selectedTagIDs: Set<String>
    public var sortOrder: LocalFavoriteLibrarySortOrder
    public var sortsDescending: Bool
    public var searchText: String

    public init(
        categoryID: String? = nil,
        collectionID: String? = nil,
        sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter = .all,
        selectedTagIDs: Set<String> = [],
        sortOrder: LocalFavoriteLibrarySortOrder = .organization,
        sortsDescending: Bool = false,
        searchText: String = ""
    ) {
        self.categoryID = categoryID
        self.collectionID = collectionID
        self.sourceGroupFilter = sourceGroupFilter
        self.selectedTagIDs = selectedTagIDs
        self.sortOrder = sortOrder
        self.sortsDescending = sortsDescending
        self.searchText = searchText
    }
}

public struct FavoriteCardProjection: Equatable, Identifiable, Sendable {
    public var item: FavoriteItem
    public var sourceGroupLabel: String
    public var collectionNames: [String]
    public var tags: [FavoriteTag]
    public var recentReadingAt: Date?
    public var lastUpdatedAt: Date?
    public var progressPercent: Int?
    public var chapterPageProgress: String?
    public var coverURL: URL?

    public var id: String { item.id }
}

public enum LocalFavoriteLibraryProjection {
    public static var supportedSortOrders: [LocalFavoriteLibrarySortOrder] {
        LocalFavoriteLibrarySortOrder.allCases
    }

    public static func cards(
        in document: FavoriteLibraryDocument,
        query: LocalFavoriteLibraryQuery = LocalFavoriteLibraryQuery(),
        readingProgress: [ReadingProgressRecord] = []
    ) -> [FavoriteCardProjection] {
        let categoryID = query.categoryID ?? document.defaultCategory.id
        let progressByKey = readingProgressLookup(readingProgress)
        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let cards = document.items
            .filter { item in
                if let collectionID = query.collectionID {
                    return item.locations.contains(.collection(categoryID: categoryID, collectionID: collectionID))
                }
                return item.locations.contains(.category(categoryID))
            }
            .filter { item in
                switch query.sourceGroupFilter {
                case .all:
                    true
                case let .group(sourceGroup):
                    matchesSourceGroup(item, filter: sourceGroup)
                }
            }
            .filter { item in
                query.selectedTagIDs.isEmpty || query.selectedTagIDs.isSubset(of: Set(item.tagIDs))
            }
            .map { item in
                card(for: item, document: document, progress: progressByKey[progressKey(for: item)])
            }
            .filter { card in
                guard !trimmedSearch.isEmpty else { return true }
                return searchFields(for: card).contains { field in
                    field.localizedCaseInsensitiveContains(trimmedSearch)
                }
            }

        return sorted(cards, by: query.sortOrder, descending: query.sortsDescending)
    }

    public static func displayedEntryCount(
        in document: FavoriteLibraryDocument,
        query: LocalFavoriteLibraryQuery = LocalFavoriteLibraryQuery(),
        readingProgress: [ReadingProgressRecord] = []
    ) -> Int {
        cards(in: document, query: query, readingProgress: readingProgress).count
    }

    private static func card(
        for item: FavoriteItem,
        document: FavoriteLibraryDocument,
        progress: ReadingProgressRecord?
    ) -> FavoriteCardProjection {
        FavoriteCardProjection(
            item: item,
            sourceGroupLabel: label(for: item.sourceGroup),
            collectionNames: collectionNames(for: item, in: document),
            tags: tags(for: item, in: document),
            recentReadingAt: progress?.lastReadAt,
            lastUpdatedAt: item.contentUpdatedAt,
            progressPercent: progressPercent(from: progress),
            chapterPageProgress: chapterPageProgress(from: progress),
            coverURL: item.coverURL
        )
    }

    private static func sorted(
        _ cards: [FavoriteCardProjection],
        by sortOrder: LocalFavoriteLibrarySortOrder,
        descending: Bool
    ) -> [FavoriteCardProjection] {
        let sortedCards = cards.sorted { lhs, rhs in
            switch sortOrder {
            case .organization:
                return compareOrganization(lhs, rhs)
            case .contentUpdatedAt:
                return compareDatesDescending(lhs.lastUpdatedAt, rhs.lastUpdatedAt, lhsID: lhs.id, rhsID: rhs.id)
            case .yamiboRemoteOrder:
                let lhsOrder = lhs.item.remoteMapping?.yamiboRemoteOrder ?? Int.max
                let rhsOrder = rhs.item.remoteMapping?.yamiboRemoteOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return lhs.id < rhs.id
            case .displayTitle:
                let result = lhs.item.resolvedDisplayTitle.localizedCaseInsensitiveCompare(rhs.item.resolvedDisplayTitle)
                return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
            case .sourceGroup:
                let result = sourceGroupSortKey(for: lhs).localizedCaseInsensitiveCompare(sourceGroupSortKey(for: rhs))
                return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
            case .lastReadAt:
                return compareDatesDescending(lhs.recentReadingAt, rhs.recentReadingAt, lhsID: lhs.id, rhsID: rhs.id)
            }
        }
        return descending ? sortedCards.reversed() : sortedCards
    }

    private static func compareOrganization(_ lhs: FavoriteCardProjection, _ rhs: FavoriteCardProjection) -> Bool {
        let lhsOrder = lhs.item.remoteMapping?.yamiboRemoteOrder
        let rhsOrder = rhs.item.remoteMapping?.yamiboRemoteOrder
        switch (lhsOrder, rhsOrder) {
        case let (lhsOrder?, rhsOrder?) where lhsOrder != rhsOrder:
            return lhsOrder < rhsOrder
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.item.createdAt != rhs.item.createdAt {
                return lhs.item.createdAt < rhs.item.createdAt
            }
            return lhs.id < rhs.id
        }
    }

    private static func compareDatesDescending(_ lhs: Date?, _ rhs: Date?, lhsID: String, rhsID: String) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhsID < rhsID
        }
    }

    private static func searchFields(for card: FavoriteCardProjection) -> [String] {
        [
            card.item.displayName,
            card.item.title,
            card.sourceGroupLabel
        ].compactMap(\.self) + card.tags.map(\.name)
    }

    private static func collectionNames(for item: FavoriteItem, in document: FavoriteLibraryDocument) -> [String] {
        let collectionIDs = Set(item.locations.compactMap(\.collectionID))
        return document.collections
            .filter { collectionIDs.contains($0.id) }
            .sorted { $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder }
            .map(\.name)
    }

    private static func tags(for item: FavoriteItem, in document: FavoriteLibraryDocument) -> [FavoriteTag] {
        let tagIDs = Set(item.tagIDs)
        return document.tags
            .filter { tagIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
        }
    }

    private static func sourceGroupSortKey(for card: FavoriteCardProjection) -> String {
        card.item.forumName ?? card.item.forumID ?? card.sourceGroupLabel
    }

    private static func matchesSourceGroup(_ item: FavoriteItem, filter: FavoriteSourceGroup) -> Bool {
        if let filterForumID = filter.forumID {
            return item.forumID == filterForumID || item.sourceGroup.forumID == filterForumID
        }
        return item.sourceGroup == filter
    }

    private static func label(for sourceGroup: FavoriteSourceGroup) -> String {
        switch sourceGroup {
        case let .forumBoard(_, label):
            label
        case let .mangaTitle(_, cleanBookName):
            cleanBookName
        case .unknown:
            L10n.string("favorites.source_group.unknown")
        }
    }

    private static func progressPercent(from record: ReadingProgressRecord?) -> Int? {
        guard let record else { return nil }
        switch record.kind {
        case .novel:
            return record.novel?.novelDocumentSurfaceProgressPercent
        case .manga:
            guard let manga = record.manga,
                  let pageCount = manga.mangaPageCount,
                  pageCount > 0 else {
                return nil
            }
            return min(max(Int(((Double(manga.mangaPageIndex) + 1) / Double(pageCount) * 100).rounded()), 0), 100)
        }
    }

    private static func chapterPageProgress(from record: ReadingProgressRecord?) -> String? {
        guard let record else { return nil }
        switch record.kind {
        case .novel:
            guard let lastChapter = record.novel?.lastChapter else { return nil }
            return lastChapter
        case .manga:
            guard let manga = record.manga else { return nil }
            if let pageCount = manga.mangaPageCount {
                return L10n.string("favorites.progress.manga_page_total", manga.lastChapter, manga.mangaPageIndex + 1, pageCount)
            }
            return L10n.string("favorites.progress.manga_page", manga.lastChapter, manga.mangaPageIndex + 1)
        }
    }

    private static func readingProgressLookup(_ records: [ReadingProgressRecord]) -> [String: ReadingProgressRecord] {
        Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    }

    private static func progressKey(for item: FavoriteItem) -> String {
        item.target.id
    }
}
