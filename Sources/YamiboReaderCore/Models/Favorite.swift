import Foundation

public struct Favorite: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var displayName: String?
    public var url: URL
    public var lastPage: Int
    public var lastView: Int
    public var lastChapter: String?
    public var authorID: String?
    public var novelResumePoint: ReaderResumePoint?
    public var isHidden: Bool
    public var type: FavoriteType
    public var lastMangaURL: URL?
    public var knownMaxView: Int?
    public var knownMaxViewFingerprint: String?
    public var novelUpdateStatus: FavoriteNovelUpdateStatus
    public var lastRemoteMaxView: Int?
    public var lastUpdateCheckedAt: Date?

    public init(
        id: String? = nil,
        title: String,
        displayName: String? = nil,
        url: URL,
        lastPage: Int = 0,
        lastView: Int = 1,
        lastChapter: String? = nil,
        authorID: String? = nil,
        novelResumePoint: ReaderResumePoint? = nil,
        isHidden: Bool = false,
        type: FavoriteType = .unknown,
        lastMangaURL: URL? = nil,
        knownMaxView: Int? = nil,
        knownMaxViewFingerprint: String? = nil,
        novelUpdateStatus: FavoriteNovelUpdateStatus = .none,
        lastRemoteMaxView: Int? = nil,
        lastUpdateCheckedAt: Date? = nil
    ) {
        self.id = id ?? url.absoluteString
        self.title = title
        self.displayName = displayName
        self.url = url
        self.lastPage = lastPage
        self.lastView = lastView
        self.lastChapter = lastChapter
        self.authorID = authorID
        self.novelResumePoint = novelResumePoint
        self.isHidden = isHidden
        self.type = type
        self.lastMangaURL = lastMangaURL
        self.knownMaxView = knownMaxView
        self.knownMaxViewFingerprint = knownMaxViewFingerprint
        self.novelUpdateStatus = novelUpdateStatus
        self.lastRemoteMaxView = lastRemoteMaxView
        self.lastUpdateCheckedAt = lastUpdateCheckedAt
    }

    public var resolvedDisplayTitle: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? title : trimmed
    }

    public var hasPendingNovelUpdate: Bool {
        novelUpdateStatus.showsUpdateBadge
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case displayName
        case url
        case lastPage
        case lastView
        case lastChapter
        case authorID
        case novelResumePoint
        case isHidden
        case type
        case lastMangaURL
        case knownMaxView
        case knownMaxViewFingerprint
        case novelUpdateStatus
        case lastRemoteMaxView
        case lastUpdateCheckedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        url = try container.decode(URL.self, forKey: .url)
        lastPage = try container.decodeIfPresent(Int.self, forKey: .lastPage) ?? 0
        lastView = try container.decodeIfPresent(Int.self, forKey: .lastView) ?? 1
        lastChapter = try container.decodeIfPresent(String.self, forKey: .lastChapter)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID)
        novelResumePoint = try container.decodeIfPresent(ReaderResumePoint.self, forKey: .novelResumePoint)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        type = try container.decodeIfPresent(FavoriteType.self, forKey: .type) ?? .unknown
        lastMangaURL = try container.decodeIfPresent(URL.self, forKey: .lastMangaURL)
        knownMaxView = try container.decodeIfPresent(Int.self, forKey: .knownMaxView)
        knownMaxViewFingerprint = try container.decodeIfPresent(String.self, forKey: .knownMaxViewFingerprint)
        novelUpdateStatus = try container.decodeIfPresent(FavoriteNovelUpdateStatus.self, forKey: .novelUpdateStatus) ?? .none
        lastRemoteMaxView = try container.decodeIfPresent(Int.self, forKey: .lastRemoteMaxView)
        lastUpdateCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckedAt)
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

public enum FavoriteNovelUpdateStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case none
    case newPage
    case contentChanged
    case structureChanged

    public var showsUpdateBadge: Bool {
        self == .newPage || self == .contentChanged
    }

    public var title: String {
        switch self {
        case .none: "无更新"
        case .newPage: "有新网页"
        case .contentChanged: "内容变更"
        case .structureChanged: "远端结构变化"
        }
    }
}
