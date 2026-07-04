import Foundation
import UIKit
import YamiboReaderCore

enum LocalFavoriteOpenTarget: Sendable {
    case reader(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case nativeThread(url: URL, title: String)
    case web(URL)
}

enum LocalFavoriteDeleteScope: Equatable {
    case currentLocation
    case everywhere
}

@MainActor
final class LocalFavoritesViewModel: ObservableObject {
    @Published private(set) var document = FavoriteLibraryDocument()
    @Published private(set) var cards: [FavoriteCardProjection] = []
    @Published private(set) var categoryEntryCounts: [String: Int] = [:]
    @Published private(set) var collectionEntryCounts: [String: Int] = [:]
    @Published private(set) var sourceGroupEntryCounts: [FavoriteSourceGroup: Int] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategoryID = FavoriteCategory.defaultID {
        didSet {
            if let selectedCollectionID,
               !document.collections.contains(where: { $0.id == selectedCollectionID && $0.categoryID == selectedCategoryID }) {
                self.selectedCollectionID = nil
            }
            rebuildCards()
            persistFavoriteNavigationState(
                categoryID: selectedCategoryID,
                collectionID: selectedCollectionID
            )
        }
    }
    @Published private(set) var selectedCollectionID: String? {
        didSet {
            persistFavoriteNavigationState(
                categoryID: selectedCategoryID,
                collectionID: selectedCollectionID
            )
        }
    }
    @Published private(set) var isSelectionMode = false
    @Published private(set) var selectedFavoriteIDs: Set<String> = []
    @Published private(set) var selectedCollectionIDs: Set<String> = []
    @Published var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter = .all {
        didSet { rebuildCards() }
    }
    @Published var selectedTagIDs: Set<String> = [] {
        didSet { rebuildCards() }
    }
    @Published var sortOrder: LocalFavoriteLibrarySortOrder = .organization {
        didSet { rebuildCards() }
    }
    @Published private(set) var sortDescending = false
    @Published private(set) var layoutMode: FavoriteLibraryLayoutMode = .rowCard
    @Published private(set) var showsCategoryCounts = true
    @Published private(set) var isSearchMode = false
    @Published private(set) var remoteSyncSnapshot: FavoriteRemoteSyncSnapshot?
    @Published private(set) var favoriteUpdateSnapshot: FavoriteUpdateRunSnapshot?
    @Published private(set) var favoriteUpdateEvents: [FavoriteUpdateEvent] = []
    @Published private(set) var favoriteUpdateFidFilters: [FavoriteUpdateFidFilter] = []
    @Published private(set) var favoriteUpdateCategoryFilters: [FavoriteUpdateCategoryFilter] = []
    @Published var searchDraftText = ""
    @Published var searchText = "" {
        didSet { rebuildCards() }
    }

    private let appContext: YamiboAppContext
    private var readingProgress: [ReadingProgressRecord] = []
    private var contentCoverURLsByTargetID: [String: URL] = [:]
    private var libraryUpdatesTask: Task<Void, Never>?
    private var progressUpdatesTask: Task<Void, Never>?
    private var remoteSyncTask: Task<Void, Never>?
    private var favoriteUpdateTask: Task<Void, Never>?
    private let remoteFavoriteSyncExecutor: ((String, String) async throws -> YamiboFavoriteSyncReport)?
    private let favoriteUpdatePageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)?
    private let remoteFavoriteDeleteHandler: (([FavoriteItem]) async throws -> Void)?
#if canImport(UIKit)
    private var remoteSyncBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
#endif

    private static var activeRemoteSyncCancelHandlers: [String: () -> Void] = [:]

    static func isRemoteSyncRunActive(_ runID: String) -> Bool {
        activeRemoteSyncCancelHandlers[runID] != nil
    }

    init(
        appContext: YamiboAppContext,
        remoteFavoriteSyncExecutor: ((String, String) async throws -> YamiboFavoriteSyncReport)? = nil,
        favoriteUpdatePageFetcher: ((FavoriteItem) async throws -> ForumThreadPage)? = nil,
        remoteFavoriteDeleteHandler: (([FavoriteItem]) async throws -> Void)? = nil
    ) {
        self.appContext = appContext
        self.remoteFavoriteSyncExecutor = remoteFavoriteSyncExecutor
        self.favoriteUpdatePageFetcher = favoriteUpdatePageFetcher
        self.remoteFavoriteDeleteHandler = remoteFavoriteDeleteHandler
        libraryUpdatesTask = Task { @MainActor [weak self, store = appContext.localFavoriteLibraryStore] in
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
        progressUpdatesTask = Task { @MainActor [weak self, store = appContext.readingProgressStore] in
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
        remoteSyncTask?.cancel()
        favoriteUpdateTask?.cancel()
    }

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

    var selectedFavoriteCount: Int {
        selectedFavoriteIDs.count
    }

    var selectedCollectionCount: Int {
        selectedCollectionIDs.count
    }

    var selectedEntryCount: Int {
        selectedFavoriteIDs.count + selectedCollectionIDs.count
    }

    var canCreateCollectionFromSelection: Bool {
        !selectedFavoriteIDs.isEmpty
    }

    var singleSelectedCollection: LocalFavoriteCollection? {
        guard selectedCollectionIDs.count == 1,
              let id = selectedCollectionIDs.first else { return nil }
        return document.collections.first { $0.id == id }
    }

    var availableSourceGroups: [FavoriteSourceGroup] {
        sourceGroupEntryCounts.keys
            .sorted { sourceGroupLabel($0).localizedCaseInsensitiveCompare(sourceGroupLabel($1)) == .orderedAscending }
    }

    func load() async {
        document = await appContext.localFavoriteLibraryStore.load()
        readingProgress = await appContext.readingProgressStore.loadAll()
        contentCoverURLsByTargetID = await contentCoverURLs(for: document.items)
        let settings = await appContext.settingsStore.load()
        layoutMode = settings.favoriteLayoutMode
        sortOrder = settings.favoriteSortOrder
        sortDescending = settings.favoriteSortDescending
        showsCategoryCounts = settings.favoriteShowsCategoryCounts
        remoteSyncSnapshot = await interruptedSnapshotIfNeeded(settings.favoriteRemoteSyncSnapshot)
        await reloadFavoriteUpdateState()
        let savedCollection = settings.favoriteSelectedCollectionID.flatMap { savedID in
            document.collections.first { $0.id == savedID }
        }
        if let savedCollection {
            selectedCategoryID = savedCollection.categoryID
        } else if let savedCategoryID = settings.favoriteSelectedCategoryID,
                  document.categories.contains(where: { $0.id == savedCategoryID }) {
            selectedCategoryID = savedCategoryID
        }
        if !document.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = document.defaultCategory.id
        }
        if let savedCollection, savedCollection.categoryID == selectedCategoryID {
            selectedCollectionID = savedCollection.id
        } else {
            selectedCollectionID = nil
        }
        rebuildCards()
    }

    func startFavoriteUpdateCheck() async -> String? {
        if favoriteUpdateSnapshot?.status == .running {
            return favoriteUpdateSnapshot?.runID
        }
        let now = Date()
        let snapshot = FavoriteUpdateRunSnapshot(
            status: .running,
            phase: .preparing,
            startedAt: now,
            updatedAt: now,
            currentItem: L10n.string("favorites.updates.preparing")
        )
        favoriteUpdateSnapshot = snapshot
        do {
            try await appContext.favoriteUpdateStore.saveRun(snapshot)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        favoriteUpdateTask?.cancel()
        favoriteUpdateTask = Task { @MainActor [weak self] in
            await self?.runFavoriteUpdateCheck(runID: snapshot.runID)
        }
        return snapshot.runID
    }

    func interruptFavoriteUpdateCheck() async {
        guard favoriteUpdateSnapshot?.status == .running else { return }
        favoriteUpdateTask?.cancel()
        await updateFavoriteUpdateSnapshot { snapshot in
            snapshot.status = .interrupted
            snapshot.phase = .interrupted
            snapshot.finishedAt = .now
            snapshot.errorMessage = L10n.string("favorites.updates.interrupted")
            snapshot.currentItem = L10n.string("favorites.updates.interrupted")
        }
    }

    func markFavoriteUpdateEventRead(_ eventID: String) async {
        do {
            try await appContext.favoriteUpdateStore.markEventRead(eventID)
            await reloadFavoriteUpdateState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissFavoriteUpdateEvent(_ eventID: String) async {
        do {
            try await appContext.favoriteUpdateStore.dismissEvent(eventID)
            await reloadFavoriteUpdateState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissAllFavoriteUpdateEvents() async {
        do {
            try await appContext.favoriteUpdateStore.dismissAllEvents()
            await reloadFavoriteUpdateState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFavoriteUpdateFidFilter(_ fid: String, enabled: Bool) async {
        do {
            try await appContext.favoriteUpdateStore.setFidEnabled(fid, enabled: enabled)
            await reloadFavoriteUpdateState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFavoriteUpdateCategoryFilter(_ categoryID: String, enabled: Bool) async {
        do {
            try await appContext.favoriteUpdateStore.setCategoryEnabled(categoryID, enabled: enabled)
            await reloadFavoriteUpdateState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateLayoutMode(_ value: FavoriteLibraryLayoutMode) {
        guard value != layoutMode else { return }
        let previous = layoutMode
        layoutMode = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.favoriteLayoutMode = value
            settings.favoriteShowsCategoryCounts = showsCategoryCounts
            settings.favoriteSortOrder = sortOrder
            settings.favoriteSortDescending = sortDescending
            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if layoutMode == value {
                        layoutMode = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateShowsCategoryCounts(_ value: Bool) {
        guard value != showsCategoryCounts else { return }
        let previous = showsCategoryCounts
        showsCategoryCounts = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.favoriteShowsCategoryCounts = value
            settings.favoriteLayoutMode = layoutMode
            settings.favoriteSortOrder = sortOrder
            settings.favoriteSortDescending = sortDescending
            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if showsCategoryCounts == value {
                        showsCategoryCounts = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateSortOrder(_ value: LocalFavoriteLibrarySortOrder) {
        guard value != sortOrder else { return }
        let previous = sortOrder
        sortOrder = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.favoriteSortOrder = value
            settings.favoriteSortDescending = sortDescending
            settings.favoriteLayoutMode = layoutMode
            settings.favoriteShowsCategoryCounts = showsCategoryCounts
            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if sortOrder == value {
                        sortOrder = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateSortDescending(_ value: Bool) {
        guard value != sortDescending else { return }
        let previous = sortDescending
        sortDescending = value
        rebuildCards()

        Task {
            var settings = await appContext.settingsStore.load()
            settings.favoriteSortOrder = sortOrder
            settings.favoriteSortDescending = value
            settings.favoriteLayoutMode = layoutMode
            settings.favoriteShowsCategoryCounts = showsCategoryCounts
            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if sortDescending == value {
                        sortDescending = previous
                        rebuildCards()
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func toggleTagFilter(id tagID: String) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
    }

    func clearTagFilter() {
        selectedTagIDs.removeAll()
    }

    func enterSearchMode() {
        exitSelectionMode()
        searchDraftText = searchText
        isSearchMode = true
    }

    func submitSearch() {
        let submittedText = searchDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchText != submittedText {
            searchText = submittedText
        }
        isSearchMode = true
    }

    func exitSearchMode() {
        isSearchMode = false
        searchDraftText = ""
        if searchText != "" {
            searchText = ""
        }
        exitSelectionMode()
    }

    func enterSelectionMode() {
        isSearchMode = false
        isSelectionMode = true
    }

    func exitSelectionMode() {
        isSelectionMode = false
        clearSelection()
    }

    func clearSelection() {
        selectedFavoriteIDs.removeAll()
        selectedCollectionIDs.removeAll()
    }

    func toggleFavoriteSelection(id: String) {
        isSearchMode = false
        isSelectionMode = true
        if selectedFavoriteIDs.contains(id) {
            selectedFavoriteIDs.remove(id)
        } else {
            selectedFavoriteIDs.insert(id)
        }
    }

    func toggleCollectionSelection(id: String) {
        guard selectedCollectionID == nil else { return }
        isSearchMode = false
        isSelectionMode = true
        if selectedCollectionIDs.contains(id) {
            selectedCollectionIDs.remove(id)
        } else {
            selectedCollectionIDs.insert(id)
        }
    }

    func selectAllVisible() {
        isSearchMode = false
        isSelectionMode = true
        selectedFavoriteIDs.formUnion(cards.map(\.id))
        if selectedCollectionID == nil {
            selectedCollectionIDs.formUnion(currentCategoryCollections.map(\.id))
        }
    }

    func invertVisibleSelection() {
        isSearchMode = false
        isSelectionMode = true
        for id in cards.map(\.id) {
            if selectedFavoriteIDs.contains(id) {
                selectedFavoriteIDs.remove(id)
            } else {
                selectedFavoriteIDs.insert(id)
            }
        }
        guard selectedCollectionID == nil else { return }
        for id in currentCategoryCollections.map(\.id) {
            if selectedCollectionIDs.contains(id) {
                selectedCollectionIDs.remove(id)
            } else {
                selectedCollectionIDs.insert(id)
            }
        }
    }

    @discardableResult
    func createCategory(name: String) async -> FavoriteCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            let category = updatedDocument.createCategory(name: trimmed)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            selectedCategoryID = category.id
            rebuildCards()
            return category
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameCategory(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.renameCategory(id: id, name: trimmed)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCategory(id: String) async {
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.deleteCategory(id: id)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            if !updatedDocument.categories.contains(where: { $0.id == selectedCategoryID }) {
                selectedCategoryID = updatedDocument.defaultCategory.id
            }
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCategory(id: String, direction: CategoryMoveDirection) async {
        let nonDefaultCategories = document.categories
            .filter { !$0.isDefault }
            .sorted { $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder }
        guard let index = nonDefaultCategories.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard nonDefaultCategories.indices.contains(targetIndex) else { return }
        var orderedIDs = nonDefaultCategories.map(\.id)
        orderedIDs.swapAt(index, targetIndex)

        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.reorderCategories(orderedIDs: orderedIDs)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openCollection(id: String) {
        guard let collection = document.collections.first(where: { $0.id == id }) else { return }
        if selectedCategoryID != collection.categoryID {
            selectedCategoryID = collection.categoryID
        }
        selectedCollectionID = id
        rebuildCards()
    }

    func closeCollection() {
        selectedCollectionID = nil
        rebuildCards()
    }

    @discardableResult
    func createCollection(name: String, color: FavoriteCollectionColor = .gray) async -> LocalFavoriteCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            let collection = updatedDocument.createCollection(categoryID: selectedCategoryID, name: trimmed, color: color)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            selectedCollectionID = collection.id
            rebuildCards()
            return collection
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateCollection(id: String, name: String, color: FavoriteCollectionColor) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.renameCollection(id: id, name: trimmed)
            updatedDocument.recolorCollection(id: id, color: color)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dissolveCollection(id: String) async {
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.dissolveCollection(id: id)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            if selectedCollectionID == id {
                selectedCollectionID = nil
            }
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCollection(id: String, direction: CategoryMoveDirection) async {
        guard let collection = document.collections.first(where: { $0.id == id }) else { return }
        let siblings = document.collections
            .filter { $0.categoryID == collection.categoryID }
            .sorted { $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder }
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = direction == .up ? index - 1 : index + 1
        guard siblings.indices.contains(targetIndex) else { return }
        var orderedIDs = siblings.map(\.id)
        orderedIDs.swapAt(index, targetIndex)

        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.reorderCollections(categoryID: collection.categoryID, orderedIDs: orderedIDs)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveCollection(id: String, toCategoryID categoryID: String) async {
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.moveCollection(id: id, toCategoryID: categoryID)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            if selectedCollectionID == id {
                selectedCategoryID = categoryID
            }
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createCollectionFromSelection(name: String, color: FavoriteCollectionColor = .gray) async -> LocalFavoriteCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedFavoriteIDs.isEmpty else { return nil }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            let collection = updatedDocument.createCollection(categoryID: selectedCategoryID, name: trimmed, color: color)
            Self.moveItems(
                ids: selectedFavoriteIDs,
                to: .collection(categoryID: collection.categoryID, collectionID: collection.id),
                removing: selectionSourceLocation,
                in: &updatedDocument
            )
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            selectedCollectionID = collection.id
            clearSelection()
            isSelectionMode = false
            rebuildCards()
            return collection
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func moveSelectionToCategory(id categoryID: String) async {
        guard selectedEntryCount > 0 else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            for collectionID in selectedCollectionIDs {
                updatedDocument.moveCollection(id: collectionID, toCategoryID: categoryID)
            }
            Self.moveItems(
                ids: selectedFavoriteIDs,
                to: .category(categoryID),
                removing: selectionSourceLocation,
                in: &updatedDocument
            )
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            selectedCategoryID = categoryID
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveSelectionToCollection(id collectionID: String) async {
        guard !selectedFavoriteIDs.isEmpty,
              let collection = document.collections.first(where: { $0.id == collectionID }) else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            Self.moveItems(
                ids: selectedFavoriteIDs,
                to: .collection(categoryID: collection.categoryID, collectionID: collection.id),
                removing: selectionSourceLocation,
                in: &updatedDocument
            )
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            selectedCategoryID = collection.categoryID
            selectedCollectionID = collection.id
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSelectionToCategory(id categoryID: String) async {
        guard !selectedFavoriteIDs.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            Self.moveItems(
                ids: selectedFavoriteIDs,
                to: .category(categoryID),
                removing: nil,
                in: &updatedDocument
            )
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSelectionToCollection(id collectionID: String) async {
        guard !selectedFavoriteIDs.isEmpty,
              let collection = document.collections.first(where: { $0.id == collectionID }) else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            Self.moveItems(
                ids: selectedFavoriteIDs,
                to: .collection(categoryID: collection.categoryID, collectionID: collection.id),
                removing: nil,
                in: &updatedDocument
            )
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectionFromCurrentLocation() async {
        guard !selectedFavoriteIDs.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            Self.removeItems(
                ids: selectedFavoriteIDs,
                from: selectionSourceLocation,
                in: &updatedDocument
            )
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dissolveSelectedCollections() async {
        guard !selectedCollectionIDs.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            for collectionID in selectedCollectionIDs {
                updatedDocument.dissolveCollection(id: collectionID)
            }
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelection(scope: LocalFavoriteDeleteScope = .everywhere) async {
        guard selectedEntryCount > 0 else { return }
        let favoriteIDs = selectedFavoriteIDs
        let collectionIDs = selectedCollectionIDs
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            let selectedItems = updatedDocument.items.filter { favoriteIDs.contains($0.id) }
            let itemsDeletedEverywhere: [FavoriteItem]
            let collectionsDeletedEverywhere: Set<String>
            switch scope {
            case .currentLocation:
                Self.removeItems(
                    ids: favoriteIDs,
                    from: selectionSourceLocation,
                    in: &updatedDocument
                )
                itemsDeletedEverywhere = []
                collectionsDeletedEverywhere = []
            case .everywhere:
                itemsDeletedEverywhere = selectedItems
                collectionsDeletedEverywhere = collectionIDs
            }
            try await deleteRemoteFavorites(for: itemsDeletedEverywhere)
            for item in itemsDeletedEverywhere {
                updatedDocument.removeItem(target: item.target)
            }
            for collectionID in collectionsDeletedEverywhere {
                updatedDocument.dissolveCollection(id: collectionID)
            }
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            clearSelection()
            isSelectionMode = false
            rebuildCards()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createTag(name: String, color: FavoriteTagColor = .gray) async -> FavoriteTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            let tag = updatedDocument.createTag(name: trimmed, color: color)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
            return tag
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateTag(id tagID: String, name: String, color: FavoriteTagColor) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.renameTag(id: tagID, name: trimmed)
            updatedDocument.recolorTag(id: tagID, color: color)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTag(id tagID: String) async {
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            updatedDocument.deleteTag(id: tagID)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            selectedTagIDs.remove(tagID)
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTags(for itemID: String, tagIDs: Set<String>) async {
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            Self.replaceTags(for: [itemID], with: tagIDs, in: &updatedDocument)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTagsForSelection(_ tagIDs: Set<String>) async {
        guard !selectedFavoriteIDs.isEmpty else { return }
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            Self.replaceTags(for: selectedFavoriteIDs, with: tagIDs, in: &updatedDocument)
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            clearSelection()
            isSelectionMode = false
            rebuildCards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        document = await appContext.localFavoriteLibraryStore.load()
        contentCoverURLsByTargetID = await contentCoverURLs(for: document.items)
        if !document.categories.contains(where: { $0.id == selectedCategoryID }) {
            selectedCategoryID = document.defaultCategory.id
        }
        if let selectedCollectionID,
           !document.collections.contains(where: { $0.id == selectedCollectionID && $0.categoryID == selectedCategoryID }) {
            self.selectedCollectionID = nil
        }
        rebuildCards()
    }

    func reloadReadingProgress() async {
        readingProgress = await appContext.readingProgressStore.loadAll()
        rebuildCards()
    }

    @discardableResult
    func startRemoteFavoriteSync(targetCategoryID: String) async -> String? {
        if remoteSyncSnapshot?.status == .running {
            return remoteSyncSnapshot?.runID
        }

        let categoryName = document.categories.first { $0.id == targetCategoryID }?.displayName ?? document.defaultCategory.displayName
        let now = Date()
        let snapshot = FavoriteRemoteSyncSnapshot(
            status: .running,
            targetCategoryID: targetCategoryID,
            targetCategoryName: categoryName,
            phase: L10n.string("favorites.sync.phase.queued"),
            startedAt: now,
            updatedAt: now,
            logMessages: [L10n.string("favorites.sync.log.started", categoryName)]
        )
        remoteSyncSnapshot = snapshot
        await persistRemoteSyncSnapshot(snapshot)

        remoteSyncTask?.cancel()
        remoteSyncTask = Task { @MainActor [weak self] in
            await self?.runRemoteFavoriteSync(runID: snapshot.runID, targetCategoryID: targetCategoryID)
        }
        Self.activeRemoteSyncCancelHandlers[snapshot.runID] = { [weak self] in
            self?.remoteSyncTask?.cancel()
        }
        return snapshot.runID
    }

    @discardableResult
    func resumeRemoteFavoriteSync() async -> String? {
        guard let snapshot = remoteSyncSnapshot else { return nil }
        return await startRemoteFavoriteSync(targetCategoryID: snapshot.targetCategoryID)
    }

    func interruptRemoteFavoriteSync() async {
        guard let runID = remoteSyncSnapshot?.runID,
              remoteSyncSnapshot?.status == .running else { return }
        remoteSyncTask?.cancel()
        Self.activeRemoteSyncCancelHandlers[runID]?()
        await updateRemoteSyncSnapshot { snapshot in
            snapshot.status = .interrupted
            snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
            snapshot.finishedAt = .now
            snapshot.warningMessages.append(L10n.string("favorites.sync.warning.interrupted_by_user"))
            snapshot.logMessages.append(L10n.string("favorites.sync.log.interrupted"))
        }
        endRemoteSyncBackgroundTask()
    }

    func hideRemoteFavoriteSyncCard() async {
        guard remoteSyncSnapshot != nil else { return }
        await updateRemoteSyncSnapshot { snapshot in
            snapshot.isHiddenFromFavoritePage = true
        }
    }

    func refreshRemoteFavorites() async {
        _ = await startRemoteFavoriteSync(targetCategoryID: selectedCategoryID)
    }

    private func runRemoteFavoriteSync(runID: String, targetCategoryID: String) async {
        beginRemoteSyncBackgroundTask(runID: runID)
        defer {
            endRemoteSyncBackgroundTask()
            Self.activeRemoteSyncCancelHandlers[runID] = nil
        }

        do {
            await updateRemoteSyncSnapshot(runID: runID) { snapshot in
                snapshot.phase = L10n.string("favorites.sync.phase.fetching")
                snapshot.logMessages.append(L10n.string("favorites.sync.log.fetching"))
            }
            if let remoteFavoriteSyncExecutor {
                let report = try await remoteFavoriteSyncExecutor(runID, targetCategoryID)
                try Task.checkCancellation()
                await finishRemoteFavoriteSync(runID: runID, report: report)
                return
            }
            let repository = await appContext.makeFavoriteRepository()
            let remoteFavorites = try await repository.fetchFavorites()
            try Task.checkCancellation()
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            let entries = remoteFavorites.enumerated().map { index, favorite in
                YamiboRemoteFavoriteEntry(
                    remoteFavoriteID: favorite.remoteFavoriteID ?? favorite.id,
                    threadURL: favorite.url,
                    title: favorite.title,
                    remoteOrder: index
                )
            }
            await updateRemoteSyncSnapshot(runID: runID) { snapshot in
                snapshot.phase = L10n.string("favorites.sync.phase.importing")
                snapshot.totalRemoteCount = entries.count
                snapshot.scannedCount = entries.count
                snapshot.logMessages.append(L10n.string("favorites.sync.log.fetched", entries.count))
            }
            let resolver = await appContext.makeThreadOpenResolver()
            let coverRepository = await appContext.makeForumThreadReaderRepository()
            let report = await updatedDocument.syncYamiboRemoteFavorites(
                into: targetCategoryID,
                remoteEntries: entries,
                date: .now,
                probe: { url in
                    let targetKey = YamiboThreadURLCanonicalizer.canonicalThreadURLKey(for: url)
                    let title = remoteFavorites.first {
                        YamiboThreadURLCanonicalizer.canonicalThreadURLKey(for: $0.url) == targetKey
                    }?.title
                    return try await Self.probeResult(
                        for: url,
                        title: title,
                        resolver: resolver,
                        coverRepository: coverRepository
                    )
                }
            )
            try Task.checkCancellation()
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            contentCoverURLsByTargetID = await contentCoverURLs(for: updatedDocument.items)
            errorMessage = nil
            rebuildCards()
            await finishRemoteFavoriteSync(runID: runID, report: report)
        } catch {
            if isCancellationError(error) {
                await updateRemoteSyncSnapshot(runID: runID) { snapshot in
                    snapshot.status = .interrupted
                    snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
                    snapshot.finishedAt = .now
                    snapshot.warningMessages.append(L10n.string("favorites.sync.warning.interrupted"))
                    snapshot.logMessages.append(L10n.string("favorites.sync.log.interrupted"))
                }
                return
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            await updateRemoteSyncSnapshot(runID: runID) { snapshot in
                snapshot.status = .failed
                snapshot.phase = L10n.string("favorites.sync.phase.failed")
                snapshot.finishedAt = .now
                snapshot.errorMessages.append(message)
                snapshot.logMessages.append(L10n.string("favorites.sync.log.failed"))
            }
        }
    }

    private func finishRemoteFavoriteSync(runID: String, report: YamiboFavoriteSyncReport) async {
        await updateRemoteSyncSnapshot(runID: runID) { snapshot in
            snapshot.status = .completed
            snapshot.phase = L10n.string("favorites.sync.phase.completed")
            snapshot.finishedAt = .now
            snapshot.importedCount = report.importedTargetIDs.count
            snapshot.failedCount = report.failedRemoteFavoriteIDs.count
            snapshot.markedMissingCount = report.markedMissingTargetIDs.count
            snapshot.uploadTargetCount = report.uploadTargetIDs.count
            snapshot.logMessages.append(L10n.string("favorites.sync.log.completed", report.importedTargetIDs.count))
            if !report.failedRemoteFavoriteIDs.isEmpty {
                snapshot.warningMessages.append(L10n.string("favorites.sync.warning.failed_items", report.failedRemoteFavoriteIDs.count))
            }
            if !report.uploadTargetIDs.isEmpty {
                snapshot.warningMessages.append(L10n.string("favorites.sync.warning.upload_pending", report.uploadTargetIDs.count))
            }
        }
    }

    private func reloadFavoriteUpdateState() async {
        var latest = await appContext.favoriteUpdateStore.latestRun()
        if var loaded = latest, loaded.status == .running {
            loaded.status = .interrupted
            loaded.phase = .interrupted
            loaded.finishedAt = loaded.finishedAt ?? .now
            loaded.updatedAt = .now
            loaded.errorMessage = L10n.string("favorites.updates.task_lost")
            try? await appContext.favoriteUpdateStore.saveRun(loaded)
            latest = loaded
        }
        favoriteUpdateSnapshot = latest
        let state = await appContext.favoriteUpdateStore.loadState()
        favoriteUpdateEvents = state.events
            .filter { $0.dismissedAt == nil }
            .sorted { lhs, rhs in
                if lhs.detectedAt != rhs.detectedAt { return lhs.detectedAt > rhs.detectedAt }
                return lhs.id > rhs.id
            }
        favoriteUpdateFidFilters = state.fidFilters.sorted { lhs, rhs in
            if lhs.forumName != rhs.forumName { return lhs.forumName < rhs.forumName }
            return lhs.fid < rhs.fid
        }
        favoriteUpdateCategoryFilters = state.categoryFilters.sorted { lhs, rhs in
            if lhs.categoryName != rhs.categoryName { return lhs.categoryName < rhs.categoryName }
            return lhs.categoryID < rhs.categoryID
        }
    }

    private func runFavoriteUpdateCheck(runID: String) async {
        do {
            let loadedDocument = await appContext.localFavoriteLibraryStore.load()
            let candidates = favoriteUpdateCandidates(in: loadedDocument)
            try await refreshFavoriteUpdateFilters(candidates: candidates, document: loadedDocument)
            let scopedCandidates = await scopedFavoriteUpdateCandidates(candidates)
            try await replaceFavoriteUpdateTargetsIfNeeded(candidates)
            await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                snapshot.phase = .checking
                snapshot.totalCount = scopedCandidates.count
                snapshot.currentItem = L10n.string("favorites.updates.loaded_targets", scopedCandidates.count)
            }

            var detectedCount = 0
            for (index, item) in scopedCandidates.enumerated() {
                try Task.checkCancellation()
                await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                    snapshot.currentItem = L10n.string("favorites.updates.checking_item", index + 1, scopedCandidates.count, item.resolvedDisplayTitle)
                }
                let result = await checkFavoriteUpdate(for: item)
                switch result {
                case let .checked(detected):
                    detectedCount += detected
                    await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                        snapshot.completedCount += 1
                        snapshot.detectedCount = detectedCount
                    }
                case .skipped:
                    await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                        snapshot.skippedCount += 1
                    }
                case let .failed(message):
                    await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                        snapshot.failedCount += 1
                        snapshot.warningMessage = [snapshot.warningMessage, message].compactMap { $0 }.joined(separator: "\n")
                    }
                }
            }

            await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                snapshot.status = .completed
                snapshot.phase = .completed
                snapshot.finishedAt = .now
                snapshot.currentItem = L10n.string("favorites.updates.completed")
                snapshot.logMessage = L10n.string("favorites.updates.detected_count", detectedCount)
            }
            await reloadFavoriteUpdateState()
        } catch {
            if isCancellationError(error) {
                await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                    snapshot.status = .interrupted
                    snapshot.phase = .interrupted
                    snapshot.finishedAt = .now
                    snapshot.currentItem = L10n.string("favorites.updates.interrupted")
                    snapshot.errorMessage = L10n.string("favorites.updates.interrupted")
                }
                await reloadFavoriteUpdateState()
                return
            }
            await updateFavoriteUpdateSnapshot(runID: runID) { snapshot in
                snapshot.status = .failed
                snapshot.phase = .failed
                snapshot.finishedAt = .now
                snapshot.currentItem = L10n.string("favorites.updates.failed")
                snapshot.errorMessage = error.localizedDescription
            }
            await reloadFavoriteUpdateState()
        }
    }

    private func updateFavoriteUpdateSnapshot(
        runID: String? = nil,
        mutate: (inout FavoriteUpdateRunSnapshot) -> Void
    ) async {
        guard var snapshot = favoriteUpdateSnapshot else { return }
        if let runID, snapshot.runID != runID { return }
        mutate(&snapshot)
        snapshot.updatedAt = .now
        favoriteUpdateSnapshot = snapshot
        do {
            try await appContext.favoriteUpdateStore.saveRun(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func favoriteUpdateCandidates(in document: FavoriteLibraryDocument) -> [FavoriteItem] {
        document.items.filter { item in
            item.target.threadID != nil && (item.target.kind == .normalThread || item.target.kind == .novelThread)
        }
    }

    private func refreshFavoriteUpdateFilters(candidates: [FavoriteItem], document: FavoriteLibraryDocument) async throws {
        let now = Date()
        let categoryNames = Dictionary(uniqueKeysWithValues: document.categories.map { ($0.id, $0.displayName) })
        var categoryCounts: [String: Int] = [:]
        var fidCounts: [FavoriteSourceGroup: Int] = [:]
        for item in candidates {
            for categoryID in Set(item.locations.compactMap(\.categoryID)) {
                categoryCounts[categoryID, default: 0] += 1
            }
            fidCounts[item.sourceGroup, default: 0] += 1
        }
        let categoryFilters = categoryCounts.map { categoryID, count in
            FavoriteUpdateCategoryFilter(
                categoryID: categoryID,
                categoryName: categoryNames[categoryID] ?? categoryID,
                itemCount: count,
                updatedAt: now
            )
        }
        let fidFilters = fidCounts.compactMap { sourceGroup, count -> FavoriteUpdateFidFilter? in
            guard case let .forumBoard(id, label) = sourceGroup else { return nil }
            return FavoriteUpdateFidFilter(fid: id, forumName: label, itemCount: count, updatedAt: now)
        }
        try await appContext.favoriteUpdateStore.replaceFilters(
            fidFilters: fidFilters.sorted { $0.fid < $1.fid },
            categoryFilters: categoryFilters.sorted { $0.categoryID < $1.categoryID }
        )
    }

    private func scopedFavoriteUpdateCandidates(_ candidates: [FavoriteItem]) async -> [FavoriteItem] {
        let state = await appContext.favoriteUpdateStore.loadState()
        let enabledFids = Set(state.fidFilters.filter(\.enabled).map(\.fid))
        let disabledFidsExist = state.fidFilters.contains { !$0.enabled }
        let enabledCategories = Set(state.categoryFilters.filter(\.enabled).map(\.categoryID))
        let disabledCategoriesExist = state.categoryFilters.contains { !$0.enabled }
        return candidates.filter { item in
            let fidMatches: Bool
            if disabledFidsExist {
                if case let .forumBoard(id, _) = item.sourceGroup {
                    fidMatches = enabledFids.contains(id)
                } else {
                    fidMatches = false
                }
            } else {
                fidMatches = true
            }
            let categoryMatches = !disabledCategoriesExist || !Set(item.locations.compactMap(\.categoryID)).isDisjoint(with: enabledCategories)
            return fidMatches && categoryMatches
        }
    }

    private func replaceFavoriteUpdateTargetsIfNeeded(_ candidates: [FavoriteItem]) async throws {
        let state = await appContext.favoriteUpdateStore.loadState()
        let existingByID = Dictionary(uniqueKeysWithValues: state.trackedTargets.map { ($0.id, $0) })
        let targets = candidates.map { item -> FavoriteUpdateTrackedTarget in
            var existing = existingByID[item.target.id] ?? FavoriteUpdateTrackedTarget(
                target: item.target,
                title: item.resolvedDisplayTitle,
                mode: item.target.kind == .novelThread ? .novelThread : .normalThread
            )
            existing.title = item.resolvedDisplayTitle
            existing.mode = item.target.kind == .novelThread ? .novelThread : .normalThread
            existing.categoryIDs = Set(item.locations.compactMap(\.categoryID))
            if case let .forumBoard(id, label) = item.sourceGroup {
                existing.fid = id
                existing.forumName = label
            }
            existing.coverURL = item.coverURL
            return existing
        }
        try await appContext.favoriteUpdateStore.replaceTrackedTargets(targets)
    }

    private enum FavoriteUpdateCheckResult {
        case checked(detected: Int)
        case skipped
        case failed(String)
    }

    private func checkFavoriteUpdate(for item: FavoriteItem) async -> FavoriteUpdateCheckResult {
        guard let page = await favoriteUpdatePage(for: item) else { return .skipped }
        let fingerprint = FavoriteUpdateFingerprint(page: page)
        let state = await appContext.favoriteUpdateStore.loadState()
        var target = state.trackedTargets.first { $0.target == item.target } ?? FavoriteUpdateTrackedTarget(
            target: item.target,
            title: item.resolvedDisplayTitle,
            mode: item.target.kind == .novelThread ? .novelThread : .normalThread
        )
        let previous = FavoriteUpdateFingerprint(target: target)
        target.knownLatestPostID = fingerprint.latestPostID
        target.knownReplyCount = fingerprint.replyCount
        target.knownPageCount = fingerprint.pageCount
        target.baselineReady = true
        target.lastCheckedAt = .now
        target.lastError = nil
        target.consecutiveFailures = 0
        if let forumID = page.forumID ?? page.thread.fid {
            target.fid = forumID
        }
        if let forumName = page.forumName {
            target.forumName = forumName
        }

        do {
            try await appContext.favoriteUpdateStore.upsertTrackedTarget(target)
            guard previous.isReady, fingerprint.isNewer(than: previous) else {
                return .checked(detected: 0)
            }
            let summary = FavoriteUpdateFingerprint.summary(from: previous, to: fingerprint)
            let event = FavoriteUpdateEvent(
                target: item.target,
                title: item.resolvedDisplayTitle,
                mode: item.target.kind == .novelThread ? .novelThread : .normalThread,
                fid: target.fid,
                forumName: target.forumName,
                summary: summary,
                detailIDs: fingerprint.latestPostID.map { [$0] } ?? [],
                coverURL: item.coverURL,
                detectedAt: .now,
                ambiguous: fingerprint.latestPostID == nil
            )
            try await appContext.favoriteUpdateStore.insertEvent(event)
            return .checked(detected: 1)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func favoriteUpdatePage(for item: FavoriteItem) async -> ForumThreadPage? {
        do {
            if let favoriteUpdatePageFetcher {
                return try await favoriteUpdatePageFetcher(item)
            }
            guard let tid = item.target.threadID,
                  let url = threadURL(for: item.target) else {
                return nil
            }
            let repository = await appContext.makeForumThreadReaderRepository()
            let thread = ThreadIdentity(tid: tid, canonicalURL: url, fid: item.fid)
            let context = ThreadReaderLaunchContext(thread: thread, title: item.resolvedDisplayTitle)
            return try await repository.fetchThreadPage(context: context, page: 1)
        } catch {
            return nil
        }
    }

    private func interruptedSnapshotIfNeeded(_ snapshot: FavoriteRemoteSyncSnapshot?) async -> FavoriteRemoteSyncSnapshot? {
        guard var snapshot else { return nil }
        guard snapshot.status == .running else { return snapshot }
        guard !Self.isRemoteSyncRunActive(snapshot.runID) else { return snapshot }
        snapshot.status = .interrupted
        snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
        snapshot.finishedAt = snapshot.finishedAt ?? .now
        snapshot.updatedAt = .now
        snapshot.warningMessages.append(L10n.string("favorites.sync.warning.task_lost"))
        snapshot.logMessages.append(L10n.string("favorites.sync.log.task_lost"))
        await persistRemoteSyncSnapshot(snapshot)
        return snapshot
    }

    private func updateRemoteSyncSnapshot(
        runID: String? = nil,
        mutate: (inout FavoriteRemoteSyncSnapshot) -> Void
    ) async {
        guard var snapshot = remoteSyncSnapshot else { return }
        if let runID, snapshot.runID != runID { return }
        mutate(&snapshot)
        snapshot.updatedAt = .now
        remoteSyncSnapshot = snapshot
        await persistRemoteSyncSnapshot(snapshot)
    }

    private func persistRemoteSyncSnapshot(_ snapshot: FavoriteRemoteSyncSnapshot) async {
        var settings = await appContext.settingsStore.load()
        settings.favoriteRemoteSyncSnapshot = snapshot
        do {
            try await appContext.settingsStore.save(settings)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginRemoteSyncBackgroundTask(runID: String) {
        guard remoteSyncBackgroundTaskID == .invalid else { return }
        remoteSyncBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "FavoriteRemoteSync") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.remoteSyncTask?.cancel()
                await self.updateRemoteSyncSnapshot(runID: runID) { snapshot in
                    snapshot.status = .interrupted
                    snapshot.phase = L10n.string("favorites.sync.phase.interrupted")
                    snapshot.finishedAt = .now
                    snapshot.warningMessages.append(L10n.string("favorites.sync.warning.background_expired"))
                    snapshot.logMessages.append(L10n.string("favorites.sync.log.interrupted"))
                }
                self.endRemoteSyncBackgroundTask()
            }
        }
        if remoteSyncBackgroundTaskID == .invalid {
            Task { @MainActor in
                await updateRemoteSyncSnapshot(runID: runID) { snapshot in
                    snapshot.warningMessages.append(L10n.string("favorites.sync.warning.background_unavailable"))
                }
            }
        }
    }

    private func endRemoteSyncBackgroundTask() {
        guard remoteSyncBackgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(remoteSyncBackgroundTaskID)
        remoteSyncBackgroundTaskID = .invalid
    }

    func deleteItem(_ item: FavoriteItem, scope: LocalFavoriteDeleteScope = .everywhere) async {
        do {
            var updatedDocument = await appContext.localFavoriteLibraryStore.load()
            guard let latestItem = updatedDocument.items.first(where: { $0.id == item.id }) else { return }
            switch scope {
            case .currentLocation:
                if latestItem.locations.count > 1 {
                    let location = selectedCollection.map {
                        FavoriteLocation.collection(categoryID: $0.categoryID, collectionID: $0.id)
                    } ?? .category(selectedCategoryID)
                    _ = updatedDocument.removeLocation(location, from: latestItem.target)
                }
            case .everywhere:
                try await deleteRemoteFavorites(for: [latestItem])
                updatedDocument.removeItem(target: latestItem.target)
            }
            try await appContext.localFavoriteLibraryStore.save(updatedDocument)
            document = updatedDocument
            rebuildCards()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openTarget(for item: FavoriteItem, mode: FavoriteLaunchMode = .resume) async -> LocalFavoriteOpenTarget? {
        let latestDocument = await appContext.localFavoriteLibraryStore.load()
        guard let latestItem = latestDocument.items.first(where: { $0.id == item.id }) ?? document.items.first(where: { $0.id == item.id }) else {
            return nil
        }

        let progress = await progressRecord(for: latestItem)
        switch latestItem.target {
        case let .novelThread(threadID):
            let novel = progress?.novel
            let resumePoint = mode == .start ? nil : novel?.novelResumePoint
            return .reader(
                ReaderLaunchContext(
                    threadID: threadID,
                    threadTitle: latestItem.resolvedDisplayTitle,
                    source: .favorites,
                    initialView: mode == .start ? 1 : (resumePoint?.view ?? novel?.lastView),
                    authorID: resumePoint?.authorID ?? novel?.authorID,
                    initialResumePoint: resumePoint
                )
            )
        case .normalThread:
            guard let url = threadURL(for: latestItem.target) else { return nil }
            return .nativeThread(url: url, title: latestItem.resolvedDisplayTitle)
        case let .mangaTitle(_, cleanBookName):
            guard let chapterURL = mode == .start
                ? latestItem.mangaChapterMetadata?.chapterURL
                : (progress?.manga?.lastMangaURL ?? latestItem.mangaChapterMetadata?.chapterURL) else {
                errorMessage = L10n.string("favorite_library.manga_title_resolution_failed")
                return nil
            }
            guard let chapterTID = YamiboThreadURLCanonicalizer.threadID(from: chapterURL) else {
                errorMessage = L10n.string("favorite_library.manga_title_resolution_failed")
                return nil
            }
            let originalThreadID = latestItem.mangaChapterMetadata?.chapterTID ?? chapterTID
            return .manga(
                MangaLaunchContext(
                    originalThreadID: originalThreadID,
                    chapterTID: chapterTID,
                    displayTitle: latestItem.resolvedDisplayTitle,
                    source: .favorites,
                    chapterView: Self.page(from: chapterURL),
                    initialPage: mode == .start ? 0 : (progress?.manga?.mangaPageIndex ?? 0),
                    directoryName: cleanBookName,
                    offlineCacheFavoriteID: latestItem.id
                )
            )
        }
    }

    func sourceGroupLabel(_ sourceGroup: FavoriteSourceGroup) -> String {
        Self.sourceGroupLabel(sourceGroup)
    }

    private func progressRecord(for item: FavoriteItem) async -> ReadingProgressRecord? {
        switch item.target {
        case let .normalThread(threadID), let .novelThread(threadID):
            return await appContext.readingProgressStore.load(threadID: threadID)
        case .mangaTitle:
            if let progress = await appContext.readingProgressStore.load(for: item.target) {
                return progress
            }
            if let url = item.mangaChapterMetadata?.chapterURL {
                guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: url) else { return nil }
                return await appContext.readingProgressStore.load(threadID: threadID)
            }
            return nil
        }
    }

    private func rebuildCards() {
        cards = Self.cardsWithResolvedCovers(
            LocalFavoriteLibraryProjection.cards(
                    in: document,
                    query: LocalFavoriteLibraryQuery(
                        categoryID: selectedCategoryID,
                        collectionID: selectedCollectionID,
                        sourceGroupFilter: sourceGroupFilter,
                        selectedTagIDs: selectedTagIDs,
                        sortOrder: sortOrder,
                        sortsDescending: sortDescending,
                        searchText: searchText
                ),
                readingProgress: readingProgress
            ),
            contentCoverURLsByTargetID: contentCoverURLsByTargetID
        )
        categoryEntryCounts = Self.categoryEntryCounts(
            in: document,
            sourceGroupFilter: sourceGroupFilter,
            selectedTagIDs: selectedTagIDs,
            searchText: searchText,
            readingProgress: readingProgress,
            contentCoverURLsByTargetID: contentCoverURLsByTargetID
        )
        collectionEntryCounts = Self.collectionEntryCounts(
            in: document,
            sourceGroupFilter: sourceGroupFilter,
            selectedTagIDs: selectedTagIDs,
            searchText: searchText,
            readingProgress: readingProgress,
            contentCoverURLsByTargetID: contentCoverURLsByTargetID
        )
        sourceGroupEntryCounts = Self.sourceGroupEntryCounts(
            in: document,
            categoryID: selectedCategoryID,
            collectionID: selectedCollectionID,
            selectedTagIDs: selectedTagIDs,
            searchText: searchText,
            readingProgress: readingProgress,
            contentCoverURLsByTargetID: contentCoverURLsByTargetID
        )
        pruneSelection()
    }

    private var selectionSourceLocation: FavoriteLocation {
        if let selectedCollection {
            .collection(categoryID: selectedCollection.categoryID, collectionID: selectedCollection.id)
        } else {
            .category(selectedCategoryID)
        }
    }

    private func pruneSelection() {
        let validFavoriteIDs = Set(document.items.map(\.id))
        selectedFavoriteIDs.formIntersection(validFavoriteIDs)
        let validCollectionIDs = Set(document.collections.map(\.id))
        selectedCollectionIDs.formIntersection(validCollectionIDs)
        if selectedEntryCount == 0, isSelectionMode {
            isSelectionMode = false
        }
    }

    private func deleteRemoteFavorites(for items: [FavoriteItem]) async throws {
        if let remoteFavoriteDeleteHandler {
            try await remoteFavoriteDeleteHandler(items)
            return
        }
        let remoteItems = items.filter { item in
            if let remoteFavoriteID = item.remoteMapping?.yamiboFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
               !remoteFavoriteID.isEmpty {
                return true
            }
            return item.remoteMapping != nil && item.target.threadID != nil
        }
        guard !remoteItems.isEmpty else { return }
        let repository = await appContext.makeFavoriteRepository()
        for item in remoteItems {
            let remoteFavoriteID = try await remoteFavoriteID(for: item, repository: repository)
            try await repository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
        }
    }

    private func remoteFavoriteID(for item: FavoriteItem, repository: FavoriteRepository) async throws -> String {
        if let remoteFavoriteID = item.remoteMapping?.yamiboFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteFavoriteID.isEmpty {
            return remoteFavoriteID
        }
        guard let threadURL = threadURL(for: item.target) else {
            throw YamiboError.missingFavoriteDeleteID
        }
        if let remoteFavorite = try await repository.remoteFavorite(for: threadURL, maxPages: 30),
           let remoteFavoriteID = remoteFavorite.remoteFavoriteID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteFavoriteID.isEmpty {
            return remoteFavoriteID
        }
        throw YamiboError.missingFavoriteDeleteID
    }

    private func threadURL(for target: FavoriteContentTarget) -> URL? {
        guard let threadID = target.threadID else { return nil }
        return YamiboRoute.threadByID(tid: threadID, page: 1, authorID: nil, reverse: false).url
    }

    private func contentCoverURLs(for items: [FavoriteItem]) async -> [String: URL] {
        var urlsByTargetID: [String: URL] = [:]
        for item in items {
            guard let key = Self.contentCoverKey(for: item.target),
                  let cover = await appContext.contentCoverStore.cover(for: key),
                  let resolvedURL = cover.resolvedURL else {
                continue
            }
            urlsByTargetID[item.target.id] = resolvedURL
        }
        return urlsByTargetID
    }

    private static func cardsWithResolvedCovers(
        _ cards: [FavoriteCardProjection],
        contentCoverURLsByTargetID: [String: URL]
    ) -> [FavoriteCardProjection] {
        cards.map { card in
            var card = card
            card.coverURL = contentCoverURLsByTargetID[card.item.target.id] ?? card.coverURL
            return card
        }
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

    private static func moveItems(
        ids selectedIDs: Set<String>,
        to destination: FavoriteLocation,
        removing source: FavoriteLocation?,
        in document: inout FavoriteLibraryDocument
    ) {
        guard !selectedIDs.isEmpty else { return }
        document.items = document.items.map { item in
            guard selectedIDs.contains(item.id) else { return item }
            var item = item
            var locations = item.locations
            if let source, source != destination {
                locations.removeAll { $0 == source }
            }
            locations.append(destination)
            item.locations = normalizedLocations(locations)
            item.updatedAt = .now
            return item
        }
    }

    private static func removeItems(
        ids selectedIDs: Set<String>,
        from source: FavoriteLocation,
        in document: inout FavoriteLibraryDocument
    ) {
        guard !selectedIDs.isEmpty else { return }
        document.items = document.items.map { item in
            guard selectedIDs.contains(item.id),
                  item.locations.count > 1,
                  item.locations.contains(source) else {
                return item
            }
            var item = item
            item.locations.removeAll { $0 == source }
            item.updatedAt = .now
            return item
        }
    }

    private static func normalizedLocations(_ locations: [FavoriteLocation]) -> [FavoriteLocation] {
        var seen: Set<String> = []
        return locations.filter { seen.insert($0.id).inserted }
    }

    private static func replaceTags(
        for selectedIDs: Set<String>,
        with tagIDs: Set<String>,
        in document: inout FavoriteLibraryDocument
    ) {
        let validTagIDs = Set(document.tags.map(\.id))
        let normalizedTagIDs = tagIDs.filter { validTagIDs.contains($0) }.sorted()
        document.items = document.items.map { item in
            guard selectedIDs.contains(item.id) else { return item }
            var item = item
            item.tagIDs = normalizedTagIDs
            item.updatedAt = .now
            return item
        }
    }

    private static func categoryEntryCounts(
        in document: FavoriteLibraryDocument,
        sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter,
        selectedTagIDs: Set<String>,
        searchText: String,
        readingProgress: [ReadingProgressRecord],
        contentCoverURLsByTargetID: [String: URL]
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: document.categories.map { category in
            let cards = cardsWithResolvedCovers(
                LocalFavoriteLibraryProjection.cards(
                    in: document,
                    query: LocalFavoriteLibraryQuery(
                        categoryID: category.id,
                        sourceGroupFilter: sourceGroupFilter,
                        selectedTagIDs: selectedTagIDs,
                        sortOrder: .organization,
                        searchText: searchText
                    ),
                    readingProgress: readingProgress
                ),
                contentCoverURLsByTargetID: contentCoverURLsByTargetID
            )
            let collections = visibleCollections(
                in: document,
                categoryID: category.id,
                sourceGroupFilter: sourceGroupFilter,
                selectedTagIDs: selectedTagIDs,
                searchText: searchText,
                filteredCards: cards
            )
            return (category.id, cards.count + collections.count)
        })
    }

    private static func collectionEntryCounts(
        in document: FavoriteLibraryDocument,
        sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter,
        selectedTagIDs: Set<String>,
        searchText: String,
        readingProgress: [ReadingProgressRecord],
        contentCoverURLsByTargetID: [String: URL]
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: document.collections.map { collection in
            let cards = cardsWithResolvedCovers(
                LocalFavoriteLibraryProjection.cards(
                    in: document,
                    query: LocalFavoriteLibraryQuery(
                        categoryID: collection.categoryID,
                        collectionID: collection.id,
                        sourceGroupFilter: sourceGroupFilter,
                        selectedTagIDs: selectedTagIDs,
                        sortOrder: .organization,
                        searchText: searchText
                    ),
                    readingProgress: readingProgress
                ),
                contentCoverURLsByTargetID: contentCoverURLsByTargetID
            )
            return (collection.id, cards.count)
        })
    }

    private static func sourceGroupEntryCounts(
        in document: FavoriteLibraryDocument,
        categoryID: String,
        collectionID: String?,
        selectedTagIDs: Set<String>,
        searchText: String,
        readingProgress: [ReadingProgressRecord],
        contentCoverURLsByTargetID: [String: URL]
    ) -> [FavoriteSourceGroup: Int] {
        let allCards = cardsWithResolvedCovers(
            LocalFavoriteLibraryProjection.cards(
                in: document,
                query: LocalFavoriteLibraryQuery(
                    categoryID: categoryID,
                    collectionID: collectionID,
                    sourceGroupFilter: .all,
                    selectedTagIDs: selectedTagIDs,
                    sortOrder: .organization,
                    searchText: searchText
                ),
                readingProgress: readingProgress
            ),
            contentCoverURLsByTargetID: contentCoverURLsByTargetID
        )
        return Dictionary(grouping: allCards) { card in
            canonicalSourceGroup(for: card.item)
        }
            .mapValues(\.count)
    }

    private static func canonicalSourceGroup(for item: FavoriteItem) -> FavoriteSourceGroup {
        guard let forumID = item.forumID ?? item.sourceGroup.forumID else {
            return item.sourceGroup
        }
        return .forumBoard(id: forumID, label: item.forumName ?? item.sourceGroup.forumName ?? forumID)
    }

    private static func visibleCollections(
        in document: FavoriteLibraryDocument,
        categoryID: String,
        sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter,
        selectedTagIDs: Set<String>,
        searchText: String,
        filteredCards: [FavoriteCardProjection]
    ) -> [LocalFavoriteCollection] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonSearchFiltersAreActive = sourceGroupFilter != .all || !selectedTagIDs.isEmpty
        let filtersAreActive = nonSearchFiltersAreActive || !trimmedSearch.isEmpty
        let filteredCardsByCollectionID = Dictionary(
            grouping: filteredCards,
            by: { card in
                Set(card.item.locations.compactMap(\.collectionID))
            }
        )
        return document.collections.filter { collection in
            guard collection.categoryID == categoryID else { return false }
            guard filtersAreActive else { return true }
            let hasMatchingFilteredCard = filteredCardsByCollectionID.contains { collectionIDs, _ in
                collectionIDs.contains(collection.id)
            }
            if !trimmedSearch.isEmpty,
               collection.name.localizedCaseInsensitiveContains(trimmedSearch) {
                return !nonSearchFiltersAreActive || hasMatchingFilteredCard
            }
            return hasMatchingFilteredCard
        }
    }

    private func persistFavoriteNavigationState(categoryID: String, collectionID: String?) {
        guard document.categories.contains(where: { $0.id == categoryID }) else { return }
        let validCollectionID = collectionID.flatMap { id in
            document.collections.contains { $0.id == id && $0.categoryID == categoryID } ? id : nil
        }
        Task {
            var settings = await appContext.settingsStore.load()
            guard settings.favoriteSelectedCategoryID != categoryID
                    || settings.favoriteSelectedCollectionID != validCollectionID else { return }
            settings.favoriteSelectedCategoryID = categoryID
            settings.favoriteSelectedCollectionID = validCollectionID
            try? await appContext.settingsStore.save(settings)
        }
    }

    private static func probeResult(
        for url: URL,
        title: String?,
        resolver: ThreadOpenResolver,
        coverRepository: ForumThreadReaderRepository
    ) async throws -> FavoriteThreadProbeResult {
        switch try await resolver.resolve(threadURL: url, title: title) {
        case let .novel(context):
            let metadata = await threadMetadata(
                forThreadID: context.threadID,
                title: context.threadTitle,
                repository: coverRepository
            )
            return FavoriteThreadProbeResult(
                target: .novelThread(threadID: context.threadID),
                title: context.threadTitle,
                sourceGroup: metadata.sourceGroup,
                coverURL: metadata.coverURL,
                contentUpdatedAt: metadata.contentUpdatedAt,
                authorID: context.authorID
            )
        case let .manga(context):
            let cleanBookName = context.directoryName ?? context.displayTitle
            let mangaID = context.originalThreadID
            return FavoriteThreadProbeResult(
                target: FavoriteContentTarget(mangaID: "thread:\(mangaID)", mangaCleanBookName: cleanBookName),
                title: context.displayTitle,
                sourceGroup: .mangaTitle(mangaID: "thread:\(mangaID)", cleanBookName: cleanBookName)
            )
        case let .web(url):
            let resolvedTitle = title ?? L10n.string("forum.default_title")
            let canonicalURL = ReaderModeDetector.canonicalThreadURL(from: url) ?? url
            guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: canonicalURL) else {
                throw YamiboError.missingFavoriteThreadID
            }
            let metadata = await threadMetadata(
                for: canonicalURL,
                title: resolvedTitle,
                repository: coverRepository
            )
            return FavoriteThreadProbeResult(
                target: .normalThread(threadID: threadID),
                title: resolvedTitle,
                sourceGroup: metadata.sourceGroup,
                coverURL: metadata.coverURL,
                contentUpdatedAt: metadata.contentUpdatedAt
            )
        }
    }

    private static func threadMetadata(
        for url: URL,
        title: String,
        repository: ForumThreadReaderRepository
    ) async -> (coverURL: URL?, sourceGroup: FavoriteSourceGroup, contentUpdatedAt: Date?) {
        let canonicalURL = ReaderModeDetector.canonicalThreadURL(from: url) ?? url
        guard let threadID = YamiboThreadURLCanonicalizer.threadID(from: canonicalURL)
            ?? MangaTitleCleaner.extractTid(from: canonicalURL.absoluteString) else {
            return (nil, .unknown, nil)
        }
        return await threadMetadata(
            thread: ThreadIdentity(tid: threadID, canonicalURL: canonicalURL),
            title: title,
            repository: repository
        )
    }

    private static func threadMetadata(
        forThreadID threadID: String,
        title: String,
        repository: ForumThreadReaderRepository
    ) async -> (coverURL: URL?, sourceGroup: FavoriteSourceGroup, contentUpdatedAt: Date?) {
        await threadMetadata(
            thread: ThreadIdentity(tid: threadID),
            title: title,
            repository: repository
        )
    }

    private static func threadMetadata(
        thread: ThreadIdentity,
        title: String,
        repository: ForumThreadReaderRepository
    ) async -> (coverURL: URL?, sourceGroup: FavoriteSourceGroup, contentUpdatedAt: Date?) {
        let cachedFirstPage = await repository.cachedThreadPage(thread: thread, title: title, authorID: nil, page: 1)
        let firstPage: ForumThreadPage?
        if let cachedFirstPage {
            firstPage = cachedFirstPage
        } else {
            firstPage = try? await repository.fetchThreadPage(thread: thread, title: title, authorID: nil, page: 1)
        }
        let sourceGroup = sourceGroup(from: firstPage)
        let contentUpdatedAt = contentUpdatedAt(from: firstPage)
        let coverURL = await ThreadCoverResolver().resolve(
            thread: thread,
            title: title,
            repository: repository
        )
        return (coverURL, sourceGroup, contentUpdatedAt)
    }

    private static func contentUpdatedAt(from page: ForumThreadPage?) -> Date? {
        guard let firstPost = page?.posts.first else { return nil }
        return FavoriteContentUpdateDateResolver.date(
            lastEditedText: firstPost.lastEditedText,
            postedAtText: firstPost.postedAtText
        )
    }

    private static func sourceGroup(from page: ForumThreadPage?) -> FavoriteSourceGroup {
        guard let page else { return .unknown }
        let fid = page.forumID ?? page.thread.fid
        guard let fid, !fid.isEmpty else { return .unknown }
        return .forumBoard(id: fid, label: page.forumName ?? fid)
    }

    private static func sourceGroupLabel(_ sourceGroup: FavoriteSourceGroup) -> String {
        switch sourceGroup {
        case let .forumBoard(_, label):
            label
        case let .mangaTitle(_, cleanBookName):
            cleanBookName
        case .unknown:
            L10n.string("favorites.source_group.unknown")
        }
    }

    private func sourceGroupID(_ sourceGroup: FavoriteSourceGroup) -> String {
        switch sourceGroup {
        case let .forumBoard(id, label):
            "forum:\(id):\(label)"
        case let .mangaTitle(mangaID, cleanBookName):
            "manga:\(mangaID):\(cleanBookName)"
        case .unknown:
            "unknown"
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static func page(from url: URL) -> Int {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
            .flatMap(Int.init) ?? 1
        return max(1, page)
    }
}

enum CategoryMoveDirection: Sendable {
    case up
    case down
}

private struct FavoriteUpdateFingerprint: Sendable {
    var latestPostID: String?
    var replyCount: Int?
    var pageCount: Int?
    var isReady: Bool

    init(page: ForumThreadPage) {
        latestPostID = page.posts.map(\.postID).last
        replyCount = page.totalReplies
        pageCount = page.pageNavigation?.totalPages
        isReady = latestPostID != nil || replyCount != nil || pageCount != nil
    }

    init(target: FavoriteUpdateTrackedTarget) {
        latestPostID = target.knownLatestPostID
        replyCount = target.knownReplyCount
        pageCount = target.knownPageCount
        isReady = target.baselineReady
    }

    func isNewer(than previous: FavoriteUpdateFingerprint) -> Bool {
        if let replyCount, let previousReplyCount = previous.replyCount, replyCount > previousReplyCount {
            return true
        }
        if let pageCount, let previousPageCount = previous.pageCount, pageCount > previousPageCount {
            return true
        }
        if let latestPostID, latestPostID != previous.latestPostID {
            return true
        }
        return false
    }

    static func summary(from previous: FavoriteUpdateFingerprint, to current: FavoriteUpdateFingerprint) -> String {
        if let replyCount = current.replyCount, let previousReplyCount = previous.replyCount, replyCount > previousReplyCount {
            return L10n.string("favorites.updates.summary.replies", replyCount - previousReplyCount)
        }
        if let pageCount = current.pageCount, let previousPageCount = previous.pageCount, pageCount > previousPageCount {
            return L10n.string("favorites.updates.summary.pages", pageCount - previousPageCount)
        }
        return L10n.string("favorites.updates.summary.changed")
    }
}

private extension FavoriteItem {
    var fid: String? {
        if case let .forumBoard(id, _) = sourceGroup {
            return id
        }
        return nil
    }
}
