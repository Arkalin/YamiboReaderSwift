import Foundation

public struct ReaderContent: Codable, Hashable, Sendable {
    public var data: String
    public var type: ContentType
    public var chapterTitle: String?

    public init(data: String, type: ContentType, chapterTitle: String? = nil) {
        self.data = data
        self.type = type
        self.chapterTitle = chapterTitle
    }
}

public enum ContentType: String, Codable, Sendable {
    case image
    case text
}
