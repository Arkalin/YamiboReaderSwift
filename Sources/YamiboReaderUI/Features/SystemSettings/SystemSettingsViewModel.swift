import SwiftUI
import YamiboReaderCore

@MainActor
final class SystemSettingsViewModel: ObservableObject {
    @Published var homePage: AppHomePage = .forum
    @Published var showsNavigationBar = true
    @Published var favoriteAppearance = FavoriteAppearanceSettings()
    @Published var applePencilPageTurn = ApplePencilPageTurnSettings()
    @Published private(set) var novelCacheBytes = 0
    @Published private(set) var mangaCacheBytes = 0
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

    var mangaCacheLabel: String {
        cacheLabel(for: mangaCacheBytes)
    }

    func load() async {
        activeAction = .loading
        defer { activeAction = nil }

        let settings = await appContext.settingsStore.load()
        homePage = settings.homePage
        showsNavigationBar = settings.webBrowser.showsNavigationBar
        favoriteAppearance = settings.favoriteAppearance
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

    func clearMangaCache() async -> Bool {
        activeAction = .clearingMangaCache
        defer { activeAction = nil }

        do {
            try await appContext.mangaImageCacheStore.clearAll()
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
            applePencilPageTurn = .init()
            novelCacheBytes = 0
            mangaCacheBytes = 0
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshStorageUsage() async {
        async let novelBytes = appContext.readerCacheStore.totalDiskUsageBytes()
        async let mangaBytes = appContext.mangaImageCacheStore.totalDiskUsageBytes()
        novelCacheBytes = await novelBytes
        mangaCacheBytes = await mangaBytes
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
