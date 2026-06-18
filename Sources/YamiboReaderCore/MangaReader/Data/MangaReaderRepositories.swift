import Foundation

public protocol MangaChapterDocumentLoading: Sendable {
    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument
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
    func saveDirectory(_ directory: MangaDirectory) async throws
    func deleteDirectory(named name: String) async throws
}

public protocol MangaImageDataLoading: Sendable {
    func imageData(for url: URL, refererURL: URL?) async throws -> Data
}

public protocol MangaImageDataCaching: Sendable {
    func data(for imageURL: URL) async -> Data?
    func save(_ data: Data, for imageURL: URL) async throws
    func clearAll() async throws
}
