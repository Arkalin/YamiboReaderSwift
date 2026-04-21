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
    public var parentCollectionID: String?
    public var manualOrder: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case displayName
        case url
        case remoteFavoriteID
        case lastPage
        case lastView
        case lastChapter
        case authorID
        case novelResumePoint
        case isHidden
        case type
        case lastMangaURL
        case parentCollectionID
        case manualOrder
    }

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
        lastMangaURL: URL? = nil,
        parentCollectionID: String? = nil,
        manualOrder: Int = 0
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
        self.parentCollectionID = parentCollectionID
        self.manualOrder = manualOrder
    }

    public var resolvedDisplayTitle: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? title : trimmed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        url = try container.decode(URL.self, forKey: .url)
        remoteFavoriteID = try container.decodeIfPresent(String.self, forKey: .remoteFavoriteID)
        lastPage = try container.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0
        lastView = try container.decodeIfPresent(Int.self, forKey: .lastView) ?? 1
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID)
        novelResumePoint = try container.decodeIfPresent(ReaderResumePoint.self, forKey: .novelResumePoint)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        type = try container.decodeIfPresent(FavoriteType.self, forKey: .type) ?? .unknown
        lastMangaURL = try container.decodeIfPresent(URL.self, forKey: .lastMangaURL)
        parentCollectionID = try container.decodeIfPresent(String.self, forKey: .parentCollectionID)
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
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

public struct FavoriteCollection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var manualOrder: Int

    public init(id: String = UUID().uuidString, name: String, manualOrder: Int = 0) {
        self.id = id
        self.name = name
        self.manualOrder = manualOrder
    }
}
