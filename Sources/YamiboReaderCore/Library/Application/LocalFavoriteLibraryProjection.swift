import Foundation

public enum LocalFavoriteLibrarySortOrder: String, CaseIterable, Identifiable, Sendable {
    case organization
    case contentUpdatedAt
    case yamiboRemoteOrder
    case displayTitle
    case sourceGroup
    case lastReadAt

    public var id: String { rawValue }
}

public enum LocalFavoriteLibrarySourceGroupFilter: Hashable, Sendable {
    case all
    case group(FavoriteSourceGroup)
}

public struct LocalFavoriteLibraryQuery: Equatable, Sendable {
    public var categoryID: String?
    public var collectionID: String?
    public var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    public var sortOrder: LocalFavoriteLibrarySortOrder
    public var searchText: String

    public init(
        categoryID: String? = nil,
        collectionID: String? = nil,
        sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter = .all,
        sortOrder: LocalFavoriteLibrarySortOrder = .organization,
        searchText: String = ""
    ) {
        self.categoryID = categoryID
        self.collectionID = collectionID
        self.sourceGroupFilter = sourceGroupFilter
        self.sortOrder = sortOrder
        self.searchText = searchText
    }
}

public struct FavoriteCardProjection: Equatable, Identifiable, Sendable {
    public var item: FavoriteItem
    public var sourceGroupLabel: String
    public var collectionNames: [String]
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
                return item.locations.contains { $0.categoryID == categoryID }
            }
            .filter { item in
                switch query.sourceGroupFilter {
                case .all:
                    true
                case let .group(sourceGroup):
                    item.sourceGroup == sourceGroup
                }
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

        return sorted(cards, by: query.sortOrder)
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
            recentReadingAt: progress?.lastReadAt,
            lastUpdatedAt: item.updatedAt,
            progressPercent: progressPercent(from: progress),
            chapterPageProgress: chapterPageProgress(from: progress),
            coverURL: item.coverURL
        )
    }

    private static func sorted(
        _ cards: [FavoriteCardProjection],
        by sortOrder: LocalFavoriteLibrarySortOrder
    ) -> [FavoriteCardProjection] {
        cards.sorted { lhs, rhs in
            switch sortOrder {
            case .organization:
                return lhs.item.id < rhs.item.id
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
                let result = lhs.sourceGroupLabel.localizedCaseInsensitiveCompare(rhs.sourceGroupLabel)
                return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
            case .lastReadAt:
                return compareDatesDescending(lhs.recentReadingAt, rhs.recentReadingAt, lhsID: lhs.id, rhsID: rhs.id)
            }
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
        ].compactMap(\.self) + card.collectionNames
    }

    private static func collectionNames(for item: FavoriteItem, in document: FavoriteLibraryDocument) -> [String] {
        let collectionIDs = Set(item.locations.compactMap(\.collectionID))
        return document.collections
            .filter { collectionIDs.contains($0.id) }
            .sorted { $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder }
            .map(\.name)
    }

    private static func label(for sourceGroup: FavoriteSourceGroup) -> String {
        switch sourceGroup {
        case let .forumBoard(_, label):
            label
        case let .mangaTitle(cleanBookName):
            cleanBookName
        case .unknown:
            L10n.string("favorites.source_group.unknown")
        }
    }

    private static func progressPercent(from record: ReadingProgressRecord?) -> Int? {
        record?.novel?.novelDocumentSurfaceProgressPercent
    }

    private static func chapterPageProgress(from record: ReadingProgressRecord?) -> String? {
        guard let record else { return nil }
        switch record.kind {
        case .novel:
            guard let lastChapter = record.novel?.lastChapter else { return nil }
            return lastChapter
        case .manga:
            guard let manga = record.manga else { return nil }
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
