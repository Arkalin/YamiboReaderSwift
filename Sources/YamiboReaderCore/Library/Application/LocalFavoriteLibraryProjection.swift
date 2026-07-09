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
        if item.target.kind == .mangaThread {
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
            item.target.kind == .mangaThread
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

    /// Non-nil only when `item.target` (a `.mangaThread` favorite) resolved
    /// to a `MangaDirectory` — i.e. its board currently has Smart Comic Mode
    /// on (smart-comic-mode decision #5's 2026-07-08 addendum) and the
    /// chapter tid was found in a locally-known directory. Set regardless of
    /// whether any *other* favorite shares this directory yet: it backs the
    /// directory-level ("third level") progress match (decision #14) and is
    /// the identity a later phase's open handler / cover backfill should key
    /// off, independent of `mergedMembers`/`isMergedGroup`.
    ///
    /// `item.title`/`item.displayName` are deliberately left as `item`'s own
    /// (the representative member's real post title) rather than overwritten
    /// with `mangaDirectory?.cleanBookName` — `item` stays a genuine,
    /// individually valid `FavoriteItem` so any single-item affordance that
    /// still reads it directly keeps working. UI that wants the manga's own
    /// title for a resolved-directory card should prefer
    /// `mangaDirectory?.cleanBookName` over `item.resolvedDisplayTitle`.
    public var mangaDirectory: MangaDirectory? = nil

    /// Every `.mangaThread` favorite this card actually merges display for —
    /// non-nil (and always 2+ items) only once at least one *other*
    /// favorite shares `mangaDirectory` with `item`. `item` is always one of
    /// these members (the earliest-chapter one, chosen deterministically —
    /// see `LocalFavoriteLibraryProjection`'s grouping). `nil` here — even
    /// when `mangaDirectory` is set — means this card is still visually a
    /// lone favorite; a merge-badge/unfavorite-all confirmation should gate
    /// on this, not on `mangaDirectory` alone.
    public var mergedMembers: [FavoriteItem]? = nil

    public var isMergedGroup: Bool { mergedMembers != nil }

    /// Deliberately still `item.id` — the representative member's own real
    /// id — even for a merged card, *not* a synthetic directory-based id.
    /// The existing (unmodified by this phase) selection/bulk-action UI
    /// already reads `card.id` as a real `FavoriteItem.id` to look items up
    /// in `document.items` (`LocalFavoriteGridCard`/`LocalFavoriteListContent`
    /// pass `card.id` straight into `selection.toggleFavoriteSelection`,
    /// and `FavoriteLibraryOrganizer`'s bulk actions filter
    /// `document.items` by `favoriteIDs.contains($0.id)`) — a made-up id
    /// with no matching item would make a merged card's selection silently
    /// unpickable (pruned by `LocalFavoriteBrowseSession.prune` on the very
    /// next derive, since it'd never appear in `validFavoriteIDs`) with no
    /// corresponding Phase F work having happened yet to handle that. The
    /// cost is that this id can change if a new, earlier-chapter favorite
    /// later joins the group and displaces the current representative
    /// member — an occasional SwiftUI identity churn, not a correctness bug.
    public var id: String { item.id }
}

/// One `MangaDirectory` with every mode-on `.mangaThread` favorite currently
/// resolved to it — the same grouping `FavoriteCardProjection`'s merged
/// cards are built from, exposed standalone for callers (cover backfill)
/// that need the raw group rather than a display card.
public struct MangaDirectoryFavoriteGroup: Equatable, Sendable {
    public var directory: MangaDirectory
    /// Ordered to match `directory.chapters` (earliest first); `.first` is
    /// the earliest-chapter favorite, used as the cover-backfill anchor.
    public var members: [FavoriteItem]
}

public enum LocalFavoriteLibraryProjection {
    public static var supportedSortOrders: [LocalFavoriteLibrarySortOrder] {
        LocalFavoriteLibrarySortOrder.allCases
    }

    public static func cards(
        in document: FavoriteLibraryDocument,
        query: LocalFavoriteLibraryQuery = LocalFavoriteLibraryQuery(),
        readingProgress: [ReadingProgressRecord] = [],
        // Both default to "nothing resolved locally yet" so every existing
        // caller (in particular the whole pre-Phase-E test suite) keeps
        // building exclusively standalone cards without passing anything
        // new — `groupedCardEntries` short-circuits to "everything
        // standalone" whenever `mangaDirectoriesByTID` is empty, before ever
        // consulting `smartComicModeSettings`.
        mangaDirectoriesByTID: [String: MangaDirectory] = [:],
        smartComicModeSettings: SmartComicModeSettings = SmartComicModeSettings()
    ) -> [FavoriteCardProjection] {
        let categoryID = query.categoryID ?? document.defaultCategory.id
        let progressByKey = readingProgressLookup(readingProgress)
        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Grouping runs over the *entire* unfiltered item list (smart-comic-
        // mode decision #5: a merged card's membership/scope is global,
        // independent of which category/collection the query is currently
        // looking at) — only after grouping do category/collection/source/
        // tag filters apply, to the resulting entries' *union* locations/
        // tags rather than any one member's own.
        let entries = groupedCardEntries(
            for: document.items,
            mangaDirectoriesByTID: mangaDirectoriesByTID,
            smartComicModeSettings: smartComicModeSettings
        )

        let cards = entries
            .filter { entry in
                if let collectionID = query.collectionID {
                    return entry.representativeItem.locations.contains(.collection(categoryID: categoryID, collectionID: collectionID))
                }
                return entry.representativeItem.locations.contains(.category(categoryID))
            }
            .filter { entry in
                query.selectedSourceFilters.isEmpty
                    || query.selectedSourceFilters.contains { $0.matches(entry.representativeItem) }
            }
            .filter { entry in
                query.selectedTagIDs.isEmpty || query.selectedTagIDs.isSubset(of: Set(entry.representativeItem.tagIDs))
            }
            .map { entry -> FavoriteCardProjection in
                let resolvedProgress = progress(for: entry, progressByKey: progressByKey)
                return card(for: entry, document: document, progress: resolvedProgress)
            }
            .filter { card in
                guard !trimmedSearch.isEmpty else { return true }
                return searchFields(for: card).contains { field in
                    field.localizedCaseInsensitiveContains(trimmedSearch)
                }
            }

        return sorted(cards, by: query.sortOrder, descending: query.sortsDescending)
    }

    /// Every mode-on `.mangaThread` favorite resolved to a `MangaDirectory`,
    /// grouped by that directory (smart-comic-mode decision #13's cover
    /// backfill trigger). Includes groups of exactly one favorite — a lone
    /// resolved-directory favorite still needs its `.smartManga` cover
    /// resolved even before any sibling favorite joins it into a visible
    /// merge — so this is deliberately *not* filtered down to `count >= 2`
    /// the way `FavoriteCardProjection.mergedMembers` is.
    public static func mangaDirectoryGroups(
        for items: [FavoriteItem],
        mangaDirectoriesByTID: [String: MangaDirectory],
        smartComicModeSettings: SmartComicModeSettings
    ) -> [MangaDirectoryFavoriteGroup] {
        rawGroupedFavorites(
            for: items,
            mangaDirectoriesByTID: mangaDirectoriesByTID,
            smartComicModeSettings: smartComicModeSettings
        ).groups.map { raw in
            MangaDirectoryFavoriteGroup(directory: raw.directory, members: raw.members)
        }
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
        readingProgress: [ReadingProgressRecord] = [],
        mangaDirectoriesByTID: [String: MangaDirectory] = [:],
        smartComicModeSettings: SmartComicModeSettings = SmartComicModeSettings()
    ) -> Int {
        cards(
            in: document,
            query: query,
            readingProgress: readingProgress,
            mangaDirectoriesByTID: mangaDirectoriesByTID,
            smartComicModeSettings: smartComicModeSettings
        ).count
    }

    // MARK: - Virtual merged-directory grouping (smart-comic-mode decision #3/#5)

    /// One resolved-and-possibly-merged card's worth of pre-card data: either
    /// a standalone favorite untouched (`members == nil`, `mangaDirectory ==
    /// nil`) or a directory-resolved `.mangaThread` favorite/group with its
    /// representative item's `locations`/`tagIDs` already rewritten to the
    /// *union* across every member (decision #5: a merged card appears in
    /// every location any member belongs to). Never persisted — this only
    /// ever backs a display card for the current `cards(...)` call.
    private struct GroupedFavoriteEntry {
        var representativeItem: FavoriteItem
        var members: [FavoriteItem]?
        var mangaDirectory: MangaDirectory?
    }

    private struct RawMangaDirectoryGroup {
        var directory: MangaDirectory
        var members: [FavoriteItem]
    }

    /// Partitions `items` into favorites that stay standalone and favorites
    /// resolved to a shared `MangaDirectory`, using the *explicit*
    /// `SmartComicModeSettings.isEnabled(forumID:)` check — not any proxy
    /// signal (`directoryName != nil`, `cleanBookName.isEmpty`, etc. — see
    /// the design doc's three prior same-class bugs) — as the sole
    /// mode-on/off gate. This is the cheap in-memory pre-filter the design
    /// doc's performance constraint #1 calls for: only mode-on `.mangaThread`
    /// items with a resolved directory even reach the grouping dictionaries
    /// below; everything else is appended to `standalone` without touching
    /// `mangaDirectoriesByTID` again.
    private static func rawGroupedFavorites(
        for items: [FavoriteItem],
        mangaDirectoriesByTID: [String: MangaDirectory],
        smartComicModeSettings: SmartComicModeSettings
    ) -> (standalone: [FavoriteItem], groups: [RawMangaDirectoryGroup]) {
        guard !mangaDirectoriesByTID.isEmpty else {
            return (items, [])
        }

        var standalone: [FavoriteItem] = []
        var membersByDirectoryID: [String: [FavoriteItem]] = [:]
        var directoryByID: [String: MangaDirectory] = [:]

        for item in items {
            guard item.target.kind == .mangaThread,
                  let threadID = item.target.threadID,
                  smartComicModeSettings.isEnabled(forumID: item.forumID),
                  let directory = mangaDirectoriesByTID[threadID] else {
                standalone.append(item)
                continue
            }
            directoryByID[directory.id] = directory
            membersByDirectoryID[directory.id, default: []].append(item)
        }

        let groups = membersByDirectoryID.compactMap { directoryID, members -> RawMangaDirectoryGroup? in
            guard let directory = directoryByID[directoryID] else { return nil }
            return RawMangaDirectoryGroup(directory: directory, members: orderedByChapter(members, in: directory))
        }
        return (standalone, groups)
    }

    /// Orders `members` to match `directory.chapters` (earliest chapter
    /// first). Every member's own tid is guaranteed present in
    /// `directory.chapters` by construction — `mangaDirectoriesByTID` only
    /// ever resolves a directory whose chapter list contains that tid — so
    /// `members` and the ordered result should always be the same length;
    /// the equal-length check is a defensive fallback only, so a stale/edited
    /// directory can never silently drop a favorite from its own card.
    private static func orderedByChapter(_ members: [FavoriteItem], in directory: MangaDirectory) -> [FavoriteItem] {
        let membersByThreadID = Dictionary(uniqueKeysWithValues: members.compactMap { item -> (String, FavoriteItem)? in
            guard let threadID = item.target.threadID else { return nil }
            return (threadID, item)
        })
        let ordered = directory.chapters.compactMap { membersByThreadID[$0.tid] }
        return ordered.count == members.count ? ordered : members
    }

    private static func groupedCardEntries(
        for items: [FavoriteItem],
        mangaDirectoriesByTID: [String: MangaDirectory],
        smartComicModeSettings: SmartComicModeSettings
    ) -> [GroupedFavoriteEntry] {
        let raw = rawGroupedFavorites(
            for: items,
            mangaDirectoriesByTID: mangaDirectoriesByTID,
            smartComicModeSettings: smartComicModeSettings
        )
        let standaloneEntries = raw.standalone.map {
            GroupedFavoriteEntry(representativeItem: $0, members: nil, mangaDirectory: nil)
        }
        let resolvedEntries = raw.groups.map(cardEntry(for:))
        return standaloneEntries + resolvedEntries
    }

    /// Builds one display entry from a raw directory group: the
    /// earliest-chapter member becomes `representativeItem` (a deterministic,
    /// reload-stable choice — also the anchor cover backfill resolves from),
    /// its `locations`/`tagIDs` rewritten in place to the union across every
    /// member. `members` on the result is nil (not a 1-element array) when
    /// the group has exactly one favorite, matching `mergedMembers`'s "only
    /// non-nil for an actual merge" contract.
    private static func cardEntry(for group: RawMangaDirectoryGroup) -> GroupedFavoriteEntry {
        let members = group.members
        // `rawGroupedFavorites` only ever creates a `membersByDirectoryID`
        // entry by appending to it, so every group it produces has at least
        // one member — this can never actually fire.
        precondition(!members.isEmpty, "RawMangaDirectoryGroup must have at least one member")
        var representative = members[0]
        var unionLocations: [FavoriteLocation] = []
        var seenLocationIDs: Set<String> = []
        var unionTagIDs: [String] = []
        var seenTagIDs: Set<String> = []
        for member in members {
            for location in member.locations where seenLocationIDs.insert(location.id).inserted {
                unionLocations.append(location)
            }
            for tagID in member.tagIDs where seenTagIDs.insert(tagID).inserted {
                unionTagIDs.append(tagID)
            }
        }
        representative.locations = FavoriteItem.normalizedLocations(unionLocations)
        representative.tagIDs = FavoriteItem.normalizedIDs(unionTagIDs)

        return GroupedFavoriteEntry(
            representativeItem: representative,
            members: members.count > 1 ? members : nil,
            mangaDirectory: group.directory
        )
    }

    /// Progress third-level match (design decision #14): a directory-resolved
    /// entry (merged or a lone favorite alike) prefers the directory-level
    /// `.mangaTitle` reading-progress record — the same record decision #7's
    /// mode-on resume path reads via `LocalFavoriteOpenTargetResolver` — over
    /// its representative member's own per-thread `.mangaThread` record,
    /// since the whole point is showing the manga's current position rather
    /// than whichever specific chapter happens to be the earliest one
    /// favorited. Falls back to the direct id match only when the directory
    /// has no progress record of its own yet (e.g. resolved via sync/cover
    /// backfill but never actually opened locally).
    private static func progress(
        for entry: GroupedFavoriteEntry,
        progressByKey: [String: ReadingProgressRecord]
    ) -> ReadingProgressRecord? {
        if let directory = entry.mangaDirectory,
           let directoryProgress = progressByKey[directoryProgressKey(for: directory)] {
            return directoryProgress
        }
        return progressByKey[progressKey(for: entry.representativeItem)]
    }

    private static func directoryProgressKey(for directory: MangaDirectory) -> String {
        FavoriteContentTarget(mangaID: directory.favoriteIdentity, mangaCleanBookName: directory.cleanBookName).id
    }

    private static func card(
        for entry: GroupedFavoriteEntry,
        document: FavoriteLibraryDocument,
        progress: ReadingProgressRecord?
    ) -> FavoriteCardProjection {
        let item = entry.representativeItem
        return FavoriteCardProjection(
            item: item,
            sourceGroupLabel: label(for: item.sourceGroup),
            collectionNames: collectionNames(for: item, in: document),
            tags: tags(for: item, in: document),
            recentReadingAt: progress?.lastReadAt,
            // A merged card's "content updated" proxy is the freshest of any
            // member's own content update, not just the representative
            // (earliest-chapter) member's — otherwise a manga that just got a
            // brand-new favorited chapter wouldn't visibly bubble up under
            // the "recently updated" sort.
            lastUpdatedAt: entry.members?.compactMap(\.contentUpdatedAt).max() ?? item.contentUpdatedAt,
            progressPercent: progressPercent(from: progress),
            chapterPageProgress: chapterPageProgress(from: progress),
            // Filled from ContentCoverStore by the library derivation; items
            // deliberately carry no cover of their own.
            coverURL: nil,
            mangaDirectory: entry.mangaDirectory,
            mergedMembers: entry.members
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
        var fields = [
            card.item.displayName,
            card.item.title,
            card.sourceGroupLabel
        ].compactMap(\.self) + card.tags.map(\.name)
        // A resolved-directory card's `item.title` is deliberately still its
        // representative member's own post title (see `FavoriteCardProjection
        // .mangaDirectory`'s doc comment), so without this the manga's own
        // name would never be searchable — only whichever specific chapter
        // happened to become the representative. Merged members' own titles
        // are included too so searching by a *specific* favorited chapter's
        // title still finds the merged card it belongs to.
        if let mangaDirectory = card.mangaDirectory {
            fields.append(mangaDirectory.cleanBookName)
        }
        if let members = card.mergedMembers {
            fields += members.map(\.title)
            fields += members.compactMap(\.displayName)
        }
        return fields
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

    /// `.mangaThread` favorites are plain per-thread favorites of one of the
    /// three manga forums now (smart-comic-mode design decision #4), so they
    /// carry real forum metadata just like any other thread; this falls back
    /// to the source group label only if that metadata is somehow missing.
    private static func sourceGroupSortKey(for card: FavoriteCardProjection) -> String {
        if let forumName = card.item.forumName {
            return forumName
        }
        if let forumID = card.item.forumID {
            return forumID
        }
        return card.sourceGroupLabel
    }

    private static func label(for sourceGroup: FavoriteSourceGroup) -> String {
        switch sourceGroup {
        case let .forumBoard(_, label):
            label
        case .smartManga:
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

    private static func progressKey(for item: FavoriteItem) -> String {
        item.target.id
    }
}
