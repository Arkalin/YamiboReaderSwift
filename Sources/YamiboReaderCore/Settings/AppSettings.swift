import Foundation

/// Thin aggregate over feature-owned settings. Each nested struct is defined
/// by the feature that owns it and uses compiler-synthesized Codable.
/// `SettingsStore` falls back to defaults when stored data fails to decode.
public struct AppSettings: Codable, Hashable, Sendable {
    public var novelReader: NovelReaderAppearanceSettings
    public var novelOfflineCache: NovelOfflineCacheSettings
    public var manga: MangaReaderSettings
    public var favorites: FavoriteLibrarySettings
    public var webBrowser: WebBrowserSettings
    public var system: SystemSettings

    public init(
        novelReader: NovelReaderAppearanceSettings = .init(),
        novelOfflineCache: NovelOfflineCacheSettings = .init(),
        manga: MangaReaderSettings = .init(),
        favorites: FavoriteLibrarySettings = .init(),
        webBrowser: WebBrowserSettings = .init(),
        system: SystemSettings = .init()
    ) {
        self.novelReader = novelReader
        self.novelOfflineCache = novelOfflineCache
        self.manga = manga
        self.favorites = favorites
        self.webBrowser = webBrowser
        self.system = system
    }
}
