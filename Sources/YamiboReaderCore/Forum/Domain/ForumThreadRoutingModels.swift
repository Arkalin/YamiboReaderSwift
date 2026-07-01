import Foundation

public enum YamiboForumThreadKind: String, Codable, Hashable, Sendable {
    case novel
    case manga
    case regular
    case unknown
}

public struct ThreadIdentity: Codable, Hashable, Sendable {
    public var tid: String
    public var canonicalURL: URL
    public var fid: String?

    public init(tid: String, canonicalURL: URL, fid: String? = nil) {
        self.tid = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        self.canonicalURL = canonicalURL
        self.fid = fid?.threadRoutingTrimmedNonEmpty
    }
}

public struct ForumThreadTapContext: Codable, Hashable, Sendable {
    public var containingFid: String?
    public var isTagMangaMode: Bool

    public init(containingFid: String? = nil, isTagMangaMode: Bool = false) {
        self.containingFid = containingFid?.threadRoutingTrimmedNonEmpty
        self.isTagMangaMode = isTagMangaMode
    }
}

public enum ThreadRouteIntent: String, Codable, Hashable, Sendable {
    case contentRoute
    case nativeThreadReader
}

public struct ThreadRouteRequest: Codable, Hashable, Sendable {
    public var threadURL: URL
    public var threadID: String?
    public var title: String?
    public var authorID: String?
    public var threadFid: String?
    public var targetPostID: String?
    public var knownThreadKind: YamiboForumThreadKind?
    public var intent: ThreadRouteIntent
    public var tapContext: ForumThreadTapContext

    public init(
        threadURL: URL,
        threadID: String? = nil,
        title: String? = nil,
        authorID: String? = nil,
        threadFid: String? = nil,
        targetPostID: String? = nil,
        knownThreadKind: YamiboForumThreadKind? = nil,
        intent: ThreadRouteIntent = .contentRoute,
        tapContext: ForumThreadTapContext = ForumThreadTapContext()
    ) {
        self.threadURL = threadURL
        self.threadID = threadID?.threadRoutingTrimmedNonEmpty
        self.title = title?.threadRoutingTrimmedNonEmpty
        self.authorID = authorID?.threadRoutingTrimmedNonEmpty
        self.threadFid = threadFid?.threadRoutingTrimmedNonEmpty
        self.targetPostID = targetPostID?.threadRoutingTrimmedNonEmpty
        self.knownThreadKind = knownThreadKind
        self.intent = intent
        self.tapContext = tapContext
    }
}

public struct NovelDetailLaunchContext: Codable, Hashable, Sendable {
    public var thread: ThreadIdentity
    public var title: String
    public var authorID: String?

    public init(thread: ThreadIdentity, title: String, authorID: String? = nil) {
        self.thread = thread
        self.title = title.threadRoutingTrimmedNonEmpty ?? L10n.string("reader.title")
        self.authorID = authorID?.threadRoutingTrimmedNonEmpty
    }
}

public struct MangaDetailLaunchContext: Codable, Hashable, Sendable {
    public var thread: ThreadIdentity
    public var title: String
    public var focusedChapterTID: String?
    public var directoryNameHint: String?

    public init(
        thread: ThreadIdentity,
        title: String,
        focusedChapterTID: String? = nil,
        directoryNameHint: String? = nil
    ) {
        self.thread = thread
        self.title = title.threadRoutingTrimmedNonEmpty ?? L10n.string("manga.reader.title")
        self.focusedChapterTID = focusedChapterTID?.threadRoutingTrimmedNonEmpty
        self.directoryNameHint = directoryNameHint?.threadRoutingTrimmedNonEmpty
    }
}

public struct ThreadReaderLaunchContext: Codable, Hashable, Sendable {
    public var thread: ThreadIdentity
    public var title: String
    public var initialPage: Int
    public var targetPostID: String?
    public var authorID: String?

    public var loadsAllPosts: Bool { true }

    public init(
        thread: ThreadIdentity,
        title: String,
        initialPage: Int = 1,
        targetPostID: String? = nil,
        authorID: String? = nil
    ) {
        self.thread = thread
        self.title = title.threadRoutingTrimmedNonEmpty ?? L10n.string("forum.default_title")
        self.initialPage = max(1, initialPage)
        self.targetPostID = targetPostID?.threadRoutingTrimmedNonEmpty
        self.authorID = authorID?.threadRoutingTrimmedNonEmpty
    }
}

public enum ThreadRouteTarget: Hashable, Sendable {
    case novelDetail(NovelDetailLaunchContext)
    case mangaDetail(MangaDetailLaunchContext)
    case threadReader(ThreadReaderLaunchContext)
    case webFallback(URL)
}

extension String {
    var threadRoutingTrimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
