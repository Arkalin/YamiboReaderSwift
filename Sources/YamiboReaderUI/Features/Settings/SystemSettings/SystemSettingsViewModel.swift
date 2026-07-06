import SwiftUI
import YamiboReaderCore

@MainActor
final class SystemSettingsViewModel: ObservableObject {
    @Published var homePage: AppHomePage = .forum
    @Published var favoriteAppearance = FavoriteAppearanceSettings()
    @Published var favoriteBackground = FavoriteBackgroundSettings()
    @Published var favoriteLayoutMode: FavoriteLibraryLayoutMode = .rowCard
    @Published var favoriteSortOrder: LocalFavoriteLibrarySortOrder = .organization
    @Published var favoriteSortDescending = false
    @Published var favoriteShowsCategoryCounts = true
    @Published var novelOfflineCache = NovelOfflineCacheSettings()
    @Published var applePencilPageTurn = ApplePencilPageTurnSettings()
    @Published private(set) var novelCacheBytes = 0
    @Published private(set) var mangaIndexCacheBytes = 0
    @Published private(set) var offlineCacheBytes = 0
    @Published private(set) var offlineCacheManagementRows: [OfflineCacheManagementRow] = []
    @Published private(set) var selectedOfflineCacheGroupIDs: Set<OfflineCacheGroupID> = []
    @Published var isOfflineCacheManagementSelectionMode = false
    @Published private(set) var pendingOfflineCacheManagementConfirmation: OfflineCacheManagementConfirmation?
    @Published private(set) var activeAction: SystemSettingsAction?
    @Published var errorMessage: String?

    private let appContext: YamiboAppContext

    init(appContext: YamiboAppContext) {
        self.appContext = appContext
    }

    var isBusy: Bool {
        activeAction != nil
    }

    var novelCacheLabel: String {
        cacheLabel(for: novelCacheBytes)
    }

    var mangaIndexCacheLabel: String {
        cacheLabel(for: mangaIndexCacheBytes)
    }

    var offlineCacheLabel: String {
        cacheLabel(for: offlineCacheBytes)
    }

    var offlineCacheManagementIsEmpty: Bool {
        offlineCacheManagementRows.isEmpty
    }

    var selectedOfflineCacheGroupCount: Int {
        selectedOfflineCacheGroupIDs.count
    }

    var offlineCacheManagementSelectionActionState: OfflineCacheManagementSelectionActionState {
        OfflineCacheManagementSelectionActionState(
            selectedGroupCount: selectedOfflineCacheGroupIDs.count,
            canDelete: !selectedOfflineCacheGroupIDs.isEmpty
                && activeAction != .clearingOfflineCache
        )
    }

    func load() async {
        activeAction = .loading
        defer { activeAction = nil }

        let settings = await appContext.settingsStore.load()
        homePage = settings.system.homePage
        favoriteAppearance = settings.favorites.appearance
        favoriteBackground = settings.favorites.background
        favoriteLayoutMode = settings.favorites.layoutMode
        favoriteSortOrder = settings.favorites.sortOrder
        favoriteSortDescending = settings.favorites.sortDescending
        favoriteShowsCategoryCounts = settings.favorites.showsCategoryCounts
        novelOfflineCache = settings.novelOfflineCache
        applePencilPageTurn = settings.system.applePencilPageTurn
        await refreshStorageUsage()
    }

    func updateHomePage(_ value: AppHomePage) {
        let previous = homePage
        homePage = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.system.homePage = value

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    homePage = previous
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateFavoriteAppearanceColor(_ color: FavoriteAppearanceColor, for category: FavoriteAppearanceCategory) {
        let previous = favoriteAppearance
        var updated = favoriteAppearance
        updated.setColor(color, for: category)
        favoriteAppearance = updated

        Task {
            var settings = await appContext.settingsStore.load()
            settings.favorites.appearance = updated

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if favoriteAppearance == updated {
                        favoriteAppearance = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func loadFavoriteBackgroundImageData() async -> Data? {
        await appContext.favoriteBackgroundImageStore.loadData(imageID: favoriteBackground.imageID)
    }

    func normalizedFavoriteBackgroundImageData(from data: Data) throws -> Data {
        try FavoriteBackgroundImageProcessor.normalizedJPEGData(from: data)
    }

    func applyFavoriteBackground(
        imageData: Data,
        draftSettings: FavoriteBackgroundSettings
    ) async -> Bool {
        let imageID = UUID().uuidString
        var updatedBackground = FavoriteBackgroundSettings(
            isEnabled: true,
            imageID: imageID,
            scale: draftSettings.scale,
            offsetX: draftSettings.offsetX,
            offsetY: draftSettings.offsetY,
            blurRadius: draftSettings.blurRadius
        )
        updatedBackground.isEnabled = true

        do {
            try await appContext.favoriteBackgroundImageStore.save(imageData, imageID: imageID)

            var settings = await appContext.settingsStore.load()
            settings.favorites.background = updatedBackground
            try await appContext.settingsStore.save(settings)

            favoriteBackground = updatedBackground
            try? await appContext.favoriteBackgroundImageStore.prune(keeping: imageID)
            return true
        } catch {
            try? await appContext.favoriteBackgroundImageStore.delete(imageID: imageID)
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restoreDefaultFavoriteBackground() async -> Bool {
        do {
            var settings = await appContext.settingsStore.load()
            settings.favorites.background = FavoriteBackgroundSettings()
            try await appContext.settingsStore.save(settings)

            favoriteBackground = FavoriteBackgroundSettings()
            try? await appContext.favoriteBackgroundImageStore.deleteAll()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateFavoriteLayoutMode(_ value: FavoriteLibraryLayoutMode) {
        let previous = favoriteLayoutMode
        favoriteLayoutMode = value

        Task {
            var settings = await appContext.settingsStore.load()
            applyFavoriteLibraryDisplaySettings(to: &settings)

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if favoriteLayoutMode == value {
                        favoriteLayoutMode = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateFavoriteSortOrder(_ value: LocalFavoriteLibrarySortOrder) {
        let previous = favoriteSortOrder
        favoriteSortOrder = value

        Task {
            var settings = await appContext.settingsStore.load()
            applyFavoriteLibraryDisplaySettings(to: &settings)

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if favoriteSortOrder == value {
                        favoriteSortOrder = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateFavoriteSortDescending(_ value: Bool) {
        let previous = favoriteSortDescending
        favoriteSortDescending = value

        Task {
            var settings = await appContext.settingsStore.load()
            applyFavoriteLibraryDisplaySettings(to: &settings)

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if favoriteSortDescending == value {
                        favoriteSortDescending = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func updateFavoriteShowsCategoryCounts(_ value: Bool) {
        let previous = favoriteShowsCategoryCounts
        favoriteShowsCategoryCounts = value

        Task {
            var settings = await appContext.settingsStore.load()
            applyFavoriteLibraryDisplaySettings(to: &settings)

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if favoriteShowsCategoryCounts == value {
                        favoriteShowsCategoryCounts = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyFavoriteLibraryDisplaySettings(to settings: inout AppSettings) {
        settings.favorites.layoutMode = favoriteLayoutMode
        settings.favorites.sortOrder = favoriteSortOrder
        settings.favorites.sortDescending = favoriteSortDescending
        settings.favorites.showsCategoryCounts = favoriteShowsCategoryCounts
    }

    func updateApplePencilPageTurnEnabled(_ isEnabled: Bool) {
        var updated = applePencilPageTurn
        updated.isEnabled = isEnabled
        updateApplePencilPageTurn(updated)
    }

    func updateApplePencilPageTurnBehavior(_ behavior: ApplePencilPageTurnBehavior) {
        var updated = applePencilPageTurn
        updated.behavior = behavior
        updateApplePencilPageTurn(updated)
    }

    func updateNovelOfflineCacheRetainsInlineImages(_ retainsInlineImages: Bool) {
        var updated = novelOfflineCache
        updated.retainsInlineImages = retainsInlineImages
        updateNovelOfflineCache(updated)
    }

    func updateNovelOfflineCacheAutoRefreshEnabled(_ isAutoRefreshEnabled: Bool) {
        var updated = novelOfflineCache
        updated.isAutoRefreshEnabled = isAutoRefreshEnabled
        updateNovelOfflineCache(updated)
    }

    func clearNovelCache() async -> Bool {
        activeAction = .clearingNovelCache
        defer { activeAction = nil }

        do {
            try await appContext.novelReaderCacheStore.clearAll()
            await refreshStorageUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearMangaIndexCache() async -> Bool {
        activeAction = .clearingMangaIndexCache
        defer { activeAction = nil }

        do {
            try await appContext.mangaDirectoryStore.clearAll()
            try await appContext.mangaReaderProjectionStore.clearAll()
            await refreshStorageUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearImageCache() async -> Bool {
        activeAction = .clearingImageCache
        defer { activeAction = nil }

        await appContext.clearOrdinaryImageCache()
        await refreshStorageUsage()
        return true
    }

    func resetApplication() async -> Bool {
        activeAction = .resettingApplication
        defer { activeAction = nil }

        do {
            try await appContext.resetApplicationData()
            homePage = .forum
            favoriteAppearance = .init()
            favoriteBackground = .init()
            novelOfflineCache = .init()
            applePencilPageTurn = .init()
            novelCacheBytes = 0
            mangaIndexCacheBytes = 0
            offlineCacheBytes = 0
            offlineCacheManagementRows = []
            selectedOfflineCacheGroupIDs = []
            isOfflineCacheManagementSelectionMode = false
            pendingOfflineCacheManagementConfirmation = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshStorageUsage() async {
        novelCacheBytes = await appContext.novelReaderCacheStore.totalDiskUsageBytes()
        let directoryBytes = await appContext.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytes = await appContext.mangaReaderProjectionStore.totalDiskUsageBytes()
        mangaIndexCacheBytes = directoryBytes + projectionBytes
        offlineCacheBytes = await appContext.offlineCacheStore.totalDiskUsageBytes()
    }

    func refreshOfflineCacheManagement() async {
        activeAction = .loading
        defer { activeAction = nil }

        await refreshOfflineCacheManagementRows()
    }

    func requestOfflineCacheGroupDeletion(id: OfflineCacheGroupID) {
        prepareOfflineCacheManagementConfirmation(groupIDs: [id])
    }

    func requestOfflineCacheSwipeGroupDeletion(id: OfflineCacheGroupID) {
        requestOfflineCacheGroupDeletion(id: id)
    }

    func requestOfflineCacheEntryDeletion(id: OfflineCacheEntryID) {
        prepareOfflineCacheManagementConfirmation(entryIDs: [id])
    }

    func requestSelectedOfflineCacheGroupDeletion() {
        prepareOfflineCacheManagementConfirmation(groupIDs: Array(selectedOfflineCacheGroupIDs))
    }

    func cancelOfflineCacheManagementConfirmation() {
        pendingOfflineCacheManagementConfirmation = nil
    }

    func confirmPendingOfflineCacheManagementDeletion() async -> Bool {
        guard let confirmation = pendingOfflineCacheManagementConfirmation else { return false }
        return await confirmOfflineCacheManagementDeletion(confirmation)
    }

    func confirmOfflineCacheManagementDeletion(_ confirmation: OfflineCacheManagementConfirmation) async -> Bool {
        await clearOfflineCache(groupIDs: confirmation.groupIDs, entryIDs: confirmation.entryIDs)
    }

    func setOfflineCacheManagementSelectionMode(_ isSelecting: Bool) {
        isOfflineCacheManagementSelectionMode = isSelecting
        if !isSelecting {
            selectedOfflineCacheGroupIDs.removeAll()
        }
    }

    func toggleOfflineCacheManagementSelection(id: OfflineCacheGroupID) {
        let visibleIDs = Set(offlineCacheManagementRows.map(\.id))
        guard visibleIDs.contains(id) else { return }
        if selectedOfflineCacheGroupIDs.contains(id) {
            selectedOfflineCacheGroupIDs.remove(id)
        } else {
            selectedOfflineCacheGroupIDs.insert(id)
        }
    }

    var isOfflineCacheManagementSelectionComplete: Bool {
        let visibleGroupIDs = Set(offlineCacheManagementRows.map(\.id))
        return !visibleGroupIDs.isEmpty && visibleGroupIDs.isSubset(of: selectedOfflineCacheGroupIDs)
    }

    func toggleAllOfflineCacheManagementRows() {
        let visibleGroupIDs = Set(offlineCacheManagementRows.map(\.id))
        guard !visibleGroupIDs.isEmpty else { return }

        if visibleGroupIDs.isSubset(of: selectedOfflineCacheGroupIDs) {
            selectedOfflineCacheGroupIDs.subtract(visibleGroupIDs)
        } else {
            selectedOfflineCacheGroupIDs.formUnion(visibleGroupIDs)
        }
    }

    func offlineCacheManagementRow(id: OfflineCacheGroupID) -> OfflineCacheManagementRow? {
        offlineCacheManagementRows.first { $0.id == id }
    }

    private func clearOfflineCache(groupIDs: [OfflineCacheGroupID], entryIDs: [OfflineCacheEntryID]) async -> Bool {
        let normalizedGroupIDs = normalizedOfflineCacheGroupIDs(groupIDs)
        let normalizedEntryIDs = normalizedOfflineCacheEntryIDs(entryIDs)
        guard !normalizedGroupIDs.isEmpty || !normalizedEntryIDs.isEmpty else { return false }

        activeAction = .clearingOfflineCache
        defer { activeAction = nil }

        do {
            for groupID in normalizedGroupIDs {
                try await appContext.offlineCacheStore.removeOfflineCacheGroup(groupID)
            }
            for entryID in normalizedEntryIDs {
                try await appContext.offlineCacheStore.removeOfflineCacheEntry(entryID)
            }
            pendingOfflineCacheManagementConfirmation = nil
            selectedOfflineCacheGroupIDs.subtract(normalizedGroupIDs)
            if selectedOfflineCacheGroupIDs.isEmpty {
                isOfflineCacheManagementSelectionMode = false
            }
            await refreshStorageUsage()
            await refreshOfflineCacheManagementRows()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshOfflineCacheManagementRows() async {
        let snapshot = await appContext.offlineCacheStore.offlineCacheManagementSnapshot()
        offlineCacheManagementRows = snapshot.groups
            .map(OfflineCacheManagementRow.init(group:))
            .sorted { lhs, rhs in
                let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return lhs.id.ownerKey.localizedStandardCompare(rhs.id.ownerKey) == .orderedAscending
            }

        let visibleIDs = Set(offlineCacheManagementRows.map(\.id))
        selectedOfflineCacheGroupIDs.formIntersection(visibleIDs)
        if selectedOfflineCacheGroupIDs.isEmpty && offlineCacheManagementRows.isEmpty {
            isOfflineCacheManagementSelectionMode = false
        }
    }

    private func prepareOfflineCacheManagementConfirmation(
        groupIDs: [OfflineCacheGroupID] = [],
        entryIDs: [OfflineCacheEntryID] = []
    ) {
        let normalizedGroupIDs = normalizedOfflineCacheGroupIDs(groupIDs)
        let normalizedEntryIDs = normalizedOfflineCacheEntryIDs(entryIDs)
        guard !normalizedGroupIDs.isEmpty || !normalizedEntryIDs.isEmpty else { return }
        let rowsByID = Dictionary(uniqueKeysWithValues: offlineCacheManagementRows.map { ($0.id, $0) })
        let entriesByID = Dictionary(
            uniqueKeysWithValues: offlineCacheManagementRows.flatMap(\.entries).map { ($0.id, $0) }
        )
        pendingOfflineCacheManagementConfirmation = OfflineCacheManagementConfirmation(
            groupIDs: normalizedGroupIDs,
            entryIDs: normalizedEntryIDs,
            titles: normalizedGroupIDs.map { rowsByID[$0]?.title ?? $0.ownerKey }
                + normalizedEntryIDs.map { entriesByID[$0]?.title ?? $0.entryKey }
        )
    }

    private func normalizedOfflineCacheGroupIDs(_ groupIDs: [OfflineCacheGroupID]) -> [OfflineCacheGroupID] {
        let visibleIDs = Set(offlineCacheManagementRows.map(\.id))
        var seen: Set<OfflineCacheGroupID> = []
        return groupIDs
            .filter { visibleIDs.contains($0) && seen.insert($0).inserted }
            .sorted { lhs, rhs in
                lhs.ownerKey.localizedStandardCompare(rhs.ownerKey) == .orderedAscending
            }
    }

    private func normalizedOfflineCacheEntryIDs(_ entryIDs: [OfflineCacheEntryID]) -> [OfflineCacheEntryID] {
        let visibleIDs = Set(offlineCacheManagementRows.flatMap(\.entries).map(\.id))
        var seen: Set<OfflineCacheEntryID> = []
        return entryIDs
            .filter { visibleIDs.contains($0) && seen.insert($0).inserted }
            .sorted { lhs, rhs in
                if lhs.ownerKey != rhs.ownerKey {
                    return lhs.ownerKey.localizedStandardCompare(rhs.ownerKey) == .orderedAscending
                }
                return lhs.entryKey.localizedStandardCompare(rhs.entryKey) == .orderedAscending
            }
    }

    private func cacheLabel(for bytes: Int) -> String {
        let megabytes = Double(max(0, bytes)) / 1_048_576
        return String(format: "%.2f MB", megabytes)
    }

    private func updateApplePencilPageTurn(_ updated: ApplePencilPageTurnSettings) {
        let previous = applePencilPageTurn
        applePencilPageTurn = updated

        Task {
            var settings = await appContext.settingsStore.load()
            settings.system.applePencilPageTurn = updated

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if applePencilPageTurn == updated {
                        applePencilPageTurn = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func updateNovelOfflineCache(_ updated: NovelOfflineCacheSettings) {
        let previous = novelOfflineCache
        novelOfflineCache = updated

        Task {
            var settings = await appContext.settingsStore.load()
            settings.novelOfflineCache = updated

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    if novelOfflineCache == updated {
                        novelOfflineCache = previous
                    }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
