import Foundation

public protocol YamiboRepositoryProviding {
    func makeRepository() async -> YamiboRepository
}

public final class YamiboAppContext: YamiboRepositoryProviding, Sendable {
    public let sessionStore: SessionStore
    public let settingsStore: SettingsStore
    public let favoriteStore: FavoriteStore
    public let readerCacheStore: ReaderCacheStore
    private let session: URLSession

    public init(
        sessionStore: SessionStore = SessionStore(),
        settingsStore: SettingsStore = SettingsStore(),
        favoriteStore: FavoriteStore = FavoriteStore(),
        readerCacheStore: ReaderCacheStore = ReaderCacheStore(),
        session: URLSession = .shared
    ) {
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.favoriteStore = favoriteStore
        self.readerCacheStore = readerCacheStore
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

    public func bootstrap() async -> YamiboBootstrapState {
        YamiboBootstrapState(
            session: await sessionStore.load(),
            settings: await settingsStore.load(),
            favorites: await favoriteStore.loadFavorites()
        )
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
