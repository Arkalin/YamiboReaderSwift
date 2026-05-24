import Foundation

public enum ChapterCommentSource: String, Codable, Hashable, Sendable {
    case postComment
    case ratingReason
    case reply
}

public struct ChapterComment: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var source: ChapterCommentSource
    public var authorName: String
    public var metadata: String?
    public var body: String
    public var postID: String?

    public init(
        id: String,
        source: ChapterCommentSource,
        authorName: String,
        metadata: String? = nil,
        body: String,
        postID: String? = nil
    ) {
        self.id = id
        self.source = source
        self.authorName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.metadata = Self.nilIfEmpty(metadata?.trimmingCharacters(in: .whitespacesAndNewlines))
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.postID = Self.nilIfEmpty(postID?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public struct ChapterCommentsPage: Codable, Hashable, Sendable {
    public var target: ReaderChapterCommentTarget
    public var comments: [ChapterComment]
    public var isBoundaryClosed: Bool

    public init(
        target: ReaderChapterCommentTarget,
        comments: [ChapterComment],
        isBoundaryClosed: Bool
    ) {
        self.target = target
        self.comments = comments
        self.isBoundaryClosed = isBoundaryClosed
    }
}
