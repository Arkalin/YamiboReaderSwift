import Foundation

public struct Favorite: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var displayName: String?
    public var url: URL
    public var remoteFavoriteID: String?
    public var lastPage: Int
    public var lastView: Int
    public var lastChapter: String?
    public var authorID: String?
    public var novelResumePoint: ReaderResumePoint?
    public var isHidden: Bool
    public var type: FavoriteType
    public var lastMangaURL: URL?

    public init(
        id: String? = nil,
        title: String,
        displayName: String? = nil,
        url: URL,
        remoteFavoriteID: String? = nil,
        lastPage: Int = 0,
        lastView: Int = 1,
        lastChapter: String? = nil,
        authorID: String? = nil,
        novelResumePoint: ReaderResumePoint? = nil,
        isHidden: Bool = false,
        type: FavoriteType = .unknown,
        lastMangaURL: URL? = nil
    ) {
        self.id = id ?? url.absoluteString
        self.title = title
        self.displayName = displayName
        self.url = url
        self.remoteFavoriteID = remoteFavoriteID
        self.lastPage = lastPage
        self.lastView = lastView
        self.lastChapter = lastChapter
        self.authorID = authorID
        self.novelResumePoint = novelResumePoint
        self.isHidden = isHidden
        self.type = type
        self.lastMangaURL = lastMangaURL
    }

    public var resolvedDisplayTitle: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? title : trimmed
    }
}

public enum FavoriteType: Int, Codable, CaseIterable, Sendable {
    case unknown = 0
    case novel = 1
    case manga = 2
    case other = 3

    public var title: String {
        switch self {
        case .unknown: "未定"
        case .novel: "小说"
        case .manga: "漫画"
        case .other: "其他"
        }
    }
}
