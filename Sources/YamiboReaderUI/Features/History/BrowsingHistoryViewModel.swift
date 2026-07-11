import Foundation
import Observation
import YamiboReaderCore

/// Drives the browsing-history page: timeline entries with type filtering
/// and title search, per-row covers, and the quick-favorite heart.
///
/// The heart acts on "the thread this row currently points at" — for a
/// directory-level manga row that is the current chapter, never the whole
/// merged group (browsing-history decision #11: a light tap stays a light
/// action). Add/remove reuse the standard quick-action decision flow
/// (remembered sync choices raise the same prompts the reader's star button
/// does).
@MainActor
@Observable
final class BrowsingHistoryViewModel {
    var entries: [BrowsingHistoryEntry] = []
    var selectedCategory: BrowsingHistoryCategory?
    var searchText = ""
    var isLoading = false
    var hasLoaded = false
    var favoritedThreadIDs: Set<String> = []
    var coverURLsByEntryID: [String: URL] = [:]
    var errorMessage: String?
    var transientMessage: String?
    var favoriteAddPromptPresented = false
    var favoriteRemovePrompt: FavoriteRemovePrompt?
    var clearAllConfirmationPresented = false

    @ObservationIgnored private let browsingHistoryStore: BrowsingHistoryStore?
    @ObservationIgnored private let favoriteLibraryStore: FavoriteLibraryStore
    @ObservationIgnored private let contentCoverStore: ContentCoverStore
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    @ObservationIgnored private let openTargetResolver: BrowsingHistoryOpenTargetResolver
    /// The entry whose heart raised the currently presented add prompt.
    @ObservationIgnored private var pendingFavoriteAddEntry: BrowsingHistoryEntry?
    /// Debounces the reload storms this page is exposed to: store-change
    /// notifications fire every ~350ms while a reader opened from here keeps
    /// saving positions, and the search field fires per keystroke.
    @ObservationIgnored private var pendingReloadTask: Task<Void, Never>?
    /// Drops stale reload results when a newer reload has since started.
    @ObservationIgnored private var reloadGeneration = 0

    init(dependencies: LibraryDependencies) {
        browsingHistoryStore = dependencies.browsingHistoryStore
        favoriteLibraryStore = dependencies.localFavoriteLibraryStore
        contentCoverStore = dependencies.contentCoverStore
        settingsStore = dependencies.settingsStore
        makeFavoriteRepository = dependencies.makeFavoriteRepository
        openTargetResolver = BrowsingHistoryOpenTargetResolver(
            readingProgressStore: dependencies.readingProgressStore,
            mangaDirectoryStore: dependencies.mangaDirectoryStore,
            settingsStore: dependencies.settingsStore
        )
    }

    func load() async {
        isLoading = entries.isEmpty
        defer {
            isLoading = false
            hasLoaded = true
        }
        await reload()
    }

    func reload() async {
        guard let browsingHistoryStore else {
            entries = []
            return
        }
        reloadGeneration += 1
        let generation = reloadGeneration
        let searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let loadedEntries = await browsingHistoryStore.entries(
            category: selectedCategory,
            searchText: searchQuery.isEmpty ? nil : searchQuery
        )
        guard generation == reloadGeneration else { return }
        entries = loadedEntries
        await refreshFavoritedThreadIDs()
        await refreshCovers(for: loadedEntries, generation: generation)
    }

    /// Coalesces reload triggers behind a short debounce; `reload()` itself
    /// stays available for the initial load and explicit user actions.
    func scheduleReload() {
        pendingReloadTask?.cancel()
        pendingReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    /// Follows history-store changes (recording readers, deletes from this
    /// page) and favorite-library changes (heart state) for the lifetime of
    /// the page.
    func observeHistoryChanges() async {
        for await _ in NotificationCenter.default.notifications(named: BrowsingHistoryStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            scheduleReload()
        }
    }

    func observeFavoriteChanges() async {
        for await _ in NotificationCenter.default.notifications(named: FavoriteLibraryStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            await refreshFavoritedThreadIDs()
        }
    }

    func delete(_ entry: BrowsingHistoryEntry) async {
        guard let browsingHistoryStore else { return }
        entries.removeAll { $0.id == entry.id }
        do {
            try await browsingHistoryStore.delete(id: entry.id)
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    func clearAll() async {
        guard let browsingHistoryStore else { return }
        entries = []
        do {
            try await browsingHistoryStore.clearAll()
        } catch {
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    func openTarget(for entry: BrowsingHistoryEntry) async -> BrowsingHistoryOpenTarget? {
        await openTargetResolver.openTarget(for: entry)
    }

    // MARK: - Favorite heart

    /// The thread the heart reads and writes for this row (decision #11):
    /// the row's own thread, or the current chapter for a directory-level
    /// manga row.
    func heartThreadID(for entry: BrowsingHistoryEntry) -> String? {
        entry.target.threadID ?? entry.chapterThreadID
    }

    func isFavorited(_ entry: BrowsingHistoryEntry) -> Bool {
        guard let threadID = heartThreadID(for: entry) else { return false }
        return favoritedThreadIDs.contains(threadID)
    }

    func toggleFavorite(_ entry: BrowsingHistoryEntry) async {
        guard let threadID = heartThreadID(for: entry) else { return }
        let settings = await settingsStore.load().favorites
        if let item = await storedFavoriteItem(threadID: threadID) {
            let favorite = Favorite(
                id: item.id,
                title: item.title,
                displayName: item.displayName,
                threadID: threadID,
                remoteFavoriteID: item.remoteMapping?.yamiboFavoriteID,
                type: .other,
                tagIDs: item.tagIDs
            )
            let canRemoveRemote = favorite.remoteFavoriteID?.isEmpty == false
            switch FavoriteRemoveRemoteDecision.resolve(settings: settings, canRemoveRemote: canRemoveRemote) {
            case .prompt:
                favoriteRemovePrompt = FavoriteRemovePrompt(favorite: favorite)
            case let .silent(removeRemote):
                await performFavoriteRemoval(favorite, removeRemote: removeRemote)
            }
            return
        }

        switch FavoriteAddSyncDecision.resolve(settings: settings, canSyncRemote: true) {
        case .prompt:
            pendingFavoriteAddEntry = entry
            favoriteAddPromptPresented = true
        case let .silent(syncToRemote):
            await performFavoriteAdd(entry, syncToRemote: syncToRemote)
        }
    }

    func confirmFavoriteAdd(syncToRemote: Bool, remember: Bool) async {
        favoriteAddPromptPresented = false
        guard let entry = pendingFavoriteAddEntry else { return }
        pendingFavoriteAddEntry = nil
        if remember {
            await rememberAddSyncChoice(syncToRemote)
        }
        await performFavoriteAdd(entry, syncToRemote: syncToRemote)
    }

    func confirmFavoriteRemoval(_ favorite: Favorite, removeRemote: Bool, remember: Bool) async {
        favoriteRemovePrompt = nil
        if remember {
            await rememberRemoveRemoteChoice(removeRemote)
        }
        await performFavoriteRemoval(favorite, removeRemote: removeRemote)
    }

    func clearTransientMessage() {
        transientMessage = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func performFavoriteAdd(_ entry: BrowsingHistoryEntry, syncToRemote: Bool) async {
        guard let threadID = heartThreadID(for: entry) else { return }
        do {
            let result = try await FavoriteQuickActions.addFavorite(
                threadID: threadID,
                title: favoriteTitle(for: entry),
                type: .other,
                authorID: entry.authorID,
                forumID: entry.forumID,
                localTargetKindOverride: favoriteTargetKind(for: entry),
                formHash: nil,
                syncToRemote: syncToRemote,
                localFavoriteLibraryStore: favoriteLibraryStore,
                remoteRepository: await makeFavoriteRepository()
            )
            favoritedThreadIDs.insert(threadID)
            transientMessage = result.remote.addFeedbackMessage
        } catch {
            errorMessage = error.localizedDescription
            await refreshFavoritedThreadIDs()
        }
    }

    private func performFavoriteRemoval(_ favorite: Favorite, removeRemote: Bool) async {
        do {
            try await FavoriteQuickActions.removeFavorite(
                favorite,
                removeRemote: removeRemote,
                localFavoriteLibraryStore: favoriteLibraryStore,
                remoteRepository: removeRemote ? await makeFavoriteRepository() : nil
            )
            favoritedThreadIDs.remove(favorite.threadID)
            transientMessage = removeRemote
                ? L10n.string("favorites.quick.removed_with_remote")
                : L10n.string("favorites.quick.removed")
        } catch {
            errorMessage = error.localizedDescription
            await refreshFavoritedThreadIDs()
        }
    }

    /// A directory-level row favorites its *current chapter* (decision #11),
    /// so the stored favorite title carries the chapter alongside the work
    /// name — the row itself only knows the work title, not the chapter
    /// thread's real forum title.
    private func favoriteTitle(for entry: BrowsingHistoryEntry) -> String {
        if entry.target.kind == .mangaTitle, let chapterTitle = entry.chapterTitle,
           !chapterTitle.isEmpty, chapterTitle != entry.title {
            return "\(entry.title) \(chapterTitle)"
        }
        return entry.title
    }

    /// History rows already know their content's form — no fid-based
    /// re-classification (a manga row's board may not even be recorded).
    private func favoriteTargetKind(for entry: BrowsingHistoryEntry) -> FavoriteItemTargetKind {
        switch entry.target.kind {
        case .normalThread:
            .normalThread
        case .novelThread:
            .novelThread
        case .mangaTitle, .mangaThread:
            .mangaThread
        }
    }

    private func storedFavoriteItem(threadID: String) async -> FavoriteItem? {
        (try? await favoriteLibraryStore.load())?.items.first { $0.target.threadID == threadID }
    }

    private func refreshFavoritedThreadIDs() async {
        let document = try? await favoriteLibraryStore.load()
        favoritedThreadIDs = Set((document?.items ?? []).compactMap { $0.target.threadID })
    }

    private func refreshCovers(for entries: [BrowsingHistoryEntry], generation: Int) async {
        var keysByEntryID: [String: ContentCoverKey] = [:]
        for entry in entries {
            if let key = ContentCoverKey(target: entry.target) {
                keysByEntryID[entry.id] = key
            }
        }
        let coversByKey = await contentCoverStore.covers(for: Array(keysByEntryID.values))
        guard generation == reloadGeneration else { return }
        var covers: [String: URL] = [:]
        for (entryID, key) in keysByEntryID {
            if let url = coversByKey[key]?.resolvedURL {
                covers[entryID] = url
            }
        }
        coverURLsByEntryID = covers
    }

    private func rememberAddSyncChoice(_ syncToRemote: Bool) async {
        var settings = await settingsStore.load()
        settings.favorites.addSyncPromptEnabled = false
        settings.favorites.addSyncDefault = syncToRemote
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.library.error("Failed to save remembered add-sync choice from history page: \(error)")
        }
    }

    private func rememberRemoveRemoteChoice(_ removeRemote: Bool) async {
        var settings = await settingsStore.load()
        settings.favorites.removeRemotePromptEnabled = false
        settings.favorites.removeRemoteDefault = removeRemote
        do {
            try await settingsStore.save(settings)
        } catch {
            YamiboLog.library.error("Failed to save remembered remove-remote choice from history page: \(error)")
        }
    }
}
