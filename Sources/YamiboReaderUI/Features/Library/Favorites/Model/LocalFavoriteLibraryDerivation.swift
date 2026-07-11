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

/// One slot of a collection's 4-tile preview mosaic: a member's own cover
/// (when it has one) or its own title for a text-fallback tile — never
/// silently dropped just because it has no image. A mode-on `.mangaThread`
/// favorite resolved to an actual `MangaDirectory` does NOT get its own slot
/// per favorited chapter: every member of the same virtual merged smart-card
/// group (smart-comic-mode decision #5) collapses into a single tile sharing
/// that group's title/cover, exactly matching how the group displays as one
/// card in the main list. A mode-on favorite with no resolved directory yet
/// (the local-clean-fallback case) still keeps its own individual slot even
/// if another favorite happens to guess the same cleaned title — the main
/// card list itself only merges on an actually-resolved directory
/// (`LocalFavoriteLibraryProjection.rawGroupedFavorites`), never on a
/// same-guess coincidence alone, and this mosaic must not summarize the
/// collection as more merged than its own card list actually shows.
/// `LocalFavoriteLibraryDerivation.collectionPreviewTiles(_:mangaThreadItemsByEffectiveTitle:)`
/// is what performs the resolved-directory collapsing.
struct LocalFavoriteCollectionPreviewTile: Equatable {
    let coverURL: URL?
    let title: String
}

/// Everything the favorites UI renders that is computed from the library
/// document plus filter state. Produced only by `LocalFavoriteLibraryDerivation`.
struct LocalFavoriteDerivedState: Equatable {
    var cards: [FavoriteCardProjection] = []
    var visibleCollections: [LocalFavoriteCollection] = []
    /// Collections and cards merged into the order the list/grid renders —
    /// collections pinned first only in manual sort order, interleaved with
    /// cards under every other sort order (see
    /// `LocalFavoriteLibraryProjection.mixedEntries`).
    var mixedEntries: [FavoriteMixedEntry] = []
    var categoryEntryCounts: [String: Int] = [:]
    var collectionEntryCounts: [String: Int] = [:]
    var sourceFilterEntryCounts: [LocalFavoriteSourceFilter: Int] = [:]
    /// Up to four preview tiles per visible collection for the preview
    /// mosaic, resolved from the collection's own members (not the filtered
    /// cards).
    var collectionPreviewTiles: [String: [LocalFavoriteCollectionPreviewTile]] = [:]
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
        /// Resolved cover URLs for every row a visible card can display,
        /// keyed by the SAME `ContentCoverKey` each card's own
        /// `contentCoverKey` resolves: per-favorite `.thread(tid:)` entries
        /// plus `.smartManga(cleanBookName:)` entries for resolved
        /// directories (smart-comic-mode decision #13/#16). One keyspace so
        /// a card's display lookup and its cover-action writes
        /// (`FavoriteLibraryOrganizer.toggleTextCover`) can never disagree
        /// about which row the card means.
        var coverURLsByKey: [ContentCoverKey: URL]
        /// Keys whose stored cover has `textCoverForced` set — same keyspace
        /// as `coverURLsByKey` (a forced key also resolves no URL there; the
        /// flag is surfaced separately so the card's context menu can offer
        /// "使用图片封面" instead of "使用文字封面").
        var textCoverForcedKeys: Set<ContentCoverKey>
        /// tid → resolved `MangaDirectory`, computed once at
        /// `FavoriteLibraryOrganizer.load()`/`reload()` time (smart-comic-mode
        /// design doc's performance constraint #2) — never recomputed here.
        var mangaDirectoriesByTID: [String: MangaDirectory] = [:]
        /// Snapshot of the per-board reader configuration taken at the same
        /// load/reload time as `mangaDirectoriesByTID`, so grouping and the
        /// settings it was computed against never disagree mid-derivation.
        var boardReaderSettings: BoardReaderSettings = BoardReaderSettings()
        /// Non-nil only while a merged smart-comic card's "查看归档收藏" detail
        /// page is open — threaded straight into the `cards` query as
        /// `LocalFavoriteLibraryQuery.memberScopeCleanBookName`. Deliberately
        /// left `nil` for `rootDerived`'s own `Inputs` (see
        /// `FavoriteLibraryOrganizer.refreshDerivedState()`), the same way
        /// `rootDerived` already forces `selectedCollectionID` to `nil`, so
        /// the root screen never narrows to this scope.
        var memberScopeCleanBookName: String? = nil
    }

    static func derive(_ inputs: Inputs) -> LocalFavoriteDerivedState {
        // Computed once per `derive(_:)` call and threaded into every one of
        // this single derive's several internal `resolvedCards` calls (the
        // main call below, plus `categoryEntryCounts`'s per-category call,
        // `collectionAggregates`'s per-collection call, and
        // `sourceFilterEntryCounts`'s call) — without this, each of those
        // calls would independently rebuild the same grouping from
        // `inputs.document.items`, and `LocalFavoriteLibraryProjection
        // .cards(...)` would additionally rebuild it once per smart card on
        // top of that. Always freshly computed here, at the top of every
        // `derive(_:)` call, from the CURRENT `inputs.document.items` — never
        // hoisted up into `FavoriteLibraryOrganizer` or cached across
        // separate `derive(_:)` calls, since `document.items` can change on
        // every commit.
        let mangaThreadItemsByEffectiveTitle = LocalFavoriteLibraryProjection.mangaThreadItemsByEffectiveTitle(
            in: inputs.document.items,
            mangaDirectoriesByTID: inputs.mangaDirectoriesByTID,
            boardReaderSettings: inputs.boardReaderSettings
        )
        let cards = resolvedCards(
            in: inputs.document,
            query: LocalFavoriteLibraryQuery(
                categoryID: inputs.selectedCategoryID,
                collectionID: inputs.selectedCollectionID,
                selectedSourceFilters: inputs.filter.selectedSourceFilters,
                selectedTagIDs: inputs.filter.selectedTagIDs,
                sortOrder: inputs.filter.sortOrder,
                sortsDescending: inputs.filter.sortDescending,
                searchText: inputs.filter.searchText,
                memberScopeCleanBookName: inputs.memberScopeCleanBookName
            ),
            inputs: inputs,
            mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle
        )
        let aggregates = collectionAggregates(inputs, mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle)
        let collectionCounts = aggregates.mapValues(\.entryCount)
        let collections = visibleCollections(
            in: inputs.document,
            categoryID: inputs.selectedCategoryID,
            filter: inputs.filter,
            collectionEntryCounts: collectionCounts
        )
        return LocalFavoriteDerivedState(
            cards: cards,
            visibleCollections: collections,
            mixedEntries: LocalFavoriteLibraryProjection.mixedEntries(
                cards: cards,
                // No nested collections in the domain model: a collection's
                // own detail page — or a merged smart card's "查看归档收藏"
                // archive detail page — never shows sibling collections.
                // Gating on `selectedCollectionID` alone missed the archive
                // page's common case of being opened directly from the root
                // list (where `selectedCollectionID` stays `nil`), which let
                // the current category's collections leak into the archive
                // page's content.
                collections: (inputs.selectedCollectionID == nil && inputs.memberScopeCleanBookName == nil)
                    ? collections
                    : [],
                collectionSummaries: aggregates.mapValues(\.sortSummary),
                sortOrder: inputs.filter.sortOrder,
                descending: inputs.filter.sortDescending
            ),
            categoryEntryCounts: categoryEntryCounts(
                inputs,
                collectionEntryCounts: collectionCounts,
                mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle
            ),
            collectionEntryCounts: collectionCounts,
            sourceFilterEntryCounts: sourceFilterEntryCounts(inputs, mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle),
            collectionPreviewTiles: collectionPreviewTiles(inputs, mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle)
        )
    }

    // MARK: - Cards

    private static func resolvedCards(
        in document: FavoriteLibraryDocument,
        query: LocalFavoriteLibraryQuery,
        inputs: Inputs,
        mangaThreadItemsByEffectiveTitle: [String: [FavoriteItem]]
    ) -> [FavoriteCardProjection] {
        LocalFavoriteLibraryProjection.cards(
            in: document,
            query: query,
            readingProgress: inputs.readingProgress,
            mangaDirectoriesByTID: inputs.mangaDirectoriesByTID,
            boardReaderSettings: inputs.boardReaderSettings,
            mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle
        )
        .map { card in
            var card = card
            // `contentCoverKey` picks the row this card actually displays —
            // the directory's shared `.smartManga` key for a resolved-
            // directory card (merged or a lone favorite that simply hasn't
            // been joined by a sibling yet, smart-comic-mode decision
            // #13/#16), the favorite's own `.thread` key otherwise. Reading
            // the URL and the text-cover flag through that same key keeps
            // them consistent with each other and with
            // `FavoriteLibraryOrganizer.toggleTextCover`, which writes
            // through this exact property.
            if let key = card.contentCoverKey {
                card.coverURL = inputs.coverURLsByKey[key]
                card.textCoverForced = inputs.textCoverForcedKeys.contains(key)
            }
            return card
        }
    }

    // MARK: - Counts

    private static func categoryEntryCounts(
        _ inputs: Inputs,
        collectionEntryCounts: [String: Int],
        mangaThreadItemsByEffectiveTitle: [String: [FavoriteItem]]
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
                inputs: inputs,
                mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle
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

    private struct CollectionAggregate {
        var entryCount: Int
        var sortSummary: FavoriteCollectionSortSummary
    }

    private static func collectionAggregates(
        _ inputs: Inputs,
        mangaThreadItemsByEffectiveTitle: [String: [FavoriteItem]]
    ) -> [String: CollectionAggregate] {
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
                inputs: inputs,
                mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle
            )
            return (collection.id, CollectionAggregate(entryCount: cards.count, sortSummary: .summarizing(cards)))
        })
    }

    /// One preview-tile candidate before the final sort/take-4 — kept as a
    /// small file-scope struct (mirroring `CollectionAggregate` above) rather
    /// than a plain tuple purely for the named fields' readability.
    private struct CollectionPreviewCandidate {
        var sortDate: Date
        var coverURL: URL?
        var title: String
    }

    private static func collectionPreviewTiles(
        _ inputs: Inputs,
        mangaThreadItemsByEffectiveTitle: [String: [FavoriteItem]]
    ) -> [String: [LocalFavoriteCollectionPreviewTile]] {
        Dictionary(uniqueKeysWithValues: inputs.document.collections.map { collection in
            let location = FavoriteLocation.collection(categoryID: collection.categoryID, collectionID: collection.id)
            let members = inputs.document.items.filter { $0.locations.contains(location) }

            // Every member gets a tile — image-backed when a cover resolves,
            // otherwise its own title for a text-fallback tile — EXCEPT a
            // mode-on `.mangaThread` favorite resolved to an actual
            // `MangaDirectory`, which collapses with every other member of
            // its virtual merged smart-card group (smart-comic-mode decision
            // #5) into a single shared tile, matching how the main card list
            // already shows that manga as one card. A mode-on favorite with
            // no resolved directory yet keeps its own tile even if another
            // favorite guesses the same cleaned title — see
            // `LocalFavoriteCollectionPreviewTile`'s own doc comment for why
            // (the main list itself only merges on a resolved directory).
            // Non-manga members and mode-off manga favorites must not be
            // silently dropped here, or the mosaic shows fewer/blank tiles
            // instead of that member's text cover.
            var candidates: [CollectionPreviewCandidate] = []
            var seenEffectiveTitles: Set<String> = []
            for item in members {
                let isModeOnMangaThread = item.target.kind == .mangaThread
                    && inputs.boardReaderSettings.isSmartComicModeEnabled(forumID: item.forumID)
                guard isModeOnMangaThread else {
                    candidates.append(CollectionPreviewCandidate(
                        sortDate: item.updatedAt,
                        coverURL: ContentCoverKey(target: item.target).flatMap { inputs.coverURLsByKey[$0] },
                        title: item.resolvedDisplayTitle
                    ))
                    continue
                }

                let mangaDirectory = inputs.mangaDirectoriesByTID[item.target.threadID ?? ""]
                let effectiveTitle = FavoriteCardProjection.resolvedTitle(
                    item: item,
                    mangaDirectory: mangaDirectory,
                    isModeOnMangaThread: true
                )
                guard let mangaDirectory else {
                    // No resolved `MangaDirectory` yet — the main card list
                    // itself does not merge two such favorites just because
                    // they happen to guess the same locally-cleaned title
                    // (`LocalFavoriteLibraryProjection.rawGroupedFavorites`
                    // only forms a group once a real directory has resolved;
                    // an unresolved favorite always stays `standalone`
                    // there). This tile must not merge more aggressively
                    // than the card list it's summarizing, so each
                    // unresolved favorite keeps its own tile — its own
                    // locally-cleaned title, its own per-thread cover.
                    candidates.append(CollectionPreviewCandidate(
                        sortDate: item.updatedAt,
                        coverURL: ContentCoverKey(target: item.target).flatMap { inputs.coverURLsByKey[$0] },
                        title: effectiveTitle
                    ))
                    continue
                }

                // A second/third member of the same resolved-directory group
                // already produced this group's one tile — skip, rather than
                // adding another.
                guard seenEffectiveTitles.insert(effectiveTitle).inserted else { continue }

                // The group's full membership (possibly reaching beyond this
                // collection — decision #5: a merged group is global) decides
                // recency and cover, so the tile is consistent regardless of
                // which collection it's viewed from — mirrors `card(for:)`'s
                // own "freshest of any member" logic, just keyed on
                // `updatedAt` since that's what this function sorts by.
                let groupMembers = mangaThreadItemsByEffectiveTitle[effectiveTitle] ?? [item]
                let sortDate = groupMembers.map(\.updatedAt).max() ?? item.updatedAt
                let coverURL = inputs.coverURLsByKey[.smartManga(cleanBookName: mangaDirectory.cleanBookName)]
                candidates.append(CollectionPreviewCandidate(sortDate: sortDate, coverURL: coverURL, title: effectiveTitle))
            }

            let tiles = candidates
                .sorted { $0.sortDate > $1.sortDate }
                .prefix(4)
                .map { LocalFavoriteCollectionPreviewTile(coverURL: $0.coverURL, title: $0.title) }
            return (collection.id, Array(tiles))
        })
    }

    private static func sourceFilterEntryCounts(
        _ inputs: Inputs,
        mangaThreadItemsByEffectiveTitle: [String: [FavoriteItem]]
    ) -> [LocalFavoriteSourceFilter: Int] {
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
            inputs: inputs,
            mangaThreadItemsByEffectiveTitle: mangaThreadItemsByEffectiveTitle
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
