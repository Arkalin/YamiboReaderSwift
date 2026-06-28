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
    @Published private(set) var selectedMangaOfflineCacheOwnerNames: Set<String> = []
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

    var selectedMangaOfflineCacheOwnerCount: Int {
        selectedMangaOfflineCacheOwnerNames.count
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
            selectedMangaOfflineCacheOwnerNames = []
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

    func requestMangaOfflineCacheCleanup(ownerName: String) {
        prepareMangaOfflineCacheCleanupConfirmation(ownerNames: [ownerName])
    }

    func requestMangaOfflineCacheSwipeCleanup(ownerName: String) {
        requestMangaOfflineCacheCleanup(ownerName: ownerName)
    }

    func requestSelectedMangaOfflineCacheCleanup() {
        prepareMangaOfflineCacheCleanupConfirmation(ownerNames: Array(selectedMangaOfflineCacheOwnerNames))
    }

    func cancelMangaOfflineCacheCleanupConfirmation() {
        pendingMangaOfflineCacheCleanupConfirmation = nil
    }

    func confirmPendingMangaOfflineCacheCleanup() async -> Bool {
        guard let confirmation = pendingMangaOfflineCacheCleanupConfirmation else { return false }
        return await confirmMangaOfflineCacheCleanup(confirmation)
    }

    func confirmMangaOfflineCacheCleanup(_ confirmation: MangaOfflineCacheCleanupConfirmation) async -> Bool {
        await clearMangaOfflineCache(ownerNames: confirmation.ownerNames)
    }

    func setMangaOfflineCacheCleanupSelectionMode(_ isSelecting: Bool) {
        isMangaOfflineCacheCleanupSelectionMode = isSelecting
        if !isSelecting {
            selectedMangaOfflineCacheOwnerNames.removeAll()
        }
    }

    func toggleMangaOfflineCacheCleanupSelection(ownerName: String) {
        let visibleIDs = Set(mangaOfflineCacheCleanupRows.map(\.ownerName))
        guard visibleIDs.contains(ownerName) else { return }
        if selectedMangaOfflineCacheOwnerNames.contains(ownerName) {
            selectedMangaOfflineCacheOwnerNames.remove(ownerName)
        } else {
            selectedMangaOfflineCacheOwnerNames.insert(ownerName)
        }
    }

    var isMangaOfflineCacheCleanupSelectionComplete: Bool {
        let visibleOwnerNames = Set(mangaOfflineCacheCleanupRows.map(\.ownerName))
        return !visibleOwnerNames.isEmpty && visibleOwnerNames.isSubset(of: selectedMangaOfflineCacheOwnerNames)
    }

    func toggleAllMangaOfflineCacheCleanupRows() {
        let visibleOwnerNames = Set(mangaOfflineCacheCleanupRows.map(\.ownerName))
        guard !visibleOwnerNames.isEmpty else { return }

        if visibleOwnerNames.isSubset(of: selectedMangaOfflineCacheOwnerNames) {
            selectedMangaOfflineCacheOwnerNames.subtract(visibleOwnerNames)
        } else {
            selectedMangaOfflineCacheOwnerNames.formUnion(visibleOwnerNames)
        }
    }

    private func clearMangaOfflineCache(ownerNames: [String]) async -> Bool {
        let normalizedOwnerNames = normalizedMangaOfflineCacheOwnerNames(ownerNames)
        guard !normalizedOwnerNames.isEmpty else { return false }

        activeAction = .clearingMangaOfflineCache
        defer { activeAction = nil }

        do {
            for ownerName in normalizedOwnerNames {
                try await appContext.mangaOfflineCacheStore.removeMemberships(forOwnerName: ownerName)
            }
            pendingMangaOfflineCacheCleanupConfirmation = nil
            selectedMangaOfflineCacheOwnerNames.subtract(normalizedOwnerNames)
            if selectedMangaOfflineCacheOwnerNames.isEmpty {
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
        let usageByOwnerName = Dictionary(
            uniqueKeysWithValues: await store.diskUsageByOwner().map { ($0.ownerName, $0.byteCount) }
        )
        let ownerNames = Set(memberships.map(\.ownerName)).union(works.map(\.ownerName))

        mangaOfflineCacheCleanupRows = ownerNames
            .map { ownerName in
                MangaOfflineCacheCleanupRow(
                    ownerName: ownerName,
                    title: ownerName,
                    byteCount: usageByOwnerName[ownerName] ?? 0
                )
            }
            .sorted { lhs, rhs in
                let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return lhs.ownerName.localizedStandardCompare(rhs.ownerName) == .orderedAscending
            }

        let visibleIDs = Set(mangaOfflineCacheCleanupRows.map(\.ownerName))
        selectedMangaOfflineCacheOwnerNames.formIntersection(visibleIDs)
        if selectedMangaOfflineCacheOwnerNames.isEmpty && mangaOfflineCacheCleanupRows.isEmpty {
            isMangaOfflineCacheCleanupSelectionMode = false
        }
    }

    private func prepareMangaOfflineCacheCleanupConfirmation(ownerNames: [String]) {
        let normalizedOwnerNames = normalizedMangaOfflineCacheOwnerNames(ownerNames)
        guard !normalizedOwnerNames.isEmpty else { return }
        let rowsByOwnerName = Dictionary(uniqueKeysWithValues: mangaOfflineCacheCleanupRows.map { ($0.ownerName, $0) })
        pendingMangaOfflineCacheCleanupConfirmation = MangaOfflineCacheCleanupConfirmation(
            ownerNames: normalizedOwnerNames,
            ownerTitles: normalizedOwnerNames.map { rowsByOwnerName[$0]?.title ?? $0 }
        )
    }

    private func normalizedMangaOfflineCacheOwnerNames(_ ownerNames: [String]) -> [String] {
        let visibleIDs = Set(mangaOfflineCacheCleanupRows.map(\.ownerName))
        var seen: Set<String> = []
        return ownerNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && visibleIDs.contains($0) && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
