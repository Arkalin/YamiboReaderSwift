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
            refreshDerivedState()
            persistNavigationState()
        }
    }
    @Published var filter = LocalFavoriteFilterState() {
        didSet {
            guard filter != oldValue else { return }
            refreshDerivedState()
        }
    }
    @Published private(set) var derived = LocalFavoriteDerivedState()
    @Published private(set) var display = FavoriteLibraryDisplayState()
    @Published var errorMessage: String?

    /// Selection and search-mode session shared with the views.
    let selection = LocalFavoriteBrowseSession()

    private let libraryStore: FavoriteLibraryStore
    private let readingProgressStore: ReadingProgressStore
    private let settingsStore: SettingsStore
    private let contentCoverStore: ContentCoverStore
    private let remoteDeleter: YamiboRemoteFavoriteDeleter

    private var readingProgress: [ReadingProgressRecord] = []
    private var contentCoverURLsByTargetID: [String: URL] = [:]
    private var libraryUpdatesTask: Task<Void, Never>?
    private var progressUpdatesTask: Task<Void, Never>?

    init(
        libraryStore: FavoriteLibraryStore,
        readingProgressStore: ReadingProgressStore,
        settingsStore: SettingsStore,
        contentCoverStore: ContentCoverStore,
        makeFavoriteRepository: @escaping @Sendable () async -> FavoriteRepository,
        remoteFavoriteDeleteHandler: (([FavoriteItem]) async throws -> Void)? = nil
    ) {
        self.libraryStore = libraryStore
        self.readingProgressStore = readingProgressStore
        self.settingsStore = settingsStore
        self.contentCoverStore = contentCoverStore
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
    }

    deinit {
        libraryUpdatesTask?.cancel()
        progressUpdatesTask?.cancel()
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
        let loadedDocument = await libraryStore.load()
        contentCoverURLsByTargetID = await contentCoverURLs(for: loadedDocument.items)
        let settings = await settingsStore.load()
        display = FavoriteLibraryDisplayState(
            layoutMode: settings.favorites.layoutMode,
            showsCategoryCounts: settings.favorites.showsCategoryCounts
        )
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
    }

    func reload() async {
        let loadedDocument = await libraryStore.load()
        contentCoverURLsByTargetID = await contentCoverURLs(for: loadedDocument.items)
        document = loadedDocument
        if !loadedDocument.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = loadedDocument.defaultCategory.id
        }
        if let selectedCollectionID,
           !loadedDocument.collections.contains(where: { $0.id == selectedCollectionID && $0.categoryID == selectedCategoryID }) {
            self.selectedCollectionID = nil
        }
    }

    private func reloadReadingProgress() async {
        readingProgress = await readingProgressStore.loadAll()
        refreshDerivedState()
    }

    // MARK: - Categories

    @discardableResult
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

    func updateTags(for itemID: String, tagIDs: Set<String>) async {
        await commit { document in
            document.replaceTags(for: [itemID], with: tagIDs)
        }
    }

    func updateTagsForSelection(_ tagIDs: Set<String>) async {
        let favoriteIDs = selection.selectedFavoriteIDs
        guard !favoriteIDs.isEmpty else { return }
        let committed: Void? = await commit { document in
            document.replaceTags(for: favoriteIDs, with: tagIDs)
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    // MARK: - Selection operations

    func toggleCollectionSelection(id: String) {
        guard selectedCollectionID == nil else { return }
        selection.toggleCollectionSelection(id: id)
    }

    func selectAllVisible() {
        selection.selectAll(
            favoriteIDs: derived.cards.map(\.id),
            collectionIDs: selectedCollectionID == nil ? currentCategoryCollections.map(\.id) : []
        )
    }

    func invertVisibleSelection() {
        selection.invertSelection(
            favoriteIDs: derived.cards.map(\.id),
            collectionIDs: selectedCollectionID == nil ? currentCategoryCollections.map(\.id) : []
        )
    }

    @discardableResult
    func createCollectionFromSelection(name: String, color: FavoriteCollectionColor = .gray) async -> LocalFavoriteCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let favoriteIDs = selection.selectedFavoriteIDs
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
        let favoriteIDs = selection.selectedFavoriteIDs
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
        let favoriteIDs = selection.selectedFavoriteIDs
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
        let favoriteIDs = selection.selectedFavoriteIDs
        guard !favoriteIDs.isEmpty else { return }
        let committed: Void? = await commit { document in
            document.moveItems(ids: favoriteIDs, to: .category(categoryID), removing: nil)
        }
        guard committed != nil else { return }
        selection.exitSelectionMode()
    }

    func addSelectionToCollection(id collectionID: String) async {
        let favoriteIDs = selection.selectedFavoriteIDs
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

    func deleteSelection(scope: LocalFavoriteDeleteScope = .everywhere) async {
        guard selection.selectedEntryCount > 0 else { return }
        let favoriteIDs = selection.selectedFavoriteIDs
        let collectionIDs = selection.selectedCollectionIDs
        let source = selectionSourceLocation
        let deleter = remoteDeleter
        let committed: Void? = await commit { document in
            switch scope {
            case .currentLocation:
                document.removeItems(ids: favoriteIDs, from: source)
            case .everywhere:
                let selectedItems = document.items.filter { favoriteIDs.contains($0.id) }
                try await deleter.deleteRemoteFavorites(for: selectedItems)
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

    func deleteItem(_ item: FavoriteItem, scope: LocalFavoriteDeleteScope = .everywhere) async {
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
                try await deleter.deleteRemoteFavorites(for: [latestItem])
                document.removeItem(target: latestItem.target)
            }
        }
    }

    // MARK: - Search

    func enterSearchMode() {
        selection.enterSearchMode(draftText: filter.searchText)
    }

    func submitSearch() {
        let submittedText = selection.submitSearchDraft()
        if filter.searchText != submittedText {
            filter.searchText = submittedText
        }
    }

    func exitSearchMode() {
        selection.exitSearchMode()
        if !filter.searchText.isEmpty {
            filter.searchText = ""
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
                contentCoverURLsByTargetID: contentCoverURLsByTargetID
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
    @discardableResult
    private func commit<Result>(
        _ transform: (inout FavoriteLibraryDocument) async throws -> Result
    ) async -> Result? {
        do {
            var updatedDocument = await libraryStore.load()
            let result = try await transform(&updatedDocument)
            try await libraryStore.save(updatedDocument)
            document = updatedDocument
            errorMessage = nil
            return result
        } catch is CommitAbort {
            return nil
        } catch {
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
            try? await settingsStore.save(settings)
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
                await MainActor.run {
                    rollback()
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Covers

    private func contentCoverURLs(for items: [FavoriteItem]) async -> [String: URL] {
        var urlsByTargetID: [String: URL] = [:]
        for item in items {
            guard let key = Self.contentCoverKey(for: item.target),
                  let cover = await contentCoverStore.cover(for: key),
                  let resolvedURL = cover.resolvedURL else {
                continue
            }
            urlsByTargetID[item.target.id] = resolvedURL
        }
        return urlsByTargetID
    }

    private static func contentCoverKey(for target: FavoriteContentTarget) -> ContentCoverKey? {
        guard let threadID = target.threadID else { return nil }
        switch target.kind {
        case .normalThread:
            return ContentCoverKey(targetType: .threadNormal, targetID: threadID)
        case .novelThread:
            return ContentCoverKey(targetType: .threadNovel, targetID: threadID)
        case .mangaTitle:
            return nil
        }
    }
}
