import Foundation

public struct MangaOfflineCacheMembershipID: Codable, Hashable, Sendable {
    public var favoriteID: String
    public var tid: String

    public init(favoriteID: String, tid: String) {
        self.favoriteID = favoriteID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct MangaOfflineCacheMembership: Codable, Hashable, Identifiable, Sendable {
    public var favoriteID: String
    public var favoriteTitle: String
    public var favoriteURL: URL
    public var tid: String
    public var chapterTitle: String
    public var chapterURL: URL
    public var imageURLs: [URL]
    public var createdAt: Date

    public var id: MangaOfflineCacheMembershipID {
        MangaOfflineCacheMembershipID(favoriteID: favoriteID, tid: tid)
    }

    public init(
        favoriteID: String,
        favoriteTitle: String,
        favoriteURL: URL,
        tid: String,
        chapterTitle: String,
        chapterURL: URL,
        imageURLs: [URL],
        createdAt: Date = .now
    ) {
        self.favoriteID = favoriteID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.favoriteTitle = favoriteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.favoriteURL = favoriteURL
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterURL = MangaReaderDataSupport.normalizedChapterURL(chapterURL)
        self.imageURLs = imageURLs
        self.createdAt = createdAt
    }
}

public struct MangaOfflineCacheFavoriteUsage: Codable, Equatable, Sendable {
    public var favoriteID: String
    public var byteCount: Int

    public init(favoriteID: String, byteCount: Int) {
        self.favoriteID = favoriteID
        self.byteCount = max(0, byteCount)
    }
}
