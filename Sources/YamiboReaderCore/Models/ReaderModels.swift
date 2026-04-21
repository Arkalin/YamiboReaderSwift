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
    public var refreshPolicy: ReaderLaunchRefreshPolicy

    public var id: String { threadURL.absoluteString }

    public init(
        threadURL: URL,
        threadTitle: String,
        source: ReaderLaunchSource,
        initialView: Int? = nil,
        initialPage: Int? = nil,
        authorID: String? = nil,
        refreshPolicy: ReaderLaunchRefreshPolicy = .normal
    ) {
        self.threadURL = threadURL
        self.threadTitle = threadTitle
        self.source = source
        self.initialView = initialView
        self.initialPage = initialPage
        self.authorID = authorID
        self.refreshPolicy = refreshPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case threadURL
        case threadTitle
        case source
        case initialView
        case initialPage
        case authorID
        case refreshPolicy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadURL = try container.decode(URL.self, forKey: .threadURL)
        threadTitle = try container.decode(String.self, forKey: .threadTitle)
        source = try container.decode(ReaderLaunchSource.self, forKey: .source)
        initialView = try container.decodeIfPresent(Int.self, forKey: .initialView)
        initialPage = try container.decodeIfPresent(Int.self, forKey: .initialPage)
        authorID = try container.decodeIfPresent(String.self, forKey: .authorID)
        refreshPolicy = try container.decodeIfPresent(ReaderLaunchRefreshPolicy.self, forKey: .refreshPolicy) ?? .normal
    }
}

public enum ReaderLaunchRefreshPolicy: Codable, Hashable, Sendable {
    case normal
    case refreshKnownMaxView(view: Int)
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

    public var chapterTitle: String? {
        switch self {
        case let .text(_, chapterTitle), let .image(_, chapterTitle):
            return chapterTitle
        }
    }
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
    public var ordinal: Int
    public var title: String
    public var startIndex: Int

    public init(ordinal: Int, title: String, startIndex: Int) {
        self.ordinal = max(0, ordinal)
        self.title = title
        self.startIndex = startIndex
    }
}

public struct ReaderResumePoint: Codable, Hashable, Sendable {
    public var view: Int
    public var chapterOrdinal: Int
    public var chapterTitle: String?
    public var segmentIndex: Int
    public var segmentOffset: Int
    public var segmentProgress: Double
    public var authorID: String?
    public var readingModeHint: ReaderReadingMode

    public init(
        view: Int,
        chapterOrdinal: Int,
        chapterTitle: String? = nil,
        segmentIndex: Int,
        segmentOffset: Int,
        segmentProgress: Double,
        authorID: String? = nil,
        readingModeHint: ReaderReadingMode
    ) {
        self.view = max(1, view)
        self.chapterOrdinal = max(0, chapterOrdinal)
        self.chapterTitle = chapterTitle
        self.segmentIndex = max(0, segmentIndex)
        self.segmentOffset = max(0, segmentOffset)
        self.segmentProgress = min(max(segmentProgress, 0), 1)
        self.authorID = authorID
        self.readingModeHint = readingModeHint
    }
}

public struct ReaderProgress: Codable, Hashable, Sendable {
    public var view: Int
    public var page: Int
    public var chapterTitle: String?
    public var authorID: String?
    public var resumePoint: ReaderResumePoint?

    public init(
        view: Int,
        page: Int,
        chapterTitle: String? = nil,
        authorID: String? = nil,
        resumePoint: ReaderResumePoint? = nil
    ) {
        self.view = max(1, resumePoint?.view ?? view)
        self.page = max(0, page)
        self.chapterTitle = resumePoint?.chapterTitle ?? chapterTitle
        self.authorID = resumePoint?.authorID ?? authorID
        self.resumePoint = resumePoint
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
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var segmentIndex: Int?
    public var segmentStartOffset: Int
    public var segmentEndOffset: Int

    public var id: Int { index }

    public init(
        index: Int,
        blocks: [ReaderRenderedBlock],
        documentView: Int = 1,
        chapterOrdinal: Int? = nil,
        chapterTitle: String? = nil,
        segmentIndex: Int? = nil,
        segmentStartOffset: Int = 0,
        segmentEndOffset: Int = 0
    ) {
        self.index = index
        self.blocks = blocks
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.segmentIndex = segmentIndex
        self.segmentStartOffset = max(0, segmentStartOffset)
        self.segmentEndOffset = max(self.segmentStartOffset, segmentEndOffset)
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

public struct ReaderCacheBatchProgress: Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case running
        case completed
        case cancelled
    }

    public var totalCount: Int
    public var completedCount: Int
    public var currentView: Int?
    public var completedViews: [Int]
    public var failedViews: [Int]
    public var status: Status

    public init(
        totalCount: Int,
        completedCount: Int,
        currentView: Int?,
        completedViews: [Int],
        failedViews: [Int],
        status: Status
    ) {
        self.totalCount = totalCount
        self.completedCount = completedCount
        self.currentView = currentView
        self.completedViews = completedViews
        self.failedViews = failedViews
        self.status = status
    }
}

public struct ReaderCacheBatchResult: Hashable, Sendable {
    public var totalCount: Int
    public var completedViews: [Int]
    public var failedViews: [Int]
    public var wasCancelled: Bool

    public init(
        totalCount: Int,
        completedViews: [Int],
        failedViews: [Int],
        wasCancelled: Bool
    ) {
        self.totalCount = totalCount
        self.completedViews = completedViews
        self.failedViews = failedViews
        self.wasCancelled = wasCancelled
    }
}
