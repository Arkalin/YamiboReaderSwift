import Foundation

public struct Favorite: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var displayName: String?
    public var url: URL
    public var remoteFavoriteID: String?
    public var mangaPageIndex: Int
    public var lastView: Int
    public var lastChapter: String?
    public var authorID: String?
    public var novelResumePoint: ReaderResumePoint?
    public var novelMaxView: Int?
    public var isHidden: Bool
    public var type: FavoriteType
    public var lastMangaURL: URL?
    public var parentCollectionID: String?
    public var manualOrder: Int
    public var lastReadAt: Date?
    public var tagIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case displayName
        case url
        case remoteFavoriteID
        case mangaPageIndex = "lastPage"
        case lastView
        case lastChapter
        case authorID
        case novelResumePoint
        case novelMaxView
        case isHidden
        case type
        case lastMangaURL
        case parentCollectionID
        case manualOrder
        case lastReadAt
        case tagIDs
    }

    public init(
        id: String? = nil,
        title: String,
        displayName: String? = nil,
        url: URL,
        remoteFavoriteID: String? = nil,
        mangaPageIndex: Int = 0,
        lastView: Int = 1,
        lastChapter: String? = nil,
        authorID: String? = nil,
        novelResumePoint: ReaderResumePoint? = nil,
        novelMaxView: Int? = nil,
        isHidden: Bool = false,
        type: FavoriteType = .unknown,
        lastMangaURL: URL? = nil,
        parentCollectionID: String? = nil,
        manualOrder: Int = 0,
        lastReadAt: Date? = nil,
        tagIDs: [String] = []
    ) {
        self.id = id ?? url.absoluteString
        self.title = title
        self.displayName = displayName
        self.url = url
        self.remoteFavoriteID = remoteFavoriteID
        self.mangaPageIndex = max(0, mangaPageIndex)
        self.lastView = lastView
        self.lastChapter = lastChapter
        self.authorID = authorID
        self.novelResumePoint = novelResumePoint
        self.novelMaxView = novelMaxView.map { max(1, $0) }
        self.isHidden = isHidden
        self.type = type
        self.lastMangaURL = lastMangaURL
        self.parentCollectionID = parentCollectionID
        self.manualOrder = manualOrder
        self.lastReadAt = lastReadAt
        self.tagIDs = tagIDs
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
        mangaPageIndex = max(0, try container.decodeIfPresent(Int.self, forKey: .mangaPageIndex) ?? 0)
        lastView = try container.decodeIfPresent(Int.self, forKey: .lastView) ?? 1
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID)
        novelResumePoint = try container.decodeIfPresent(ReaderResumePoint.self, forKey: .novelResumePoint)
        novelMaxView = try container.decodeIfPresent(Int.self, forKey: .novelMaxView).map { max(1, $0) }
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        type = try container.decodeIfPresent(FavoriteType.self, forKey: .type) ?? .unknown
        lastMangaURL = try container.decodeIfPresent(URL.self, forKey: .lastMangaURL)
        parentCollectionID = try container.decodeIfPresent(String.self, forKey: .parentCollectionID)
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        tagIDs = try container.decodeIfPresent([String].self, forKey: .tagIDs) ?? []
    }
}

public enum FavoriteType: Int, Codable, CaseIterable, Sendable {
    case unknown = 0
    case novel = 1
    case manga = 2
    case other = 3

    public var title: String {
        switch self {
        case .unknown: L10n.string("favorite_type.unknown")
        case .novel: L10n.string("favorite_type.novel")
        case .manga: L10n.string("favorite_type.manga")
        case .other: L10n.string("favorite_type.other")
        }
    }
}

public struct FavoriteCollection: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var manualOrder: Int
    public var isHidden: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case manualOrder
        case isHidden
    }

    public init(id: String = UUID().uuidString, name: String, manualOrder: Int = 0, isHidden: Bool = false) {
        self.id = id
        self.name = name
        self.manualOrder = manualOrder
        self.isHidden = isHidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

public enum FavoriteTagColor: String, Codable, CaseIterable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray
}

public struct FavoriteTag: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var color: FavoriteTagColor
    public var manualOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case manualOrder
        case createdAt
        case updatedAt
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        color: FavoriteTagColor,
        manualOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.manualOrder = manualOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decodeIfPresent(FavoriteTagColor.self, forKey: .color) ?? .gray
        manualOrder = try container.decodeIfPresent(Int.self, forKey: .manualOrder) ?? 0
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }
}
