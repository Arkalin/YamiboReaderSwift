import Foundation
#if canImport(WebKit)
import WebKit
#endif

public protocol YamiboRepositoryProviding {
    func makeRepository() async -> YamiboRepository
}

public final class YamiboAppContext: YamiboRepositoryProviding, Sendable {
    private static let resettableUserDefaultsKeys = [
        "yamibo.favorite.filter",
        "yamibo.favorite.sort",
        "yamibo.favorite.showHidden"
    ]

    public let sessionStore: SessionStore
    public let autoSignInStore: AutoSignInStore
    public let settingsStore: SettingsStore
    public let webDAVSyncSettingsStore: WebDAVSyncSettingsStore
    public let favoriteStore: FavoriteStore
    public let readerCacheStore: ReaderCacheStore
    public let mangaImageCacheStore: MangaImageCacheStore
    public let mangaImageRepository: MangaImageRepository
    public let mangaDirectoryStore: MangaDirectoryStore
    private let session: URLSession

    public init(
        sessionStore: SessionStore = SessionStore(),
        autoSignInStore: AutoSignInStore = AutoSignInStore(),
        settingsStore: SettingsStore = SettingsStore(),
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore = WebDAVSyncSettingsStore(),
        favoriteStore: FavoriteStore = FavoriteStore(),
        readerCacheStore: ReaderCacheStore = ReaderCacheStore(),
        mangaImageCacheStore: MangaImageCacheStore = MangaImageCacheStore(),
        mangaDirectoryStore: MangaDirectoryStore = MangaDirectoryStore(),
        session: URLSession = .shared
    ) {
        self.sessionStore = sessionStore
        self.autoSignInStore = autoSignInStore
        self.settingsStore = settingsStore
        self.webDAVSyncSettingsStore = webDAVSyncSettingsStore
        self.favoriteStore = favoriteStore
        self.readerCacheStore = readerCacheStore
        self.mangaImageCacheStore = mangaImageCacheStore
        self.mangaDirectoryStore = mangaDirectoryStore
        self.session = session
        self.mangaImageRepository = MangaImageRepository(
            session: session,
            sessionStore: sessionStore,
            cacheStore: mangaImageCacheStore
        )
    }

    public func makeRepository() async -> YamiboRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return YamiboRepository(client: client)
    }

    public func makeReaderRepository() async -> ReaderRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ReaderRepository(client: client, cacheStore: readerCacheStore)
    }

    public func makeMangaRepository() async -> MangaRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return MangaRepository(client: client)
    }

    public func makeMangaImageRepository() async -> MangaImageRepository {
        mangaImageRepository
    }

    public func makeThreadOpenResolver() async -> ThreadOpenResolver {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ThreadOpenResolver(client: client)
    }

    public func makeAutoSignInService() -> AutoSignInService {
        AutoSignInService(
            sessionStore: sessionStore,
            autoSignInStore: autoSignInStore,
            session: session
        )
    }

    public func makeWebDAVSyncService() -> WebDAVSyncService {
        WebDAVSyncService(
            settingsStore: webDAVSyncSettingsStore,
            favoriteStore: favoriteStore,
            sessionStore: sessionStore,
            autoSignInStore: autoSignInStore,
            client: WebDAVClient(session: session)
        )
    }

    public func bootstrap() async -> YamiboBootstrapState {
        YamiboBootstrapState(
            session: await sessionStore.load(),
            settings: await settingsStore.load(),
            favorites: await favoriteStore.loadFavorites()
        )
    }

    public func resetApplicationData() async throws {
        try await sessionStore.reset()
        try await settingsStore.reset()
        try await webDAVSyncSettingsStore.reset()
        try await favoriteStore.clearAll()
        try await readerCacheStore.clearAll()
        try await mangaImageCacheStore.clearAll()
        try await mangaDirectoryStore.clearAll()
        clearLocalUIState()
        await clearWebData()
    }

    private func clearLocalUIState() {
        let defaults = UserDefaults.standard
        Self.resettableUserDefaultsKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    @MainActor
    private func clearWebData() async {
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
        URLCache.shared.removeAllCachedResponses()

        #if canImport(WebKit)
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) { continuation.resume(returning: $0) }
        }
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, for: records) {
                continuation.resume()
            }
        }
        #endif
    }
}

public struct YamiboBootstrapState: Sendable {
    public let session: SessionState
    public let settings: AppSettings
    public let favorites: [Favorite]

    public init(session: SessionState, settings: AppSettings, favorites: [Favorite]) {
        self.session = session
        self.settings = settings
        self.favorites = favorites
    }
}
