import Foundation

public enum ChapterCommentSource: String, Codable, Hashable, Sendable {
    case postComment
    case ratingReason
    case reply

    public var displayLabel: String {
        switch self {
        case .postComment:
            L10n.string("reader.comment_source.post_comment")
        case .ratingReason:
            L10n.string("reader.comment_source.rating_reason")
        case .reply:
            L10n.string("reader.comment_source.others_post")
        }
    }
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

    public func originalPostURL(threadURL: URL) -> URL? {
        guard let postID, !postID.isEmpty,
              let threadID = Self.threadID(from: threadURL) else {
            return nil
        }
        var components = URLComponents(
            url: URL(string: threadURL.absoluteString, relativeTo: YamiboRoute.baseURL)?.absoluteURL ?? threadURL.absoluteURL,
            resolvingAgainstBaseURL: false
        ) ?? URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        if components.host == nil {
            components.scheme = YamiboRoute.baseURL.scheme
            components.host = YamiboRoute.baseURL.host
        }
        components.path = "/forum.php"
        components.queryItems = [
            .init(name: "goto", value: "findpost"),
            .init(name: "mobile", value: "2"),
            .init(name: "mod", value: "redirect"),
            .init(name: "pid", value: postID),
            .init(name: "ptid", value: threadID)
        ]
        return components.url
    }

    private static func threadID(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "tid" })?
            .value
            .flatMap(nilIfEmpty)
    }
}

public struct ChapterCommentsPage: Codable, Hashable, Sendable {
    public var target: ReaderChapterCommentTarget
    public var comments: [ChapterComment]
    public var isBoundaryClosed: Bool
    public var nextView: Int?

    public init(
        target: ReaderChapterCommentTarget,
        comments: [ChapterComment],
        isBoundaryClosed: Bool,
        nextView: Int? = nil
    ) {
        self.target = target
        self.comments = comments
        self.isBoundaryClosed = isBoundaryClosed
        self.nextView = nextView
    }
}
