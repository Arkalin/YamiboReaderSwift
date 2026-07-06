import Foundation

/// Everything the novel reader feature UI (reader, offline cache panel)
/// needs from the composition root.
public struct NovelReaderDependencies: Sendable {
    public let sessionStore: SessionStore
    public let settingsStore: SettingsStore
    public let readingProgressStore: ReadingProgressStore
    public let offlineCacheStore: any OfflineCacheStoring
    public let makeNovelReaderRepository: @Sendable () async -> NovelReaderRepository
    public let makeChapterCommentsRepository: @Sendable () async -> ReaderChapterCommentsRepository
    public let makeOfflineCacheQueueExecutor: @Sendable () async -> OfflineCacheQueueExecutor
    /// The cache panel embeds the account feature's offline queue view model.
    public let account: AccountDependencies

    public init(
        sessionStore: SessionStore,
        settingsStore: SettingsStore,
        readingProgressStore: ReadingProgressStore,
        offlineCacheStore: any OfflineCacheStoring,
        makeNovelReaderRepository: @escaping @Sendable () async -> NovelReaderRepository,
        makeChapterCommentsRepository: @escaping @Sendable () async -> ReaderChapterCommentsRepository,
        makeOfflineCacheQueueExecutor: @escaping @Sendable () async -> OfflineCacheQueueExecutor,
        account: AccountDependencies
    ) {
        self.sessionStore = sessionStore
        self.settingsStore = settingsStore
        self.readingProgressStore = readingProgressStore
        self.offlineCacheStore = offlineCacheStore
        self.makeNovelReaderRepository = makeNovelReaderRepository
        self.makeChapterCommentsRepository = makeChapterCommentsRepository
        self.makeOfflineCacheQueueExecutor = makeOfflineCacheQueueExecutor
        self.account = account
    }
}
