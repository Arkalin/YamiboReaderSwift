import Foundation

public protocol MangaChapterDocumentLoading: Sendable {
    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument
}

public protocol MangaChapterDocumentPersisting: Sendable {
    func document(for chapterURL: URL) async -> MangaChapterDocument?
    func save(_ document: MangaChapterDocument, for chapterURL: URL) async throws
    func clearAll() async throws
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

public protocol MangaImageDataLoading: Sendable {
    func imageData(for url: URL, refererURL: URL?) async throws -> Data
    func imageData(
        for url: URL,
        refererURL: URL?,
        offlineCacheContext: MangaImageOfflineCacheContext?
    ) async throws -> Data
}

public struct MangaImageOfflineCacheContext: Hashable, Sendable {
    public var favoriteID: String
    public var tid: String

    public init?(favoriteID: String?, tid: String) {
        guard let favoriteID = favoriteID?.mangaReaderTrimmedNonEmpty,
              let tid = tid.mangaReaderTrimmedNonEmpty else {
            return nil
        }
        self.favoriteID = favoriteID
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
    func membership(favoriteID: String, tid: String) async -> MangaOfflineCacheMembership?
    func memberships(forFavoriteID favoriteID: String) async -> [MangaOfflineCacheMembership]
    func allMemberships() async -> [MangaOfflineCacheMembership]
    func saveMembership(_ membership: MangaOfflineCacheMembership) async throws
    func removeMembership(favoriteID: String, tid: String) async throws
    func removeMemberships(forFavoriteID favoriteID: String) async throws
    func offlineImageData(for imageURL: URL) async -> Data?
    func saveOfflineImageData(_ data: Data, for imageURL: URL) async throws
    func diskUsageByFavorite() async -> [MangaOfflineCacheFavoriteUsage]
    func offlineCacheWork(favoriteID: String, tid: String) async -> MangaOfflineCacheWork?
    func allOfflineCacheWorks() async -> [MangaOfflineCacheWork]
    func enqueueOfflineCacheWork(_ request: MangaOfflineCacheWorkRequest) async throws -> MangaOfflineCacheEnqueueResult
    func updateOfflineCacheWorkProgress(favoriteID: String, tid: String, targetImageURLs: [URL]?, completedImageURLs: [URL]) async throws
    func prepareOfflineCacheWorkForRun(favoriteID: String, tid: String, targetImageURLs: [URL]?, completedImageURLs: [URL]) async throws
    func markOfflineCacheWorkFailed(favoriteID: String, tid: String, message: String?) async throws
    func cancelOfflineCacheWork(favoriteID: String, tid: String) async throws
    func cancelOfflineCacheWorks(forFavoriteID favoriteID: String) async throws
    func clearOfflineCacheQueue() async throws
    func offlineCacheQueueRunState() async -> MangaOfflineCacheQueueRunState
    func setOfflineCacheQueueRunState(_ state: MangaOfflineCacheQueueRunState) async throws
    func offlineCacheState(favoriteID: String, tid: String) async -> MangaOfflineCacheState
    func clearAll() async throws
}
