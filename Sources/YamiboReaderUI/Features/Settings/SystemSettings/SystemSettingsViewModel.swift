import SwiftUI
import YamiboReaderCore

@MainActor
final class SystemSettingsViewModel: ObservableObject {
    @Published var homePage: AppHomePage = .forum
    @Published var showsNavigationBar = true
    @Published var favoriteAppearance = FavoriteAppearanceSettings()
    @Published var favoriteBackground = FavoriteBackgroundSettings()
    @Published var applePencilPageTurn = ApplePencilPageTurnSettings()
    @Published private(set) var novelCacheBytes = 0
    @Published private(set) var mangaIndexCacheBytes = 0
    @Published private(set) var mangaImageCacheBytes = 0
    @Published private(set) var mangaOfflineCacheBytes = 0
    @Published private(set) var mangaOfflineCacheCleanupRows: [MangaOfflineCacheCleanupRow] = []
    @Published private(set) var selectedMangaOfflineCacheFavoriteIDs: Set<String> = []
    @Published var isMangaOfflineCacheCleanupSelectionMode = false
    @Published private(set) var pendingMangaOfflineCacheCleanupConfirmation: MangaOfflineCacheCleanupConfirmation?
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

    var mangaImageCacheLabel: String {
        cacheLabel(for: mangaImageCacheBytes)
    }

    var mangaOfflineCacheLabel: String {
        cacheLabel(for: mangaOfflineCacheBytes)
    }

    var mangaOfflineCacheCleanupIsEmpty: Bool {
        mangaOfflineCacheCleanupRows.isEmpty
    }

    var selectedMangaOfflineCacheFavoriteCount: Int {
        selectedMangaOfflineCacheFavoriteIDs.count
    }

    func load() async {
        activeAction = .loading
        defer { activeAction = nil }

        let settings = await appContext.settingsStore.load()
        homePage = settings.homePage
        showsNavigationBar = settings.webBrowser.showsNavigationBar
        favoriteAppearance = settings.favoriteAppearance
        favoriteBackground = settings.favoriteBackground
        applePencilPageTurn = settings.applePencilPageTurn
        await refreshStorageUsage()
    }

    func updateHomePage(_ value: AppHomePage) {
        let previous = homePage
        homePage = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.homePage = value

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

    func updateShowsNavigationBar(_ value: Bool) {
        let previous = showsNavigationBar
        showsNavigationBar = value

        Task {
            var settings = await appContext.settingsStore.load()
            settings.webBrowser.showsNavigationBar = value

            do {
                try await appContext.settingsStore.save(settings)
            } catch {
                await MainActor.run {
                    showsNavigationBar = previous
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
            settings.favoriteAppearance = updated

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
            settings.favoriteBackground = updatedBackground
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
            settings.favoriteBackground = FavoriteBackgroundSettings()
            try await appContext.settingsStore.save(settings)

            favoriteBackground = FavoriteBackgroundSettings()
            try? await appContext.favoriteBackgroundImageStore.deleteAll()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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

    func clearNovelCache() async -> Bool {
        activeAction = .clearingNovelCache
        defer { activeAction = nil }

        do {
            try await appContext.readerCacheStore.clearAll()
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
            try await appContext.mangaChapterDocumentStore.clearAll()
            await refreshStorageUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearMangaImageCache() async -> Bool {
        activeAction = .clearingMangaImageCache
        defer { activeAction = nil }

        do {
            try await appContext.mangaImageDataCacheStore.clearAll()
            await refreshStorageUsage()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resetApplication() async -> Bool {
        activeAction = .resettingApplication
        defer { activeAction = nil }

        do {
            try await appContext.resetApplicationData()
            homePage = .forum
            showsNavigationBar = true
            favoriteAppearance = .init()
            favoriteBackground = .init()
            applePencilPageTurn = .init()
            novelCacheBytes = 0
            mangaIndexCacheBytes = 0
            mangaImageCacheBytes = 0
            mangaOfflineCacheBytes = 0
            mangaOfflineCacheCleanupRows = []
            selectedMangaOfflineCacheFavoriteIDs = []
            isMangaOfflineCacheCleanupSelectionMode = false
            pendingMangaOfflineCacheCleanupConfirmation = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshStorageUsage() async {
        novelCacheBytes = await appContext.readerCacheStore.totalDiskUsageBytes()
        let directoryBytes = await appContext.mangaDirectoryStore.totalDiskUsageBytes()
        let chapterDocumentBytes = await appContext.mangaChapterDocumentStore.totalDiskUsageBytes()
        mangaIndexCacheBytes = directoryBytes + chapterDocumentBytes
        mangaImageCacheBytes = await appContext.mangaImageDataCacheStore.totalDiskUsageBytes()
        mangaOfflineCacheBytes = await appContext.mangaOfflineCacheStore.totalDiskUsageBytes()
    }

    func refreshMangaOfflineCacheCleanup() async {
        activeAction = .loading
        defer { activeAction = nil }

        await refreshMangaOfflineCacheCleanupRows()
    }

    func requestMangaOfflineCacheCleanup(favoriteID: String) {
        prepareMangaOfflineCacheCleanupConfirmation(favoriteIDs: [favoriteID])
    }

    func requestMangaOfflineCacheSwipeCleanup(favoriteID: String) {
        requestMangaOfflineCacheCleanup(favoriteID: favoriteID)
    }

    func requestSelectedMangaOfflineCacheCleanup() {
        prepareMangaOfflineCacheCleanupConfirmation(favoriteIDs: Array(selectedMangaOfflineCacheFavoriteIDs))
    }

    func cancelMangaOfflineCacheCleanupConfirmation() {
        pendingMangaOfflineCacheCleanupConfirmation = nil
    }

    func confirmPendingMangaOfflineCacheCleanup() async -> Bool {
        guard let confirmation = pendingMangaOfflineCacheCleanupConfirmation else { return false }
        return await confirmMangaOfflineCacheCleanup(confirmation)
    }

    func confirmMangaOfflineCacheCleanup(_ confirmation: MangaOfflineCacheCleanupConfirmation) async -> Bool {
        await clearMangaOfflineCache(favoriteIDs: confirmation.favoriteIDs)
    }

    func setMangaOfflineCacheCleanupSelectionMode(_ isSelecting: Bool) {
        isMangaOfflineCacheCleanupSelectionMode = isSelecting
        if !isSelecting {
            selectedMangaOfflineCacheFavoriteIDs.removeAll()
        }
    }

    func toggleMangaOfflineCacheCleanupSelection(favoriteID: String) {
        let visibleIDs = Set(mangaOfflineCacheCleanupRows.map(\.favoriteID))
        guard visibleIDs.contains(favoriteID) else { return }
        if selectedMangaOfflineCacheFavoriteIDs.contains(favoriteID) {
            selectedMangaOfflineCacheFavoriteIDs.remove(favoriteID)
        } else {
            selectedMangaOfflineCacheFavoriteIDs.insert(favoriteID)
        }
    }

    func selectAllMangaOfflineCacheCleanupRows() {
        selectedMangaOfflineCacheFavoriteIDs = Set(mangaOfflineCacheCleanupRows.map(\.favoriteID))
    }

    private func clearMangaOfflineCache(favoriteIDs: [String]) async -> Bool {
        let normalizedFavoriteIDs = normalizedMangaOfflineCacheFavoriteIDs(favoriteIDs)
        guard !normalizedFavoriteIDs.isEmpty else { return false }

        activeAction = .clearingMangaOfflineCache
        defer { activeAction = nil }

        do {
            for favoriteID in normalizedFavoriteIDs {
                try await appContext.mangaOfflineCacheStore.removeMemberships(forFavoriteID: favoriteID)
            }
            pendingMangaOfflineCacheCleanupConfirmation = nil
            selectedMangaOfflineCacheFavoriteIDs.subtract(normalizedFavoriteIDs)
            if selectedMangaOfflineCacheFavoriteIDs.isEmpty {
                isMangaOfflineCacheCleanupSelectionMode = false
            }
            await refreshStorageUsage()
            await refreshMangaOfflineCacheCleanupRows()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshMangaOfflineCacheCleanupRows() async {
        let store = appContext.mangaOfflineCacheStore
        let memberships = await store.allMemberships()
        let works = await store.allOfflineCacheWorks()
        let usageByFavoriteID = Dictionary(
            uniqueKeysWithValues: await store.diskUsageByFavorite().map { ($0.favoriteID, $0.byteCount) }
        )
        let favoritesByID = Dictionary(
            uniqueKeysWithValues: await appContext.favoriteStore.loadFavorites().map { ($0.id, $0) }
        )
        let membershipTitles = Dictionary(grouping: memberships, by: \.favoriteID).mapValues { memberships in
            memberships.first?.favoriteTitle ?? ""
        }
        let workTitles = Dictionary(grouping: works, by: \.favoriteID).mapValues { works in
            works.first?.favoriteTitle ?? ""
        }
        let favoriteIDs = Set(memberships.map(\.favoriteID)).union(works.map(\.favoriteID))

        mangaOfflineCacheCleanupRows = favoriteIDs
            .map { favoriteID in
                MangaOfflineCacheCleanupRow(
                    favoriteID: favoriteID,
                    title: cleanupTitle(
                        favoriteID: favoriteID,
                        favoritesByID: favoritesByID,
                        membershipTitles: membershipTitles,
                        workTitles: workTitles
                    ),
                    byteCount: usageByFavoriteID[favoriteID] ?? 0
                )
            }
            .sorted { lhs, rhs in
                let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return lhs.favoriteID.localizedStandardCompare(rhs.favoriteID) == .orderedAscending
            }

        let visibleIDs = Set(mangaOfflineCacheCleanupRows.map(\.favoriteID))
        selectedMangaOfflineCacheFavoriteIDs.formIntersection(visibleIDs)
        if selectedMangaOfflineCacheFavoriteIDs.isEmpty && mangaOfflineCacheCleanupRows.isEmpty {
            isMangaOfflineCacheCleanupSelectionMode = false
        }
    }

    private func prepareMangaOfflineCacheCleanupConfirmation(favoriteIDs: [String]) {
        let normalizedFavoriteIDs = normalizedMangaOfflineCacheFavoriteIDs(favoriteIDs)
        guard !normalizedFavoriteIDs.isEmpty else { return }
        let rowsByFavoriteID = Dictionary(uniqueKeysWithValues: mangaOfflineCacheCleanupRows.map { ($0.favoriteID, $0) })
        pendingMangaOfflineCacheCleanupConfirmation = MangaOfflineCacheCleanupConfirmation(
            favoriteIDs: normalizedFavoriteIDs,
            favoriteTitles: normalizedFavoriteIDs.map { rowsByFavoriteID[$0]?.title ?? $0 }
        )
    }

    private func normalizedMangaOfflineCacheFavoriteIDs(_ favoriteIDs: [String]) -> [String] {
        let visibleIDs = Set(mangaOfflineCacheCleanupRows.map(\.favoriteID))
        var seen: Set<String> = []
        return favoriteIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && visibleIDs.contains($0) && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func cleanupTitle(
        favoriteID: String,
        favoritesByID: [String: Favorite],
        membershipTitles: [String: String],
        workTitles: [String: String]
    ) -> String {
        if let title = trimmedNonEmpty(favoritesByID[favoriteID]?.resolvedDisplayTitle) {
            return title
        }
        if let title = trimmedNonEmpty(membershipTitles[favoriteID]) {
            return title
        }
        if let title = trimmedNonEmpty(workTitles[favoriteID]) {
            return title
        }
        return favoriteID
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
            settings.applePencilPageTurn = updated

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
}
