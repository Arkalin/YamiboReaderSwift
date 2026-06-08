import SwiftUI
import UniformTypeIdentifiers
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#endif

public enum FavoriteFilter: String, CaseIterable, Identifiable {
    case all
    case novel
    case manga
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: L10n.string("favorites.filter.all")
        case .novel: L10n.string("favorite_type.novel")
        case .manga: L10n.string("favorite_type.manga")
        case .other: L10n.string("favorite_type.other")
        }
    }

    fileprivate func matches(_ favorite: Favorite) -> Bool {
        switch self {
        case .all:
            true
        case .novel:
            favorite.type == .novel
        case .manga:
            favorite.type == .manga
        case .other:
            favorite.type == .other || favorite.type == .unknown
        }
    }

    fileprivate var libraryFilter: FavoriteLibraryFilter {
        switch self {
        case .all: .all
        case .novel: .novel
        case .manga: .manga
        case .other: .other
        }
    }
}

public enum FavoriteSortOrder: String, CaseIterable, Identifiable {
    case manual
    case title
    case progress
    case recentRead

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: L10n.string("favorites.sort.manual")
        case .title: L10n.string("favorites.sort.title")
        case .progress: L10n.string("favorites.sort.progress")
        case .recentRead: L10n.string("favorites.sort.recent_read")
        }
    }

    fileprivate var librarySortOrder: FavoriteLibrarySortOrder {
        switch self {
        case .manual: .manual
        case .title: .title
        case .progress: .progress
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

    fileprivate var libraryTagSortOrder: FavoriteLibraryTagSortOrder {
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

    fileprivate var collection: FavoriteCollection? {
        if case let .collection(collection) = self {
            return collection
        }
        return nil
    }

    fileprivate var libraryScope: FavoriteLibraryScope {
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

private extension FavoriteLibraryEntry {
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

private struct FavoriteSharePresenter: ViewModifier {
    @Binding var favorite: Favorite?

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.background {
            FavoriteActivityPresenter(favorite: $favorite)
                .allowsHitTesting(false)
        }
        #else
        content
        #endif
    }
}

#if canImport(UIKit)
private struct FavoriteActivityPresenter: UIViewControllerRepresentable {
    @Binding var favorite: Favorite?

    func makeUIViewController(context: Context) -> FavoriteShareAnchorViewController {
        let controller = FavoriteShareAnchorViewController()
        controller.onFinish = {
            favorite = nil
        }
        return controller
    }

    func updateUIViewController(_ controller: FavoriteShareAnchorViewController, context: Context) {
        controller.presentShareSheet(for: favorite)
    }
}

@MainActor
private final class FavoriteShareAnchorViewController: UIViewController {
    var onFinish: (() -> Void)?

    private var presentedFavoriteID: String?
    private var pendingFavorite: Favorite?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let pendingFavorite {
            self.pendingFavorite = nil
            presentShareSheet(for: pendingFavorite)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePopoverAnchor()
    }

    func presentShareSheet(for favorite: Favorite?) {
        guard let favorite else { return }
        guard presentedFavoriteID != favorite.id else { return }

        guard view.window != nil else {
            pendingFavorite = favorite
            return
        }

        if presentedViewController != nil {
            dismiss(animated: false) { [weak self] in
                self?.presentShareSheet(for: favorite)
            }
            return
        }

        let activityController = UIActivityViewController(
            activityItems: [favorite.url],
            applicationActivities: nil
        )
        activityController.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.presentedFavoriteID = nil
            self?.onFinish?()
        }

        presentedFavoriteID = favorite.id
        configurePopover(for: activityController)
        present(activityController, animated: true)
    }

    private func configurePopover(for activityController: UIActivityViewController) {
        guard let popover = activityController.popoverPresentationController else { return }

        popover.sourceView = view
        popover.sourceRect = anchorRect
        popover.permittedArrowDirections = []
    }

    private func updatePopoverAnchor() {
        guard let activityController = presentedViewController as? UIActivityViewController else { return }
        configurePopover(for: activityController)
    }

    private var anchorRect: CGRect {
        let bounds = view.bounds
        guard !bounds.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    }
}
#endif

@MainActor
public final class FavoritesViewModel: ObservableObject {
    @Published public private(set) var favorites: [Favorite] = []
    @Published public private(set) var collections: [FavoriteCollection] = []
    @Published public private(set) var tags: [FavoriteTag] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var resolvingFavoriteID: String?
    @Published public private(set) var deletingFavoriteID: String?
    @Published public private(set) var favoriteAppearance = FavoriteAppearanceSettings()
    @Published public var errorMessage: String?

    private let appContext: YamiboAppContext
    private let favoriteStore: FavoriteStore
    private var favoriteUpdatesTask: Task<Void, Never>?
    private var settingsUpdatesTask: Task<Void, Never>?

    public init(appContext: YamiboAppContext, favoriteStore: FavoriteStore) {
        self.appContext = appContext
        self.favoriteStore = favoriteStore
        favoriteUpdatesTask = Task { @MainActor [weak self, favoriteStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteStore.changeIDUserInfoKey] as? String,
                      changeID == favoriteStore.changeID else {
                    continue
                }
                await self.reloadLocalFavorites()
            }
        }
        settingsUpdatesTask = Task { @MainActor [weak self, settingsStore = appContext.settingsStore] in
            for await notification in NotificationCenter.default.notifications(named: SettingsStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[SettingsStore.changeIDUserInfoKey] as? String,
                      changeID == settingsStore.changeID else {
                    continue
                }
                await self.reloadFavoriteAppearance()
            }
        }
    }

    deinit {
        favoriteUpdatesTask?.cancel()
        settingsUpdatesTask?.cancel()
    }

    public func loadCachedFavorites() async {
        await reloadFavoriteAppearance()
        await reloadLocalFavorites()
    }

    public func reloadLocalFavorites() async {
        applySnapshot(await favoriteStore.loadLibrarySnapshot())
    }

    public func reloadFavoriteAppearance() async {
        favoriteAppearance = await appContext.settingsStore.load().favoriteAppearance
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = await appContext.makeRepository()
            let remote = try await repository.fetchFavorites()
            favorites = try await favoriteStore.mergeRemoteFavorites(remote)
            collections = await favoriteStore.loadCollections()
            tags = await favoriteStore.loadTags()
            errorMessage = nil
        } catch {
            errorMessage = refreshErrorMessage(for: error)
        }
    }

    private func refreshErrorMessage(for error: Error) -> String {
        if (error as? YamiboError) == .notAuthenticated {
            return L10n.string("favorites.error.login_required")
        }
        return error.localizedDescription
    }

    func canReorderFavorites(
        sortOrder: FavoriteSortOrder,
        searchText: String,
        selectedTagIDs: Set<String> = []
    ) -> Bool {
        canReorderFavoriteEntries(
            sortOrder: sortOrder,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        ) &&
        !isLoading &&
        deletingFavoriteID == nil
    }

    func canReorderEntries(
        scope: FavoriteScope,
        filter: FavoriteFilter,
        sortOrder: FavoriteSortOrder,
        searchText: String,
        selectedTagIDs: Set<String> = [],
        isSelecting: Bool
    ) -> Bool {
        guard !isSelecting else { return false }
        return canReorderFavorites(
            sortOrder: sortOrder,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    }

    func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async {
        await reorderFavorites(in: nil, visibleIDs: visibleIDs, fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func reorderFavorites(
        in parentCollectionID: String?,
        visibleIDs: [String],
        fromOffsets: IndexSet,
        toOffset: Int
    ) async {
        guard !visibleIDs.isEmpty, !fromOffsets.isEmpty else { return }

        do {
            favorites = try await favoriteStore.reorderFavorites(
                in: parentCollectionID,
                visibleIDs: visibleIDs,
                fromOffsets: fromOffsets,
                toOffset: toOffset
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderRootEntries(visibleEntryKeys: [String], fromOffsets: IndexSet, toOffset: Int) async {
        guard !visibleEntryKeys.isEmpty, !fromOffsets.isEmpty else { return }

        do {
            applySnapshot(
                try await favoriteStore.reorderRootEntries(
                    visibleEntryKeys: visibleEntryKeys,
                    fromOffsets: fromOffsets,
                    toOffset: toOffset
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderFavorites(
        in parentCollectionID: String?,
        visibleIDs: [String],
        moves: [FavoriteVisibleOrderMove]
    ) async {
        guard !visibleIDs.isEmpty, !moves.isEmpty else { return }

        var workingVisibleIDs = visibleIDs

        do {
            for move in moves {
                favorites = try await favoriteStore.reorderFavorites(
                    in: parentCollectionID,
                    visibleIDs: workingVisibleIDs,
                    fromOffsets: move.fromOffsets,
                    toOffset: move.toOffset
                )
                workingVisibleIDs.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderRootEntries(visibleEntryKeys: [String], moves: [FavoriteVisibleOrderMove]) async {
        guard !visibleEntryKeys.isEmpty, !moves.isEmpty else { return }

        var workingVisibleEntryKeys = visibleEntryKeys

        do {
            for move in moves {
                applySnapshot(
                    try await favoriteStore.reorderRootEntries(
                        visibleEntryKeys: workingVisibleEntryKeys,
                        fromOffsets: move.fromOffsets,
                        toOffset: move.toOffset
                    )
                )
                workingVisibleEntryKeys.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setDisplayName(_ displayName: String?, for favorite: Favorite) async {
        await setDisplayName(displayName, forFavoriteID: favorite.id, originalTitle: favorite.title)
    }

    public func setDisplayName(_ displayName: String?, forFavoriteID favoriteID: String, originalTitle: String) async {
        do {
            let normalized = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueToPersist: String? = if let normalized, !normalized.isEmpty, normalized != originalTitle {
                normalized
            } else {
                nil
            }
            favorites = try await favoriteStore.setDisplayName(valueToPersist, for: favoriteID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setHidden(_ isHidden: Bool, for favorite: Favorite) async {
        do {
            favorites = try await favoriteStore.setHidden(isHidden, for: favorite.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setTagIDs(_ tagIDs: [String], forFavoriteID favoriteID: String) async -> Bool {
        await setTagIDs(tagIDs, forFavoriteIDs: [favoriteID])
    }

    public func setTagIDs(_ tagIDs: [String], forFavoriteIDs favoriteIDs: [String]) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.setTagIDs(tagIDs, forFavoriteIDs: favoriteIDs))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func createTag(name: String, color: FavoriteTagColor) async -> FavoriteTag? {
        do {
            let snapshot = try await favoriteStore.createTag(name: name, color: color)
            applySnapshot(snapshot)
            errorMessage = nil
            return snapshot.tags.first
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func updateTag(id tagID: String, name: String, color: FavoriteTagColor) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.updateTag(id: tagID, name: name, color: color))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteTag(id tagID: String) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.deleteTag(id: tagID))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func reorderTags(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async -> Bool {
        do {
            applySnapshot(
                try await favoriteStore.reorderTags(
                    visibleIDs: visibleIDs,
                    fromOffsets: fromOffsets,
                    toOffset: toOffset
                )
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func createCollection(name: String, favoriteIDs: [String]) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.createCollection(name: name, favoriteIDs: favoriteIDs))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func setCollectionName(_ name: String, for collectionID: String) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.setCollectionName(name, for: collectionID))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func setCollectionHidden(_ isHidden: Bool, for collection: FavoriteCollection) async {
        do {
            applySnapshot(try await favoriteStore.setCollectionHidden(isHidden, for: collection.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func moveFavorites(ids: [String], toCollectionID: String?) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.moveFavorites(ids: ids, toCollectionID: toCollectionID))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteFavorite(_ favorite: Favorite) async {
        _ = await deleteSelections(favoriteIDs: [favorite.id], collectionIDs: [])
    }

    public func deleteSelections(favoriteIDs: [String], collectionIDs: [String]) async -> Bool {
        var changed = false
        var firstError: String?

        if !collectionIDs.isEmpty {
            do {
                applySnapshot(try await favoriteStore.dissolveCollections(ids: collectionIDs))
                changed = true
            } catch {
                firstError = error.localizedDescription
            }
        }

        for favoriteID in favoriteIDs {
            guard firstError == nil || changed else { break }
            guard let favorite = await favoriteStore.favorite(id: favoriteID) else { continue }
            guard let remoteFavoriteID = favorite.remoteFavoriteID, !remoteFavoriteID.isEmpty else {
                firstError = firstError ?? YamiboError.missingFavoriteDeleteID.localizedDescription
                continue
            }

            deletingFavoriteID = favorite.id
            defer { deletingFavoriteID = nil }

            do {
                let repository = await appContext.makeRepository()
                try await repository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
                applySnapshot(try await favoriteStore.deleteFavorites(ids: [favorite.id]))
                changed = true
            } catch {
                firstError = firstError ?? error.localizedDescription
            }
        }

        errorMessage = firstError
        return changed
    }

    func openTarget(for favorite: Favorite, mode: FavoriteLaunchMode = .resume) async -> FavoriteOpenTarget {
        var latestFavorite = await favoriteStore.favorite(id: favorite.id) ?? favorite
        do {
            let updatedFavorites = try await favoriteStore.markLastReadAt(for: latestFavorite.id, date: .now)
            favorites = updatedFavorites
            latestFavorite = updatedFavorites.first(where: { $0.id == latestFavorite.id }) ?? latestFavorite
        } catch {
            // Opening should not be blocked by a best-effort recency write.
        }

        switch latestFavorite.type {
        case .novel:
            return .reader(
                ReaderLaunchContext(
                    threadURL: latestFavorite.url,
                    threadTitle: latestFavorite.resolvedDisplayTitle,
                    source: .favorites,
                    initialView: mode == .start ? 1 : nil,
                    authorID: latestFavorite.authorID,
                    initialResumePoint: mode == .start ? nil : latestFavorite.novelResumePoint
                )
            )
        case .manga:
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: latestFavorite.url,
                    chapterURL: mode == .start ? latestFavorite.url : (latestFavorite.lastMangaURL ?? latestFavorite.url),
                    displayTitle: latestFavorite.resolvedDisplayTitle,
                    source: .favorites,
                    initialPage: mode == .start ? 0 : latestFavorite.mangaPageIndex
                )
            )
        case .other:
            return .web(latestFavorite)
        case .unknown:
            resolvingFavoriteID = latestFavorite.id
            defer { resolvingFavoriteID = nil }

            do {
                let resolver = await appContext.makeThreadOpenResolver()
                let target = try await resolver.resolve(
                    threadURL: latestFavorite.url,
                    title: latestFavorite.resolvedDisplayTitle,
                    htmlOverride: nil,
                    favoriteType: .unknown,
                    favoriteChapterURL: latestFavorite.lastMangaURL,
                    initialMangaPageIndex: latestFavorite.mangaPageIndex
                )

                switch target {
                case let .novel(context):
                    favorites = try await favoriteStore.setType(.novel, for: latestFavorite.id)
                    return .reader(applyStartModeIfNeeded(to: context, for: latestFavorite, mode: mode))
                case let .manga(context):
                    favorites = try await favoriteStore.setType(.manga, for: latestFavorite.id)
                    return .manga(applyStartModeIfNeeded(to: context, for: latestFavorite, mode: mode))
                case .web:
                    favorites = try await favoriteStore.setType(.other, for: latestFavorite.id)
                    var updated = latestFavorite
                    updated.type = .other
                    return .web(updated)
                }
            } catch {
                errorMessage = error.localizedDescription
                return .web(latestFavorite)
            }
        }
    }

    func resolveOpenTarget(for favorite: Favorite) async -> FavoriteOpenTarget {
        await openTarget(for: favorite, mode: .resume)
    }

    private func applySnapshot(_ snapshot: FavoriteLibrarySnapshot) {
        favorites = snapshot.favorites
        collections = snapshot.collections
        tags = snapshot.tags
    }

    private func applyStartModeIfNeeded(
        to context: ReaderLaunchContext,
        for favorite: Favorite,
        mode: FavoriteLaunchMode
    ) -> ReaderLaunchContext {
        guard mode == .start else { return context }

        return ReaderLaunchContext(
            threadURL: context.threadURL,
            threadTitle: favorite.resolvedDisplayTitle,
            source: context.source,
            initialView: 1,
            authorID: context.authorID
        )
    }

    private func applyStartModeIfNeeded(
        to context: MangaLaunchContext,
        for favorite: Favorite,
        mode: FavoriteLaunchMode
    ) -> MangaLaunchContext {
        guard mode == .start else { return context }

        return MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: favorite.url,
            displayTitle: favorite.resolvedDisplayTitle,
            source: context.source,
            initialPage: 0,
            directoryName: context.directoryName
        )
    }
}

public enum FavoriteOpenTarget: Sendable {
    case reader(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case web(Favorite)
}

private struct FavoriteDisplayNameDraft {
    let favoriteID: String
    let originalTitle: String
    var displayName: String

    init(favorite: Favorite) {
        favoriteID = favorite.id
        originalTitle = favorite.title
        displayName = favorite.displayName ?? favorite.resolvedDisplayTitle
    }
}

private struct FavoriteCollectionNameDraft {
    let collectionID: String
    var name: String

    init(collection: FavoriteCollection) {
        collectionID = collection.id
        name = collection.name
    }
}

private struct FavoriteTagPickerContext: Identifiable {
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

private struct FavoriteTagEditorDraft: Identifiable {
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

private struct FavoriteSearchModifier: ViewModifier {
    @Binding var searchText: String

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: L10n.string("common.search")
            )
        #else
        content
            .searchable(text: $searchText, prompt: L10n.string("common.search"))
        #endif
    }
}

private struct FavoriteSettingsMenuButton: View {
    @Binding var showingSettingsSheet: Bool
    @Binding var showingAboutSheet: Bool

    var body: some View {
        Menu {
            Button {
                showingSettingsSheet = true
            } label: {
                Label(L10n.string("settings.title"), systemImage: "gearshape")
            }

            Button {
                showingAboutSheet = true
            } label: {
                Label(L10n.string("about.title"), systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

private struct FavoriteSortMenuButton: View {
    @Binding var sortRawValue: String

    var body: some View {
        Menu {
            Picker(L10n.string("favorites.sort"), selection: $sortRawValue) {
                ForEach(FavoriteSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title).tag(sortOrder.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }
}

private struct FavoriteSelectionToggleButton: View {
    let isSelecting: Bool
    let action: () -> Void

    var body: some View {
        Button(isSelecting ? L10n.string("common.done") : L10n.string("common.select"), action: action)
    }
}

private struct FavoriteToolbarMenuButton: View {
    @Binding var filterRawValue: String
    @Binding var showsHidden: Bool
    let favoriteAppearance: FavoriteAppearanceSettings
    let selectedTagCount: Int
    let allTitle: String
    let onEditTagFilter: () -> Void
    let onClearTagFilter: () -> Void

    var body: some View {
        Menu {
            Picker(L10n.string("favorites.category"), selection: $filterRawValue) {
                ForEach(FavoriteFilter.allCases) { filter in
                    Label {
                        Text(filter == .all ? allTitle : filter.title)
                    } icon: {
                        filter.menuIcon(appearance: favoriteAppearance)
                    }
                    .tag(filter.rawValue)
                }
            }

            Button(action: onEditTagFilter) {
                Label(tagFilterTitle, systemImage: "tag")
            }

            if selectedTagCount > 0 {
                Button(action: onClearTagFilter) {
                    Label(L10n.string("favorites.filter.clear_tags"), systemImage: "xmark.circle")
                }
            }

            Divider()

            Toggle(isOn: $showsHidden) {
                Label(L10n.string("favorites.show_hidden"), systemImage: "eye.slash")
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private var currentFilter: FavoriteFilter {
        FavoriteFilter(rawValue: filterRawValue) ?? .all
    }

    private var currentTitle: String {
        currentFilter == .all ? allTitle : currentFilter.title
    }

    private var tagFilterTitle: String {
        guard selectedTagCount > 0 else {
            return L10n.string("favorites.filter.tags")
        }
        return L10n.string("favorites.filter.tags_count", selectedTagCount)
    }
}

private extension FavoriteFilter {
    var menuIconName: String {
        switch self {
        case .all:
            "square.grid.2x2.fill"
        case .novel:
            "book.closed.fill"
        case .manga:
            "photo.on.rectangle.angled"
        case .other:
            "ellipsis.circle.fill"
        }
    }

    @ViewBuilder
    func menuIcon(appearance: FavoriteAppearanceSettings) -> some View {
        #if canImport(UIKit)
        if let icon = UIImage(systemName: menuIconName)?
            .withTintColor(menuUIColor(appearance: appearance), renderingMode: .alwaysOriginal) {
            Image(uiImage: icon)
        } else {
            Image(systemName: menuIconName)
                .foregroundStyle(menuColor(appearance: appearance))
        }
        #else
        Image(systemName: menuIconName)
            .foregroundStyle(menuColor(appearance: appearance))
        #endif
    }

    func menuColor(appearance: FavoriteAppearanceSettings) -> Color {
        switch self {
        case .all:
            .black
        case .novel:
            favoriteAccentColor(for: .novel, appearance: appearance)
        case .manga:
            favoriteAccentColor(for: .manga, appearance: appearance)
        case .other:
            favoriteAccentColor(for: .other, appearance: appearance)
        }
    }

    #if canImport(UIKit)
    func menuUIColor(appearance: FavoriteAppearanceSettings) -> UIColor {
        switch self {
        case .all:
            .black
        case .novel:
            appearance.novel.uiColor
        case .manga:
            appearance.manga.uiColor
        case .other:
            appearance.other.uiColor
        }
    }
    #endif
}

#if canImport(UIKit)
private extension FavoriteAppearanceColor {
    var uiColor: UIColor {
        switch self {
        case .red: .systemRed
        case .pink: .systemPink
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .cyan: .systemCyan
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .gray: .systemGray
        }
    }
}
#endif

private struct FavoriteToolbarModifier: ViewModifier {
    @Binding var showingSettingsSheet: Bool
    @Binding var showingAboutSheet: Bool
    @Binding var filterRawValue: String
    @Binding var sortRawValue: String
    @Binding var showsHidden: Bool
    @Binding var isSelecting: Bool
    let favoriteAppearance: FavoriteAppearanceSettings
    let showsSettingsMenu: Bool
    let selectedTagCount: Int
    let visibleSelectionIsComplete: Bool
    let canToggleVisibleSelection: Bool
    let allTitle: String
    let onFinishSelection: () -> Void
    let onToggleVisibleSelection: () -> Void
    let onEditTagFilter: () -> Void
    let onClearTagFilter: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            #if os(iOS)
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        visibleSelectionIsComplete ? L10n.string("common.invert_selection") : L10n.string("common.select_all"),
                        action: onToggleVisibleSelection
                    )
                    .disabled(!canToggleVisibleSelection)
                }
            } else if showsSettingsMenu {
                ToolbarItemGroup(placement: .topBarLeading) {
                    FavoriteSettingsMenuButton(
                        showingSettingsSheet: $showingSettingsSheet,
                        showingAboutSheet: $showingAboutSheet
                    )

                    FavoriteSortMenuButton(sortRawValue: $sortRawValue)
                }
            }
            #else
            if showsSettingsMenu {
                ToolbarItem(placement: .automatic) {
                    FavoriteSettingsMenuButton(
                        showingSettingsSheet: $showingSettingsSheet,
                        showingAboutSheet: $showingAboutSheet
                    )
                }
            }
            #endif

            ToolbarItem(placement: .principal) {
                FavoriteToolbarMenuButton(
                    filterRawValue: $filterRawValue,
                    showsHidden: $showsHidden,
                    favoriteAppearance: favoriteAppearance,
                    selectedTagCount: selectedTagCount,
                    allTitle: allTitle,
                    onEditTagFilter: onEditTagFilter,
                    onClearTagFilter: onClearTagFilter
                )
            }

            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteSelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        onFinishSelection()
                    } else {
                        isSelecting = true
                    }
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                FavoriteSelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        onFinishSelection()
                    } else {
                        isSelecting = true
                    }
                }
            }
            #endif
        }
    }
}

private struct FavoriteCollectionNavigationDestinationModifier: ViewModifier {
    let isEnabled: Bool
    let appContext: YamiboAppContext
    let appModel: YamiboAppModel

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationDestination(for: FavoriteCollection.self) { collection in
                FavoritesView(
                    favoriteStore: appContext.favoriteStore,
                    appContext: appContext,
                    appModel: appModel,
                    scope: .collection(collection)
                )
            }
        } else {
            content
        }
    }
}

private struct FavoriteCollectionDialogsModifier: ViewModifier {
    @Binding var collectionNameDraft: FavoriteCollectionNameDraft?
    @Binding var pendingDeleteCollection: FavoriteCollection?
    let saveName: (FavoriteCollectionNameDraft) -> Void
    let dissolveCollection: (FavoriteCollection) -> Void

    func body(content: Content) -> some View {
        content
            .alert(L10n.string("favorites.edit_collection_name"), isPresented: collectionNameAlertBinding) {
                TextField(L10n.string("favorites.collection_name"), text: collectionNameTextBinding)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    collectionNameDraft = nil
                }
                Button(L10n.string("common.save")) {
                    guard let draft = collectionNameDraft else { return }
                    saveName(draft)
                }
                .disabled(collectionNameDraft?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            } message: {
                Text(L10n.string("favorites.collection_name_message"))
            }
            .alert(
                L10n.string("favorites.dissolve_collection"),
                isPresented: pendingCollectionDeleteAlertBinding,
                presenting: pendingDeleteCollection
            ) { collection in
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteCollection = nil
                }
                Button(L10n.string("favorites.dissolve"), role: .destructive) {
                    dissolveCollection(collection)
                }
            } message: { collection in
                Text(L10n.string("favorites.dissolve_collection_message", collection.name))
            }
    }

    private var collectionNameAlertBinding: Binding<Bool> {
        Binding(
            get: { collectionNameDraft != nil },
            set: { isPresented in
                if !isPresented {
                    collectionNameDraft = nil
                }
            }
        )
    }

    private var collectionNameTextBinding: Binding<String> {
        Binding(
            get: { collectionNameDraft?.name ?? "" },
            set: { collectionNameDraft?.name = $0 }
        )
    }

    private var pendingCollectionDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCollection != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteCollection = nil
                }
            }
        )
    }
}

private struct FavoriteEntryDropDelegate: DropDelegate {
    let draggedEntryKey: String?
    let targetEntry: FavoriteListEntry?
    let column: FavoriteListColumn
    let canReorder: Bool
    let onDropOnEntry: (String, FavoriteListEntry, FavoriteDropPosition) -> Void
    let onDropToColumnBottom: (String, FavoriteListColumn) -> Void
    let onFinish: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        canReorder && draggedEntryKey != nil && info.hasItemsConforming(to: [UTType.plainText.identifier])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder, draggedEntryKey != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canReorder, let draggedEntryKey else { return false }

        if let targetEntry {
            let position: FavoriteDropPosition = info.location.y < 56 ? .before : .after
            onDropOnEntry(draggedEntryKey, targetEntry, position)
        } else {
            onDropToColumnBottom(draggedEntryKey, column)
        }

        onFinish()
        return true
    }
}

public struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @AppStorage("yamibo.favorite.filter") private var filterRawValue = FavoriteFilter.all.rawValue
    @AppStorage("yamibo.favorite.sort") private var sortRawValue = FavoriteSortOrder.manual.rawValue
    @AppStorage("yamibo.favorite.showHidden") private var showsHidden = false
    @State private var searchText = ""
    @State private var selectedFavorite: Favorite?
    @State private var showingSettingsSheet = false
    @State private var showingAboutSheet = false
    @State private var displayNameDraft: FavoriteDisplayNameDraft?
    @State private var pendingEditFavorite: Favorite?
    @State private var tagPickerContext: FavoriteTagPickerContext?
    @State private var collectionNameDraft: FavoriteCollectionNameDraft?
    @State private var pendingDeleteFavorite: Favorite?
    @State private var pendingDeleteCollection: FavoriteCollection?
    @State private var isSelecting = false
    @State private var selectedFavoriteIDs: Set<String> = []
    @State private var selectedCollectionIDs: Set<String> = []
    @State private var selectedFilterTagIDs: Set<String> = []
    @State private var showingCreateCollectionPrompt = false
    @State private var createCollectionName = ""
    @State private var showingMoveDialog = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var didLoadInitialFavorites = false
    @State private var draggedEntryKey: String?
    @State private var sharingFavorite: Favorite?
    @State private var openingMangaFavoriteID: String?

    private let scope: FavoriteScope
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(
        favoriteStore: FavoriteStore,
        appContext: YamiboAppContext,
        appModel: YamiboAppModel,
        scope: FavoriteScope = .root
    ) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore))
        self.scope = scope
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        if case .root = scope {
            NavigationStack {
                favoritesContent
            }
        } else {
            favoritesContent
        }
    }

    private var favoritesContent: some View {
        let content = favoritesChromeContent

        return Group {
            if isSelecting {
                content.safeAreaInset(edge: .bottom, spacing: 0) {
                    selectionActionBar
                }
            } else {
                content
            }
        }
        .disabled(isOpeningManga)
        .overlay {
            if isOpeningManga {
                mangaOpeningOverlay
            }
        }
        #if os(iOS)
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        #endif
    }

    private var favoritesChromeContent: some View {
        favoritesDialogContent
    }

    private var favoritesNavigationContent: some View {
        favoritesListLayout
            .navigationTitle("")
            .modifier(FavoriteSearchModifier(searchText: $searchText))
            .modifier(
                FavoriteToolbarModifier(
                    showingSettingsSheet: $showingSettingsSheet,
                    showingAboutSheet: $showingAboutSheet,
                    filterRawValue: $filterRawValue,
                    sortRawValue: $sortRawValue,
                    showsHidden: $showsHidden,
                    isSelecting: $isSelecting,
                    favoriteAppearance: viewModel.favoriteAppearance,
                    showsSettingsMenu: isRootScope,
                    selectedTagCount: selectedFilterTagIDs.count,
                    visibleSelectionIsComplete: visibleSelectionIsComplete,
                    canToggleVisibleSelection: !visibleEntries.isEmpty,
                    allTitle: filterLabel(for: .all),
                    onFinishSelection: exitSelectionMode,
                    onToggleVisibleSelection: toggleVisibleSelection,
                    onEditTagFilter: presentFilterTagPicker,
                    onClearTagFilter: {
                        selectedFilterTagIDs.removeAll()
                    }
                )
            )
            .modifier(
                FavoriteCollectionNavigationDestinationModifier(
                    isEnabled: isRootScope,
                    appContext: appContext,
                    appModel: appModel
                )
            )
    }

    private var favoritesListLayout: some View {
        GeometryReader { geometry in
            ZStack {
                if shouldUseTwoColumnLayout(in: geometry.size) {
                    twoColumnFavoritesList
                } else {
                    singleColumnFavoritesList(entries: visibleEntries)
                }
            }
            .overlay(content: overlayContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var favoritesLifecycleContent: some View {
        favoritesNavigationContent
            .task {
                await loadInitialFavorites()
            }
            .onChange(of: filterRawValue) { _, _ in
                searchText = ""
            }
            .onChange(of: isSelecting) { _, isSelecting in
                if !isSelecting {
                    selectedFavoriteIDs.removeAll()
                    selectedCollectionIDs.removeAll()
                }
            }
            .onChange(of: viewModel.favorites.map(\.id)) { _, _ in
                pruneSelections()
            }
            .onChange(of: viewModel.collections.map(\.id)) { _, _ in
                pruneSelections()
            }
            .onChange(of: viewModel.tags.map(\.id)) { _, tagIDs in
                selectedFilterTagIDs.formIntersection(Set(tagIDs))
            }
            .sensoryFeedback(.selection, trigger: selectedFavoriteIDs)
            .sensoryFeedback(.selection, trigger: selectedCollectionIDs)
            .refreshable {
                await viewModel.refresh()
            }
    }

    private var favoritesDialogContent: some View {
        favoritesLifecycleContent
            .alert(L10n.string("common.load_failed"), isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button(L10n.string("common.ok")) {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .alert(L10n.string("favorites.edit_display_name"), isPresented: editNameAlertBinding) {
                TextField(L10n.string("favorites.display_name"), text: displayNameTextBinding)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    displayNameDraft = nil
                }
                Button(L10n.string("common.save")) {
                    guard let draft = displayNameDraft else { return }
                    Task {
                        await viewModel.setDisplayName(
                            draft.displayName,
                            forFavoriteID: draft.favoriteID,
                            originalTitle: draft.originalTitle
                        )
                    }
                    displayNameDraft = nil
                }
            } message: {
                Text(L10n.string("favorites.display_name_message"))
            }
            .alert("", isPresented: editActionAlertBinding, presenting: pendingEditFavorite) { favorite in
                Button(L10n.string("favorites.edit_display_name")) {
                    displayNameDraft = FavoriteDisplayNameDraft(favorite: favorite)
                    pendingEditFavorite = nil
                }
                Button(L10n.string("favorites.edit_tags")) {
                    tagPickerContext = FavoriteTagPickerContext(
                        favoriteID: favorite.id,
                        initialTagIDs: Set(favorite.tagIDs)
                    )
                    pendingEditFavorite = nil
                }
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingEditFavorite = nil
                }
            }
            .alert(L10n.string("favorites.create_collection"), isPresented: $showingCreateCollectionPrompt) {
                TextField(L10n.string("favorites.collection_name"), text: $createCollectionName)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    createCollectionName = ""
                }
                Button(L10n.string("common.create")) {
                    let selectedIDs = Array(selectedFavoriteIDs)
                    let targetName = createCollectionName
                    createCollectionName = ""
                    Task {
                        if await viewModel.createCollection(name: targetName, favoriteIDs: selectedIDs) {
                            exitSelectionMode()
                        }
                    }
                }
                .disabled(createCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text(L10n.string("favorites.create_collection_message"))
            }
            .alert(
                L10n.string("favorites.delete_favorite"),
                isPresented: pendingDeleteAlertBinding,
                presenting: pendingDeleteFavorite
            ) { favorite in
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteFavorite = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        await viewModel.deleteFavorite(favorite)
                    }
                    pendingDeleteFavorite = nil
                }
            } message: { favorite in
                Text(L10n.string("favorites.delete_favorite_message", favorite.resolvedDisplayTitle))
            }
            .alert(L10n.string("favorites.delete_selection"), isPresented: $showingBulkDeleteConfirmation) {
                Button(L10n.string("common.cancel"), role: .cancel) {}
                Button(L10n.string("common.delete"), role: .destructive) {
                    let favoriteIDs = Array(selectedFavoriteIDs)
                    let collectionIDs = Array(selectedCollectionIDs)
                    Task {
                        let changed = await viewModel.deleteSelections(favoriteIDs: favoriteIDs, collectionIDs: collectionIDs)
                        if changed {
                            exitSelectionMode()
                        }
                    }
                }
            } message: {
                Text(bulkDeleteMessage)
            }
            .sheet(item: $selectedFavorite) { favorite in
                ForumBrowserView(url: favorite.url, appContext: appContext, appModel: appModel)
                    .ignoresSafeArea()
            }
            .sheet(item: $tagPickerContext) { context in
                FavoriteTagPickerView(
                    tags: viewModel.tags,
                    favorites: viewModel.favorites,
                    initialSelection: context.initialTagIDs,
                    showsOverwriteWarning: context.showsOverwriteWarning,
                    onCancel: {
                        tagPickerContext = nil
                    },
                    onConfirm: { selectedTagIDs in
                        if context.isFilter {
                            selectedFilterTagIDs = selectedTagIDs
                            tagPickerContext = nil
                            return true
                        }

                        let orderedTagIDs = viewModel.tags
                            .map(\.id)
                            .filter { selectedTagIDs.contains($0) }
                        if await viewModel.setTagIDs(orderedTagIDs, forFavoriteIDs: context.favoriteIDs) {
                            tagPickerContext = nil
                            if context.exitsSelectionModeOnConfirm {
                                exitSelectionMode()
                            }
                            return true
                        }
                        return false
                    },
                    onCreateTag: { name, color in
                        await viewModel.createTag(name: name, color: color)
                    },
                    onUpdateTag: { tagID, name, color in
                        await viewModel.updateTag(id: tagID, name: name, color: color)
                    },
                    onDeleteTag: { tagID in
                        await viewModel.deleteTag(id: tagID)
                    },
                    onReorderTags: { visibleIDs, fromOffsets, toOffset in
                        await viewModel.reorderTags(
                            visibleIDs: visibleIDs,
                            fromOffsets: fromOffsets,
                            toOffset: toOffset
                        )
                    }
                )
            }
            .sheet(isPresented: $showingSettingsSheet) {
                FavoritesSettingsView(appContext: appContext) {
                    filterRawValue = FavoriteFilter.all.rawValue
                    sortRawValue = FavoriteSortOrder.manual.rawValue
                    showsHidden = false
                    searchText = ""
                    await appModel.bootstrap()
                }
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView(appContext: appContext)
            }
            .modifier(FavoriteSharePresenter(favorite: $sharingFavorite))
            .modifier(
                FavoriteCollectionDialogsModifier(
                    collectionNameDraft: $collectionNameDraft,
                    pendingDeleteCollection: $pendingDeleteCollection,
                    saveName: saveCollectionName,
                    dissolveCollection: dissolveCollection
                )
            )
    }

    private var leftColumnEntries: [FavoriteListEntry] {
        splitAlternatingColumns(visibleEntries).left
    }

    private var rightColumnEntries: [FavoriteListEntry] {
        splitAlternatingColumns(visibleEntries).right
    }

    private var twoColumnFavoritesList: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                twoColumnFavoritesColumn(entries: leftColumnEntries, column: .left)
                twoColumnFavoritesColumn(entries: rightColumnEntries, column: .right)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func twoColumnFavoritesColumn(
        entries: [FavoriteListEntry],
        column: FavoriteListColumn
    ) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(entries) { entry in
                twoColumnRow(for: entry)
                    .onDrop(
                        of: [UTType.plainText.identifier],
                        delegate: FavoriteEntryDropDelegate(
                            draggedEntryKey: draggedEntryKey,
                            targetEntry: entry,
                            column: column,
                            canReorder: canReorderEntries,
                            onDropOnEntry: handleDrop,
                            onDropToColumnBottom: handleDropToColumnBottom,
                            onFinish: { draggedEntryKey = nil }
                        )
                    )
                    .onDragIf(canReorderEntries, value: entry.moveKey) {
                        draggedEntryKey = entry.moveKey
                    }
            }

            Color.clear
                .frame(height: 88)
                .contentShape(Rectangle())
                .onDrop(
                    of: [UTType.plainText.identifier],
                    delegate: FavoriteEntryDropDelegate(
                        draggedEntryKey: draggedEntryKey,
                        targetEntry: nil,
                        column: column,
                        canReorder: canReorderEntries,
                        onDropOnEntry: handleDrop,
                        onDropToColumnBottom: handleDropToColumnBottom,
                        onFinish: { draggedEntryKey = nil }
                    )
                )
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func singleColumnFavoritesList(entries: [FavoriteListEntry]) -> some View {
        List {
            ForEach(entries) { entry in
                row(for: entry)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: handleMove)
            .moveDisabled(!canReorderEntries)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func overlayContent() -> some View {
        if viewModel.isLoading {
            ProgressView(L10n.string("favorites.syncing"))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)
        } else if visibleEntries.isEmpty {
            emptyStateView
        }
    }

    private var mangaOpeningOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            ProgressView(L10n.string("manga.loading"))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 18, y: 6)
        }
        .allowsHitTesting(true)
    }

    private var currentCollection: FavoriteCollection? {
        guard let scopedCollection = scope.collection else { return nil }
        return viewModel.collections.first(where: { $0.id == scopedCollection.id }) ?? scopedCollection
    }

    private var isRootScope: Bool {
        if case .root = scope {
            return true
        }
        return false
    }

    private var usesIPadSharePresenter: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private var currentFilter: FavoriteFilter {
        FavoriteFilter(rawValue: filterRawValue) ?? .all
    }

    private var currentSortOrder: FavoriteSortOrder {
        FavoriteSortOrder(rawValue: sortRawValue) ?? .manual
    }

    private var canReorderEntries: Bool {
        viewModel.canReorderEntries(
            scope: scope,
            filter: currentFilter,
            sortOrder: currentSortOrder,
            searchText: searchText,
            selectedTagIDs: selectedFilterTagIDs,
            isSelecting: isSelecting
        )
    }

    private var isOpeningManga: Bool {
        shouldBlockFavoriteInteractions(openingMangaFavoriteID: openingMangaFavoriteID)
    }

    private var selectionActionState: FavoriteSelectionActionState {
        makeFavoriteSelectionActionState(
            scope: scope,
            selectedFavoriteCount: selectedFavoriteIDs.count,
            selectedCollectionCount: selectedCollectionIDs.count
        )
    }

    private var visibleEntries: [FavoriteListEntry] {
        makeFavoriteListEntries(
            scope: scope,
            favorites: viewModel.favorites,
            collections: viewModel.collections,
            showsHidden: showsHidden,
            filter: currentFilter,
            sortOrder: currentSortOrder,
            searchText: searchText,
            selectedTagIDs: selectedFilterTagIDs
        )
    }

    private var visibleSelectionIsComplete: Bool {
        guard !visibleEntries.isEmpty else { return false }
        return visibleEntries.allSatisfy { entry in
            switch entry {
            case let .collection(collection):
                selectedCollectionIDs.contains(collection.id)
            case let .favorite(favorite):
                selectedFavoriteIDs.contains(favorite.id)
            }
        }
    }

    private var moveTargets: [FavoriteCollection] {
        let targetCollections = orderedCollections(viewModel.collections)
        guard let currentCollection else { return targetCollections }
        return targetCollections.filter { $0.id != currentCollection.id }
    }

    private var bulkDeleteMessage: String {
        if selectedCollectionIDs.isEmpty {
            return L10n.string("favorites.bulk_delete_favorites_message")
        }
        if selectedFavoriteIDs.isEmpty {
            return L10n.string("favorites.bulk_dissolve_collections_message")
        }
        return L10n.string("favorites.bulk_delete_mixed_message")
    }

    private var editNameAlertBinding: Binding<Bool> {
        Binding(
            get: { displayNameDraft != nil },
            set: { isPresented in
                if !isPresented {
                    displayNameDraft = nil
                }
            }
        )
    }

    private var editActionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingEditFavorite != nil },
            set: { isPresented in
                if !isPresented {
                    pendingEditFavorite = nil
                }
            }
        )
    }

    private var displayNameTextBinding: Binding<String> {
        Binding(
            get: { displayNameDraft?.displayName ?? "" },
            set: { displayNameDraft?.displayName = $0 }
        )
    }

    private var pendingDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteFavorite != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteFavorite = nil
                }
            }
        )
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if viewModel.isLoading {
            EmptyView()
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(L10n.string("favorites.empty.no_results"), systemImage: "magnifyingglass")
        } else if !selectedFilterTagIDs.isEmpty {
            ContentUnavailableView(L10n.string("favorites.empty.no_results"), systemImage: "tag")
        } else if currentCollection != nil {
            ContentUnavailableView(L10n.string("favorites.empty.collection"), systemImage: "folder")
        } else {
            ContentUnavailableView(L10n.string("favorites.empty.favorites"), systemImage: "books.vertical")
        }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                selectionActionButton(
                    title: L10n.string("favorites.tags_action"),
                    systemImage: "tag",
                    isEnabled: selectionActionState.canTag
                ) {
                    presentBatchTagPicker()
                }
                .disabled(!selectionActionState.canTag)

                selectionActionButton(
                    title: L10n.string("favorites.create_collection"),
                    systemImage: "folder.badge.plus",
                    isEnabled: selectionActionState.canCreateCollection
                ) {
                    showingCreateCollectionPrompt = true
                }
                .disabled(!selectionActionState.canCreateCollection)

                selectionActionButton(
                    title: L10n.string("common.move"),
                    systemImage: "doc.on.doc",
                    isEnabled: selectionActionState.canMove
                ) {
                    showingMoveDialog = true
                }
                .disabled(!selectionActionState.canMove)
                .confirmationDialog(L10n.string("favorites.move_to_collection"), isPresented: $showingMoveDialog, titleVisibility: .visible) {
                    Button(L10n.string("favorites.move_to_root")) {
                        moveSelectedFavorites(to: nil)
                    }
                    ForEach(moveTargets) { collection in
                        Button(collection.name) {
                            moveSelectedFavorites(to: collection.id)
                        }
                    }
                    Button(L10n.string("common.cancel"), role: .cancel) {}
                } message: {
                    Text(L10n.string("favorites.select_target_collection"))
                }

                selectionActionButton(
                    title: L10n.string("common.delete"),
                    systemImage: "trash",
                    role: .destructive,
                    isEnabled: selectionActionState.canDelete
                ) {
                    showingBulkDeleteConfirmation = true
                }
                .disabled(!selectionActionState.canDelete)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(selectionActionBarBackground)
    }

    private var selectionActionBarBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGray6)
        #else
        Color.gray.opacity(0.12)
        #endif
    }

    private func selectionActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .regular))
                    .frame(width: 28, height: 27)

                Text(title)
                    .font(.caption)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .opacity(isEnabled ? 1 : 0.28)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func twoColumnRow(for entry: FavoriteListEntry) -> some View {
        switch entry {
        case let .collection(collection):
            let summary = collectionSummary(for: collection)
            if isSelecting {
                Button {
                    toggleCollectionSelection(collection)
                } label: {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: selectedCollectionIDs.contains(collection.id),
                        isSelecting: true,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: collection) {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: false,
                        isSelecting: false,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    collectionActionMenuButton(collection)
                }
            }
        case let .favorite(favorite):
            let favoriteRow = FavoriteRow(
                favorite: favorite,
                isResolving: viewModel.resolvingFavoriteID == favorite.id,
                isDeleting: viewModel.deletingFavoriteID == favorite.id,
                isSelected: selectedFavoriteIDs.contains(favorite.id),
                isSelecting: isSelecting,
                tags: viewModel.tags,
                tagSearchText: searchText,
                prioritizedTagIDs: selectedFilterTagIDs,
                accentColor: favoriteAccentColor(for: favorite.type, appearance: viewModel.favoriteAppearance),
                onOpen: {
                    if isSelecting {
                        toggleFavoriteSelection(favorite)
                    } else {
                        open(favorite, mode: .resume)
                    }
                }
            )

            if isSelecting {
                Button {
                    toggleFavoriteSelection(favorite)
                } label: {
                    favoriteRow
                }
                .buttonStyle(.plain)
            } else {
                favoriteRow
                    .overlay(alignment: .topTrailing) {
                        favoriteActionMenuButton(favorite)
                    }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: FavoriteListEntry) -> some View {
        switch entry {
        case let .collection(collection):
            let summary = collectionSummary(for: collection)
            if isSelecting {
                Button {
                    toggleCollectionSelection(collection)
                } label: {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: selectedCollectionIDs.contains(collection.id),
                        isSelecting: true,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: collection) {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: false,
                        isSelecting: false,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDeleteCollection = collection
                    } label: {
                        swipeActionLabel(title: L10n.string("common.delete"), systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        Task {
                            await viewModel.setCollectionHidden(!collection.isHidden, for: collection)
                        }
                    } label: {
                        swipeActionLabel(
                            title: collection.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"),
                            systemImage: collection.isHidden ? "eye" : "eye.slash"
                        )
                    }
                    .tint(.orange)

                    Button {
                        collectionNameDraft = FavoriteCollectionNameDraft(collection: collection)
                    } label: {
                        swipeActionLabel(title: L10n.string("common.edit"), systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
            }
        case let .favorite(favorite):
            let row = FavoriteRow(
                favorite: favorite,
                isResolving: viewModel.resolvingFavoriteID == favorite.id,
                isDeleting: viewModel.deletingFavoriteID == favorite.id,
                isSelected: selectedFavoriteIDs.contains(favorite.id),
                isSelecting: isSelecting,
                tags: viewModel.tags,
                tagSearchText: searchText,
                prioritizedTagIDs: selectedFilterTagIDs,
                accentColor: favoriteAccentColor(for: favorite.type, appearance: viewModel.favoriteAppearance),
                onOpen: {
                    if isSelecting {
                        toggleFavoriteSelection(favorite)
                    } else {
                        open(favorite, mode: .resume)
                    }
                }
            )

            if isSelecting {
                Button {
                    toggleFavoriteSelection(favorite)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        favoriteSwipeShareButton(favorite)
                        .tint(.teal)
                        .disabled(viewModel.deletingFavoriteID != nil)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDeleteFavorite = favorite
                        } label: {
                            swipeActionLabel(
                                title: viewModel.deletingFavoriteID == favorite.id ? L10n.string("common.deleting") : L10n.string("common.delete"),
                                systemImage: "trash"
                            )
                        }
                        .tint(.red)
                        .disabled(viewModel.deletingFavoriteID != nil)

                        Button {
                            Task {
                                await viewModel.setHidden(!favorite.isHidden, for: favorite)
                            }
                        } label: {
                            swipeActionLabel(
                                title: favorite.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"),
                                systemImage: favorite.isHidden ? "eye" : "eye.slash"
                            )
                        }
                        .tint(.orange)
                        .disabled(viewModel.deletingFavoriteID != nil)

                        Button {
                            pendingEditFavorite = favorite
                        } label: {
                            swipeActionLabel(title: L10n.string("common.edit"), systemImage: "pencil")
                        }
                        .tint(.indigo)
                        .disabled(viewModel.deletingFavoriteID != nil)
                    }
            }
        }
    }

    private func favoriteActionMenuButton(_ favorite: Favorite) -> some View {
        Menu {
            favoriteMenuShareButton(favorite)

            Button {
                pendingEditFavorite = favorite
            } label: {
                Label(L10n.string("common.edit"), systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setHidden(!favorite.isHidden, for: favorite)
                }
            } label: {
                Label(favorite.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"), systemImage: favorite.isHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                pendingDeleteFavorite = favorite
            } label: {
                Label(viewModel.deletingFavoriteID == favorite.id ? L10n.string("common.deleting") : L10n.string("common.delete"), systemImage: "trash")
            }
            .disabled(viewModel.deletingFavoriteID != nil)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.deletingFavoriteID != nil)
    }

    @ViewBuilder
    private func favoriteSwipeShareButton(_ favorite: Favorite) -> some View {
        #if canImport(UIKit)
        if usesIPadSharePresenter {
            Button {
                sharingFavorite = favorite
            } label: {
                swipeActionLabel(title: L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: favorite.url) {
                swipeActionLabel(title: L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        }
        #else
        ShareLink(item: favorite.url) {
            swipeActionLabel(title: L10n.string("common.share"), systemImage: "square.and.arrow.up")
        }
        #endif
    }

    @ViewBuilder
    private func favoriteMenuShareButton(_ favorite: Favorite) -> some View {
        #if canImport(UIKit)
        if usesIPadSharePresenter {
            Button {
                sharingFavorite = favorite
            } label: {
                Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: favorite.url) {
                Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        }
        #else
        ShareLink(item: favorite.url) {
            Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
        }
        #endif
    }

    private func collectionActionMenuButton(_ collection: FavoriteCollection) -> some View {
        Menu {
            Button {
                collectionNameDraft = FavoriteCollectionNameDraft(collection: collection)
            } label: {
                Label(L10n.string("common.edit"), systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setCollectionHidden(!collection.isHidden, for: collection)
                }
            } label: {
                Label(collection.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"), systemImage: collection.isHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                pendingDeleteCollection = collection
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shouldUseTwoColumnLayout(in size: CGSize) -> Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && size.width > size.height
        #else
        false
        #endif
    }

    private func handleMove(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard canReorderEntries else { return }

        switch scope {
        case .root:
            Task {
                await viewModel.reorderRootEntries(
                    visibleEntryKeys: visibleEntries.map(\.moveKey),
                    fromOffsets: source,
                    toOffset: destination
                )
            }
        case let .collection(collection):
            let visibleIDs = visibleEntries.compactMap { entry -> String? in
                guard case let .favorite(favorite) = entry else { return nil }
                return favorite.id
            }
            Task {
                await viewModel.reorderFavorites(
                    in: collection.id,
                    visibleIDs: visibleIDs,
                    fromOffsets: source,
                    toOffset: destination
                )
            }
        }
    }

    private func handleDrop(
        draggedEntryKey: String,
        onto targetEntry: FavoriteListEntry,
        position: FavoriteDropPosition
    ) {
        let reorderedKeys = reorderedItemsAfterDrop(
            visibleEntries.map(\.moveKey),
            draggedItem: draggedEntryKey,
            targetItem: targetEntry.moveKey,
            position: position
        )
        applyReorderedVisibleEntries(for: reorderedKeys)
    }

    private func handleDropToColumnBottom(
        draggedEntryKey: String,
        column: FavoriteListColumn
    ) {
        let reorderedKeys = reorderedItemsAfterDroppingAtColumnBottom(
            visibleEntries.map(\.moveKey),
            draggedItem: draggedEntryKey,
            column: column
        )
        applyReorderedVisibleEntries(for: reorderedKeys)
    }

    private func applyReorderedVisibleEntries(for reorderedKeys: [String]) {
        let originalKeys = visibleEntries.map(\.moveKey)
        guard reorderedKeys != originalKeys else { return }
        let moves = makeVisibleOrderMovesToTransform(from: originalKeys, to: reorderedKeys)
        guard !moves.isEmpty else { return }

        switch scope {
        case .root:
            Task {
                await viewModel.reorderRootEntries(visibleEntryKeys: originalKeys, moves: moves)
            }
        case let .collection(collection):
            let originalFavoriteIDs = visibleEntries.compactMap { entry -> String? in
                guard case let .favorite(favorite) = entry else { return nil }
                return favorite.id
            }
            Task {
                await viewModel.reorderFavorites(
                    in: collection.id,
                    visibleIDs: originalFavoriteIDs,
                    moves: moves
                )
            }
        }
    }

    private func open(_ favorite: Favorite, mode: FavoriteLaunchMode) {
        Task {
            if favoriteLaunchNeedsMangaProbeBlocker(favorite) {
                openingMangaFavoriteID = favorite.id
            }

            let target = await viewModel.openTarget(for: favorite, mode: mode)
            switch target {
            case let .reader(context):
                openingMangaFavoriteID = nil
                appModel.presentReader(context)
            case let .manga(context):
                openingMangaFavoriteID = nil
                appModel.presentManga(context)
            case let .web(resolvedFavorite):
                openingMangaFavoriteID = nil
                selectedFavorite = resolvedFavorite
            }
        }
    }

    private func toggleFavoriteSelection(_ favorite: Favorite) {
        if selectedFavoriteIDs.contains(favorite.id) {
            selectedFavoriteIDs.remove(favorite.id)
        } else {
            selectedFavoriteIDs.insert(favorite.id)
        }
    }

    private func toggleCollectionSelection(_ collection: FavoriteCollection) {
        if selectedCollectionIDs.contains(collection.id) {
            selectedCollectionIDs.remove(collection.id)
        } else {
            selectedCollectionIDs.insert(collection.id)
        }
    }

    private func toggleVisibleSelection() {
        if visibleSelectionIsComplete {
            for entry in visibleEntries {
                switch entry {
                case let .collection(collection):
                    selectedCollectionIDs.remove(collection.id)
                case let .favorite(favorite):
                    selectedFavoriteIDs.remove(favorite.id)
                }
            }
        } else {
            for entry in visibleEntries {
                switch entry {
                case let .collection(collection):
                    selectedCollectionIDs.insert(collection.id)
                case let .favorite(favorite):
                    selectedFavoriteIDs.insert(favorite.id)
                }
            }
        }
    }

    private func moveSelectedFavorites(to collectionID: String?) {
        let ids = Array(selectedFavoriteIDs)
        Task {
            if await viewModel.moveFavorites(ids: ids, toCollectionID: collectionID) {
                exitSelectionMode()
            }
        }
    }

    private func presentBatchTagPicker() {
        let tagSelectionState = makeBatchTagSelectionState(
            favorites: viewModel.favorites,
            selectedFavoriteIDs: selectedFavoriteIDs
        )
        tagPickerContext = FavoriteTagPickerContext(
            favoriteIDs: Array(selectedFavoriteIDs),
            initialTagIDs: tagSelectionState.initialTagIDs,
            showsOverwriteWarning: tagSelectionState.showsOverwriteWarning,
            exitsSelectionModeOnConfirm: true
        )
    }

    private func presentFilterTagPicker() {
        tagPickerContext = FavoriteTagPickerContext(filterTagIDs: selectedFilterTagIDs)
    }

    private func loadInitialFavorites() async {
        guard !didLoadInitialFavorites else { return }
        didLoadInitialFavorites = true

        await viewModel.loadCachedFavorites()
        if case .root = scope {
            await viewModel.refresh()
        }
    }

    private func saveCollectionName(_ draft: FavoriteCollectionNameDraft) {
        Task {
            if await viewModel.setCollectionName(draft.name, for: draft.collectionID) {
                collectionNameDraft = nil
            }
        }
    }

    private func dissolveCollection(_ collection: FavoriteCollection) {
        Task {
            _ = await viewModel.deleteSelections(favoriteIDs: [], collectionIDs: [collection.id])
        }
        pendingDeleteCollection = nil
    }

    private func pruneSelections() {
        let validFavoriteIDs = Set(viewModel.favorites.map(\.id))
        let validCollectionIDs = Set(viewModel.collections.map(\.id))
        selectedFavoriteIDs = selectedFavoriteIDs.intersection(validFavoriteIDs)
        selectedCollectionIDs = selectedCollectionIDs.intersection(validCollectionIDs)
        if isSelecting, selectedFavoriteIDs.isEmpty, selectedCollectionIDs.isEmpty {
            // Keep selection mode active so the toolbar can still be used consistently.
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedFavoriteIDs.removeAll()
        selectedCollectionIDs.removeAll()
    }

    private func filterLabel(for filter: FavoriteFilter) -> String {
        guard filter == .all else { return filter.title }
        return currentCollection?.name ?? filter.title
    }

    private func collectionSummary(for collection: FavoriteCollection) -> FavoriteCollectionSummary {
        makeFavoriteCollectionSummary(
            for: collection,
            favorites: viewModel.favorites,
            scope: scope,
            showsHidden: showsHidden,
            filter: currentFilter,
            searchText: searchText,
            selectedTagIDs: selectedFilterTagIDs
        )
    }

    @ViewBuilder
    private func swipeActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct FavoriteTagPickerView: View {
    let tags: [FavoriteTag]
    let favorites: [Favorite]
    let initialSelection: Set<String>
    let showsOverwriteWarning: Bool
    let onCancel: () -> Void
    let onConfirm: (Set<String>) async -> Bool
    let onCreateTag: (String, FavoriteTagColor) async -> FavoriteTag?
    let onUpdateTag: (String, String, FavoriteTagColor) async -> Bool
    let onDeleteTag: (String) async -> Bool
    let onReorderTags: ([String], IndexSet, Int) async -> Bool

    @AppStorage("yamibo.favorite.tag.sort") private var sortRawValue = FavoriteTagSortOrder.manual.rawValue
    @State private var selectionDraft: FavoriteTagSelectionDraft
    @State private var searchText = ""
    @State private var selectionErrorMessage: String?
    @State private var editorDraft: FavoriteTagEditorDraft?
    @State private var pendingDeleteTag: FavoriteTag?
    @State private var isConfirming = false

    init(
        tags: [FavoriteTag],
        favorites: [Favorite],
        initialSelection: Set<String>,
        showsOverwriteWarning: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (Set<String>) async -> Bool,
        onCreateTag: @escaping (String, FavoriteTagColor) async -> FavoriteTag?,
        onUpdateTag: @escaping (String, String, FavoriteTagColor) async -> Bool,
        onDeleteTag: @escaping (String) async -> Bool,
        onReorderTags: @escaping ([String], IndexSet, Int) async -> Bool
    ) {
        self.tags = tags
        self.favorites = favorites
        self.initialSelection = initialSelection
        self.showsOverwriteWarning = showsOverwriteWarning
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onCreateTag = onCreateTag
        self.onUpdateTag = onUpdateTag
        self.onDeleteTag = onDeleteTag
        self.onReorderTags = onReorderTags
        _selectionDraft = State(initialValue: FavoriteTagSelectionDraft(selectedTagIDs: initialSelection))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    tagSelectionHeader
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if showsOverwriteWarning {
                        Text(L10n.string("favorites.tags_overwrite_warning"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(visibleTags) { tag in
                        let isSelected = selectionDraft.selectedTagIDs.contains(tag.id)

                        Button {
                            toggle(tag)
                        } label: {
                            FavoriteTagPickerRow(
                                tag: tag,
                                isSelected: isSelected,
                                includesReorderHandle: canReorderCurrentTags
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button {
                                editorDraft = FavoriteTagEditorDraft(tag: tag, defaultColor: nextDefaultColor)
                            } label: {
                                Label(L10n.string("common.edit"), systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                pendingDeleteTag = tag
                            } label: {
                                Label(L10n.string("common.delete"), systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: moveTags)
                }
                .overlay {
                    if tags.isEmpty {
                        ContentUnavailableView(L10n.string("favorites.tags.empty"), systemImage: "tag")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                tagSelectionFooter
            }
            .favoriteTagPickerSearch(text: $searchText)
            .navigationTitle(L10n.string("favorites.select_tags"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(visibleTagsAreFullySelected ? L10n.string("favorites.tags_deselect_all") : L10n.string("favorites.tags_select_all")) {
                        toggleVisibleTagsSelection()
                    }
                    .disabled(visibleTags.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorDraft = FavoriteTagEditorDraft(tag: nil, defaultColor: nextDefaultColor)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectionDraft.selectedTagIDs)
            .sheet(item: $editorDraft) { draft in
                FavoriteTagEditorView(draft: draft) { name, color in
                    if let tagID = draft.tag?.id {
                        if await onUpdateTag(tagID, name, color) {
                            editorDraft = nil
                            return true
                        }
                        return false
                    }

                    guard let tag = await onCreateTag(name, color) else {
                        return false
                    }
                    searchText = ""
                    handleSelectionResult(selectionDraft.select(tag.id))
                    editorDraft = nil
                    return true
                } onCancel: {
                    editorDraft = nil
                }
            }
            .alert(
                L10n.string("favorites.delete_tag"),
                isPresented: pendingDeleteTagBinding,
                presenting: pendingDeleteTag
            ) { tag in
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteTag = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        if await onDeleteTag(tag.id) {
                            selectionDraft.selectedTagIDs.remove(tag.id)
                            pendingDeleteTag = nil
                        }
                    }
                }
            } message: { tag in
                Text(L10n.string("favorites.delete_tag_message", tag.name))
            }
            #if os(iOS)
            .environment(\.editMode, .constant(canReorderCurrentTags ? .active : .inactive))
            #endif
        }
    }

    private var tagSelectionHeader: some View {
        tagSortMenu
    }

    private var tagSortMenu: some View {
        Menu {
            Picker(L10n.string("favorites.sort"), selection: $sortRawValue) {
                ForEach(FavoriteTagSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title).tag(sortOrder.rawValue)
                }
            }
        } label: {
            VStack(spacing: 0) {
                Divider()

                HStack {
                    Text(L10n.string("favorites.sort"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(currentSortOrder.title)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)

                Divider()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tagSelectionFooter: some View {
        HStack {
            Button(L10n.string("common.cancel"), action: onCancel)
                .font(.headline)
                .foregroundStyle(.red)

            Spacer()

            Text(selectionPrompt)
                .font(.headline)
                .foregroundStyle(selectionErrorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Spacer()

            Button(L10n.string("common.ok")) {
                Task {
                    isConfirming = true
                    _ = await onConfirm(selectionDraft.selectedTagIDs)
                    isConfirming = false
                }
            }
            .font(.headline)
            .disabled(isConfirming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var pendingDeleteTagBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTag != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteTag = nil
                }
            }
        )
    }

    private var nextDefaultColor: FavoriteTagColor {
        let colors = FavoriteTagColor.allCases
        guard !colors.isEmpty else { return .gray }
        return colors[tags.count % colors.count]
    }

    private var orderedTags: [FavoriteTag] {
        sortedFavoriteTags(tags, favorites: favorites, sortOrder: currentSortOrder)
    }

    private var visibleTags: [FavoriteTag] {
        filteredFavoriteTags(orderedTags, searchText: searchText)
    }

    private var currentSortOrder: FavoriteTagSortOrder {
        FavoriteTagSortOrder(rawValue: sortRawValue) ?? .manual
    }

    private var canReorderCurrentTags: Bool {
        canReorderFavoriteTags(sortOrder: currentSortOrder, searchText: searchText)
    }

    private var visibleTagIDs: [String] {
        visibleTags.map(\.id)
    }

    private var visibleTagsAreFullySelected: Bool {
        let ids = Set(visibleTagIDs)
        return !ids.isEmpty && ids.isSubset(of: selectionDraft.selectedTagIDs)
    }

    private var selectionPrompt: String {
        selectionErrorMessage ?? L10n.string("favorites.tags_selected_count", selectionDraft.selectedTagIDs.count)
    }

    private func toggle(_ tag: FavoriteTag) {
        handleSelectionResult(selectionDraft.toggle(tag.id))
    }

    private func toggleVisibleTagsSelection() {
        let ids = visibleTagIDs
        if visibleTagsAreFullySelected {
            handleSelectionResult(selectionDraft.deselectAll(visibleTagIDs: ids))
        } else {
            handleSelectionResult(selectionDraft.selectAll(visibleTagIDs: ids))
        }
    }

    private func moveTags(fromOffsets: IndexSet, toOffset: Int) {
        guard canReorderCurrentTags else { return }
        let visibleIDs = visibleTags.map(\.id)
        Task {
            _ = await onReorderTags(visibleIDs, fromOffsets, toOffset)
        }
    }

    private func handleSelectionResult(_ result: FavoriteTagSelectionDraftResult) {
        switch result {
        case .changed:
            selectionErrorMessage = nil
        case .unchanged:
            break
        case let .selectionLimitExceeded(max):
            selectionErrorMessage = L10n.string("favorites.tags_limit_message", max)
        }
    }
}

private struct FavoriteTagPickerRow: View {
    let tag: FavoriteTag
    let isSelected: Bool
    let includesReorderHandle: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tag.color.swiftUIColor)
                    .frame(width: isSelected ? 31 : 28, height: isSelected ? 31 : 28)

                Text(tagInitial)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(tag.color.iconTextColor)
            }
            .frame(width: 34, height: 34)
            .shadow(color: tag.color.swiftUIColor.opacity(isSelected ? 0.28 : 0.18), radius: 8, y: 4)

            Text(tag.name)
                .font(isSelected ? .body.weight(.semibold) : .body)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer()

            ZStack {
                if isSelected {
                    Circle()
                        .fill(tag.color.swiftUIColor)
                        .frame(width: 24, height: 24)

                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(.secondary.opacity(0.55), lineWidth: 2.25)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tag.color.swiftUIColor.opacity(0.10) : .clear)
                .padding(.trailing, -selectionOutlineTrailingExtension)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? tag.color.swiftUIColor : .clear, lineWidth: 2)
                .padding(.trailing, -selectionOutlineTrailingExtension)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private var tagInitial: String {
        let trimmedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.first.map(String.init) ?? "#"
    }

    private var selectionOutlineTrailingExtension: CGFloat {
        includesReorderHandle ? 52 : 0
    }
}

private extension View {
    @ViewBuilder
    func favoriteTagPickerSearch(text: Binding<String>) -> some View {
        #if os(iOS)
        self
            .searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.string("favorites.search_tags")
            )
        #else
        self
            .searchable(text: text, prompt: L10n.string("favorites.search_tags"))
        #endif
    }
}

private struct FavoriteTagEditorView: View {
    let draft: FavoriteTagEditorDraft
    let onSave: (String, FavoriteTagColor) async -> Bool
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: FavoriteTagColor
    @State private var isSaving = false

    init(
        draft: FavoriteTagEditorDraft,
        onSave: @escaping (String, FavoriteTagColor) async -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _color = State(initialValue: draft.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("favorites.tag_name"), text: $name)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(FavoriteTagColor.allCases, id: \.self) { tagColor in
                            Button {
                                color = tagColor
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(tagColor.swiftUIColor)
                                        .frame(width: 32, height: 32)
                                    if color == tagColor {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .disabled(isSaving)
            .navigationTitle(draft.tag == nil ? L10n.string("favorites.new_tag") : L10n.string("favorites.edit_tag"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        Task {
                            isSaving = true
                            let didSave = await onSave(name, color)
                            isSaving = false
                            if didSave {
                                onCancel()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

private extension FavoriteTagColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }

    var iconTextColor: Color {
        relativeLuminance > 0.52 ? .black : .white
    }

    private var relativeLuminance: Double {
        let components: (red: Double, green: Double, blue: Double) = switch self {
        case .red: (1.00, 0.23, 0.19)
        case .orange: (1.00, 0.58, 0.00)
        case .yellow: (1.00, 0.80, 0.00)
        case .green: (0.20, 0.78, 0.35)
        case .blue: (0.00, 0.48, 1.00)
        case .purple: (0.69, 0.32, 0.87)
        case .pink: (1.00, 0.18, 0.33)
        case .gray: (0.56, 0.56, 0.58)
        }

        return 0.2126 * components.red + 0.7152 * components.green + 0.0722 * components.blue
    }
}

struct FavoriteRow: View {
    let favorite: Favorite
    let isResolving: Bool
    let isDeleting: Bool
    let isSelected: Bool
    let isSelecting: Bool
    let tags: [FavoriteTag]
    let tagSearchText: String
    let prioritizedTagIDs: Set<String>
    let accentColor: Color
    let onOpen: () -> Void

    private var tagChipSummary: FavoriteTagChipSummary {
        makeFavoriteTagChipSummary(
            for: favorite,
            tags: tags,
            searchText: tagSearchText,
            prioritizedTagIDs: prioritizedTagIDs
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accentColor)
                .frame(width: 5)
                .padding(.vertical, 14)
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(favorite.resolvedDisplayTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isResolving || isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(favoriteDetailLineItems(for: favorite), id: \.self) { line in
                        FavoriteDetailLineView(line: line)
                    }

                    if favorite.isHidden {
                        Label(L10n.string("common.hidden"), systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !tagChipSummary.chips.isEmpty {
                        FavoriteTagChipRow(summary: tagChipSummary)
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.leading, 16)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : accentColor.opacity(0.18),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }

    private var titleColor: Color {
        isSelecting && !isSelected ? .secondary : .primary
    }
}

private struct FavoriteDetailLineView: View {
    let line: FavoriteDetailLine

    var body: some View {
        switch line {
        case let .text(text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .novelProgress(chapterTitle, progressText):
            HStack(spacing: 0) {
                if let chapterTitle, !chapterTitle.isEmpty {
                    Text(chapterTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)

                    Text(" · \(progressText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                } else {
                    Text(progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FavoriteTagChipRow: View {
    let summary: FavoriteTagChipSummary

    var body: some View {
        HStack(spacing: 6) {
            ForEach(summary.chips) { tag in
                FavoriteTagChip(tag: tag)
            }

            if summary.overflowCount > 0 {
                Text("+\(summary.overflowCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.secondary.opacity(0.12))
                    )
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FavoriteTagChip: View {
    let tag: FavoriteTag

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.color.swiftUIColor)
                .frame(width: 6, height: 6)

            Text(tag.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Capsule(style: .continuous)
                .fill(tag.color.swiftUIColor.opacity(0.13))
        )
    }
}

struct FavoriteCollectionRow: View {
    let collection: FavoriteCollection
    let summary: FavoriteCollectionSummary
    let isSelected: Bool
    let isSelecting: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accentColor)
                .frame(width: 7)
                .padding(.vertical, 14)
                .padding(.leading, 10)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "folder.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(collection.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(titleColor)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(L10n.string("favorite_category.collection"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(accentColor)

                        if collection.isHidden {
                            Label(L10n.string("common.hidden"), systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.leading, 16)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : accentColor.opacity(0.32), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var titleColor: Color {
        isSelecting && !isSelected ? .secondary : .primary
    }

    private var summaryText: String {
        if summary.hiddenCount > 0 {
            return L10n.string("favorites.collection_summary_hidden", summary.itemCount, summary.hiddenCount)
        }
        return L10n.string("favorites.collection_summary", summary.itemCount)
    }
}

func makeFavoriteSelectionActionState(
    scope: FavoriteScope,
    selectedFavoriteCount: Int,
    selectedCollectionCount: Int
) -> FavoriteSelectionActionState {
    let state = FavoriteLibraryProjection.selectionActionState(
        scope: scope.libraryScope,
        selectedFavoriteCount: selectedFavoriteCount,
        selectedCollectionCount: selectedCollectionCount
    )
    return FavoriteSelectionActionState(
        canTag: state.canTag,
        canCreateCollection: state.canCreateCollection,
        canMove: state.canMove,
        canDelete: state.canDelete
    )
}

func makeBatchTagSelectionState(
    favorites: [Favorite],
    selectedFavoriteIDs: Set<String>
) -> FavoriteBatchTagSelectionState {
    let state = FavoriteLibraryProjection.batchTagSelectionState(
        favorites: favorites,
        selectedFavoriteIDs: selectedFavoriteIDs
    )
    return FavoriteBatchTagSelectionState(
        initialTagIDs: state.initialTagIDs,
        showsOverwriteWarning: state.showsOverwriteWarning
    )
}

func filteredFavoriteTags(_ tags: [FavoriteTag], searchText: String) -> [FavoriteTag] {
    FavoriteLibraryProjection.filteredTags(tags, searchText: searchText)
}

func canReorderFavoriteTags(sortOrder: FavoriteTagSortOrder, searchText: String) -> Bool {
    FavoriteLibraryProjection.canReorderTags(sortOrder: sortOrder.libraryTagSortOrder, searchText: searchText)
}

func canReorderFavoriteEntries(
    sortOrder: FavoriteSortOrder,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Bool {
    FavoriteLibraryProjection.canReorderEntries(
        sortOrder: sortOrder.librarySortOrder,
        searchText: searchText,
        selectedTagIDs: selectedTagIDs
    )
}

func sortedFavoriteTags(
    _ tags: [FavoriteTag],
    favorites: [Favorite],
    sortOrder: FavoriteTagSortOrder
) -> [FavoriteTag] {
    FavoriteLibraryProjection.sortedTags(tags, favorites: favorites, sortOrder: sortOrder.libraryTagSortOrder)
}

func favoriteTagAssociationCounts(from favorites: [Favorite]) -> [String: Int] {
    FavoriteLibraryProjection.tagAssociationCounts(from: favorites)
}

func makeFavoriteTagChipSummary(
    for favorite: Favorite,
    tags: [FavoriteTag],
    searchText: String,
    prioritizedTagIDs: Set<String> = []
) -> FavoriteTagChipSummary {
    let summary = FavoriteLibraryProjection.tagChipSummary(
        for: favorite,
        tags: tags,
        searchText: searchText,
        prioritizedTagIDs: prioritizedTagIDs
    )
    return FavoriteTagChipSummary(
        chips: summary.chips,
        overflowCount: summary.overflowCount
    )
}

func favoriteProgressScore(for favorite: Favorite) -> Int {
    favorite.lastView * 1000 + favorite.mangaPageIndex
}

func progressScore(for favorite: Favorite) -> Int {
    favoriteProgressScore(for: favorite)
}

func makeFilteredFavorites(
    from favorites: [Favorite],
    scope: FavoriteScope = .root,
    showsHidden: Bool,
    filter: FavoriteFilter,
    sortOrder: FavoriteSortOrder,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> [Favorite] {
    let snapshot = FavoriteLibrarySnapshot(favorites: favorites, collections: [])
    return FavoriteLibraryProjection.favorites(
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: scope.libraryScope,
            showsHidden: showsHidden,
            filter: filter.libraryFilter,
            sortOrder: sortOrder.librarySortOrder,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    )
}

func makeFavoriteListEntries(
    scope: FavoriteScope,
    favorites: [Favorite],
    collections: [FavoriteCollection],
    showsHidden: Bool,
    filter: FavoriteFilter,
    sortOrder: FavoriteSortOrder,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> [FavoriteListEntry] {
    let snapshot = FavoriteLibrarySnapshot(favorites: favorites, collections: collections)
    return FavoriteLibraryProjection.entries(
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: scope.libraryScope,
            showsHidden: showsHidden,
            filter: filter.libraryFilter,
            sortOrder: sortOrder.librarySortOrder,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    )
    .map(\.favoriteListEntry)
}

func rootCollectionMatches(
    _ collection: FavoriteCollection,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Bool {
    let entries = makeFavoriteListEntries(
        scope: .root,
        favorites: favorites,
        collections: [collection],
        showsHidden: showsHidden,
        filter: filter,
        sortOrder: .manual,
        searchText: searchText,
        selectedTagIDs: selectedTagIDs
    )
    return entries.contains(.collection(collection))
}

func makeFavoriteCollectionSummary(
    for collection: FavoriteCollection,
    favorites: [Favorite],
    scope: FavoriteScope,
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> FavoriteCollectionSummary {
    let snapshot = FavoriteLibrarySnapshot(favorites: favorites, collections: [])
    let summary = FavoriteLibraryProjection.collectionSummary(
        for: collection,
        in: snapshot,
        query: FavoriteLibraryQuery(
            scope: scope.libraryScope,
            showsHidden: showsHidden,
            filter: filter.libraryFilter,
            sortOrder: .manual,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    )
    return FavoriteCollectionSummary(
        itemCount: summary.itemCount,
        hiddenCount: summary.hiddenCount
    )
}

private func favoriteSearchTextForCollectionMatch(
    _ collection: FavoriteCollection,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String>
) -> String {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !selectedTagIDs.isEmpty,
          filter == .all,
          !trimmedSearchText.isEmpty,
          collection.name.localizedCaseInsensitiveContains(trimmedSearchText) else {
        return searchText
    }
    return ""
}

enum FavoriteDetailLine: Hashable {
    case text(String)
    case novelProgress(chapterTitle: String?, progressText: String)

    var displayText: String {
        switch self {
        case let .text(text):
            return text
        case let .novelProgress(chapterTitle, progressText):
            if let chapterTitle, !chapterTitle.isEmpty {
                return "\(chapterTitle) · \(progressText)"
            }
            return progressText
        }
    }
}

func favoriteProgressText(for favorite: Favorite) -> String? {
    if favorite.type == .novel {
        return favoriteNovelProgressText(for: favorite)
    }
    if let lastChapter = favorite.lastChapter, !lastChapter.isEmpty {
        if favorite.type == .manga, favorite.mangaPageIndex > 0 {
            if let chapterLabel = favoriteMangaChapterLabel(from: lastChapter) {
                return L10n.string("favorites.progress.page_with_chapter", favorite.mangaPageIndex + 1, chapterLabel)
            }
            return L10n.string("favorites.progress.page", favorite.mangaPageIndex + 1)
        }
        return lastChapter
    }
    if favorite.type == .manga, favorite.mangaPageIndex > 0 {
        return L10n.string("favorites.progress.page", favorite.mangaPageIndex + 1)
    }
    if favorite.type == .unknown, favorite.mangaPageIndex > 0 || favorite.lastView > 1 {
        return L10n.string("favorites.progress.page_web", favorite.mangaPageIndex + 1, favorite.lastView)
    }
    return nil
}

func favoriteNovelProgressText(for favorite: Favorite) -> String? {
    guard favorite.type == .novel,
          favorite.novelResumePoint != nil else {
        return nil
    }

    let percent = favorite.novelDocumentSurfaceProgressPercent
    guard let maxView = favorite.novelMaxView, maxView > 1 else {
        guard let percent else { return nil }
        return L10n.string("favorites.progress.novel_percent", percent)
    }

    let view = min(max(favorite.lastView, 1), maxView)
    guard let percent else {
        return L10n.string("favorites.progress.novel_web", view, maxView)
    }

    return L10n.string(
        "favorites.progress.novel_page_web",
        percent,
        view,
        maxView
    )
}

func favoriteMangaChapterLabel(from rawTitle: String) -> String? {
    let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return nil }

    let chapterNumber = MangaTitleCleaner.extractChapterNumber(trimmedTitle)
    let displayNumber = MangaChapterDisplayFormatter.displayNumber(
        rawTitle: trimmedTitle,
        chapterNumber: chapterNumber
    )

    guard !displayNumber.isEmpty else { return nil }
    return L10n.string("favorites.manga_chapter", displayNumber)
}

func favoriteDetailLineItems(for favorite: Favorite) -> [FavoriteDetailLine] {
    var lines: [FavoriteDetailLine] = []

    if favorite.type == .manga {
        if let progressText = favoriteProgressText(for: favorite) {
            lines.append(.text(progressText))
        } else if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !lastChapter.isEmpty {
            lines.append(.text(lastChapter))
        }

        if lines.isEmpty {
            lines.append(.text(favorite.type.title))
        }

        return Array(lines.prefix(1))
    }

    if favorite.type == .novel {
        let chapterTitle = favorite.novelResumePoint?.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackChapterTitle = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayChapterTitle = [chapterTitle, fallbackChapterTitle]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        let progressText = favoriteProgressText(for: favorite)

        if let progressText {
            lines.append(.novelProgress(chapterTitle: displayChapterTitle, progressText: progressText))
        } else if let displayChapterTitle {
            lines.append(.text(displayChapterTitle))
        }
    } else if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastChapter.isEmpty {
        lines.append(.text(lastChapter))
    }

    if favorite.type != .novel,
       let progressText = favoriteProgressText(for: favorite),
       !lines.contains(.text(progressText)) {
        lines.append(.text(progressText))
    }

    if lines.isEmpty {
        lines.append(.text(favorite.type.title))
    }

    return Array(lines.prefix(2))
}

func favoriteDetailLines(for favorite: Favorite) -> [String] {
    favoriteDetailLineItems(for: favorite).map(\.displayText)
}

func favoriteAccentAppearanceColor(
    for type: FavoriteType,
    appearance: FavoriteAppearanceSettings
) -> FavoriteAppearanceColor {
    switch type {
    case .novel:
        appearance.novel
    case .manga:
        appearance.manga
    case .other:
        appearance.other
    case .unknown:
        .gray
    }
}

func favoriteAccentColor(for type: FavoriteType, appearance: FavoriteAppearanceSettings) -> Color {
    favoriteAccentAppearanceColor(for: type, appearance: appearance).swiftUIColor
}

func favoriteCollectionAccentColor(for appearance: FavoriteAppearanceSettings) -> Color {
    appearance.collection.swiftUIColor
}

func favoriteCollectionAccentAppearanceColor(for appearance: FavoriteAppearanceSettings) -> FavoriteAppearanceColor {
    appearance.collection
}

func favoriteAccentColor(for type: FavoriteType) -> Color {
    favoriteAccentColor(for: type, appearance: .init())
}

func favoriteCollectionAccentColor() -> Color {
    favoriteCollectionAccentColor(for: .init())
}

func orderedCollections(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
    collections.sorted { lhs, rhs in
        if lhs.manualOrder != rhs.manualOrder {
            return lhs.manualOrder < rhs.manualOrder
        }
        return lhs.id < rhs.id
    }
}

private func entryManualOrder(_ entry: FavoriteListEntry) -> Int {
    switch entry {
    case let .collection(collection):
        collection.manualOrder
    case let .favorite(favorite):
        favorite.manualOrder
    }
}

private func compareRecentReadFavorites(_ lhs: Favorite, _ rhs: Favorite) -> Bool {
    switch (lhs.lastReadAt, rhs.lastReadAt) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        if lhs.manualOrder != rhs.manualOrder {
            return lhs.manualOrder < rhs.manualOrder
        }
        return lhs.id < rhs.id
    }
}

private func compareRecentReadEntries(
    _ lhs: FavoriteListEntry,
    _ rhs: FavoriteListEntry,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Bool {
    switch (
        entryLastReadAt(
            lhs,
            favorites: favorites,
            showsHidden: showsHidden,
            filter: filter,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        ),
        entryLastReadAt(
            rhs,
            favorites: favorites,
            showsHidden: showsHidden,
            filter: filter,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
    ) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        if entryManualOrder(lhs) != entryManualOrder(rhs) {
            return entryManualOrder(lhs) < entryManualOrder(rhs)
        }
        return lhs.id < rhs.id
    }
}

private func entryLastReadAt(
    _ entry: FavoriteListEntry,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String,
    selectedTagIDs: Set<String> = []
) -> Date? {
    switch entry {
    case let .favorite(favorite):
        return favorite.lastReadAt
    case let .collection(collection):
        let containedFavoriteSearchText = favoriteSearchTextForCollectionMatch(
            collection,
            filter: filter,
            searchText: searchText,
            selectedTagIDs: selectedTagIDs
        )
        return makeFilteredFavorites(
            from: favorites,
            scope: .collection(collection),
            showsHidden: showsHidden,
            filter: filter,
            sortOrder: .recentRead,
            searchText: containedFavoriteSearchText,
            selectedTagIDs: selectedTagIDs
        )
        .compactMap(\.lastReadAt)
        .max()
    }
}

private extension View {
    @ViewBuilder
    func onDragIf(_ condition: Bool, value: String, onStart: @escaping () -> Void) -> some View {
        if condition {
            onDrag {
                onStart()
                return NSItemProvider(object: value as NSString)
            }
        } else {
            self
        }
    }
}
