import Foundation
import CoreGraphics

public enum ReaderLaunchSource: String, Codable, Hashable, Sendable {
    case forum
    case favorites
    case resume
}

public struct ReaderLaunchContext: Codable, Hashable, Identifiable, Sendable {
    public var threadURL: URL
    public var threadTitle: String
    public var source: ReaderLaunchSource
    public var initialView: Int?
    public var initialPage: Int?
    public var authorID: String?

    public var id: String { threadURL.absoluteString }

    public init(
        threadURL: URL,
        threadTitle: String,
        source: ReaderLaunchSource,
        initialView: Int? = nil,
        initialPage: Int? = nil,
        authorID: String? = nil
    ) {
        self.threadURL = threadURL
        self.threadTitle = threadTitle
        self.source = source
        self.initialView = initialView
        self.initialPage = initialPage
        self.authorID = authorID
    }
}

public struct ReaderPageRequest: Codable, Hashable, Sendable {
    public var threadURL: URL
    public var view: Int
    public var authorID: String?

    public init(threadURL: URL, view: Int, authorID: String? = nil) {
        self.threadURL = threadURL
        self.view = max(1, view)
        self.authorID = authorID
    }
}

public enum ReaderContentSource: String, Codable, Hashable, Sendable {
    case allPostsPage
    case authorFilteredPage
    case fallbackUnfilteredPage

    public var isAuthorFiltered: Bool {
        self == .authorFilteredPage
    }
}

public enum ReaderSegment: Hashable, Sendable {
    case text(String, chapterTitle: String?)
    case image(URL, chapterTitle: String?)
}

extension ReaderSegment: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case imageURL
        case chapterTitle
    }

    private enum Kind: String, Codable {
        case text
        case image
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text, chapterTitle):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(chapterTitle, forKey: .chapterTitle)
        case let .image(url, chapterTitle):
            try container.encode(Kind.image, forKey: .kind)
            try container.encode(url, forKey: .imageURL)
            try container.encodeIfPresent(chapterTitle, forKey: .chapterTitle)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .text:
            self = .text(
                try container.decode(String.self, forKey: .text),
                chapterTitle: try container.decodeIfPresent(String.self, forKey: .chapterTitle)
            )
        case .image:
            self = .image(
                try container.decode(URL.self, forKey: .imageURL),
                chapterTitle: try container.decodeIfPresent(String.self, forKey: .chapterTitle)
            )
        }
    }
}

public struct ReaderPageDocument: Codable, Hashable, Sendable {
    public var threadURL: URL
    public var view: Int
    public var maxView: Int
    public var resolvedAuthorID: String?
    public var contentSource: ReaderContentSource
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int
    public var segments: [ReaderSegment]
    public var fetchedAt: Date

    public init(
        threadURL: URL,
        view: Int,
        maxView: Int,
        resolvedAuthorID: String? = nil,
        contentSource: ReaderContentSource = .allPostsPage,
        retainedChapterCount: Int = 0,
        filteredChapterCandidateCount: Int = 0,
        segments: [ReaderSegment],
        fetchedAt: Date = .now
    ) {
        self.threadURL = threadURL
        self.view = max(1, view)
        self.maxView = max(self.view, maxView)
        self.resolvedAuthorID = resolvedAuthorID
        self.contentSource = contentSource
        self.retainedChapterCount = retainedChapterCount
        self.filteredChapterCandidateCount = filteredChapterCandidateCount
        self.segments = segments
        self.fetchedAt = fetchedAt
    }
}

public struct ReaderChapter: Codable, Hashable, Sendable {
    public var title: String
    public var startIndex: Int

    public init(title: String, startIndex: Int) {
        self.title = title
        self.startIndex = startIndex
    }
}

public struct ReaderProgress: Codable, Hashable, Sendable {
    public var view: Int
    public var page: Int
    public var chapterTitle: String?
    public var authorID: String?

    public init(view: Int, page: Int, chapterTitle: String? = nil, authorID: String? = nil) {
        self.view = max(1, view)
        self.page = max(0, page)
        self.chapterTitle = chapterTitle
        self.authorID = authorID
    }
}

public enum ReaderRenderedBlock: Hashable, Identifiable, Sendable {
    case text(String, chapterTitle: String?)
    case image(URL, chapterTitle: String?)
    case footer(String)

    public var id: String {
        switch self {
        case let .text(text, chapterTitle):
            return "text:\(chapterTitle ?? ""):\(text.hashValue)"
        case let .image(url, chapterTitle):
            return "image:\(chapterTitle ?? ""):\(url.absoluteString)"
        case let .footer(text):
            return "footer:\(text)"
        }
    }

    public var chapterTitle: String? {
        switch self {
        case let .text(_, chapterTitle), let .image(_, chapterTitle):
            return chapterTitle
        case .footer:
            return nil
        }
    }
}

public struct ReaderRenderedPage: Hashable, Identifiable, Sendable {
    public var index: Int
    public var blocks: [ReaderRenderedBlock]

    public var id: Int { index }

    public init(index: Int, blocks: [ReaderRenderedBlock]) {
        self.index = index
        self.blocks = blocks
    }
}

public struct ReaderPaginationResult: Hashable, Sendable {
    public var pages: [ReaderRenderedPage]
    public var chapters: [ReaderChapter]

    public init(pages: [ReaderRenderedPage], chapters: [ReaderChapter]) {
        self.pages = pages
        self.chapters = chapters
    }
}

public struct ReaderContainerLayout: Hashable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    public static let zero = ReaderContainerLayout(width: 0, height: 0)
}
