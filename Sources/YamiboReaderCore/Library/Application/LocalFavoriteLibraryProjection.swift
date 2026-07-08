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

/// One choosable source filter: a forum board, all manga aggregated into a
/// single entry (mirroring the Android filter's single "標籤" row), or items
/// with an unknown source. Forum boards compare by id only.
public enum LocalFavoriteSourceFilter: Hashable, Sendable {
    case forumBoard(id: String, label: String)
    case manga
    case unknown

    public static func == (lhs: LocalFavoriteSourceFilter, rhs: LocalFavoriteSourceFilter) -> Bool {
        switch (lhs, rhs) {
        case let (.forumBoard(lhsID, _), .forumBoard(rhsID, _)):
            lhsID == rhsID
        case (.manga, .manga), (.unknown, .unknown):
            true
        default:
            false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .forumBoard(id, _):
            hasher.combine("forumBoard")
            hasher.combine(id)
        case .manga:
            hasher.combine("manga")
        case .unknown:
            hasher.combine("unknown")
        }
    }

    public var displayLabel: String {
        switch self {
        case let .forumBoard(id, label):
            label.isEmpty ? id : label
        case .manga:
            L10n.string("favorites.filter.manga")
        case .unknown:
            L10n.string("favorites.source_group.unknown")
        }
    }

    /// Canonical filter bucket an item belongs to.
    public static func key(for item: FavoriteItem) -> LocalFavoriteSourceFilter {
        if item.target.kind == .mangaTitle {
            return .manga
        }
        if let forumID = item.forumID ?? item.sourceGroup.forumID {
            return .forumBoard(id: forumID, label: item.forumName ?? item.sourceGroup.forumName ?? forumID)
        }
        return .unknown
    }

    public func matches(_ item: FavoriteItem) -> Bool {
        switch self {
        case let .forumBoard(id, _):
            item.forumID == id || item.sourceGroup.forumID == id
        case .manga:
            item.target.kind == .mangaTitle
        case .unknown:
            LocalFavoriteSourceFilter.key(for: item) == .unknown
        }
    }
}

public struct LocalFavoriteLibraryQuery: Equatable, Sendable {
    public var categoryID: String?
    public var collectionID: String?
    /// Source filters to keep; empty means no source filtering (Android's
    /// forum filter is a multi-select).
    public var selectedSourceFilters: Set<LocalFavoriteSourceFilter>
    public var selectedTagIDs: Set<String>
    public var sortOrder: LocalFavoriteLibrarySortOrder
    public var sortsDescending: Bool
    public var searchText: String

    public init(
        categoryID: String? = nil,
        collectionID: String? = nil,
        selectedSourceFilters: Set<LocalFavoriteSourceFilter> = [],
        selectedTagIDs: Set<String> = [],
        sortOrder: LocalFavoriteLibrarySortOrder = .organization,
        sortsDescending: Bool = false,
        searchText: String = ""
    ) {
        self.categoryID = categoryID
        self.collectionID = collectionID
        self.selectedSourceFilters = selectedSourceFilters
        self.selectedTagIDs = selectedTagIDs
        self.sortOrder = sortOrder
        self.sortsDescending = sortsDescending
        self.searchText = searchText
    }
}

/// Aggregate stand-ins for the sort fields a collection has no value of its
/// own for, derived from its (filtered) member cards so a collection can be
/// merged into the same ordering as individual favorites.
public struct FavoriteCollectionSortSummary: Equatable, Sendable {
    public var latestUpdatedAt: Date?
    public var latestReadAt: Date?
    public var minRemoteOrder: Int?

    public init(latestUpdatedAt: Date? = nil, latestReadAt: Date? = nil, minRemoteOrder: Int? = nil) {
        self.latestUpdatedAt = latestUpdatedAt
        self.latestReadAt = latestReadAt
        self.minRemoteOrder = minRemoteOrder
    }

    public static func summarizing(_ cards: [FavoriteCardProjection]) -> FavoriteCollectionSortSummary {
        FavoriteCollectionSortSummary(
            latestUpdatedAt: cards.compactMap(\.lastUpdatedAt).max(),
            latestReadAt: cards.compactMap(\.recentReadingAt).max(),
            minRemoteOrder: cards.compactMap { $0.item.remoteMapping?.yamiboRemoteOrder }.min()
        )
    }
}

/// One row of the favorites list/grid once collections and individual
/// favorites are merged into a single ordering.
public enum FavoriteMixedEntry: Equatable, Identifiable, Sendable {
    case collection(LocalFavoriteCollection)
    case card(FavoriteCardProjection)

    public var id: String {
        switch self {
        case let .collection(collection):
            "collection-\(collection.id)"
        case let .card(card):
            "item-\(card.id)"
        }
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
        let progressByMangaCleanBookName = mangaReadingProgressLookup(readingProgress)
        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let cards = document.items
            .filter { item in
                if let collectionID = query.collectionID {
                    return item.locations.contains(.collection(categoryID: categoryID, collectionID: collectionID))
                }
                return item.locations.contains(.category(categoryID))
            }
            .filter { item in
                query.selectedSourceFilters.isEmpty
                    || query.selectedSourceFilters.contains { $0.matches(item) }
            }
            .filter { item in
                query.selectedTagIDs.isEmpty || query.selectedTagIDs.isSubset(of: Set(item.tagIDs))
            }
            .map { item in
                let progress = progressByKey[progressKey(for: item)]
                    ?? item.target.mangaCleanBookName.flatMap { progressByMangaCleanBookName[$0] }
                return card(for: item, document: document, progress: progress)
            }
            .filter { card in
                guard !trimmedSearch.isEmpty else { return true }
                return searchFields(for: card).contains { field in
                    field.localizedCaseInsensitiveContains(trimmedSearch)
                }
            }

        return sorted(cards, by: query.sortOrder, descending: query.sortsDescending)
    }

    /// Merges collections and cards into one ordering. `.organization` is
    /// each side's own manual/remote order — a collection's `manualOrder`
    /// (set via the up/down arrows) and a card's remote/creation order live
    /// on unrelated scales, so that's the one mode where collections stay a
    /// pinned block ahead of the cards rather than interleaving.
    public static func mixedEntries(
        cards: [FavoriteCardProjection],
        collections: [LocalFavoriteCollection],
        collectionSummaries: [String: FavoriteCollectionSortSummary],
        sortOrder: LocalFavoriteLibrarySortOrder,
        descending: Bool
    ) -> [FavoriteMixedEntry] {
        let entries = collections.map(FavoriteMixedEntry.collection) + cards.map(FavoriteMixedEntry.card)
        guard sortOrder != .organization else {
            return entries
        }
        let sortedEntries = entries.sorted { lhs, rhs in
            compareMixed(lhs, rhs, by: sortOrder, descending: descending, collectionSummaries: collectionSummaries)
        }
        // See the matching switch in `sorted(_:by:descending:)`: date modes
        // bake `descending` into the comparator so undated entries stay
        // last regardless of direction; other modes reverse as a whole.
        switch sortOrder {
        case .contentUpdatedAt, .lastReadAt:
            return sortedEntries
        default:
            return descending ? sortedEntries.reversed() : sortedEntries
        }
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
            // Filled from ContentCoverStore by the library derivation; items
            // deliberately carry no cover of their own.
            coverURL: nil
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
                return compareDates(lhs.lastUpdatedAt, rhs.lastUpdatedAt, lhsID: lhs.id, rhsID: rhs.id, descending: descending)
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
                return compareDates(lhs.recentReadingAt, rhs.recentReadingAt, lhsID: lhs.id, rhsID: rhs.id, descending: descending)
            }
        }
        // .contentUpdatedAt/.lastReadAt already bake `descending` into the
        // comparator above so undated items stay last regardless of
        // direction; every other mode sorts ascending here and is reversed
        // as a whole, which is safe because those modes have no "missing
        // value" sentinel that would otherwise jump to the wrong end.
        switch sortOrder {
        case .contentUpdatedAt, .lastReadAt:
            return sortedCards
        default:
            return descending ? sortedCards.reversed() : sortedCards
        }
    }

    private static func compareMixed(
        _ lhs: FavoriteMixedEntry,
        _ rhs: FavoriteMixedEntry,
        by sortOrder: LocalFavoriteLibrarySortOrder,
        descending: Bool,
        collectionSummaries: [String: FavoriteCollectionSortSummary]
    ) -> Bool {
        switch sortOrder {
        case .organization:
            return false
        case .contentUpdatedAt:
            return compareDates(
                mixedUpdatedAt(lhs, collectionSummaries), mixedUpdatedAt(rhs, collectionSummaries),
                lhsID: lhs.id, rhsID: rhs.id, descending: descending
            )
        case .yamiboRemoteOrder:
            let lhsOrder = mixedRemoteOrder(lhs, collectionSummaries) ?? Int.max
            let rhsOrder = mixedRemoteOrder(rhs, collectionSummaries) ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.id < rhs.id
        case .displayTitle:
            let result = mixedTitle(lhs).localizedCaseInsensitiveCompare(mixedTitle(rhs))
            return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
        case .sourceGroup:
            let result = mixedSourceGroupKey(lhs).localizedCaseInsensitiveCompare(mixedSourceGroupKey(rhs))
            return result == .orderedSame ? lhs.id < rhs.id : result == .orderedAscending
        case .lastReadAt:
            return compareDates(
                mixedReadAt(lhs, collectionSummaries), mixedReadAt(rhs, collectionSummaries),
                lhsID: lhs.id, rhsID: rhs.id, descending: descending
            )
        }
    }

    private static func mixedUpdatedAt(_ entry: FavoriteMixedEntry, _ summaries: [String: FavoriteCollectionSortSummary]) -> Date? {
        switch entry {
        case let .card(card):
            card.lastUpdatedAt
        case let .collection(collection):
            summaries[collection.id]?.latestUpdatedAt
        }
    }

    private static func mixedReadAt(_ entry: FavoriteMixedEntry, _ summaries: [String: FavoriteCollectionSortSummary]) -> Date? {
        switch entry {
        case let .card(card):
            card.recentReadingAt
        case let .collection(collection):
            summaries[collection.id]?.latestReadAt
        }
    }

    private static func mixedRemoteOrder(_ entry: FavoriteMixedEntry, _ summaries: [String: FavoriteCollectionSortSummary]) -> Int? {
        switch entry {
        case let .card(card):
            card.item.remoteMapping?.yamiboRemoteOrder
        case let .collection(collection):
            summaries[collection.id]?.minRemoteOrder
        }
    }

    /// A collection has no single title/source group of its own — its name
    /// stands in for both, so it sorts alongside cards' titles/source groups
    /// as its own pseudo-entry rather than always leading or trailing them.
    private static func mixedTitle(_ entry: FavoriteMixedEntry) -> String {
        switch entry {
        case let .card(card):
            card.item.resolvedDisplayTitle
        case let .collection(collection):
            collection.name
        }
    }

    private static func mixedSourceGroupKey(_ entry: FavoriteMixedEntry) -> String {
        switch entry {
        case let .card(card):
            sourceGroupSortKey(for: card)
        case let .collection(collection):
            collection.name
        }
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

    /// Dated items compare by date, oldest/most-recent-first per
    /// `descending`; undated items always sort last, in both directions,
    /// so switching direction can't fast-forward "never read"/"never
    /// updated" entries to the very top ahead of real recent activity.
    private static func compareDates(_ lhs: Date?, _ rhs: Date?, lhsID: String, rhsID: String, descending: Bool) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs:
            return descending ? lhs > rhs : lhs < rhs
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

    /// Manga has no forum metadata, so its sort key falls back to the clean
    /// book name directly rather than `sourceGroupLabel`, which shows the
    /// fixed "智能漫画" category text and would collapse every manga card
    /// into one bucket.
    private static func sourceGroupSortKey(for card: FavoriteCardProjection) -> String {
        if let forumName = card.item.forumName {
            return forumName
        }
        if let forumID = card.item.forumID {
            return forumID
        }
        if let cleanBookName = card.item.target.mangaCleanBookName {
            return cleanBookName
        }
        return card.sourceGroupLabel
    }

    private static func label(for sourceGroup: FavoriteSourceGroup) -> String {
        switch sourceGroup {
        case let .forumBoard(_, label):
            label
        case .mangaTitle:
            L10n.string("favorites.filter.manga")
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

    /// Fallback lookup for manga progress by book title: the favorite item's
    /// mangaID and the live progress record's mangaID are computed
    /// independently (different ID schemes) and drift apart, but both
    /// reliably carry the same cleanBookName. Picks the most recently
    /// updated record per title.
    private static func mangaReadingProgressLookup(_ records: [ReadingProgressRecord]) -> [String: ReadingProgressRecord] {
        var result: [String: ReadingProgressRecord] = [:]
        for record in records {
            guard record.kind == .manga, let cleanBookName = record.contentTarget?.mangaCleanBookName else { continue }
            if let existing = result[cleanBookName], existing.updatedAt >= record.updatedAt {
                continue
            }
            result[cleanBookName] = record
        }
        return result
    }

    private static func progressKey(for item: FavoriteItem) -> String {
        item.target.id
    }
}
