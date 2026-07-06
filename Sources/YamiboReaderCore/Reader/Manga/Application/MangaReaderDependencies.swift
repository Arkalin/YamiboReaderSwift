import Foundation

/// Everything the manga reader feature UI (reader, directory panel, offline
/// cache sheet) needs from the composition root.
public struct MangaReaderDependencies: Sendable {
    public let settingsStore: SettingsStore
    public let readingProgressStore: ReadingProgressStore
    public let localFavoriteLibraryStore: FavoriteLibraryStore
    public let mangaDirectoryStore: any MangaDirectoryPersisting
    public let mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState
    public let offlineCacheStore: any OfflineCacheStoring
    public let contentCoverStore: ContentCoverStore
    public let makeProjectionLoader: @Sendable () async -> any MangaReaderProjectionSnapshotLoading
    public let makeDirectoryRepository: @Sendable () async -> any MangaDirectoryRepository
    public let makeChapterCommentsRepository: @Sendable () async -> ReaderChapterCommentsRepository
    public let makeOfflineCacheQueueExecutor: @Sendable () async -> OfflineCacheQueueExecutor
    /// The cache sheet embeds the account feature's offline queue view model.
    public let account: AccountDependencies

    public init(
        settingsStore: SettingsStore,
        readingProgressStore: ReadingProgressStore,
        localFavoriteLibraryStore: FavoriteLibraryStore,
        mangaDirectoryStore: any MangaDirectoryPersisting,
        mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState,
        offlineCacheStore: any OfflineCacheStoring,
        contentCoverStore: ContentCoverStore,
        makeProjectionLoader: @escaping @Sendable () async -> any MangaReaderProjectionSnapshotLoading,
        makeDirectoryRepository: @escaping @Sendable () async -> any MangaDirectoryRepository,
        makeChapterCommentsRepository: @escaping @Sendable () async -> ReaderChapterCommentsRepository,
        makeOfflineCacheQueueExecutor: @escaping @Sendable () async -> OfflineCacheQueueExecutor,
        account: AccountDependencies
    ) {
        self.settingsStore = settingsStore
        self.readingProgressStore = readingProgressStore
        self.localFavoriteLibraryStore = localFavoriteLibraryStore
        self.mangaDirectoryStore = mangaDirectoryStore
        self.mangaDirectorySearchCooldownState = mangaDirectorySearchCooldownState
        self.offlineCacheStore = offlineCacheStore
        self.contentCoverStore = contentCoverStore
        self.makeProjectionLoader = makeProjectionLoader
        self.makeDirectoryRepository = makeDirectoryRepository
        self.makeChapterCommentsRepository = makeChapterCommentsRepository
        self.makeOfflineCacheQueueExecutor = makeOfflineCacheQueueExecutor
        self.account = account
    }
}
