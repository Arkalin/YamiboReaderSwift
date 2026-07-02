@preconcurrency import Foundation
@preconcurrency import GRDB
#if canImport(WebKit)
import WebKit
#endif

public protocol FavoriteRepositoryProviding {
    func makeFavoriteRepository() async -> FavoriteRepository
}

public final class YamiboAppContext: FavoriteRepositoryProviding, Sendable {
    private static let resettableUserDefaultsKeys = [
        "yamibo.favorite.filter",
        "yamibo.favorite.sort",
        "yamibo.favorite.tag.sort",
        "yamibo.favorite.showHidden"
    ]

    public let sessionStore: SessionStore
    public let profileStore: YamiboProfileStore
    public let checkInStore: YamiboCheckInStore
    public let settingsStore: SettingsStore
    public let webDAVSyncSettingsStore: WebDAVSyncSettingsStore
    public let readerResumeRouteStore: ReaderResumeRouteStore
    public let localFavoriteLibraryStore: FavoriteLibraryStore
    public let favoriteUpdateStore: FavoriteUpdateStore
    public let readingProgressStore: ReadingProgressStore
    public let contentCoverStore: ContentCoverStore
    public let readerCacheStore: ReaderCacheStore
    public let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
    public let mangaDirectoryStore: any MangaDirectoryPersisting & MangaDirectoryStorageReporting & MangaDirectoryClearing
    public let mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState
    public let mangaChapterDocumentStore: any MangaChapterDocumentPersisting & MangaChapterDocumentStorageReporting
    public let imageDataCacheStore: FileImageDataCacheStore
    public let mangaOfflineCacheStore: any MangaOfflineCacheStoring
    public let forumCacheStore: ForumCacheStore
    public let mangaOfflineCacheBackgroundDownloadTransport: MangaOfflineCacheBackgroundDownloadTransport
    public let mangaOfflineCacheContinuedProcessingCoordinator: MangaOfflineCacheContinuedProcessingCoordinator
    let session: URLSession
    private let mangaOfflineCacheQueueExecutorBox = MangaOfflineCacheQueueExecutorBox()
    private nonisolated(unsafe) let uiDefaults: UserDefaults
    private let clearsWebDataOnReset: Bool

    public init(
        sessionStore: SessionStore = SessionStore(),
        profileStore: YamiboProfileStore = YamiboProfileStore(),
        checkInStore: YamiboCheckInStore = YamiboCheckInStore(),
        settingsStore: SettingsStore = SettingsStore(),
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore = WebDAVSyncSettingsStore(),
        readerResumeRouteStore: ReaderResumeRouteStore = ReaderResumeRouteStore(),
        localFavoriteLibraryStore: FavoriteLibraryStore? = nil,
        favoriteUpdateStore: FavoriteUpdateStore = FavoriteUpdateStore(),
        readingProgressStore: ReadingProgressStore? = nil,
        contentCoverStore: ContentCoverStore = ContentCoverStore(),
        readerCacheStore: ReaderCacheStore? = nil,
        favoriteBackgroundImageStore: FavoriteBackgroundImageStore? = nil,
        mangaDirectoryStore: (any MangaDirectoryPersisting & MangaDirectoryStorageReporting & MangaDirectoryClearing)? = nil,
        mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState = MangaDirectorySearchCooldownState(),
        mangaChapterDocumentStore: (any MangaChapterDocumentPersisting & MangaChapterDocumentStorageReporting)? = nil,
        imageDataCacheStore: FileImageDataCacheStore? = nil,
        mangaOfflineCacheStore: (any MangaOfflineCacheStoring)? = nil,
        forumCacheStore: ForumCacheStore? = nil,
        mangaOfflineCacheBackgroundDownloadTransport: MangaOfflineCacheBackgroundDownloadTransport = MangaOfflineCacheBackgroundDownloadTransport(),
        mangaOfflineCacheContinuedProcessingCoordinator: MangaOfflineCacheContinuedProcessingCoordinator = MangaOfflineCacheContinuedProcessingCoordinator(),
        grdbRootDirectory: URL? = nil,
        uiDefaults: UserDefaults = .standard,
        clearsWebDataOnReset: Bool = true,
        session: URLSession = YamiboNetworkConfiguration.makeSession()
    ) {
        let resolvedGRDBRootDirectory = grdbRootDirectory ?? YamiboDatabase.defaultRootDirectory()
        let resolvedGRDBDatabasePool = Self.openGRDBDatabase(rootDirectory: resolvedGRDBRootDirectory)
        let transparentJSONCacheStore = JSONCacheStore(
            writer: resolvedGRDBDatabasePool,
            rootDirectory: resolvedGRDBRootDirectory
        )
        self.uiDefaults = uiDefaults
        self.clearsWebDataOnReset = clearsWebDataOnReset
        self.sessionStore = sessionStore
        self.profileStore = profileStore
        self.checkInStore = checkInStore
        self.settingsStore = settingsStore
        self.webDAVSyncSettingsStore = webDAVSyncSettingsStore
        self.readerResumeRouteStore = readerResumeRouteStore
        let resolvedMangaOfflineCacheStore = mangaOfflineCacheStore ?? MangaOfflineCacheStore(
            databasePool: resolvedGRDBDatabasePool,
            baseDirectory: Self.mangaOfflineCacheDirectory(rootDirectory: resolvedGRDBRootDirectory)
        )
        self.localFavoriteLibraryStore = localFavoriteLibraryStore ?? FavoriteLibraryStore(databasePool: resolvedGRDBDatabasePool)
        self.favoriteUpdateStore = favoriteUpdateStore
        self.readingProgressStore = readingProgressStore ?? ReadingProgressStore(databasePool: resolvedGRDBDatabasePool)
        self.contentCoverStore = contentCoverStore
        self.readerCacheStore = readerCacheStore ?? ReaderCacheStore(
            databasePool: resolvedGRDBDatabasePool,
            baseDirectory: Self.readerCacheDirectory(rootDirectory: resolvedGRDBRootDirectory)
        )
        self.favoriteBackgroundImageStore = favoriteBackgroundImageStore ?? FavoriteBackgroundImageStore(
            baseDirectory: Self.favoriteBackgroundDirectory(rootDirectory: resolvedGRDBRootDirectory)
        )
        self.mangaDirectoryStore = mangaDirectoryStore ?? MangaDirectoryStore(databasePool: resolvedGRDBDatabasePool)
        self.mangaDirectorySearchCooldownState = mangaDirectorySearchCooldownState
        self.mangaChapterDocumentStore = mangaChapterDocumentStore ?? MangaChapterDocumentStore(databasePool: resolvedGRDBDatabasePool)
        self.imageDataCacheStore = imageDataCacheStore ?? FileImageDataCacheStore(
            databasePool: resolvedGRDBDatabasePool,
            baseDirectory: Self.imageDataDirectory(rootDirectory: resolvedGRDBRootDirectory)
        )
        self.mangaOfflineCacheStore = resolvedMangaOfflineCacheStore
        self.forumCacheStore = forumCacheStore ?? ForumCacheStore(
            jsonCacheStore: transparentJSONCacheStore
        )
        self.mangaOfflineCacheBackgroundDownloadTransport = mangaOfflineCacheBackgroundDownloadTransport
        self.mangaOfflineCacheContinuedProcessingCoordinator = mangaOfflineCacheContinuedProcessingCoordinator
        self.session = session
    }

    public func makeFavoriteRepository() async -> FavoriteRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return FavoriteRepository(client: client)
    }

    public func makeNovelReaderRepository() async -> NovelReaderRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return NovelReaderRepository(
            client: client,
            cacheStore: readerCacheStore,
            forumCacheStore: forumCacheStore
        )
    }

    public func makeReaderChapterCommentsRepository() async -> ReaderChapterCommentsRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ReaderChapterCommentsRepository(client: client)
    }

    public func makeNovelInlineImageLoadingContext() async -> NovelInlineImageLoadingContext {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        let cacheNamespace = YamiboImageCacheNamespace.ordinarySessionNamespace(
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return NovelInlineImageLoadingContext(
            loader: YamiboNovelInlineImageDataLoader(
                imageDataLoader: CachedYamiboImageDataLoader(
                    cache: imageDataCacheStore,
                    upstream: YamiboImageDataLoader(client: client),
                    retentionPolicy: .evictable
                ),
                cacheNamespace: cacheNamespace
            ),
            cacheNamespace: NovelInlineImageCacheNamespace.namespace(
                cookie: sessionState.cookie,
                userAgent: sessionState.userAgent
            )
        )
    }

    public func makeImagePipelineContext() async -> YamiboImageLoadingContext {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return YamiboImageLoadingContext(
            dataLoader: CachedYamiboImageDataLoader(
                cache: imageDataCacheStore,
                upstream: YamiboImageDataLoader(client: client),
                retentionPolicy: .evictable
            ),
            cacheNamespace: YamiboImageCacheNamespace.ordinarySessionNamespace(
                cookie: sessionState.cookie,
                userAgent: sessionState.userAgent
            )
        )
    }

    public func makeProfileAvatarLoader() -> any YamiboProfileAvatarLoading {
        YamiboProfileAvatarLoader(
            session: session,
            sessionStore: sessionStore,
            imageDataLoaderFactory: { [imageDataCacheStore, session] sessionState in
                let client = YamiboClient(
                    session: session,
                    cookie: sessionState.cookie,
                    userAgent: sessionState.userAgent
                )
                return CachedYamiboImageDataLoader(
                    cache: imageDataCacheStore,
                    upstream: YamiboImageDataLoader(client: client),
                    retentionPolicy: .protected
                )
            },
            cacheNamespaceProvider: {
                YamiboImageCacheNamespace.avatarSessionNamespace(cookie: $0.cookie, userAgent: $0.userAgent)
            }
        )
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

    public func makeForumThreadRouteResolver() async -> ForumThreadRouteResolver {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ForumThreadRouteResolver(client: client)
    }

    public func makeForumThreadReaderRepository() async -> ForumThreadReaderRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ForumThreadReaderRepository(client: client, cacheStore: forumCacheStore)
    }

    public func makeForumRepository() async -> ForumRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return ForumRepository(client: client, cacheStore: forumCacheStore)
    }

    public func makeUserSpaceRepository() async -> UserSpaceRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return UserSpaceRepository(client: client)
    }

    public func makeBlogReaderRepository() async -> BlogReaderRepository {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return BlogReaderRepository(client: client)
    }

    public func makeMangaChapterDocumentLoader() async -> any MangaChapterDocumentLoading {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return CachedMangaChapterDocumentLoader(
            store: mangaChapterDocumentStore,
            upstream: YamiboMangaChapterDocumentLoader(client: client)
        )
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
        let cacheNamespace = YamiboImageCacheNamespace.ordinarySessionNamespace(
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return CachedMangaImageDataLoader(
            imageDataLoader: CachedYamiboImageDataLoader(
                cache: imageDataCacheStore,
                upstream: YamiboImageDataLoader(client: client),
                retentionPolicy: .evictable
            ),
            cacheNamespace: cacheNamespace,
            offlineCacheStore: mangaOfflineCacheStore
        )
    }

    public func makeMangaOfflineCacheStore() -> any MangaOfflineCacheStoring {
        mangaOfflineCacheStore
    }

    public func makeMangaOfflineCacheQueueExecutor() async -> MangaOfflineCacheQueueExecutor {
        if let executor = await mangaOfflineCacheQueueExecutorBox.value {
            return executor
        }

        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        let executor = MangaOfflineCacheQueueExecutor(
            store: mangaOfflineCacheStore,
            chapterDocumentLoader: await makeMangaChapterDocumentLoader(),
            imageAcquirer: MangaOfflineCacheImageAcquirer(
                transparentCache: imageDataCacheStore,
                cacheNamespace: YamiboImageCacheNamespace.ordinarySessionNamespace(
                    cookie: sessionState.cookie,
                    userAgent: sessionState.userAgent
                ),
                networkLoader: YamiboImageDataLoader(client: client),
                backgroundTransport: mangaOfflineCacheBackgroundDownloadTransport
            ),
            runObserver: mangaOfflineCacheContinuedProcessingCoordinator
        )
        return await mangaOfflineCacheQueueExecutorBox.setIfEmpty(executor)
    }

    public func makeCheckInService() -> any YamiboCheckInServicing {
        YamiboCheckInService(
            sessionStore: sessionStore,
            checkInStore: checkInStore,
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
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            sessionStore: sessionStore,
            appSettingsStore: settingsStore,
            client: WebDAVClient(session: session)
        )
    }

    public func bootstrap() async -> YamiboBootstrapState {
        return YamiboBootstrapState(
            session: await sessionStore.load(),
            profile: await profileStore.load(),
            settings: await settingsStore.load(),
            localFavoriteLibrary: await localFavoriteLibraryStore.load()
        )
    }

    public func resetApplicationData() async throws {
        try await sessionStore.reset()
        await profileStore.clear()
        try await settingsStore.reset()
        try await webDAVSyncSettingsStore.reset()
        await readerResumeRouteStore.clear()
        try await localFavoriteLibraryStore.clearAll()
        try await readingProgressStore.clearAll()
        try await contentCoverStore.clearAll()
        try await readerCacheStore.clearAll()
        try await mangaDirectoryStore.clearAll()
        await mangaDirectorySearchCooldownState.clear()
        try await mangaChapterDocumentStore.clearAll()
        try await imageDataCacheStore.clearAll()
        try await mangaOfflineCacheStore.clearAll()
        try await forumCacheStore.clearAll()
        try await favoriteBackgroundImageStore.deleteAll()
        clearLocalUIState()
        if clearsWebDataOnReset {
            await clearWebData()
        }
    }

    private func clearLocalUIState() {
        Self.resettableUserDefaultsKeys.forEach { uiDefaults.removeObject(forKey: $0) }
    }

    private static func openGRDBDatabase(rootDirectory: URL) -> DatabasePool {
        do {
            return try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory)
        } catch {
            fatalError("Failed to open Yamibo app database: \(error)")
        }
    }

    private static func forumCacheDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("forum-cache", isDirectory: true)
    }

    private static func readerCacheDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("reader-cache", isDirectory: true)
    }

    private static func favoriteBackgroundDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("favorite-background", isDirectory: true)
    }

    private static func imageDataDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("image-data", isDirectory: true)
    }

    private static func mangaOfflineCacheDirectory(rootDirectory: URL) -> URL {
        rootDirectory
            .appendingPathComponent("manga-reader", isDirectory: true)
            .appendingPathComponent("offline-cache", isDirectory: true)
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

private actor MangaOfflineCacheQueueExecutorBox {
    var value: MangaOfflineCacheQueueExecutor?

    func setIfEmpty(_ executor: MangaOfflineCacheQueueExecutor) -> MangaOfflineCacheQueueExecutor {
        if let value {
            return value
        }
        value = executor
        return executor
    }
}

public struct YamiboBootstrapState: Sendable {
    public let session: SessionState
    public let profile: YamiboProfile?
    public let settings: AppSettings
    public let localFavoriteLibrary: FavoriteLibraryDocument

    public init(
        session: SessionState,
        profile: YamiboProfile?,
        settings: AppSettings,
        localFavoriteLibrary: FavoriteLibraryDocument = FavoriteLibraryDocument()
    ) {
        self.session = session
        self.profile = profile
        self.settings = settings
        self.localFavoriteLibrary = localFavoriteLibrary
    }
}
