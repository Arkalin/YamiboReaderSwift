import Foundation

public enum MangaDirectoryStrategy: String, Codable, Hashable, Sendable {
    case tag
    case links
    case pendingSearch
    case searched
}

public struct MangaDirectory: Codable, Hashable, Sendable, Identifiable {
    public var cleanBookName: String
    public var strategy: MangaDirectoryStrategy
    public var sourceKey: String
    public var chapters: [MangaChapter]
    public var lastUpdatedAt: Date?
    public var searchKeyword: String?

    public var id: String { cleanBookName }

    public var favoriteIdentity: String {
        let normalizedSourceKey = sourceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedSourceKey.isEmpty, normalizedSourceKey != cleanBookName {
            return "\(strategy.rawValue):\(normalizedSourceKey)"
        }
        if let firstTID = chapters.first?.tid.trimmingCharacters(in: .whitespacesAndNewlines), !firstTID.isEmpty {
            return "chapter:\(firstTID)"
        }
        return cleanBookName
    }

    public init(
        cleanBookName: String,
        strategy: MangaDirectoryStrategy,
        sourceKey: String,
        chapters: [MangaChapter] = [],
        lastUpdatedAt: Date? = nil,
        searchKeyword: String? = nil
    ) {
        self.cleanBookName = cleanBookName
        self.strategy = strategy
        self.sourceKey = sourceKey
        self.chapters = chapters
        self.lastUpdatedAt = lastUpdatedAt
        self.searchKeyword = searchKeyword
    }
}
