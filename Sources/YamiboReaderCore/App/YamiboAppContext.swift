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
    public let mangaReaderProjectionStore: any MangaReaderProjectionPersisting & MangaReaderProjectionStorageReporting
    public let offlineCacheStore: any OfflineCacheStoring
    public let forumCacheStore: ForumCacheStore
    public let ordinaryImageCache: any YamiboOrdinaryImageCacheClearing
    public let offlineCacheBackgroundDownloadTransport: OfflineCacheBackgroundDownloadTransport
    public let offlineCacheContinuedProcessingCoordinator: OfflineCacheContinuedProcessingCoordinator
    let session: URLSession
    let imageSession: URLSession
    private let offlineCacheQueueExecutorBox = OfflineCacheQueueExecutorBox()
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
        mangaReaderProjectionStore: (any MangaReaderProjectionPersisting & MangaReaderProjectionStorageReporting)? = nil,
        offlineCacheStore: (any OfflineCacheStoring)? = nil,
        forumCacheStore: ForumCacheStore? = nil,
        ordinaryImageCache: any YamiboOrdinaryImageCacheClearing = YamiboImageDataPipeline.shared,
        offlineCacheBackgroundDownloadTransport: OfflineCacheBackgroundDownloadTransport = OfflineCacheBackgroundDownloadTransport(),
        offlineCacheContinuedProcessingCoordinator: OfflineCacheContinuedProcessingCoordinator = OfflineCacheContinuedProcessingCoordinator(),
        grdbRootDirectory: URL? = nil,
        uiDefaults: UserDefaults = .standard,
        clearsWebDataOnReset: Bool = true,
        imageSession: URLSession = YamiboNetworkConfiguration.makeImageSession(),
        session: URLSession = YamiboNetworkConfiguration.makeSession()
    ) {
        let resolvedGRDBRootDirectory = grdbRootDirectory ?? YamiboDatabase.defaultRootDirectory()
        let resolvedGRDBDatabasePool = Self.openGRDBDatabase(rootDirectory: resolvedGRDBRootDirectory)
        let diskCacheStore = DiskCacheStore(
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
        let resolvedOfflineCacheStore = offlineCacheStore ?? OfflineCacheStore(
            databasePool: resolvedGRDBDatabasePool,
            baseDirectory: Self.offlineCacheDirectory(rootDirectory: resolvedGRDBRootDirectory)
        )
        self.localFavoriteLibraryStore = localFavoriteLibraryStore ?? FavoriteLibraryStore(databasePool: resolvedGRDBDatabasePool)
        self.favoriteUpdateStore = favoriteUpdateStore
        self.readingProgressStore = readingProgressStore ?? ReadingProgressStore(databasePool: resolvedGRDBDatabasePool)
        self.contentCoverStore = contentCoverStore
        self.readerCacheStore = readerCacheStore ?? ReaderCacheStore(
            diskCacheStore: diskCacheStore
        )
        self.favoriteBackgroundImageStore = favoriteBackgroundImageStore ?? FavoriteBackgroundImageStore(
            baseDirectory: Self.favoriteBackgroundDirectory(rootDirectory: resolvedGRDBRootDirectory)
        )
        self.mangaDirectoryStore = mangaDirectoryStore ?? MangaDirectoryStore(databasePool: resolvedGRDBDatabasePool)
        self.mangaDirectorySearchCooldownState = mangaDirectorySearchCooldownState
        self.mangaReaderProjectionStore = mangaReaderProjectionStore ?? MangaReaderProjectionStore(diskCacheStore: diskCacheStore)
        self.offlineCacheStore = resolvedOfflineCacheStore
        self.forumCacheStore = forumCacheStore ?? ForumCacheStore(
            diskCacheStore: diskCacheStore
        )
        self.ordinaryImageCache = ordinaryImageCache
        self.offlineCacheBackgroundDownloadTransport = offlineCacheBackgroundDownloadTransport
        self.offlineCacheContinuedProcessingCoordinator = offlineCacheContinuedProcessingCoordinator
        self.session = session
        self.imageSession = imageSession
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
            forumCacheStore: forumCacheStore,
            offlineCacheStore: offlineCacheStore,
            novelOfflineAutoRefreshEnabled: { [settingsStore] in
                await settingsStore.load().novelOfflineCache.isAutoRefreshEnabled
            },
            novelOfflineRetainsInlineImages: { [settingsStore] in
                await settingsStore.load().novelOfflineCache.retainsInlineImages
            }
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

    public func makeNovelInlineImageLoadingContext(threadID: String? = nil) async -> NovelInlineImageLoadingContext {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: imageSession,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        let remoteLoader = YamiboNovelInlineImageDataLoader(
            imageDataLoader: YamiboImageDataLoader(client: client)
        )
        return NovelInlineImageLoadingContext(
            loader: CachedNovelInlineImageDataLoader(
                imageDataLoader: remoteLoader,
                offlineCacheStore: offlineCacheStore,
                threadID: threadID
            )
        )
    }

    public func makeImagePipelineContext() async -> YamiboImageLoadingContext {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: imageSession,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return YamiboImageLoadingContext(
            dataLoader: YamiboImageDataLoader(client: client)
        )
    }

    public func makeProfileAvatarLoader() -> any YamiboProfileAvatarLoading {
        YamiboProfileAvatarLoader(
            session: imageSession,
            sessionStore: sessionStore,
            imageDataLoaderFactory: { [imageSession] sessionState in
                let client = YamiboClient(
                    session: imageSession,
                    cookie: sessionState.cookie,
                    userAgent: sessionState.userAgent
                )
                return YamiboImageDataLoader(client: client)
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

    public func makeMangaReaderProjectionLoader() async -> any MangaReaderProjectionSnapshotLoading {
        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return YamiboMangaReaderProjectionLoader(
            client: client,
            projectionStore: mangaReaderProjectionStore,
            forumCacheStore: forumCacheStore,
            offlineCacheStore: offlineCacheStore
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
            session: imageSession,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        return CachedMangaImageDataLoader(
            imageDataLoader: YamiboImageDataLoader(client: client),
            offlineCacheStore: offlineCacheStore
        )
    }

    public func makeOfflineCacheStore() -> any OfflineCacheStoring {
        offlineCacheStore
    }

    public func makeOfflineCacheQueueExecutor() async -> OfflineCacheQueueExecutor {
        if let executor = await offlineCacheQueueExecutorBox.value {
            return executor
        }

        let sessionState = await sessionStore.load()
        let client = YamiboClient(
            session: imageSession,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
        let executor = OfflineCacheQueueExecutor(
            store: offlineCacheStore,
            readerProjectionLoader: await makeMangaReaderProjectionLoader(),
            novelSourcePageLoader: await makeNovelReaderRepository(),
            imageAcquirer: OfflineCacheImageAcquirer(
                networkLoader: YamiboImageDataLoader(client: client),
                backgroundTransport: offlineCacheBackgroundDownloadTransport
            ),
            runObserver: offlineCacheContinuedProcessingCoordinator
        )
        return await offlineCacheQueueExecutorBox.setIfEmpty(executor)
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

    public func clearOrdinaryImageCache() {
        ordinaryImageCache.removeAllCachedData()
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
        try await mangaReaderProjectionStore.clearAll()
        try await offlineCacheStore.clearAll()
        try await forumCacheStore.clearAll()
        try await favoriteBackgroundImageStore.deleteAll()
        clearOrdinaryImageCache()
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

    private static func offlineCacheDirectory(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("offline-cache", isDirectory: true)
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

private actor OfflineCacheQueueExecutorBox {
    var value: OfflineCacheQueueExecutor?

    func setIfEmpty(_ executor: OfflineCacheQueueExecutor) -> OfflineCacheQueueExecutor {
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
