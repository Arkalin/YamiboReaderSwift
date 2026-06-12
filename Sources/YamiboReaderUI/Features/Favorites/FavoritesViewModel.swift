import Foundation
import SwiftUI
import YamiboReaderCore

struct FavoriteSharePresenter: ViewModifier {
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
    @Published public private(set) var favoriteBackground = FavoriteBackgroundSettings()
    @Published public private(set) var favoriteBackgroundImageData: Data?
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
                await self.reloadFavoriteSettings()
            }
        }
    }

    deinit {
        favoriteUpdatesTask?.cancel()
        settingsUpdatesTask?.cancel()
    }

    public func loadCachedFavorites() async {
        await reloadFavoriteSettings()
        await reloadLocalFavorites()
    }

    public func reloadLocalFavorites() async {
        applySnapshot(await favoriteStore.loadLibrarySnapshot())
    }

    public func reloadFavoriteAppearance() async {
        await reloadFavoriteSettings()
    }

    public func reloadFavoriteSettings() async {
        let settings = await appContext.settingsStore.load()
        favoriteAppearance = settings.favoriteAppearance
        favoriteBackground = settings.favoriteBackground
        if settings.favoriteBackground.isEnabled {
            favoriteBackgroundImageData = await appContext.favoriteBackgroundImageStore.loadData(
                imageID: settings.favoriteBackground.imageID
            )
        } else {
            favoriteBackgroundImageData = nil
        }
    }

    public func refresh() async {
        guard !isLoading else { return }

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
            guard !isCancellationError(error) else { return }
            errorMessage = refreshErrorMessage(for: error)
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
