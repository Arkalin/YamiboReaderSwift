@preconcurrency import Foundation
@preconcurrency import GRDB
#if canImport(WebKit)
import WebKit
#endif

/// Composition root. Owns the infrastructure singletons, assembles each
/// feature's dependency package, and is referenced only by the app-entry
/// layer (`YamiboReaderApp`, `YamiboAppModel`, `RootTabView`,
/// `AppContinuityWorkflow`). Feature views and view models receive their
/// `*Dependencies` package instead of this context.
public final class YamiboAppContext: Sendable {
    private static let resettableUserDefaultsKeys = [
        "yamibo.favorite.filter",
        "yamibo.favorite.sort",
        "yamibo.favorite.tag.sort",
        "yamibo.favorite.showHidden"
    ]

    let sessionStore: SessionStore
    let profileStore: YamiboProfileStore
    let checkInStore: YamiboCheckInStore
    /// Public for change-ID observation in the app-entry layer.
    public let settingsStore: SettingsStore
    let webDAVSyncSettingsStore: WebDAVSyncSettingsStore
    let readerResumeRouteStore: ReaderResumeRouteStore
    /// Public for change-ID observation in the app-entry layer.
    public let localFavoriteLibraryStore: FavoriteLibraryStore
    let favoriteUpdateStore: FavoriteUpdateStore
    /// Public for change-ID observation in the app-entry layer.
    public let readingProgressStore: ReadingProgressStore
    let contentCoverStore: ContentCoverStore
    let novelReaderCacheStore: NovelReaderProjectionStore
    let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
    let mangaDirectoryStore: MangaDirectoryStore
    let mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState
    let mangaReaderProjectionStore: MangaReaderProjectionStore
    let offlineCacheStore: any OfflineCacheStoring
    let forumCacheStore: ForumCacheStore
    let ordinaryImageCache: any YamiboOrdinaryImageCacheClearing
    public let offlineCacheBackgroundDownloadTransport: OfflineCacheBackgroundDownloadTransport
    public let offlineCacheContinuedProcessingCoordinator: OfflineCacheContinuedProcessingCoordinator
    /// The single pool for `yamibo.sqlite`; every GRDB-backed store receives this instance.
    let databasePool: DatabasePool
    let session: URLSession
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
        novelReaderCacheStore: NovelReaderProjectionStore? = nil,
        favoriteBackgroundImageStore: FavoriteBackgroundImageStore? = nil,
        mangaDirectoryStore: MangaDirectoryStore? = nil,
        mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState = MangaDirectorySearchCooldownState(),
        mangaReaderProjectionStore: MangaReaderProjectionStore? = nil,
        offlineCacheStore: (any OfflineCacheStoring)? = nil,
        forumCacheStore: ForumCacheStore? = nil,
        ordinaryImageCache: any YamiboOrdinaryImageCacheClearing = YamiboImageDataPipeline.shared,
        offlineCacheBackgroundDownloadTransport: OfflineCacheBackgroundDownloadTransport = OfflineCacheBackgroundDownloadTransport(),
        offlineCacheContinuedProcessingCoordinator: OfflineCacheContinuedProcessingCoordinator = OfflineCacheContinuedProcessingCoordinator(),
        databasePool: DatabasePool? = nil,
        grdbRootDirectory: URL? = nil,
        uiDefaults: UserDefaults = .standard,
        clearsWebDataOnReset: Bool = true,
        session: URLSession = YamiboNetworkConfiguration.makeSession()
    ) {
        let resolvedGRDBRootDirectory = grdbRootDirectory ?? YamiboDatabase.defaultRootDirectory()
        let resolvedGRDBDatabasePool = databasePool ?? Self.openGRDBDatabase(rootDirectory: resolvedGRDBRootDirectory)
        self.databasePool = resolvedGRDBDatabasePool
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
        self.novelReaderCacheStore = novelReaderCacheStore ?? NovelReaderProjectionStore(
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
        YamiboImagePipeline.shared.setOfflineImageProvider(resolvedOfflineCacheStore)
    }

    // MARK: - Feature dependency packages

    public var forumDependencies: ForumDependencies {
        ForumDependencies(
            sessionStore: sessionStore,
            profileStore: profileStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            settingsStore: settingsStore,
            contentCoverStore: contentCoverStore,
            mangaDirectoryStore: mangaDirectoryStore,
            mangaDirectorySearchCooldownState: mangaDirectorySearchCooldownState,
            makeForumRepository: { [self] in await makeForumRepository() },
            makeForumThreadReaderRepository: { [self] in await makeForumThreadReaderRepository() },
            makeUserSpaceRepository: { [self] in await makeUserSpaceRepository() },
            makeBlogReaderRepository: { [self] in await makeBlogReaderRepository() },
            makeFavoriteRepository: { [self] in await makeFavoriteRepository() },
            makeNovelReaderRepository: { [self] in await makeNovelReaderRepository() },
            makeMangaReaderProjectionLoader: { [self] in await makeMangaReaderProjectionLoader() },
            makeMangaDirectoryRepository: { [self] in await makeMangaDirectoryRepository() },
            makeThreadRouteResolver: { [self] in await makeThreadRouteResolver() }
        )
    }

    public var libraryDependencies: LibraryDependencies {
        LibraryDependencies(
            sessionStore: sessionStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            favoriteUpdateStore: favoriteUpdateStore,
            readingProgressStore: readingProgressStore,
            settingsStore: settingsStore,
            contentCoverStore: contentCoverStore,
            makeFavoriteRepository: { [self] in await makeFavoriteRepository() },
            makeForumThreadReaderRepository: { [self] in await makeForumThreadReaderRepository() },
            makeThreadRouteResolver: { [self] in await makeThreadRouteResolver() }
        )
    }

    public var mangaReaderDependencies: MangaReaderDependencies {
        MangaReaderDependencies(
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            mangaDirectoryStore: mangaDirectoryStore,
            mangaDirectorySearchCooldownState: mangaDirectorySearchCooldownState,
            offlineCacheStore: offlineCacheStore,
            makeProjectionLoader: { [self] in await makeMangaReaderProjectionLoader() },
            makeDirectoryRepository: { [self] in await makeMangaDirectoryRepository() },
            makeChapterCommentsRepository: { [self] in await makeReaderChapterCommentsRepository() },
            makeOfflineCacheQueueExecutor: { [self] in await makeOfflineCacheQueueExecutor() },
            account: accountDependencies
        )
    }

    public var novelReaderDependencies: NovelReaderDependencies {
        NovelReaderDependencies(
            sessionStore: sessionStore,
            settingsStore: settingsStore,
            readingProgressStore: readingProgressStore,
            offlineCacheStore: offlineCacheStore,
            makeNovelReaderRepository: { [self] in await makeNovelReaderRepository() },
            makeChapterCommentsRepository: { [self] in await makeReaderChapterCommentsRepository() },
            makeOfflineCacheQueueExecutor: { [self] in await makeOfflineCacheQueueExecutor() },
            account: accountDependencies
        )
    }

    public var accountDependencies: AccountDependencies {
        AccountDependencies(
            sessionStore: sessionStore,
            profileStore: profileStore,
            checkInStore: checkInStore,
            mangaDirectoryStore: mangaDirectoryStore,
            offlineCacheStore: offlineCacheStore,
            makeAccountService: { [self] in makeAccountService() },
            makeCheckInService: { [self] in makeCheckInService() },
            makeOfflineCacheQueueExecutor: { [self] in await makeOfflineCacheQueueExecutor() }
        )
    }

    public var settingsDependencies: SettingsDependencies {
        SettingsDependencies(
            sessionStore: sessionStore,
            settingsStore: settingsStore,
            favoriteBackgroundImageStore: favoriteBackgroundImageStore,
            novelReaderCacheStore: novelReaderCacheStore,
            mangaDirectoryStore: mangaDirectoryStore,
            mangaReaderProjectionStore: mangaReaderProjectionStore,
            offlineCacheStore: offlineCacheStore,
            clearOrdinaryImageCache: { [self] in await clearOrdinaryImageCache() },
            resetApplicationData: { [self] in try await resetApplicationData() },
            library: libraryDependencies,
            webDAVSync: webDAVSyncDependencies
        )
    }

    public var webDAVSyncDependencies: WebDAVSyncDependencies {
        WebDAVSyncDependencies(
            settingsStore: webDAVSyncSettingsStore,
            makeSyncService: { [self] in makeWebDAVSyncService() }
        )
    }

    // MARK: - Factories

    private func makeClient() async -> YamiboClient {
        let sessionState = await sessionStore.load()
        return YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
    }

    func makeFavoriteRepository() async -> FavoriteRepository {
        FavoriteRepository(client: await makeClient())
    }

    func makeNovelReaderRepository() async -> NovelReaderRepository {
        NovelReaderRepository(
            client: await makeClient(),
            cacheStore: novelReaderCacheStore,
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

    func makeReaderChapterCommentsRepository() async -> ReaderChapterCommentsRepository {
        ReaderChapterCommentsRepository(client: await makeClient())
    }

    func makeThreadRouteResolver() async -> YamiboThreadRouteResolver {
        YamiboThreadRouteResolver(client: await makeClient())
    }

    func makeForumThreadReaderRepository() async -> ForumThreadReaderRepository {
        ForumThreadReaderRepository(client: await makeClient(), cacheStore: forumCacheStore)
    }

    func makeForumRepository() async -> ForumRepository {
        ForumRepository(client: await makeClient(), cacheStore: forumCacheStore)
    }

    func makeUserSpaceRepository() async -> UserSpaceRepository {
        UserSpaceRepository(client: await makeClient())
    }

    func makeBlogReaderRepository() async -> BlogReaderRepository {
        BlogReaderRepository(client: await makeClient())
    }

    func makeMangaReaderProjectionLoader() async -> any MangaReaderProjectionSnapshotLoading {
        MangaReaderProjectionLoader(
            client: await makeClient(),
            projectionStore: mangaReaderProjectionStore,
            forumCacheStore: forumCacheStore,
            offlineCacheStore: offlineCacheStore
        )
    }

    func makeMangaDirectoryRepository() async -> any MangaDirectoryRepository {
        YamiboMangaDirectoryRepository(client: await makeClient())
    }

    public func makeOfflineCacheQueueExecutor() async -> OfflineCacheQueueExecutor {
        if let executor = await offlineCacheQueueExecutorBox.value {
            return executor
        }

        let executor = OfflineCacheQueueExecutor(
            store: offlineCacheStore,
            mangaCacheStore: offlineCacheStore,
            novelCacheStore: offlineCacheStore,
            readerProjectionLoader: await makeMangaReaderProjectionLoader(),
            novelSourcePageLoader: await makeNovelReaderRepository(),
            imageAcquirer: OfflineCacheImageAcquirer(
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

    func makeAccountService() -> YamiboAccountService {
        YamiboAccountService(
            session: session,
            sessionStore: sessionStore,
            profileStore: profileStore
        )
    }

    func makeWebDAVSyncService() -> WebDAVSyncService {
        WebDAVSyncService(
            settingsStore: webDAVSyncSettingsStore,
            sessionStore: sessionStore,
            participants: [
                FavoriteLibraryWebDAVParticipant(store: localFavoriteLibraryStore),
                ReadingProgressWebDAVParticipant(store: readingProgressStore),
                AppSettingsWebDAVParticipant(store: settingsStore),
            ],
            client: WebDAVClient(session: session)
        )
    }

    func clearOrdinaryImageCache() async {
        await ordinaryImageCache.removeAllCachedData()
    }

    public func bootstrap() async -> YamiboBootstrapState {
        return YamiboBootstrapState(
            session: await sessionStore.load(),
            profile: await profileStore.load(),
            settings: await settingsStore.load(),
            localFavoriteLibrary: await localFavoriteLibraryStore.load()
        )
    }

    func resetApplicationData() async throws {
        try await sessionStore.reset()
        await profileStore.clear()
        try await settingsStore.reset()
        try await webDAVSyncSettingsStore.reset()
        await readerResumeRouteStore.clear()
        try await localFavoriteLibraryStore.clearAll()
        try await readingProgressStore.clearAll()
        try await contentCoverStore.clearAll()
        try await novelReaderCacheStore.clearAll()
        try await mangaDirectoryStore.clearAll()
        await mangaDirectorySearchCooldownState.clear()
        try await mangaReaderProjectionStore.clearAll()
        try await offlineCacheStore.clearAll()
        try await forumCacheStore.clearAll()
        try await favoriteBackgroundImageStore.deleteAll()
        await clearOrdinaryImageCache()
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
            return try YamiboDatabase.openPool(rootDirectory: rootDirectory)
        } catch {
            fatalError("Failed to open Yamibo app database: \(error)")
        }
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
