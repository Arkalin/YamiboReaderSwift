import Foundation

/// Dependency package the favorites feature's composition roots use to build
/// their modules. Each module (`FavoriteLibraryOrganizer`,
/// `FavoriteRemoteSyncSession`, `FavoriteUpdateMonitor`,
/// `LocalFavoriteOpenTargetResolver`) declares a narrow initializer taking
/// only the stores it uses; this struct just carries them from the app
/// composition root to those call sites.
public struct LibraryDependencies: Sendable {
    public let localFavoriteLibraryStore: FavoriteLibraryStore
    public let favoriteUpdateStore: FavoriteUpdateStore
    public let readingProgressStore: ReadingProgressStore
    public let settingsStore: SettingsStore
    public let contentCoverStore: ContentCoverStore
    public let mangaDirectoryStore: MangaDirectoryStore
    public let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    public let makeForumThreadReaderRepository: @Sendable () async -> ForumThreadReaderRepository
    public let makeThreadRouteResolver: @Sendable () async -> YamiboThreadRouteResolver

    public init(
        localFavoriteLibraryStore: FavoriteLibraryStore,
        favoriteUpdateStore: FavoriteUpdateStore,
        readingProgressStore: ReadingProgressStore,
        settingsStore: SettingsStore,
        contentCoverStore: ContentCoverStore,
        mangaDirectoryStore: MangaDirectoryStore,
        makeFavoriteRepository: @escaping @Sendable () async -> FavoriteRepository,
        makeForumThreadReaderRepository: @escaping @Sendable () async -> ForumThreadReaderRepository,
        makeThreadRouteResolver: @escaping @Sendable () async -> YamiboThreadRouteResolver
    ) {
        self.localFavoriteLibraryStore = localFavoriteLibraryStore
        self.favoriteUpdateStore = favoriteUpdateStore
        self.readingProgressStore = readingProgressStore
        self.settingsStore = settingsStore
        self.contentCoverStore = contentCoverStore
        self.mangaDirectoryStore = mangaDirectoryStore
        self.makeFavoriteRepository = makeFavoriteRepository
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.makeThreadRouteResolver = makeThreadRouteResolver
    }
}
