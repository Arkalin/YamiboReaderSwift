import Foundation

public protocol MangaReaderProjectionLoading: Sendable {
    func loadReaderProjection(at url: URL) async throws -> MangaReaderProjection
}

public struct MangaReaderProjectionSnapshot: Sendable {
    public var projection: MangaReaderProjection
    public var sourcePage: ForumThreadPage

    public init(projection: MangaReaderProjection, sourcePage: ForumThreadPage) {
        self.projection = projection
        self.sourcePage = sourcePage
    }
}

public protocol MangaReaderProjectionSnapshotLoading: MangaReaderProjectionLoading {
    func loadReaderProjectionSnapshot(at url: URL) async throws -> MangaReaderProjectionSnapshot
}

public protocol MangaReaderProjectionPersisting: Sendable {
    func projection(for identity: MangaReaderProjectionSourceIdentity) async -> MangaReaderProjection?
    func save(_ projection: MangaReaderProjection) async throws
    func clearAll() async throws
}

public protocol MangaReaderProjectionStorageReporting: Sendable {
    func totalDiskUsageBytes() async -> Int
}

public struct MangaDirectorySeed: Hashable, Sendable {
    public var currentChapter: MangaChapter
    public var tagIDs: [String]
    public var samePageChapters: [MangaChapter]
    public var cleanBookName: String
    public var firstPostID: String?

    public init(
        currentChapter: MangaChapter,
        tagIDs: [String] = [],
        samePageChapters: [MangaChapter] = [],
        cleanBookName: String,
        firstPostID: String? = nil
    ) {
        self.currentChapter = currentChapter
        self.tagIDs = tagIDs
        self.samePageChapters = samePageChapters
        self.cleanBookName = cleanBookName
        let normalizedFirstPostID = firstPostID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.firstPostID = normalizedFirstPostID?.isEmpty == false ? normalizedFirstPostID : nil
    }
}

public protocol MangaDirectoryRepository: Sendable {
    func loadDirectorySeed(for chapterURL: URL) async throws -> MangaDirectorySeed
    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter]
    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter]
}

public protocol MangaDirectoryPersisting: Sendable {
    func directory(named name: String) async throws -> MangaDirectory?
    func directory(containingTID tid: String) async throws -> MangaDirectory?
    func saveDirectory(_ directory: MangaDirectory) async throws
    func deleteDirectory(named name: String) async throws
}

public protocol MangaDirectoryStorageReporting: Sendable {
    func totalDiskUsageBytes() async -> Int
}

public protocol MangaDirectoryClearing: Sendable {
    func clearAll() async throws
}

public protocol MangaDirectoryRenaming: Sendable {
    func renameDirectory(
        from oldName: String,
        to newDirectory: MangaDirectory
    ) async throws
}

public protocol MangaImageDataLoading: Sendable {
    func imageData(for url: URL, refererURL: URL?) async throws -> Data
    func imageData(
        for url: URL,
        refererURL: URL?,
        offlineCacheContext: MangaImageOfflineCacheContext?
    ) async throws -> Data
}

public struct MangaImageOfflineCacheContext: Hashable, Sendable {
    public var ownerName: String
    public var tid: String

    public init?(ownerName: String?, tid: String) {
        guard let ownerName = ownerName?.mangaReaderTrimmedNonEmpty,
              let tid = tid.mangaReaderTrimmedNonEmpty else {
            return nil
        }
        self.ownerName = ownerName
        self.tid = tid
    }
}

public extension MangaImageDataLoading {
    func imageData(
        for url: URL,
        refererURL: URL?,
        offlineCacheContext: MangaImageOfflineCacheContext?
    ) async throws -> Data {
        try await imageData(for: url, refererURL: refererURL)
    }
}

public protocol OfflineCacheStoring: Sendable {
    func offlineCacheUpdates() -> AsyncStream<Void>
    func membership(ownerName: String, tid: String) async -> MangaOfflineCacheMembership?
    func memberships(forOwnerName ownerName: String) async -> [MangaOfflineCacheMembership]
    func allMemberships() async -> [MangaOfflineCacheMembership]
    func saveMembership(_ membership: MangaOfflineCacheMembership) async throws
    func removeMembership(ownerName: String, tid: String) async throws
    func removeMemberships(forOwnerName ownerName: String) async throws
    func renameOwner(from oldOwnerName: String, to newOwnerName: String) async throws
    func offlineImageData(for imageURL: URL) async -> Data?
    func saveOfflineImageData(_ data: Data, for imageURL: URL) async throws
    func diskUsageByOwner() async -> [MangaOfflineCacheOwnerUsage]
    func offlineCacheManagementSnapshot() async -> OfflineCacheManagementSnapshot
    func removeOfflineCacheGroup(_ id: OfflineCacheGroupID) async throws
    func removeOfflineCacheEntry(_ id: OfflineCacheEntryID) async throws
    func saveNovelOfflineCacheEntry(_ entry: NovelOfflineCacheEntry) async throws
    func novelOfflineCacheEntry(id: OfflineCacheEntryID) async -> NovelOfflineCacheEntry?
    func allNovelOfflineCacheEntries() async -> [NovelOfflineCacheEntry]
    func offlineCacheWork(ownerName: String, tid: String) async -> MangaOfflineCacheWork?
    func allOfflineCacheWorks() async -> [MangaOfflineCacheWork]
    func offlineCacheQueueWorks() async -> [OfflineCacheQueueWorkProjection]
    func enqueueNovelOfflineCacheWork(_ request: NovelOfflineCacheWorkRequest) async throws -> NovelOfflineCacheEnqueueResult
    func retryFailedOfflineCacheWorks() async throws
    func enqueueOfflineCacheWork(_ request: MangaOfflineCacheWorkRequest) async throws -> MangaOfflineCacheEnqueueResult
    func updateOfflineCacheWorkProgress(
        ownerName: String,
        tid: String,
        targetImageURLs: [URL]?,
        completedImageURLs: [URL],
        currentBytesPerSecond: Int?
    ) async throws
    func prepareOfflineCacheWorkForRun(ownerName: String, tid: String, targetImageURLs: [URL]?, completedImageURLs: [URL]) async throws
    func markOfflineCacheWorkFailed(ownerName: String, tid: String, message: String?) async throws
    func markOfflineCacheWorkFailed(id: OfflineCacheWorkID, message: String?) async throws
    func cancelOfflineCacheWork(ownerName: String, tid: String) async throws
    func cancelOfflineCacheWork(id: OfflineCacheWorkID) async throws
    func cancelOfflineCacheWorks(forOwnerName ownerName: String) async throws
    func cancelOfflineCacheGroup(_ id: OfflineCacheGroupID) async throws
    func clearOfflineCacheQueue() async throws
    func offlineCacheQueueRunState() async -> MangaOfflineCacheQueueRunState
    func setOfflineCacheQueueRunState(_ state: MangaOfflineCacheQueueRunState) async throws
    func offlineCacheState(ownerName: String, tid: String) async -> MangaOfflineCacheState
    func totalDiskUsageBytes() async -> Int
    func clearAll() async throws
}
