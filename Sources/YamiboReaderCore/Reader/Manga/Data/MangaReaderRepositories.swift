import Foundation

public struct MangaReaderProjectionRequest: Codable, Hashable, Sendable {
    public var threadID: String
    public var view: Int
    public var authorID: String?
    public var offlineOwnerName: String?

    public init(threadID: String, view: Int = 1, authorID: String? = nil, offlineOwnerName: String? = nil) {
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedThreadID.isEmpty, "MangaReaderProjectionRequest requires a Yamibo thread tid")
        self.threadID = normalizedThreadID
        self.view = max(1, view)
        self.authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.authorID?.isEmpty == true {
            self.authorID = nil
        }
        self.offlineOwnerName = offlineOwnerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.offlineOwnerName?.isEmpty == true {
            self.offlineOwnerName = nil
        }
    }

    public init(chapter: MangaChapter, offlineOwnerName: String? = nil) {
        self.init(threadID: chapter.tid, view: chapter.view, authorID: chapter.authorUID, offlineOwnerName: offlineOwnerName)
    }
}

public protocol MangaReaderProjectionLoading: Sendable {
    func loadReaderProjection(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjection
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
    func loadReaderProjectionSnapshot(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjectionSnapshot
}

protocol MangaReaderProjectionPersisting: Sendable {
    func projection(for identity: MangaReaderProjectionSourceIdentity) async -> MangaReaderProjection?
    func save(_ projection: MangaReaderProjection) async throws
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
    func loadDirectorySeed(for threadID: String) async throws -> MangaDirectorySeed
    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter]
    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter]
}

public protocol MangaDirectoryPersisting: Sendable {
    func directory(named name: String) async throws -> MangaDirectory?
    func directory(containingTID tid: String) async throws -> MangaDirectory?
    func saveDirectory(_ directory: MangaDirectory) async throws
    func deleteDirectory(named name: String) async throws
}

protocol MangaDirectoryRenaming: Sendable {
    func renameDirectory(
        from oldName: String,
        to newDirectory: MangaDirectory
    ) async throws
}

