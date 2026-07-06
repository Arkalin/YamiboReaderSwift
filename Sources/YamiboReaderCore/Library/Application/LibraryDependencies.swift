import Foundation

/// Everything the favorite library feature UI needs from the composition
/// root. Intentionally wide today because `LocalFavoritesViewModel` still
/// owns organization, remote sync, update detection, and open-target
/// resolution in one type; it narrows when that view model is split.
public struct LibraryDependencies: Sendable {
    public let sessionStore: SessionStore
    public let localFavoriteLibraryStore: FavoriteLibraryStore
    public let favoriteUpdateStore: FavoriteUpdateStore
    public let readingProgressStore: ReadingProgressStore
    public let settingsStore: SettingsStore
    public let contentCoverStore: ContentCoverStore
    public let makeFavoriteRepository: @Sendable () async -> FavoriteRepository
    public let makeForumThreadReaderRepository: @Sendable () async -> ForumThreadReaderRepository
    public let makeThreadRouteResolver: @Sendable () async -> YamiboThreadRouteResolver

    public init(
        sessionStore: SessionStore,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        favoriteUpdateStore: FavoriteUpdateStore,
        readingProgressStore: ReadingProgressStore,
        settingsStore: SettingsStore,
        contentCoverStore: ContentCoverStore,
        makeFavoriteRepository: @escaping @Sendable () async -> FavoriteRepository,
        makeForumThreadReaderRepository: @escaping @Sendable () async -> ForumThreadReaderRepository,
        makeThreadRouteResolver: @escaping @Sendable () async -> YamiboThreadRouteResolver
    ) {
        self.sessionStore = sessionStore
        self.localFavoriteLibraryStore = localFavoriteLibraryStore
        self.favoriteUpdateStore = favoriteUpdateStore
        self.readingProgressStore = readingProgressStore
        self.settingsStore = settingsStore
        self.contentCoverStore = contentCoverStore
        self.makeFavoriteRepository = makeFavoriteRepository
        self.makeForumThreadReaderRepository = makeForumThreadReaderRepository
        self.makeThreadRouteResolver = makeThreadRouteResolver
    }
}
