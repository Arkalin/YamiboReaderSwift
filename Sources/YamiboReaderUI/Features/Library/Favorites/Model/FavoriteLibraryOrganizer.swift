import Foundation
import YamiboReaderCore

enum CategoryMoveDirection: Sendable {
    case up
    case down
}

enum LocalFavoriteDeleteScope: Equatable {
    case currentLocation
    case everywhere
}

/// Pending "also delete from Yamibo?" question raised by a favorites-page
/// delete-everywhere action — the same second decision the quick-action
/// remove flow models with `FavoriteRemovePrompt`, kept as its own type
/// because the subject here is an item or the whole selection, not a
/// `Favorite`.
struct LocalFavoriteRemoveRemotePrompt: Identifiable, Equatable {
    enum Subject: Equatable {
        case item(FavoriteItem)
        case selection
    }

    let subject: Subject

    var id: String {
        switch subject {
        case let .item(item):
            "item-\(item.id)"
        case .selection:
            "selection"
        }
    }
}

/// Coordinates the local favorite library document: category, collection, tag
/// and item organization, navigation state, and filter-driven derivation of
/// the rendered cards.
///
/// All document mutations funnel through `commit`, and all derived output
/// (cards, counts, visible collections) is recomputed exclusively by
/// `refreshDerivedState()` whenever an input changes.
@MainActor
final class FavoriteLibraryOrganizer: ObservableObject {
    @Published private(set) var document = FavoriteLibraryDocument() {
        didSet { refreshDerivedState() }
    }
    @Published var selectedCategoryID = FavoriteCategory.defaultID {
        didSet {
            selection.clearSelection()
            if let selectedCollectionID,
               !document.collections.contains(where: { $0.id == selectedCollectionID && $0.categoryID == selectedCategoryID }) {
                self.selectedCollectionID = nil
            }
            refreshDerivedState()
            persistNavigationState()
        }
    }
    @Published private(set) var selectedCollectionID: String? {
        didSet {
            selection.clearSelection()
            refreshDerivedState()
            persistNavigationState()
        }
    }
    /// Non-nil while a smart-comic card's "查看归档收藏" detail page is open —
    /// the effective title (`FavoriteCardProjection.resolvedTitle`) every
    /// member on that page currently resolves to. Despite the property's
    /// name this is not always an actually-resolved `MangaDirectory`'s
    /// `cleanBookName` — it can equally be a locally-guessed clean title for
    /// a still-unresolved favorite (see `resolvedTitle`'s doc comment).
    /// Mirrors `selectedCollectionID`'s own navigation-state shape but is
    /// deliberately not persisted through `SettingsStore` (see
    /// `persistNavigationState()`): this scope is a live identity, not
    /// durable navigation state worth restoring across launches.
    @Published private(set) var selectedMergedGroupCleanBookName: String? = nil {
        didSet {
            selection.clearSelection()
            refreshDerivedState()
        }
    }
    @Published var filter = LocalFavoriteFilterState() {
        didSet {
            guard filter != oldValue else { return }
            refreshDerivedState()
        }
    }
    @Published private(set) var derived = LocalFavoriteDerivedState()
    /// `derived` scoped as if no collection were open, regardless of
    /// `selectedCollectionID`. The root favorites screen renders from this
    /// (never from `derived`) because `NavigationStack` keeps the root view
    /// mounted underneath a pushed collection detail page, and its stock
    /// interactive edge-swipe-back gesture reveals that root view mid-drag
    /// while `selectedCollectionID` is still set — reading the same
    /// collection-scoped `derived` there would show the collection page
    /// duplicated behind itself. See `LocalFavoritesOrganizationView`.
    @Published private(set) var rootDerived = LocalFavoriteDerivedState()
    @Published private(set) var display = FavoriteLibraryDisplayState()
    /// Backs `LocalFavoritesRootBackground` — only ever consumed by the root
    /// favorites screen (see `LocalFavoritesOrganizationView`), never by the
    /// pushed collection/merged-group detail pages.
    @Published private(set) var backgroundSettings = FavoriteBackgroundSettings()
    @Published private(set) var backgroundImageData: Data?
    @Published var errorMessage: String?
    /// Short-lived toast feedback (single-item sync results and similar).
    @Published var transientMessage: String?
    /// Non-nil while a delete-everywhere action waits for the user's "also
    /// delete from Yamibo?" answer (`removeRemotePromptEnabled`). The view
    /// renders it as a confirmation dialog; both confirm variants route back
    /// through `confirmRemoveRemotePrompt`, dismissal aborts the delete.
    @Published var removeRemotePrompt: LocalFavoriteRemoveRemotePrompt?

    /// Selection and search-mode session shared with the views.
    let selection = LocalFavoriteBrowseSession()

    private let libraryStore: FavoriteLibraryStore
    private let readingProgressStore: ReadingProgressStore
    private let settingsStore: SettingsStore
    private let contentCoverStore: ContentCoverStore
    private let mangaDirectoryStore: MangaDirectoryStore?
    private let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
    private let makeForumThreadReaderRepository: (@Sendable () async -> ForumThreadReaderRepository)?
    private let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    private let remoteDeleter: YamiboRemoteFavoriteDeleter

    private var readingProgress: [ReadingProgressRecord] = []
    /// Resolved cover URLs and text-cover-forced flags for everything the
    /// cards can display, keyed by the SAME `ContentCoverKey` each card's
    /// `contentCoverKey` resolves — per-favorite `.thread(tid:)` entries
    /// plus `.smartManga(cleanBookName:)` entries for resolved directories
    /// (decision #13/#16). A single keyspace shared with `toggleTextCover`'s
    /// write path, so the row a card displays and the row its cover actions
    /// touch are the same by construction (two parallel string-keyed maps
    /// here once let a smart card's text-cover toggle write a `.thread` row
    /// its own display never read).
    private var coverLookup = ContentCoverLookup()
    /// tid → resolved `MangaDirectory`, for virtual favorites grouping
    /// (smart-comic-mode decision #3/#5). Populated only at `load()`/
    /// `reload()` via one batched `MangaDirectoryStore.directories
    /// (containingTIDs:)` call — never recomputed per render (the design
    /// doc's performance constraint #2).
    private var mangaDirectoriesByTID: [String: MangaDirectory] = [:]
    /// Snapshot of the per-board reader configuration taken at the same
    /// load/reload as `mangaDirectoriesByTID`, so the two are always
    /// consistent with each other for a given derivation.
    private var boardReaderSettings = BoardReaderSettings()
    private var libraryUpdatesTask: Task<Void, Never>?
    private var progressUpdatesTask: Task<Void, Never>?
    private var coverUpdatesTask: Task<Void, Never>?
    private var settingsUpdatesTask: Task<Void, Never>?
    private var mangaDirectoryUpdatesTask: Task<Void, Never>?
    private var mangaCoverBackfillTask: Task<Void, Never>?
    private var attemptedMangaCoverTargetIDs: Set<String> = []

    init(
        libraryStore: FavoriteLibraryStore,
        readingProgressStore: ReadingProgressStore,
        settingsStore: SettingsStore,
        contentCoverStore: ContentCoverStore,
        favoriteBackgroundImageStore: FavoriteBackgroundImageStore,
        mangaDirectoryStore: MangaDirectoryStore? = nil,
        makeForumThreadReaderRepository: (@Sendable () async -> ForumThreadReaderRepository)? = nil,
        makeFavoriteRepository: @escaping @Sendable () async -> FavoriteRepository,
        remoteFavoriteDeleteHandler: (([FavoriteItem]) async throws -> Void)? = nil
    ) {
        self.libraryStore = libraryStore
        self.readingProgressStore = readingProgressStore
        self.settingsStore = settingsStore
        self.contentCoverStore = contentCoverStore
        self.favoriteBackgroundImageStore = favoriteBackgroundImageStore
        self.mangaDirectoryStore = mangaDirectoryStore
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.makeFavoriteRepository = makeFavoriteRepository
        remoteDeleter = YamiboRemoteFavoriteDeleter(
            makeFavoriteRepository: makeFavoriteRepository,
            overrideHandler: remoteFavoriteDeleteHandler
        )
        libraryUpdatesTask = Task { @MainActor [weak self, store = libraryStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteLibraryStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteLibraryStore.changeIDUserInfoKey] as? String,
                      changeID == store.changeID else {
                    continue
                }
                await self.reload()
            }
        }
        progressUpdatesTask = Task { @MainActor [weak self, store = readingProgressStore] in
            for await notification in NotificationCenter.default.notifications(named: ReadingProgressStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[ReadingProgressStore.changeIDUserInfoKey] as? String,
                      changeID == store.changeID else {
                    continue
                }
                await self.reloadReadingProgress()
            }
        }
        coverUpdatesTask = Task { @MainActor [weak self, store = contentCoverStore] in
            for await notification in NotificationCenter.default.notifications(named: ContentCoverStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[ContentCoverStore.changeIDUserInfoKey] as? String,
                      changeID == store.changeID else {
                    continue
                }
                await self.reloadContentCovers()
            }
        }
        // Without this, toggling the new Smart Comic Mode settings UI while
        // the Favorites tab is already loaded would leave the merged-card
        // grouping stale until some unrelated favorite/progress/cover change
        // happened to trigger a reload — the settings VALUE was always
        // modeled/consumed correctly, but nothing here reacted to it
        // changing live.
        settingsUpdatesTask = Task { @MainActor [weak self, store = settingsStore] in
            for await notification in NotificationCenter.default.notifications(named: SettingsStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[SettingsStore.changeIDUserInfoKey] as? String,
                      changeID == store.changeID else {
                    continue
                }
                await self.reloadBoardReaderSettings()
                await self.reloadFavoriteBackground()
            }
        }
        // Without this, renaming a manga directory from the manga reader's
        // directory page would leave an already-open Favorites tab showing
        // the old name/cover on a merged card until some unrelated
        // favorite/progress/cover/settings change happened to trigger a
        // full reload.
        if let mangaDirectoryStore {
            mangaDirectoryUpdatesTask = Task { @MainActor [weak self, store = mangaDirectoryStore] in
                for await notification in NotificationCenter.default.notifications(named: MangaDirectoryStore.didChangeNotification) {
                    guard !Task.isCancelled else { return }
                    guard let self else { return }
                    guard let changeID = notification.userInfo?[MangaDirectoryStore.changeIDUserInfoKey] as? String,
                          changeID == store.changeID else {
                        continue
                    }
                    await self.reloadMangaDirectories()
                }
            }
        }
    }

    deinit {
        libraryUpdatesTask?.cancel()
        progressUpdatesTask?.cancel()
        coverUpdatesTask?.cancel()
        settingsUpdatesTask?.cancel()
        mangaDirectoryUpdatesTask?.cancel()
        mangaCoverBackfillTask?.cancel()
    }

    // MARK: - Document access

    var categories: [FavoriteCategory] {
        document.categories
    }

    var collections: [LocalFavoriteCollection] {
        document.collections
    }

    var tags: [FavoriteTag] {
        document.tags.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    /// All favorite items, for tag-association-count sorting in the tag
    /// picker. Views go through the organizer's own surface rather than
    /// reaching into `document` directly.
    var favoriteItems: [FavoriteItem] {
        document.items
    }

    var currentCategoryCollections: [LocalFavoriteCollection] {
        document.collections
            .filter { $0.categoryID == selectedCategoryID }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }

    var selectedCollection: LocalFavoriteCollection? {
        guard let selectedCollectionID else { return nil }
        return document.collections.first { $0.id == selectedCollectionID }
    }

    var singleSelectedCollection: LocalFavoriteCollection? {
        guard selection.selectedCollectionIDs.count == 1,
              let id = selection.selectedCollectionIDs.first else { return nil }
        return document.collections.first { $0.id == id }
    }

    /// Whether the currently selected favorites can be removed from just this
    /// category or collection (they all remain reachable elsewhere).
    var selectedFavoritesCanRemoveCurrentLocation: Bool {
        guard selection.selectedCollectionCount == 0 else { return false }
        return derived.cards.contains { card in
            selection.selectedFavoriteIDs.contains(card.id) && card.item.locations.count > 1
        }
    }

    /// Tag IDs shared by every selected favorite; seed for bulk tag editing.
    var commonTagIDsForSelection: Set<String> {
        let selectedItems = derived.cards
            .map(\.item)
            .filter { selection.selectedFavoriteIDs.contains($0.id) }
        guard let first = selectedItems.first else { return [] }
        return selectedItems.dropFirst().reduce(Set(first.tagIDs)) { partialResult, item in
            partialResult.intersection(Set(item.tagIDs))
        }
    }

    // MARK: - Loading

    func load() async {
        readingProgress = await readingProgressStore.loadAll()
        let loadedDocument: FavoriteLibraryDocument
        do {
            loadedDocument = try await libraryStore.load()
        } catch {
            // Keep whatever the UI currently shows; an empty placeholder here
            // would read as "all favorites gone".
            errorMessage = error.localizedDescription
            return
        }
        let threadCovers = await loadContentCovers(for: loadedDocument.items)
        let settings = await settingsStore.load()
        boardReaderSettings = settings.boardReader
        mangaDirectoriesByTID = await resolveMangaDirectories(for: loadedDocument.items, boardReaderSettings: boardReaderSettings)
        coverLookup = threadCovers.merging(
            await smartMangaCoverLookup(for: Array(Set(mangaDirectoriesByTID.values)))
        )
        display = FavoriteLibraryDisplayState(
            layoutMode: settings.favorites.layoutMode,
            showsCategoryCounts: settings.favorites.showsCategoryCounts
        )
        await applyBackgroundSettings(settings.favorites.background)
        var restoredFilter = filter
        restoredFilter.sortOrder = settings.favorites.sortOrder
        restoredFilter.sortDescending = settings.favorites.sortDescending
        filter = restoredFilter
        document = loadedDocument
        let savedCollection = settings.favorites.selectedCollectionID.flatMap { savedID in
            loadedDocument.collections.first { $0.id == savedID }
        }
        if let savedCollection {
            selectedCategoryID = savedCollection.categoryID
        } else if let savedCategoryID = settings.favorites.selectedCategoryID,
                  loadedDocument.categories.contains(where: { $0.id == savedCategoryID }) {
            selectedCategoryID = savedCategoryID
        }
        if !loadedDocument.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = loadedDocument.defaultCategory.id
        }
        if let savedCollection, savedCollection.categoryID == selectedCategoryID {
            selectedCollectionID = savedCollection.id
        } else {
            selectedCollectionID = nil
        }
        scheduleMangaCoverBackfill(for: loadedDocument.items)
    }

    func reload() async {
        guard let loadedDocument = try? await libraryStore.load() else {
            // Transient read failure: keep the current document on screen and
            // let the next change notification retry.
            return
        }
        let threadCovers = await loadContentCovers(for: loadedDocument.items)
        // Only the Smart Comic Mode snapshot is refreshed here — unlike
        // `load()`, `reload()` deliberately never re-applies
        // `settings.favorites` (sort order/layout/etc.) so a background
        // reload triggered by an unrelated favorite/progress/cover change
        // can't clobber the sort order the user may have just changed live
        // in this session.
        let settings = await settingsStore.load()
        boardReaderSettings = settings.boardReader
        mangaDirectoriesByTID = await resolveMangaDirectories(for: loadedDocument.items, boardReaderSettings: boardReaderSettings)
        coverLookup = threadCovers.merging(
            await smartMangaCoverLookup(for: Array(Set(mangaDirectoriesByTID.values)))
        )
        document = loadedDocument
        if !loadedDocument.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = loadedDocument.defaultCategory.id
        }
        if let selectedCollectionID,
           !loadedDocument.collections.contains(where: { $0.id == selectedCollectionID && $0.categoryID == selectedCategoryID }) {
            self.selectedCollectionID = nil
        }
        // Tags removed by another device (WebDAV) must not linger as an
        // invisible active filter.
        let validTagIDs = Set(loadedDocument.tags.map(\.id))
        if !filter.selectedTagIDs.isSubset(of: validTagIDs) {
            filter.selectedTagIDs.formIntersection(validTagIDs)
        }
        scheduleMangaCoverBackfill(for: loadedDocument.items)
    }

    private func reloadReadingProgress() async {
        readingProgress = await readingProgressStore.loadAll()
        refreshDerivedState()
    }

    private func reloadContentCovers() async {
        let threadCovers = await loadContentCovers(for: document.items)
        coverLookup = threadCovers.merging(
            await smartMangaCoverLookup(for: Array(Set(mangaDirectoriesByTID.values)))
        )
        refreshDerivedState()
    }

    /// Re-derives only the Smart Comic Mode-dependent slice of state
    /// (`boardReaderSettings`/`mangaDirectoriesByTID`/`coverLookup`'s
    /// `.smartManga` slice) in response to *any*
    /// `SettingsStore.didChangeNotification` — mirroring `reload()`'s
    /// deliberately narrower approach (see the comment at `reload()`):
    /// this must never re-apply `settings.favorites` (sort order/layout/
    /// selected category/collection), or an unrelated settings save made
    /// elsewhere (including this organizer's own `persistViewPreferences`/
    /// `persistNavigationState`) would clobber sort/filter state the user
    /// may have just changed live in this session. Guarded on an actual
    /// diff so unrelated settings saves (which also post this notification)
    /// don't re-run the manga-directory batch query for no reason.
    private func reloadBoardReaderSettings() async {
        let settings = await settingsStore.load()
        guard settings.boardReader != boardReaderSettings else { return }
        boardReaderSettings = settings.boardReader
        mangaDirectoriesByTID = await resolveMangaDirectories(for: document.items, boardReaderSettings: boardReaderSettings)
        coverLookup.replaceSmartMangaSlice(
            with: await smartMangaCoverLookup(for: Array(Set(mangaDirectoriesByTID.values)))
        )
        refreshDerivedState()
        scheduleMangaCoverBackfill(for: document.items)
    }

    /// Re-derives `backgroundSettings`/`backgroundImageData` in response to
    /// *any* `SettingsStore.didChangeNotification`, mirroring
    /// `reloadBoardReaderSettings()`'s diff-guarded shape — this is the only
    /// path that keeps the root favorites background in sync with an edit
    /// made from Settings, since the favorites tab's `FavoriteLibraryOrganizer`
    /// is constructed once for the app's lifetime and never reloads on tab
    /// reselect.
    private func reloadFavoriteBackground() async {
        let settings = await settingsStore.load()
        guard settings.favorites.background != backgroundSettings else { return }
        await applyBackgroundSettings(settings.favorites.background)
    }

    private func applyBackgroundSettings(_ newValue: FavoriteBackgroundSettings) async {
        backgroundSettings = newValue
        backgroundImageData = await favoriteBackgroundImageStore.loadData(imageID: newValue.imageID)
    }

    /// Re-derives the manga-directory-dependent slice of state
    /// (`mangaDirectoriesByTID`/`coverLookup`'s `.smartManga` slice) in
    /// response to `MangaDirectoryStore.didChangeNotification` -- e.g.
    /// resolving a previously-unresolved manga favorite's directory for the
    /// first time (`saveDirectory`), or renaming a directory from the manga
    /// reader's directory page (`renameDirectory`). Without this, a newly-
    /// resolved directory's merge/cover (or a rename's effect on a merged
    /// card's displayed `cleanBookName`/`.smartManga` cover) would stay stale
    /// in an already-open Favorites tab until some unrelated
    /// favorite/progress/cover/settings change happened to trigger a
    /// full reload.
    ///
    /// Also reloads `readingProgress` -- `MangaDirectoryStore
    /// .renameRelatedStructuredMetadata` cascades a rename into the
    /// `reading_progress` table too (directory-level progress rows get
    /// migrated to the new clean book name), so without this an
    /// already-loaded `readingProgress` array would keep referencing the old
    /// identity and show no/stale progress on a card immediately after a
    /// rename, until some other reload happened to refresh it.
    private func reloadMangaDirectories() async {
        mangaDirectoriesByTID = await resolveMangaDirectories(for: document.items, boardReaderSettings: boardReaderSettings)
        coverLookup.replaceSmartMangaSlice(
            with: await smartMangaCoverLookup(for: Array(Set(mangaDirectoriesByTID.values)))
        )
        readingProgress = await readingProgressStore.loadAll()
        refreshDerivedState()
    }

    // MARK: - Categories

    @discardableResult
    /// Pushes one favorite item to Yamibo (card context menu action).
    func pushItemToYamibo(_ item: FavoriteItem) async {
        do {
            let repository = await makeFavoriteRepository()
            let result = try await FavoriteQuickActions.pushFavoriteItemToYamibo(
                item,
                localFavoriteLibraryStore: libraryStore,
                remoteRepository: repository
            )
            switch result {
            case .synced:
                transientMessage = L10n.string("favorites.quick.sync_item.synced")
            case .syncedWithoutMapping:
                transientMessage = L10n.string("favorites.quick.sync_item.pending")
            case .notAttempted, .failed:
                break
            }
        } catch {
            YamiboLog.sync.error("Failed to sync favorite item \(item.id) to Yamibo: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func createCategory(name: String) async -> FavoriteCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let category = await commit { document in
            document.createCategory(name: trimmed)
        }
        if let category {
            selectedCategoryID = category.id
        }
        return category
    }

    func renameCategory(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await commit { document in
            document.renameCategory(id: id, name: trimmed)
        }
    }

    func deleteCategory(id: String) async {
        await commit { document in
            document.deleteCategory(id: id)
        }
        if !document.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = document.defaultCategory.id
        }
    }

    func moveCategory(id: String, direction: CategoryMoveDirection) async {
        guard let orderedIDs = document.reorderedCategoryIDs(moving: id, direction) else { return }
        await commit { document in
            document.reorderCategories(orderedIDs: orderedIDs)
        }
    }

    // MARK: - Collections

    func openCollection(id: String) {
        guard let collection = document.collections.first(where: { $0.id == id }) else { return }
        if selectedCategoryID != collection.categoryID {
            selectedCategoryID = collection.categoryID
        }
        selectedCollectionID = id
    }

    func closeCollection() {
        selectedCollectionID = nil
    }

    @discardableResult
    func createCollection(name: String, color: FavoriteCollectionColor = .gray) async -> LocalFavoriteCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryID = selectedCategoryID
        guard !trimmed.isEmpty else { return nil }
        let collection = await commit { document in
            document.createCollection(categoryID: categoryID, name: trimmed, color: color)
        }
        if let collection {
            selectedCollectionID = collection.id
        }
        return collection
    }

    func updateCollection(id: String, name: String, color: FavoriteCollectionColor) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await commit { document in
            document.renameCollection(id: id, name: trimmed)
            document.recolorCollection(id: id, color: color)
        }
    }

    func dissolveCollection(id: String) async {
        let committed: Void? = await commit { document in
            document.dissolveCollection(id: id)
        }
        guard committed != nil else { return }
        if selectedCollectionID == id {
            selectedCollectionID = nil
        }
    }

    func moveCollection(id: String, direction: CategoryMoveDirection) async {
        guard let reorder = document.reorderedCollectionIDs(moving: id, direction) else { return }
        await commit { document in
            document.reorderCollections(categoryID: reorder.categoryID, orderedIDs: reorder.orderedIDs)
        }
    }

    func moveCollection(id: String, toCategoryID categoryID: String) async {
        let committed: Void? = await commit { document in
            document.moveCollection(id: id, toCategoryID: categoryID)
        }
        guard committed != nil else { return }
        if selectedCollectionID == id {
            selectedCategoryID = categoryID
        }
    }

    // MARK: - Merged smart-comic groups

    /// Opens a smart card's "查看归档收藏" detail page, scoping `derived.cards`
    /// (not `rootDerived`) to every individual favorite whose own effective
    /// title (`FavoriteCardProjection.resolvedTitle`) currently matches
    /// `cleanBookName` — one item for a still-solitary smart card, 2+ for an
    /// actually merged one. Mirrors `openCollection(id:)` exactly.
    func openMergedGroup(cleanBookName: String) {
        selectedMergedGroupCleanBookName = cleanBookName
    }

    /// Mirrors `closeCollection()` exactly.
    func closeMergedGroup() {
        selectedMergedGroupCleanBookName = nil
    }

    // MARK: - Tags

    @discardableResult
    func createTag(name: String, color: FavoriteTagColor = .gray) async -> FavoriteTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return await commit { document in
            document.createTag(name: trimmed, color: color)
        }
    }

    func updateTag(id tagID: String, name: String, color: FavoriteTagColor) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await commit { document in
            document.renameTag(id: tagID, name: trimmed)
            document.recolorTag(id: tagID, color: color)
        }
    }

    func deleteTag(id tagID: String) async {
        let committed: Void? = await commit { document in
            document.deleteTag(id: tagID)
        }
        guard committed != nil else { return }
        filter.selectedTagIDs.remove(tagID)
    }

    /// Reachable from a card's context-menu "标签" button, including a smart
    /// card's — that button is not gated on `isModeOnMangaThread` (see
    /// `LocalFavoriteCardContextMenu`), so `itemID` can be a smart card's
    /// representative item id. Routed through `expandedSelectionFavoriteIDs`
    /// so editing a smart card's tags from this single-item path applies to
    /// every favorite archived under it, exactly like `updateTagsForSelection`
    /// does for a bulk selection.
    func updateTags(for itemID: String, tagIDs: Set<String>) async {
        let expandedIDs = expandedSelectionFavoriteIDs([itemID])
        await commit { document in
            document.replaceTags(for: expandedIDs, with: tagIDs)
        }
    }

    func updateTagsForSelection(_ tagIDs: Set<String>) async {
        let favoriteIDs = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        guard !favoriteIDs.isEmpty else { return }
        let committed: Void? = await commit { document in
            document.replaceTags(for: favoriteIDs, with: tagIDs)
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    func reorderTags(_ orderedIDs: [String]) async {
        await commit { document in
            document.reorderTags(orderedIDs: orderedIDs)
        }
    }

    // MARK: - Selection operations

    /// True only while browsing the unscoped root list — false while either
    /// a pushed collection detail (`selectedCollectionID`) or a merged smart
    /// card's "查看归档收藏" archive detail (`selectedMergedGroupCleanBookName`)
    /// is open. Collections never appear inside either scoped detail page
    /// (no nested collections in the domain model), so every call site
    /// deciding whether to fold `derived.visibleCollections` into scope or
    /// selection must gate on both — checking only `selectedCollectionID`
    /// (as every one of these call sites once did) let the archive page leak
    /// the current category's sibling collections into its own content and
    /// "select all", since opening it directly from the root list (the
    /// common path) leaves `selectedCollectionID` `nil`.
    private var isBrowsingUnscopedRoot: Bool {
        selectedCollectionID == nil && selectedMergedGroupCleanBookName == nil
    }

    func toggleCollectionSelection(id: String) {
        guard isBrowsingUnscopedRoot else { return }
        selection.toggleCollectionSelection(id: id)
    }

    /// Whether `id` names a mode-on `.mangaThread` favorite that renders as a
    /// smart card on the main list — the ground-truth definition
    /// `LocalFavoriteLibraryProjection.cards(in:query:...)` itself uses for
    /// `isModeOnMangaThread` — computed straight from `document.items` +
    /// the current mode/directory snapshot rather than looked up in
    /// `derived.cards`.
    ///
    /// This distinction matters: `filter` (search text / tag / source
    /// filters) can narrow `derived.cards` at any time, and its own `didSet`
    /// deliberately never clears `selection` (`LocalFavoriteBrowseSession`'s
    /// own doc comment: "search is a plain live filter, not a session
    /// mode"). A smart card that's selected and then scrolled out of
    /// `derived.cards` by a filter change would stop being found by a
    /// `derived.cards.first(where:)` lookup while remaining fully selected —
    /// silently reverting it to "looks like an ordinary id" for any
    /// selection-consuming operation. For `deleteSelection` in particular
    /// that would mean deleting just its representative item instead of
    /// skipping it, orphaning every other favorite still archived under it:
    /// exactly the bug this whole feature exists to prevent. Sourcing the
    /// check from `document.items` instead makes it immune to the current
    /// filter entirely.
    ///
    /// Always `false` while the "查看归档收藏" archive page is open
    /// (`selectedMergedGroupCleanBookName != nil`), matching
    /// `cards(in:query:...)`'s own member-scoped computation: every card
    /// there is deliberately an ordinary per-item card, never a smart card.
    private func isSmartCardFavoriteID(_ id: String) -> Bool {
        guard selectedMergedGroupCleanBookName == nil,
              let item = document.items.first(where: { $0.id == id }) else { return false }
        return item.target.kind == .mangaThread && boardReaderSettings.isSmartComicModeEnabled(forumID: item.forumID)
    }

    /// Whether the current selection has anything `deleteSelection` would
    /// actually remove: at least one selected collection (dissolving a
    /// collection is unaffected by smart-card concerns entirely), or at
    /// least one selected favorite that ISN'T a smart card
    /// (`deleteSelection` skips every smart-card id, deleting nothing for
    /// them). Backs `LocalFavoriteSelectionActionBar`'s delete-button
    /// visibility — per that view's own doc comment ("hidden, not merely
    /// disabled, when the current selection can't use it"), a selection
    /// made up entirely of smart cards must not show an active delete
    /// button that silently does nothing when tapped.
    var hasDeletableSelection: Bool {
        selection.selectedCollectionCount > 0
            || selection.selectedFavoriteIDs.contains { !isSmartCardFavoriteID($0) }
    }

    /// Expands `favoriteIDs` so any smart-card id (`isSmartCardFavoriteID`)
    /// is replaced by the full set of ids for every favorite item currently
    /// archived under it — the same membership its "查看归档收藏" page and
    /// tag-union display use
    /// (`LocalFavoriteLibraryProjection.archivedItems(matching:...)`). A
    /// non-smart-card id passes through unchanged. Used by every
    /// selection-consuming operation EXCEPT `deleteSelection`, which
    /// intentionally keeps requiring the dedicated archive page for
    /// per-item-visible deletion (see its own doc comment).
    private func expandedSelectionFavoriteIDs(_ favoriteIDs: Set<String>) -> Set<String> {
        guard selectedMergedGroupCleanBookName == nil else { return favoriteIDs }
        // Built once for every id in this one call, instead of calling
        // `archivedItems(matching:...)` (a full O(N) scan of `document.items`)
        // once per selected id — an O(S x N) shape for S selected ids that
        // this single O(N) precomputation plus O(1) lookups per id replaces.
        // Still always freshly computed from the CURRENT `document.items`
        // here at the top of this call, never cached across separate calls.
        let itemsByEffectiveTitle = LocalFavoriteLibraryProjection.mangaThreadItemsByEffectiveTitle(
            in: document.items,
            mangaDirectoriesByTID: mangaDirectoriesByTID,
            boardReaderSettings: boardReaderSettings
        )
        var expanded = favoriteIDs
        for id in favoriteIDs {
            guard let item = document.items.first(where: { $0.id == id }),
                  item.target.kind == .mangaThread,
                  boardReaderSettings.isSmartComicModeEnabled(forumID: item.forumID) else { continue }
            let directory = mangaDirectoriesByTID[item.target.threadID ?? ""]
            let effectiveTitle = FavoriteCardProjection.resolvedTitle(
                item: item,
                mangaDirectory: directory,
                isModeOnMangaThread: true
            )
            let archived = itemsByEffectiveTitle[effectiveTitle] ?? []
            expanded.formUnion(archived.map(\.id))
        }
        return expanded
    }

    /// Every card currently visible, including smart cards — selecting or
    /// "select all"-ing a smart card is equivalent to selecting every
    /// favorite archived under it, expanded transparently at execution time
    /// by `expandedSelectionFavoriteIDs` (Part C); the id that actually lands
    /// in `selection.selectedFavoriteIDs` is still just the smart card's own
    /// representative id, same as any other card. Backs both
    /// `selectAllVisible()` and `isAllVisibleSelected`.
    private var selectableFavoriteIDs: [String] {
        derived.cards.map(\.id)
    }

    func selectAllVisible() {
        selection.selectAll(
            favoriteIDs: selectableFavoriteIDs,
            collectionIDs: isBrowsingUnscopedRoot ? derived.visibleCollections.map(\.id) : []
        )
    }

    /// Whether every currently-visible favorite/collection is already
    /// selected — this is a plain count comparison, not a per-item
    /// membership diff (mirrors `MangaNovelReaderCacheSelectionState
    /// .isAllSelected` in the cache sheets' own select-all button).
    var isAllVisibleSelected: Bool {
        let favoriteIDs = selectableFavoriteIDs
        let collectionIDs = isBrowsingUnscopedRoot ? derived.visibleCollections.map(\.id) : []
        let totalCount = favoriteIDs.count + collectionIDs.count
        guard totalCount > 0 else { return false }
        let selectedCount = favoriteIDs.filter(selection.selectedFavoriteIDs.contains).count
            + collectionIDs.filter(selection.selectedCollectionIDs.contains).count
        return selectedCount == totalCount
    }

    var hasVisibleSelectableEntries: Bool {
        !selectableFavoriteIDs.isEmpty || (isBrowsingUnscopedRoot && !derived.visibleCollections.isEmpty)
    }

    /// Select-all ↔ clear-all toggle (cache-sheet select-all button parity):
    /// not a strict per-item inversion — just select everything visible, or
    /// clear it all when everything is already selected.
    func toggleSelectAllVisible() {
        if isAllVisibleSelected {
            selection.clearSelection()
        } else {
            selectAllVisible()
        }
    }

    @discardableResult
    func createCollectionFromSelection(name: String, color: FavoriteCollectionColor = .gray) async -> LocalFavoriteCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let favoriteIDs = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        let categoryID = selectedCategoryID
        let source = selectionSourceLocation
        guard !trimmed.isEmpty, !favoriteIDs.isEmpty else { return nil }
        let collection = await commit { document in
            let collection = document.createCollection(categoryID: categoryID, name: trimmed, color: color)
            document.moveItems(
                ids: favoriteIDs,
                to: .collection(categoryID: collection.categoryID, collectionID: collection.id),
                removing: source
            )
            return collection
        }
        guard let collection else { return nil }
        selectedCollectionID = collection.id
        selection.exitSelectionMode()
        return collection
    }

    func moveSelectionToCategory(id categoryID: String) async {
        guard selection.selectedEntryCount > 0 else { return }
        let favoriteIDs = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        let collectionIDs = selection.selectedCollectionIDs
        let source = selectionSourceLocation
        let committed: Void? = await commit { document in
            for collectionID in collectionIDs {
                document.moveCollection(id: collectionID, toCategoryID: categoryID)
            }
            document.moveItems(ids: favoriteIDs, to: .category(categoryID), removing: source)
        }
        guard committed != nil else { return }
        selectedCategoryID = categoryID
        selection.exitSelectionMode()
    }

    func moveSelectionToCollection(id collectionID: String) async {
        let favoriteIDs = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        let source = selectionSourceLocation
        guard !favoriteIDs.isEmpty,
              let collection = document.collections.first(where: { $0.id == collectionID }) else { return }
        let committed: Void? = await commit { document in
            document.moveItems(
                ids: favoriteIDs,
                to: .collection(categoryID: collection.categoryID, collectionID: collection.id),
                removing: source
            )
        }
        guard committed != nil else { return }
        selectedCategoryID = collection.categoryID
        selectedCollectionID = collection.id
        selection.exitSelectionMode()
    }

    func addSelectionToCategory(id categoryID: String) async {
        let favoriteIDs = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        guard !favoriteIDs.isEmpty else { return }
        let committed: Void? = await commit { document in
            document.moveItems(ids: favoriteIDs, to: .category(categoryID), removing: nil)
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    func addSelectionToCollection(id collectionID: String) async {
        let favoriteIDs = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        guard !favoriteIDs.isEmpty,
              let collection = document.collections.first(where: { $0.id == collectionID }) else { return }
        let committed: Void? = await commit { document in
            document.moveItems(
                ids: favoriteIDs,
                to: .collection(categoryID: collection.categoryID, collectionID: collection.id),
                removing: nil
            )
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    /// Whether all, some, or none of the selected items carry `location` —
    /// drives the tri-state boxes in the move sheet. Routed through
    /// `expandedSelectionFavoriteIDs` exactly like every other
    /// selection-consuming operation, so a selected smart card's tri-state
    /// readout reflects every favorite archived under it, not just its
    /// representative member.
    func selectionLocationState(_ location: FavoriteLocation) -> LocalFavoriteLocationTriState {
        let ids = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        guard !ids.isEmpty else { return .none }
        let selectedItems = document.items.filter { ids.contains($0.id) }
        guard !selectedItems.isEmpty else { return .none }
        let count = selectedItems.filter { $0.locations.contains(location) }.count
        if count == 0 { return .none }
        return count == selectedItems.count ? .all : .some
    }

    /// Adds or removes one location on every selected item. Removal skips
    /// items whose last location it would be (an item always lives somewhere).
    /// Routed through `expandedSelectionFavoriteIDs` exactly like every other
    /// selection-consuming operation — this backs the move sheet
    /// (`LocalFavoriteSelectionMoveSheet`), the actual UI path a user hits
    /// when moving a selected smart card, so it must expand to every
    /// favorite archived under it rather than moving just the representative
    /// member.
    func setSelectionLocation(_ location: FavoriteLocation, included: Bool) async {
        let ids = expandedSelectionFavoriteIDs(selection.selectedFavoriteIDs)
        guard !ids.isEmpty else { return }
        _ = await commit { document in
            if included {
                document.moveItems(ids: ids, to: location, removing: nil)
            } else {
                document.removeItems(ids: ids, from: location)
            }
        }
    }

    func removeSelectionFromCurrentLocation() async {
        let favoriteIDs = selection.selectedFavoriteIDs
        let source = selectionSourceLocation
        guard !favoriteIDs.isEmpty else { return }
        let committed: Void? = await commit { document in
            document.removeItems(ids: favoriteIDs, from: source)
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    func dissolveSelectedCollections() async {
        let collectionIDs = selection.selectedCollectionIDs
        guard !collectionIDs.isEmpty else { return }
        let committed: Void? = await commit { document in
            for collectionID in collectionIDs {
                document.dissolveCollection(id: collectionID)
            }
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    /// Entry point for the selection bar's delete: resolves whether the
    /// Yamibo counterparts should be deleted too through the SAME remembered
    /// choice every other remove entry point uses
    /// (`FavoriteRemoveRemoteDecision`), prompting when the user has not
    /// remembered one. `.currentLocation` never touches the website, so it
    /// skips the decision entirely.
    func requestDeleteSelection(scope: LocalFavoriteDeleteScope) async {
        switch scope {
        case .currentLocation:
            await deleteSelection(scope: .currentLocation, removeRemote: false)
        case .everywhere:
            let deletableIDs = selection.selectedFavoriteIDs.filter { !isSmartCardFavoriteID($0) }
            let candidates = document.items.filter { deletableIDs.contains($0.id) }
            switch await resolveRemoveRemoteDecision(candidates: candidates) {
            case .prompt:
                removeRemotePrompt = LocalFavoriteRemoveRemotePrompt(subject: .selection)
            case let .silent(removeRemote):
                await deleteSelection(scope: .everywhere, removeRemote: removeRemote)
            }
        }
    }

    /// Same decision routing for a single card's delete dialog.
    func requestDeleteItem(_ item: FavoriteItem, scope: LocalFavoriteDeleteScope) async {
        switch scope {
        case .currentLocation:
            await deleteItem(item, scope: .currentLocation, removeRemote: false)
        case .everywhere:
            let latestItem = document.items.first { $0.id == item.id } ?? item
            switch await resolveRemoveRemoteDecision(candidates: [latestItem]) {
            case .prompt:
                removeRemotePrompt = LocalFavoriteRemoveRemotePrompt(subject: .item(item))
            case let .silent(removeRemote):
                await deleteItem(item, scope: .everywhere, removeRemote: removeRemote)
            }
        }
    }

    /// Completes a pending `removeRemotePrompt`: optionally persists the
    /// remembered choice (through the shared quick-actions write path), then
    /// runs the delete that raised the prompt.
    func confirmRemoveRemotePrompt(removeRemote: Bool, remember: Bool) async {
        guard let prompt = removeRemotePrompt else { return }
        removeRemotePrompt = nil
        if remember {
            await FavoriteQuickActions.rememberRemoveRemoteChoice(removeRemote, settingsStore: settingsStore)
        }
        switch prompt.subject {
        case let .item(item):
            await deleteItem(item, scope: .everywhere, removeRemote: removeRemote)
        case .selection:
            await deleteSelection(scope: .everywhere, removeRemote: removeRemote)
        }
    }

    /// Silent when no candidate plausibly exists on the website (nothing to
    /// ask about) or when the user remembered a choice; `.prompt` otherwise.
    private func resolveRemoveRemoteDecision(candidates: [FavoriteItem]) async -> FavoriteRemoveRemoteDecision {
        let canRemoveRemote = candidates.contains(where: \.hasYamiboRemoteCandidate)
        let settings = await settingsStore.load().favorites
        return FavoriteRemoveRemoteDecision.resolve(settings: settings, canRemoveRemote: canRemoveRemote)
    }

    /// Deliberately NOT routed through `expandedSelectionFavoriteIDs` —
    /// unlike every other selection-consuming operation, delete must keep
    /// requiring the dedicated "查看归档收藏" archive page for a smart card.
    /// A smart card can now enter `selection.selectedFavoriteIDs` (Part D),
    /// so any such id is partitioned out and skipped entirely here: deleting
    /// only the representative item while leaving every other archived
    /// member favorited would orphan them from their now-partially-deleted
    /// group, with no corresponding cleanup — the exact bug that originally
    /// justified excluding smart cards from selection altogether.
    func deleteSelection(scope: LocalFavoriteDeleteScope, removeRemote: Bool) async {
        guard selection.selectedEntryCount > 0 else { return }
        let allSelectedFavoriteIDs = selection.selectedFavoriteIDs
        // `isSmartCardFavoriteID` deliberately does NOT look the id up in
        // `derived.cards` — see its own doc comment — precisely so a smart
        // card scrolled out of the current search/tag/source filter while
        // still selected still gets skipped here instead of silently
        // falling through to a lone, sibling-orphaning delete below.
        let skippedSmartCardFavoriteIDs = allSelectedFavoriteIDs.filter(isSmartCardFavoriteID)
        let favoriteIDs = allSelectedFavoriteIDs.subtracting(skippedSmartCardFavoriteIDs)
        if !skippedSmartCardFavoriteIDs.isEmpty {
            transientMessage = L10n.string("favorites.bulk_delete_skipped_smart_manga_message")
        }
        let collectionIDs = selection.selectedCollectionIDs
        guard !favoriteIDs.isEmpty || !collectionIDs.isEmpty else {
            // Nothing left to delete once smart cards are skipped — still
            // exit selection mode so their now-stale ids don't linger
            // selected (`exitSelectionMode()` clears the whole selection
            // unconditionally).
            selection.exitSelectionMode()
            return
        }
        let source = selectionSourceLocation
        let deleter = remoteDeleter
        let committed: Void? = await commit { document in
            switch scope {
            case .currentLocation:
                document.removeItems(ids: favoriteIDs, from: source)
            case .everywhere:
                let selectedItems = document.items.filter { favoriteIDs.contains($0.id) }
                if removeRemote {
                    try await deleter.deleteRemoteFavorites(for: selectedItems)
                }
                for item in selectedItems {
                    document.removeItem(target: item.target)
                }
                for collectionID in collectionIDs {
                    document.dissolveCollection(id: collectionID)
                }
            }
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    // MARK: - Items

    func deleteItem(_ item: FavoriteItem, scope: LocalFavoriteDeleteScope, removeRemote: Bool) async {
        let currentLocation = selectionSourceLocation
        let deleter = remoteDeleter
        await commit { document in
            guard let latestItem = document.items.first(where: { $0.id == item.id }) else {
                throw CommitAbort()
            }
            switch scope {
            case .currentLocation:
                if latestItem.locations.count > 1 {
                    _ = document.removeLocation(currentLocation, from: latestItem.target)
                }
            case .everywhere:
                if removeRemote {
                    try await deleter.deleteRemoteFavorites(for: [latestItem])
                }
                document.removeItem(target: latestItem.target)
            }
        }
    }

    // MARK: - Display and sort preferences

    func updateLayoutMode(_ value: FavoriteLibraryLayoutMode) {
        guard value != display.layoutMode else { return }
        let previous = display.layoutMode
        display.layoutMode = value
        persistViewPreferences {
            if self.display.layoutMode == value {
                self.display.layoutMode = previous
            }
        }
    }

    func updateShowsCategoryCounts(_ value: Bool) {
        guard value != display.showsCategoryCounts else { return }
        let previous = display.showsCategoryCounts
        display.showsCategoryCounts = value
        persistViewPreferences {
            if self.display.showsCategoryCounts == value {
                self.display.showsCategoryCounts = previous
            }
        }
    }

    func updateSortOrder(_ value: LocalFavoriteLibrarySortOrder) {
        guard value != filter.sortOrder else { return }
        let previous = filter.sortOrder
        filter.sortOrder = value
        persistViewPreferences {
            if self.filter.sortOrder == value {
                self.filter.sortOrder = previous
            }
        }
    }

    func updateSortDescending(_ value: Bool) {
        guard value != filter.sortDescending else { return }
        let previous = filter.sortDescending
        filter.sortDescending = value
        persistViewPreferences {
            if self.filter.sortDescending == value {
                self.filter.sortDescending = previous
            }
        }
    }

    // MARK: - Derivation

    private func refreshDerivedState() {
        derived = LocalFavoriteLibraryDerivation.derive(
            LocalFavoriteLibraryDerivation.Inputs(
                document: document,
                selectedCategoryID: selectedCategoryID,
                selectedCollectionID: selectedCollectionID,
                filter: filter,
                readingProgress: readingProgress,
                coverURLsByKey: coverLookup.urlsByKey,
                textCoverForcedKeys: coverLookup.forcedKeys,
                mangaDirectoriesByTID: mangaDirectoriesByTID,
                boardReaderSettings: boardReaderSettings,
                memberScopeCleanBookName: selectedMergedGroupCleanBookName
            )
        )
        // `derived` can now be scoped by an open merged group even while no
        // collection is open, so the old `selectedCollectionID == nil`
        // shortcut alone is no longer sufficient — it must also gate on
        // `selectedMergedGroupCleanBookName` (see `isBrowsingUnscopedRoot`),
        // or `rootDerived` would silently inherit the merged-group scope in
        // that case (opening a merged group's detail page directly from the
        // root, not from inside a collection) and defeat the whole point of
        // `rootDerived`.
        rootDerived = isBrowsingUnscopedRoot
            ? derived
            : LocalFavoriteLibraryDerivation.derive(
                LocalFavoriteLibraryDerivation.Inputs(
                    document: document,
                    selectedCategoryID: selectedCategoryID,
                    selectedCollectionID: nil,
                    filter: filter,
                    readingProgress: readingProgress,
                    coverURLsByKey: coverLookup.urlsByKey,
                    textCoverForcedKeys: coverLookup.forcedKeys,
                    mangaDirectoriesByTID: mangaDirectoriesByTID,
                    boardReaderSettings: boardReaderSettings
                    // `memberScopeCleanBookName` intentionally omitted (nil
                    // default): `rootDerived` must never narrow to this scope.
                )
            )
        selection.prune(
            validFavoriteIDs: Set(document.items.map(\.id)),
            validCollectionIDs: Set(document.collections.map(\.id))
        )
    }

    // MARK: - Commit

    private struct CommitAbort: Error {}

    /// Loads the latest document, applies `transform`, saves, and republishes.
    /// Throwing aborts without saving; errors surface through `errorMessage`.
    /// A failed load aborts the same way — the transform must never run
    /// against a placeholder document, or the save would wipe the library.
    /// (The transform can await remote work, so this stays load-modify-save
    /// rather than `FavoriteLibraryStore.update`.)
    @discardableResult
    private func commit<Result>(
        _ transform: (inout FavoriteLibraryDocument) async throws -> Result
    ) async -> Result? {
        do {
            var updatedDocument = try await libraryStore.load()
            let result = try await transform(&updatedDocument)
            try await libraryStore.save(updatedDocument)
            document = updatedDocument
            errorMessage = nil
            return result
        } catch is CommitAbort {
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            YamiboLog.persistence.error("Favorite library document commit failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private var selectionSourceLocation: FavoriteLocation {
        if let selectedCollection {
            .collection(categoryID: selectedCollection.categoryID, collectionID: selectedCollection.id)
        } else {
            .category(selectedCategoryID)
        }
    }

    // MARK: - Persistence

    private func persistNavigationState() {
        guard document.categories.contains(where: { $0.id == selectedCategoryID }) else { return }
        let categoryID = selectedCategoryID
        let validCollectionID = selectedCollectionID.flatMap { id in
            document.collections.contains { $0.id == id && $0.categoryID == categoryID } ? id : nil
        }
        Task {
            var settings = await settingsStore.load()
            guard settings.favorites.selectedCategoryID != categoryID
                    || settings.favorites.selectedCollectionID != validCollectionID else { return }
            settings.favorites.selectedCategoryID = categoryID
            settings.favorites.selectedCollectionID = validCollectionID
            do {
                try await settingsStore.save(settings)
            } catch {
                YamiboLog.persistence.error("Failed to persist favorites navigation state: \(error.localizedDescription)")
            }
        }
    }

    /// Persists the current view preferences; on failure runs `rollback` and
    /// reports the error.
    private func persistViewPreferences(rollback: @escaping @MainActor () -> Void) {
        let display = display
        let sortOrder = filter.sortOrder
        let sortDescending = filter.sortDescending
        Task {
            var settings = await settingsStore.load()
            settings.favorites.layoutMode = display.layoutMode
            settings.favorites.showsCategoryCounts = display.showsCategoryCounts
            settings.favorites.sortOrder = sortOrder
            settings.favorites.sortDescending = sortDescending
            do {
                try await settingsStore.save(settings)
            } catch {
                YamiboLog.persistence.error("Failed to persist favorites view preferences: \(error.localizedDescription)")
                await MainActor.run {
                    rollback()
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Manga directory grouping (smart-comic-mode decision #3/#5)

    /// Resolves the tid → `MangaDirectory` map virtual favorites grouping
    /// needs, in exactly one batched query — the design doc's performance
    /// constraint #1. `items` is first narrowed in memory (no I/O) to
    /// mode-on `.mangaThread` favorites only, using the *explicit*
    /// `BoardReaderSettings.isSmartComicModeEnabled(forumID:)` check (never a proxy
    /// signal — this exact class of bug bit three earlier phases), before
    /// the single `MangaDirectoryStore.directories(containingTIDs:)` round
    /// trip. Called only from `load()`/`reload()`, never from
    /// `refreshDerivedState()` or any SwiftUI-observed computed property —
    /// performance constraint #2.
    private func resolveMangaDirectories(
        for items: [FavoriteItem],
        boardReaderSettings: BoardReaderSettings
    ) async -> [String: MangaDirectory] {
        guard let mangaDirectoryStore else { return [:] }
        let candidateTIDs = items.compactMap { item -> String? in
            guard item.target.kind == .mangaThread,
                  boardReaderSettings.isSmartComicModeEnabled(forumID: item.forumID) else {
                return nil
            }
            return item.target.threadID
        }
        guard !candidateTIDs.isEmpty else { return [:] }
        do {
            return try await mangaDirectoryStore.directories(containingTIDs: candidateTIDs)
        } catch {
            YamiboLog.persistence.warning("Failed to resolve manga directories for favorites grouping; showing manga favorites standalone this load: \(error.localizedDescription)")
            return [:]
        }
    }

    // MARK: - Covers

    /// Cover state for card display, keyed by the same `ContentCoverKey`
    /// each card's `contentCoverKey` resolves. `.thread` and `.smartManga`
    /// keys share the one keyspace; the two loaders below each fill their
    /// own disjoint slice of it.
    struct ContentCoverLookup {
        var urlsByKey: [ContentCoverKey: URL] = [:]
        var forcedKeys: Set<ContentCoverKey> = []

        /// The two slices' key spaces are disjoint (`.thread` vs
        /// `.smartManga` target types), so merging is purely additive.
        func merging(_ other: ContentCoverLookup) -> ContentCoverLookup {
            ContentCoverLookup(
                urlsByKey: urlsByKey.merging(other.urlsByKey) { _, new in new },
                forcedKeys: forcedKeys.union(other.forcedKeys)
            )
        }

        /// Replaces only the `.smartManga` entries, leaving `.thread`
        /// entries untouched — for callers that re-resolved directories or
        /// settings without re-reading every favorite's own thread cover.
        mutating func replaceSmartMangaSlice(with smart: ContentCoverLookup) {
            urlsByKey = urlsByKey.filter { $0.key.targetType != .smartManga }
                .merging(smart.urlsByKey) { _, new in new }
            forcedKeys = forcedKeys.filter { $0.targetType != .smartManga }
                .union(smart.forcedKeys)
        }
    }

    /// The per-favorite `.thread(tid:)` cover slice. `.smartManga` covers
    /// for resolved directories come from `smartMangaCoverLookup(for:)` and
    /// merge into the same keyspace.
    private func loadContentCovers(for items: [FavoriteItem]) async -> ContentCoverLookup {
        var lookup = ContentCoverLookup()
        for item in items {
            guard let key = ContentCoverKey(target: item.target),
                  let cover = await contentCoverStore.cover(for: key) else {
                continue
            }
            if let resolvedURL = cover.resolvedURL {
                lookup.urlsByKey[key] = resolvedURL
            }
            if cover.textCoverForced {
                lookup.forcedKeys.insert(key)
            }
        }
        return lookup
    }

    /// Toggles whether the card shows the text placeholder cover instead of
    /// its resolved automatic/manual cover (card context-menu action).
    /// Takes the whole card, not just `card.item`, because the key to write
    /// is the key the card's cover actually reads (`card.contentCoverKey`):
    /// a resolved-directory smart card displays the directory's shared
    /// `.smartManga` cover, while the same `FavoriteItem` surfaced as a
    /// "查看归档收藏" member card displays its own `.thread` cover.
    @discardableResult
    func toggleTextCover(for card: FavoriteCardProjection) async -> Bool {
        guard let key = card.contentCoverKey else { return false }
        let forced = !coverLookup.forcedKeys.contains(key)
        do {
            try await contentCoverStore.setTextCoverForced(forced, for: key)
        } catch {
            YamiboLog.library.error("Failed to toggle text cover for \(card.item.id): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
        let cover = await contentCoverStore.cover(for: key)
        if cover?.textCoverForced == true {
            coverLookup.forcedKeys.insert(key)
        } else {
            coverLookup.forcedKeys.remove(key)
        }
        coverLookup.urlsByKey[key] = cover?.resolvedURL
        refreshDerivedState()
        // Un-forcing a smart card whose `.smartManga` cover never resolved
        // leaves it imageless again — give the backfill a chance right away
        // instead of waiting for the next unrelated reload. (A no-op in
        // every other case: forced keys and covered groups are filtered out
        // of the backfill's own missing check.)
        scheduleMangaCoverBackfill(for: document.items)
        transientMessage = forced
            ? L10n.string("cover.use_text_cover_success_message")
            : L10n.string("cover.use_image_cover_success_message")
        return true
    }

    /// The `.smartManga(cleanBookName:)` cover slice for every currently-
    /// resolved directory (decision #13/#16) — the cover source for any card
    /// with a resolved `mangaDirectory`, merged or not.
    private func smartMangaCoverLookup(for directories: [MangaDirectory]) async -> ContentCoverLookup {
        var lookup = ContentCoverLookup()
        for directory in directories {
            let key = ContentCoverKey.smartManga(cleanBookName: directory.cleanBookName)
            guard let cover = await contentCoverStore.cover(for: key) else { continue }
            if let resolvedURL = cover.resolvedURL {
                lookup.urlsByKey[key] = resolvedURL
            }
            if cover.textCoverForced {
                lookup.forcedKeys.insert(key)
            }
        }
        return lookup
    }

    /// Resolves missing `.smartManga` covers for computed manga-directory
    /// groups (smart-comic-mode decision #13/#16). The old trigger —
    /// stored `.mangaTitle`-targeted favorites — is permanently gone since
    /// the Phase A type refactor (`FavoriteItemTarget` only has
    /// `.normalThread`/`.novelThread`/`.mangaThread`); this now triggers off
    /// `LocalFavoriteLibraryProjection.mangaDirectoryGroups` instead — the
    /// same mode-on `.mangaThread` favorites resolved to a directory that
    /// back the virtual merged-card grouping — using each group's earliest
    /// chapter tid, via the same `ThreadCoverResolver`/
    /// `ContentCoverStore.setAutomaticCover` mechanism the pre-Phase-A
    /// `.mangaTitle` implementation used. Standalone mode-off cards get
    /// their cover from `MangaReaderViewModel`'s Phase D auto-thread-cover
    /// resolution instead (when the user actually reads them), so they are
    /// deliberately not this function's concern.
    private func scheduleMangaCoverBackfill(for items: [FavoriteItem]) {
        guard let makeForumThreadReaderRepository, mangaCoverBackfillTask == nil else { return }
        let groups = LocalFavoriteLibraryProjection.mangaDirectoryGroups(
            for: items,
            mangaDirectoriesByTID: mangaDirectoriesByTID,
            boardReaderSettings: boardReaderSettings
        )
        let missing = groups.filter { group in
            let key = ContentCoverKey.smartManga(cleanBookName: group.directory.cleanBookName)
            return coverLookup.urlsByKey[key] == nil
                // A text-cover-forced group resolves no URL above, but it is
                // a deliberate "no image", not a missing cover — resolving
                // an automatic URL for it would be wasted network every
                // session (the forced flag suppresses whatever resolves).
                && !coverLookup.forcedKeys.contains(key)
                && !attemptedMangaCoverTargetIDs.contains(key.targetID)
        }
        guard !missing.isEmpty else { return }
        // Marked attempted synchronously, before the resolution task even
        // starts, so a reload firing again (from an unrelated favorite/
        // progress change) while this batch is still in flight doesn't
        // re-attempt the same groups.
        attemptedMangaCoverTargetIDs.formUnion(
            missing.map { ContentCoverKey.smartManga(cleanBookName: $0.directory.cleanBookName).targetID }
        )
        mangaCoverBackfillTask = Task { [weak self, contentCoverStore] in
            defer { self?.mangaCoverBackfillTask = nil }
            let repository = await makeForumThreadReaderRepository()
            let resolver = ThreadCoverResolver()
            for group in missing {
                if Task.isCancelled { return }
                let key = ContentCoverKey.smartManga(cleanBookName: group.directory.cleanBookName)
                // `resolvedURL` alone is not enough here: a text-cover-forced
                // row resolves nil even when a URL is stored, and overwriting
                // its automatic URL for a cover the flag suppresses anyway
                // would be wasted work.
                if let existing = await contentCoverStore.cover(for: key),
                   existing.textCoverForced || existing.resolvedURL != nil {
                    continue
                }
                guard let firstChapter = group.directory.chapters.first else { continue }
                guard let coverURL = await resolver.resolve(
                    thread: ThreadIdentity(tid: firstChapter.tid),
                    title: group.directory.cleanBookName,
                    repository: repository
                ) else {
                    continue
                }
                do {
                    _ = try await contentCoverStore.setAutomaticCover(coverURL, for: key)
                } catch {
                    YamiboLog.persistence.error("Failed to set automatic smartManga cover for \(group.directory.cleanBookName): \(error.localizedDescription)")
                }
                // `setAutomaticCover` posts `ContentCoverStore
                // .didChangeNotification` on success, which this organizer
                // already subscribes to (`coverUpdatesTask` →
                // `reloadContentCovers()`), so no manual state refresh is
                // needed here.
            }
        }
    }
}
