import Foundation

public protocol MangaChapterDocumentLoading: Sendable {
    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument
}

public protocol MangaChapterDocumentPersisting: Sendable {
    func document(for chapterURL: URL) async -> MangaChapterDocument?
    func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws
    func clearAll() async throws
}

public protocol MangaChapterDocumentStorageReporting: Sendable {
    func totalDiskUsageBytes() async -> Int
}

public extension MangaChapterDocumentPersisting {
    func document(forTID tid: String) async -> MangaChapterDocument? {
        guard let url = MangaReaderDataSupport.chapterURL(forTID: tid) else { return nil }
        return await document(for: url)
    }

    func save(_ document: MangaChapterDocument) async throws {
        try await save(document, for: document.chapterURL)
    }
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

public protocol MangaImageDataCaching: Sendable {
    func data(for imageURL: URL) async -> Data?
    func save(_ data: Data, for imageURL: URL) async throws
    func clearAll() async throws
}

public protocol MangaOfflineCacheStoring: Sendable {
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
    func offlineCacheWork(ownerName: String, tid: String) async -> MangaOfflineCacheWork?
    func allOfflineCacheWorks() async -> [MangaOfflineCacheWork]
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
    func cancelOfflineCacheWork(ownerName: String, tid: String) async throws
    func cancelOfflineCacheWorks(forOwnerName ownerName: String) async throws
    func clearOfflineCacheQueue() async throws
    func offlineCacheQueueRunState() async -> MangaOfflineCacheQueueRunState
    func setOfflineCacheQueueRunState(_ state: MangaOfflineCacheQueueRunState) async throws
    func offlineCacheState(ownerName: String, tid: String) async -> MangaOfflineCacheState
    func clearAll() async throws
}
