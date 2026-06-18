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
        "yamibo.favorite.tag.sort",
        "yamibo.favorite.showHidden"
    ]

    public let sessionStore: SessionStore
    public let profileStore: YamiboProfileStore
    public let autoSignInStore: AutoSignInStore
    public let settingsStore: SettingsStore
    public let webDAVSyncSettingsStore: WebDAVSyncSettingsStore
    public let readerResumeRouteStore: ReaderResumeRouteStore
    public let favoriteStore: FavoriteStore
    public let readerCacheStore: ReaderCacheStore
    public let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
    public let mangaDirectoryStore: FileMangaDirectoryStore
    public let mangaImageDataCacheStore: FileMangaImageDataCacheStore
    private let session: URLSession

    public init(
        sessionStore: SessionStore = SessionStore(),
        profileStore: YamiboProfileStore = YamiboProfileStore(),
        autoSignInStore: AutoSignInStore = AutoSignInStore(),
        settingsStore: SettingsStore = SettingsStore(),
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore = WebDAVSyncSettingsStore(),
        readerResumeRouteStore: ReaderResumeRouteStore = ReaderResumeRouteStore(),
        favoriteStore: FavoriteStore = FavoriteStore(),
        readerCacheStore: ReaderCacheStore = ReaderCacheStore(),
        favoriteBackgroundImageStore: FavoriteBackgroundImageStore = FavoriteBackgroundImageStore(),
        mangaDirectoryStore: FileMangaDirectoryStore = FileMangaDirectoryStore(),
        mangaImageDataCacheStore: FileMangaImageDataCacheStore = FileMangaImageDataCacheStore(),
        session: URLSession = .shared
    ) {
        self.sessionStore = sessionStore
        self.profileStore = profileStore
        self.autoSignInStore = autoSignInStore
        self.settingsStore = settingsStore
        self.webDAVSyncSettingsStore = webDAVSyncSettingsStore
        self.readerResumeRouteStore = readerResumeRouteStore
        self.favoriteStore = favoriteStore
        self.readerCacheStore = readerCacheStore
        self.favoriteBackgroundImageStore = favoriteBackgroundImageStore
        self.mangaDirectoryStore = mangaDirectoryStore
        self.mangaImageDataCacheStore = mangaImageDataCacheStore
        self.session = session
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

    public func makeThreadOpenResolver() async -> ThreadOpenResolver {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ThreadOpenResolver(client: client)
    }

    public func makeMangaChapterDocumentLoader() async -> any MangaChapterDocumentLoading {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return YamiboMangaChapterDocumentLoader(client: client)
    }

    public func makeMangaDirectoryRepository() async -> any MangaDirectoryRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return YamiboMangaDirectoryRepository(client: client)
    }

    public func makeMangaDirectoryStore() -> any MangaDirectoryPersisting {
        mangaDirectoryStore
    }

    public func makeMangaImageDataLoader() async -> any MangaImageDataLoading {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return CachedMangaImageDataLoader(
            cache: mangaImageDataCacheStore,
            upstream: YamiboMangaImageDataLoader(client: client)
        )
    }

    public func makeAutoSignInService() -> AutoSignInService {
        AutoSignInService(
            sessionStore: sessionStore,
            autoSignInStore: autoSignInStore,
            session: session
        )
    }

    public func makeAccountService() -> YamiboAccountService {
        YamiboAccountService(
            session: session,
            sessionStore: sessionStore,
            profileStore: profileStore
        )
    }

    public func makeWebDAVSyncService() -> WebDAVSyncService {
        WebDAVSyncService(
            settingsStore: webDAVSyncSettingsStore,
            favoriteStore: favoriteStore,
            sessionStore: sessionStore,
            appSettingsStore: settingsStore,
            client: WebDAVClient(session: session)
        )
    }

    public func bootstrap() async -> YamiboBootstrapState {
        YamiboBootstrapState(
            session: await sessionStore.load(),
            profile: await profileStore.load(),
            settings: await settingsStore.load(),
            favorites: await favoriteStore.loadFavorites()
        )
    }

    public func resetApplicationData() async throws {
        try await sessionStore.reset()
        await profileStore.clear()
        try await settingsStore.reset()
        try await webDAVSyncSettingsStore.reset()
        await readerResumeRouteStore.clear()
        try await favoriteStore.clearAll()
        try await readerCacheStore.clearAll()
        try await mangaDirectoryStore.clearAll()
        try await mangaImageDataCacheStore.clearAll()
        try await favoriteBackgroundImageStore.deleteAll()
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
    public let profile: YamiboProfile?
    public let settings: AppSettings
    public let favorites: [Favorite]

    public init(session: SessionState, profile: YamiboProfile?, settings: AppSettings, favorites: [Favorite]) {
        self.session = session
        self.profile = profile
        self.settings = settings
        self.favorites = favorites
    }
}
