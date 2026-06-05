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
    public var initialResumePoint: ReaderResumePoint?

    public var id: String { threadURL.absoluteString }

    public init(
        threadURL: URL,
        threadTitle: String,
        source: ReaderLaunchSource,
        initialView: Int? = nil,
        initialPage: Int? = nil,
        authorID: String? = nil,
        initialResumePoint: ReaderResumePoint? = nil
    ) {
        self.threadURL = threadURL
        self.threadTitle = threadTitle
        self.source = source
        self.initialView = initialView
        self.initialPage = initialPage
        self.authorID = authorID
        self.initialResumePoint = initialResumePoint
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

    public var chapterTitle: String? {
        switch self {
        case let .text(_, chapterTitle), let .image(_, chapterTitle):
            return chapterTitle
        }
    }
}

public struct ReaderSegmentSource: Codable, Hashable, Sendable {
    public var ownerPostID: String?

    public init(ownerPostID: String? = nil) {
        self.ownerPostID = ownerPostID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.ownerPostID?.isEmpty == true {
            self.ownerPostID = nil
        }
    }
}

public struct ReaderChapterCommentTarget: Codable, Hashable, Sendable {
    public var threadURL: URL
    public var view: Int
    public var ownerPostID: String
    public var title: String?
    public var authorID: String?

    public init(threadURL: URL, view: Int, ownerPostID: String, title: String? = nil, authorID: String? = nil) {
        self.threadURL = threadURL
        self.view = max(1, view)
        self.ownerPostID = ownerPostID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title
        self.authorID = authorID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.authorID?.isEmpty == true {
            self.authorID = nil
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
    public var segmentSources: [ReaderSegmentSource?]
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
        segmentSources: [ReaderSegmentSource?]? = nil,
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
        self.segmentSources = segmentSources ?? Array(repeating: nil, count: segments.count)
        self.fetchedAt = fetchedAt
    }

    public func source(forSegmentIndex index: Int) -> ReaderSegmentSource? {
        guard segmentSources.indices.contains(index) else { return nil }
        return segmentSources[index]
    }
}

extension ReaderPageDocument {
    private enum CodingKeys: String, CodingKey {
        case threadURL
        case view
        case maxView
        case resolvedAuthorID
        case contentSource
        case retainedChapterCount
        case filteredChapterCandidateCount
        case segments
        case segmentSources
        case fetchedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let segments = try container.decode([ReaderSegment].self, forKey: .segments)
        self.init(
            threadURL: try container.decode(URL.self, forKey: .threadURL),
            view: try container.decode(Int.self, forKey: .view),
            maxView: try container.decode(Int.self, forKey: .maxView),
            resolvedAuthorID: try container.decodeIfPresent(String.self, forKey: .resolvedAuthorID),
            contentSource: try container.decodeIfPresent(ReaderContentSource.self, forKey: .contentSource) ?? .allPostsPage,
            retainedChapterCount: try container.decodeIfPresent(Int.self, forKey: .retainedChapterCount) ?? 0,
            filteredChapterCandidateCount: try container.decodeIfPresent(Int.self, forKey: .filteredChapterCandidateCount) ?? 0,
            segments: segments,
            segmentSources: try container.decodeIfPresent([ReaderSegmentSource?].self, forKey: .segmentSources),
            fetchedAt: try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(threadURL, forKey: .threadURL)
        try container.encode(view, forKey: .view)
        try container.encode(maxView, forKey: .maxView)
        try container.encodeIfPresent(resolvedAuthorID, forKey: .resolvedAuthorID)
        try container.encode(contentSource, forKey: .contentSource)
        try container.encode(retainedChapterCount, forKey: .retainedChapterCount)
        try container.encode(filteredChapterCandidateCount, forKey: .filteredChapterCandidateCount)
        try container.encode(segments, forKey: .segments)
        try container.encode(segmentSources, forKey: .segmentSources)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }
}

public struct ReaderChapter: Codable, Hashable, Sendable {
    public var ordinal: Int
    public var title: String
    public var startIndex: Int
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        ordinal: Int,
        title: String,
        startIndex: Int,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.ordinal = max(0, ordinal)
        self.title = title
        self.startIndex = startIndex
        self.chapterCommentTarget = chapterCommentTarget
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
        self.view = max(1, view)
        self.page = max(0, page)
        self.chapterTitle = resumePoint?.chapterTitle ?? chapterTitle
        self.authorID = resumePoint?.authorID ?? authorID
        self.resumePoint = resumePoint
    }
}

public struct NovelTextDisplaySemantics: Hashable, Sendable {
    public var fontScale: Double
    public var fontFamily: ReaderFontFamily
    public var lineHeightScale: Double
    public var characterSpacingScale: Double
    public var indentsParagraphFirstLine: Bool
    public var usesJustifiedText: Bool

    public init(settings: ReaderAppearanceSettings) {
        self.fontScale = settings.fontScale
        self.fontFamily = settings.fontFamily
        self.lineHeightScale = settings.lineHeightScale
        self.characterSpacingScale = settings.characterSpacingScale
        self.indentsParagraphFirstLine = settings.indentsParagraphFirstLine
        self.usesJustifiedText = settings.usesJustifiedText
    }
}

public struct NovelTextDisplayValue: Hashable, Sendable {
    public var text: String
    public var chapterTitle: String?
    public var startsAtParagraphBoundary: Bool
    public var semantics: NovelTextDisplaySemantics
    public var ranges: [ReaderRenderedTextRange]

    public init(
        text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings = ReaderAppearanceSettings(),
        ranges: [ReaderRenderedTextRange] = []
    ) {
        self.text = text
        self.chapterTitle = chapterTitle
        self.startsAtParagraphBoundary = startsAtParagraphBoundary
        self.semantics = NovelTextDisplaySemantics(settings: settings)
        self.ranges = ranges
    }

}

public enum ReaderRenderedBlock: Hashable, Identifiable, Sendable {
    case text(displayValue: NovelTextDisplayValue)
    case image(URL, chapterTitle: String?)
    case footer(String)

    public var id: String {
        switch self {
        case let .text(displayValue):
            return "text:\(displayValue.chapterTitle ?? ""):\(displayValue.startsAtParagraphBoundary):\(displayValue.text.hashValue)"
        case let .image(url, chapterTitle):
            return "image:\(chapterTitle ?? ""):\(url.absoluteString)"
        case let .footer(text):
            return "footer:\(text)"
        }
    }

    public var chapterTitle: String? {
        switch self {
        case let .text(displayValue):
            return displayValue.chapterTitle
        case let .image(_, chapterTitle):
            return chapterTitle
        case .footer:
            return nil
        }
    }

    public var isTextBlock: Bool {
        if case .text = self {
            return true
        }
        return false
    }

    public var textContent: String? {
        if case let .text(displayValue) = self {
            return displayValue.text
        }
        return nil
    }

    public var startsAtParagraphBoundary: Bool {
        if case let .text(displayValue) = self {
            return displayValue.startsAtParagraphBoundary
        }
        return false
    }

    public var novelTextDisplayValue: NovelTextDisplayValue? {
        if case let .text(displayValue) = self {
            return displayValue
        }
        return nil
    }

    public static func text(
        _ text: String,
        chapterTitle: String?,
        startsAtParagraphBoundary: Bool = true,
        settings: ReaderAppearanceSettings = ReaderAppearanceSettings(),
        ranges: [ReaderRenderedTextRange] = []
    ) -> ReaderRenderedBlock {
        .text(
            displayValue: NovelTextDisplayValue(
                text: text,
                chapterTitle: chapterTitle,
                startsAtParagraphBoundary: startsAtParagraphBoundary,
                settings: settings,
                ranges: ranges
            )
        )
    }
}

public struct ReaderRenderedTextRange: Hashable, Sendable {
    public var segmentIndex: Int
    public var startOffset: Int
    public var endOffset: Int

    public init(segmentIndex: Int, startOffset: Int, endOffset: Int) {
        self.segmentIndex = max(0, segmentIndex)
        self.startOffset = max(0, startOffset)
        self.endOffset = max(self.startOffset, endOffset)
    }

    public var length: Int {
        max(endOffset - startOffset, 0)
    }
}

public struct ReaderRenderedPage: Hashable, Identifiable, Sendable {
    public var index: Int
    public var blocks: [ReaderRenderedBlock]
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public var id: Int { index }

    public init(
        index: Int,
        blocks: [ReaderRenderedBlock],
        documentView: Int = 1,
        chapterOrdinal: Int? = nil,
        chapterTitle: String? = nil,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.index = index
        self.blocks = blocks
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportIndexPage: Hashable, Sendable {
    public var pageIndex: Int
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var ranges: [ReaderRenderedTextRange]
    public var externalBlocks: [NovelTextViewportExternalBlock]
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        pageIndex: Int,
        documentView: Int,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        ranges: [ReaderRenderedTextRange],
        externalBlocks: [NovelTextViewportExternalBlock] = [],
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.pageIndex = max(0, pageIndex)
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.ranges = ranges
        self.externalBlocks = externalBlocks
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportIndexChapter: Hashable, Sendable {
    public var ordinal: Int
    public var title: String
    public var startPageIndex: Int
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        ordinal: Int,
        title: String,
        startPageIndex: Int,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.ordinal = max(0, ordinal)
        self.title = title
        self.startPageIndex = max(0, startPageIndex)
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportIndexPosition: Hashable, Sendable {
    public var pageIndex: Int
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var range: ReaderRenderedTextRange
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        pageIndex: Int,
        documentView: Int,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        range: ReaderRenderedTextRange,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.pageIndex = max(0, pageIndex)
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.range = range
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportSample: Hashable, Sendable {
    public var documentView: Int
    public var pageIndex: Int
    public var segmentIndex: Int
    public var segmentOffset: Int

    public init(documentView: Int, pageIndex: Int, segmentIndex: Int, segmentOffset: Int) {
        self.documentView = max(1, documentView)
        self.pageIndex = max(0, pageIndex)
        self.segmentIndex = max(0, segmentIndex)
        self.segmentOffset = max(0, segmentOffset)
    }
}

public struct NovelTextViewportIndex: Hashable, Sendable {
    public var documentView: Int
    public var readingMode: ReaderReadingMode
    public var pages: [NovelTextViewportIndexPage]
    public var chapters: [NovelTextViewportIndexChapter]

    public init(
        documentView: Int,
        readingMode: ReaderReadingMode,
        pages: [NovelTextViewportIndexPage],
        chapters: [NovelTextViewportIndexChapter]
    ) {
        self.documentView = max(1, documentView)
        self.readingMode = readingMode
        self.pages = pages
        self.chapters = chapters
    }

    public func position(forSegmentIndex segmentIndex: Int, offset: Int) -> NovelTextViewportIndexPosition? {
        let normalizedSegmentIndex = max(0, segmentIndex)
        let normalizedOffset = max(0, offset)
        for page in pages {
            if let range = page.ranges.first(where: { range in
                range.segmentIndex == normalizedSegmentIndex && range.contains(offset: normalizedOffset)
            }) {
                return NovelTextViewportIndexPosition(
                    pageIndex: page.pageIndex,
                    documentView: page.documentView,
                    chapterOrdinal: page.chapterOrdinal,
                    chapterTitle: page.chapterTitle,
                    range: range,
                    chapterCommentTarget: page.chapterCommentTarget
                )
            }
        }

        let candidates = pages.flatMap { page in
            page.ranges
                .filter { $0.segmentIndex == normalizedSegmentIndex }
                .map { range in (page: page, range: range) }
        }
        guard let nearest = candidates.min(by: {
            $0.range.distance(toOffset: normalizedOffset) < $1.range.distance(toOffset: normalizedOffset)
        }) else {
            return nil
        }
        return NovelTextViewportIndexPosition(
            pageIndex: nearest.page.pageIndex,
            documentView: nearest.page.documentView,
            chapterOrdinal: nearest.page.chapterOrdinal,
            chapterTitle: nearest.page.chapterTitle,
            range: nearest.range,
            chapterCommentTarget: nearest.page.chapterCommentTarget
        )
    }
}

public struct NovelTextViewportIdentity: Hashable, Sendable {
    public var threadURL: URL
    public var documentView: Int
    public var maxView: Int
    public var fetchedAt: Date
    public var contentSource: ReaderContentSource
    public var appearance: ReaderAppearanceSettings
    public var layout: ReaderContainerLayout

    public init(
        threadURL: URL,
        documentView: Int,
        maxView: Int,
        fetchedAt: Date,
        contentSource: ReaderContentSource,
        appearance: ReaderAppearanceSettings,
        layout: ReaderContainerLayout
    ) {
        self.threadURL = threadURL
        self.documentView = max(1, documentView)
        self.maxView = max(self.documentView, maxView)
        self.fetchedAt = fetchedAt
        self.contentSource = contentSource
        self.appearance = appearance
        self.layout = layout
    }
}

public struct NovelTextViewportDocument: Hashable, Sendable {
    public var text: String
    public var textRangesBySegment: [Int: ReaderRenderedTextRange]
    public var insertedSeparatorRanges: [ReaderRenderedTextRange]

    public init(
        text: String,
        textRangesBySegment: [Int: ReaderRenderedTextRange],
        insertedSeparatorRanges: [ReaderRenderedTextRange]
    ) {
        self.text = text
        self.textRangesBySegment = textRangesBySegment
        self.insertedSeparatorRanges = insertedSeparatorRanges
    }
}

public struct NovelTextViewportExternalBlock: Hashable, Sendable {
    public var segmentIndex: Int
    public var url: URL
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        segmentIndex: Int,
        url: URL,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.segmentIndex = max(0, segmentIndex)
        self.url = url
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportDiagnostics: Hashable, Sendable {
    public var indexBuildCount: Int
    public var visibleLayoutPassCount: Int
    public var compatibilityRenderedPageCount: Int
    public var compatibilityTextDisplayValueCount: Int

    public init(
        indexBuildCount: Int,
        visibleLayoutPassCount: Int = 0,
        compatibilityRenderedPageCount: Int = 0,
        compatibilityTextDisplayValueCount: Int = 0
    ) {
        self.indexBuildCount = max(0, indexBuildCount)
        self.visibleLayoutPassCount = max(0, visibleLayoutPassCount)
        self.compatibilityRenderedPageCount = max(0, compatibilityRenderedPageCount)
        self.compatibilityTextDisplayValueCount = max(0, compatibilityTextDisplayValueCount)
    }
}

public struct NovelTextViewportVisibleSurfaceDiagnostics: Hashable, Sendable {
    public var indexBuildCount: Int
    public var visibleSurfaceLayoutPassCount: Int
    public var perBlockTextKitDocumentCount: Int
    public var compatibilityTextDisplayValueCount: Int
    public var usesSharedViewportContext: Bool

    public init(
        viewportContext: NovelTextViewportContext?,
        viewportPage: NovelTextViewportIndexPage?,
        compatibilityBlocks: [ReaderRenderedBlock]
    ) {
        self.indexBuildCount = viewportContext?.diagnostics.indexBuildCount ?? 0
        self.visibleSurfaceLayoutPassCount = viewportContext != nil && viewportPage?.ranges.isEmpty == false ? 1 : 0
        self.perBlockTextKitDocumentCount = compatibilityBlocks.compactMap(\.novelTextDisplayValue).count
        self.compatibilityTextDisplayValueCount = compatibilityBlocks.compactMap(\.novelTextDisplayValue).count
        self.usesSharedViewportContext = viewportContext != nil && viewportPage?.ranges.isEmpty == false
    }
}

public struct NovelTextViewportContext: Hashable, Sendable {
    public var identity: NovelTextViewportIdentity
    public var document: NovelTextViewportDocument
    public var externalBlocks: [NovelTextViewportExternalBlock]
    public var diagnostics: NovelTextViewportDiagnostics

    public init(
        identity: NovelTextViewportIdentity,
        document: NovelTextViewportDocument,
        externalBlocks: [NovelTextViewportExternalBlock],
        diagnostics: NovelTextViewportDiagnostics
    ) {
        self.identity = identity
        self.document = document
        self.externalBlocks = externalBlocks
        self.diagnostics = diagnostics
    }
}

public struct NovelTextLayoutResult: Hashable, Sendable {
    public var viewportContext: NovelTextViewportContext
    public var viewportIndex: NovelTextViewportIndex
    public var compatibilityPages: [ReaderRenderedPage]
    public var compatibilityChapters: [ReaderChapter]

    public var compatibility: ReaderPaginationResult {
        ReaderPaginationResult(
            pages: compatibilityPages,
            chapters: compatibilityChapters,
            viewportIndex: viewportIndex,
            viewportContext: viewportContext
        )
    }

    public init(
        viewportContext: NovelTextViewportContext,
        viewportIndex: NovelTextViewportIndex,
        compatibilityPages: [ReaderRenderedPage],
        compatibilityChapters: [ReaderChapter]
    ) {
        self.viewportContext = viewportContext
        self.viewportIndex = viewportIndex
        self.compatibilityPages = compatibilityPages
        self.compatibilityChapters = compatibilityChapters
    }
}

public struct ReaderPaginationResult: Hashable, Sendable {
    public var pages: [ReaderRenderedPage]
    public var chapters: [ReaderChapter]
    public var viewportIndex: NovelTextViewportIndex?
    public var viewportContext: NovelTextViewportContext?

    public init(
        pages: [ReaderRenderedPage],
        chapters: [ReaderChapter],
        viewportIndex: NovelTextViewportIndex? = nil,
        viewportContext: NovelTextViewportContext? = nil
    ) {
        self.pages = pages
        self.chapters = chapters
        self.viewportIndex = viewportIndex
        self.viewportContext = viewportContext
    }
}

private extension ReaderRenderedTextRange {
    func contains(offset: Int) -> Bool {
        if startOffset == endOffset {
            return offset <= startOffset
        }
        return offset >= startOffset && offset < endOffset
    }

    func distance(toOffset offset: Int) -> Int {
        if contains(offset: offset) {
            return 0
        }
        if offset < startOffset {
            return startOffset - offset
        }
        return offset - endOffset
    }
}

public struct ReaderContainerLayout: Hashable, Sendable {
    public var containerSize: CGSize
    public var safeAreaInsets: ReaderLayoutInsets
    public var contentInsets: ReaderLayoutInsets
    public var chromeInsets: ReaderLayoutInsets
    public var readingMode: ReaderReadingMode

    public init(
        width: CGFloat,
        height: CGFloat,
        safeAreaInsets: ReaderLayoutInsets = .zero,
        contentInsets: ReaderLayoutInsets = .zero,
        chromeInsets: ReaderLayoutInsets = .zero,
        readingMode: ReaderReadingMode = .paged
    ) {
        self.init(
            containerSize: CGSize(width: width, height: height),
            safeAreaInsets: safeAreaInsets,
            contentInsets: contentInsets,
            chromeInsets: chromeInsets,
            readingMode: readingMode
        )
    }

    public init(
        containerSize: CGSize,
        safeAreaInsets: ReaderLayoutInsets = .zero,
        contentInsets: ReaderLayoutInsets = .zero,
        chromeInsets: ReaderLayoutInsets = .zero,
        readingMode: ReaderReadingMode = .paged
    ) {
        self.containerSize = containerSize
        self.safeAreaInsets = safeAreaInsets
        self.contentInsets = contentInsets
        self.chromeInsets = chromeInsets
        self.readingMode = readingMode
    }

    public var width: CGFloat { containerSize.width }
    public var height: CGFloat { containerSize.height }

    public var readableFrame: CGRect {
        let totalInsets = safeAreaInsets + contentInsets + chromeInsets
        let width = max(0, containerSize.width - totalInsets.leading - totalInsets.trailing)
        let height = max(0, containerSize.height - totalInsets.top - totalInsets.bottom)
        return CGRect(
            x: totalInsets.leading,
            y: totalInsets.top,
            width: width,
            height: height
        )
    }

    public static let zero = ReaderContainerLayout(containerSize: .zero)
}

public struct ReaderLayoutInsets: Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        bottom: CGFloat = 0,
        trailing: CGFloat = 0
    ) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = ReaderLayoutInsets()
}

public func + (lhs: ReaderLayoutInsets, rhs: ReaderLayoutInsets) -> ReaderLayoutInsets {
    ReaderLayoutInsets(
        top: lhs.top + rhs.top,
        leading: lhs.leading + rhs.leading,
        bottom: lhs.bottom + rhs.bottom,
        trailing: lhs.trailing + rhs.trailing
    )
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
