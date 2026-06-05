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

public struct NovelChapterIdentity: Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct NovelTextSegmentIdentity: Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ReaderCharacterRange: Codable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = max(0, location)
        self.length = max(0, length)
    }

    public var upperBound: Int {
        location + length
    }
}

public struct ReaderSegmentSemantics: Codable, Hashable, Sendable {
    public var chapterIdentity: NovelChapterIdentity?
    public var textSegmentIdentity: NovelTextSegmentIdentity?
    public var chapterTitleRange: ReaderCharacterRange?

    public init(
        chapterIdentity: NovelChapterIdentity? = nil,
        textSegmentIdentity: NovelTextSegmentIdentity? = nil,
        chapterTitleRange: ReaderCharacterRange? = nil
    ) {
        self.chapterIdentity = chapterIdentity
        self.textSegmentIdentity = textSegmentIdentity
        self.chapterTitleRange = chapterTitleRange
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
    public static let schemaVersion = 3

    public var threadURL: URL
    public var view: Int
    public var maxView: Int
    public var resolvedAuthorID: String?
    public var contentSource: ReaderContentSource
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int
    public var segments: [ReaderSegment]
    public var segmentSources: [ReaderSegmentSource?]
    public var segmentSemantics: [ReaderSegmentSemantics?]
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
        segmentSemantics: [ReaderSegmentSemantics?]? = nil,
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
        self.segmentSemantics = segmentSemantics ?? Self.legacySegmentSemantics(
            segments: segments,
            segmentSources: self.segmentSources,
            threadURL: self.threadURL,
            view: self.view,
            contentSource: self.contentSource
        )
        self.fetchedAt = fetchedAt
    }

    public func source(forSegmentIndex index: Int) -> ReaderSegmentSource? {
        guard segmentSources.indices.contains(index) else { return nil }
        return segmentSources[index]
    }

    public func semantics(forSegmentIndex index: Int) -> ReaderSegmentSemantics? {
        guard segmentSemantics.indices.contains(index) else { return nil }
        return segmentSemantics[index]
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
        case segmentSemantics
        case fetchedAt
        case schemaVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let segments = try container.decode([ReaderSegment].self, forKey: .segments)
        let sourceValues = try container.decodeIfPresent([ReaderSegmentSource?].self, forKey: .segmentSources)
        let threadURL = try container.decode(URL.self, forKey: .threadURL)
        let view = try container.decode(Int.self, forKey: .view)
        let contentSource = try container.decodeIfPresent(ReaderContentSource.self, forKey: .contentSource) ?? .allPostsPage
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        let segmentSemantics = try container.decodeIfPresent([ReaderSegmentSemantics?].self, forKey: .segmentSemantics)
        let resolvedSemantics: [ReaderSegmentSemantics?]
        if let segmentSemantics {
            try Self.validate(
                segmentSemantics: segmentSemantics,
                segments: segments,
                requiresExplicitTextIdentities: schemaVersion != nil
            )
            resolvedSemantics = segmentSemantics
        } else {
            let sources = sourceValues ?? Array(repeating: nil, count: segments.count)
            resolvedSemantics = Self.legacySegmentSemantics(
                segments: segments,
                segmentSources: sources,
                threadURL: threadURL,
                view: view,
                contentSource: contentSource
            )
        }
        self.init(
            threadURL: threadURL,
            view: view,
            maxView: try container.decode(Int.self, forKey: .maxView),
            resolvedAuthorID: try container.decodeIfPresent(String.self, forKey: .resolvedAuthorID),
            contentSource: contentSource,
            retainedChapterCount: try container.decodeIfPresent(Int.self, forKey: .retainedChapterCount) ?? 0,
            filteredChapterCandidateCount: try container.decodeIfPresent(Int.self, forKey: .filteredChapterCandidateCount) ?? 0,
            segments: segments,
            segmentSources: sourceValues,
            segmentSemantics: resolvedSemantics,
            fetchedAt: try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast
        )
    }

    public func encode(to encoder: any Encoder) throws {
        try Self.validate(
            segmentSemantics: segmentSemantics,
            segments: segments,
            requiresExplicitTextIdentities: true
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(threadURL, forKey: .threadURL)
        try container.encode(view, forKey: .view)
        try container.encode(maxView, forKey: .maxView)
        try container.encodeIfPresent(resolvedAuthorID, forKey: .resolvedAuthorID)
        try container.encode(contentSource, forKey: .contentSource)
        try container.encode(retainedChapterCount, forKey: .retainedChapterCount)
        try container.encode(filteredChapterCandidateCount, forKey: .filteredChapterCandidateCount)
        try container.encode(segments, forKey: .segments)
        try container.encode(segmentSources, forKey: .segmentSources)
        try container.encode(segmentSemantics, forKey: .segmentSemantics)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }
}

extension ReaderPageDocument {
    static func legacySegmentSemantics(
        segments: [ReaderSegment],
        segmentSources: [ReaderSegmentSource?],
        threadURL: URL,
        view: Int,
        contentSource: ReaderContentSource
    ) -> [ReaderSegmentSemantics?] {
        var occurrenceByPostID: [String: Int] = [:]
        var sourceOccurrence = 0
        var textOccurrenceByChapter: [NovelChapterIdentity: Int] = [:]

        return segments.enumerated().map { index, segment in
            guard let chapterTitle = segment.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !chapterTitle.isEmpty else {
                return nil
            }
            let source = segmentSources.indices.contains(index) ? segmentSources[index] : nil
            let chapterIdentity: NovelChapterIdentity
            if let ownerPostID = source?.ownerPostID, !ownerPostID.isEmpty {
                let postOccurrence = occurrenceByPostID[ownerPostID] ?? 0
                occurrenceByPostID[ownerPostID] = postOccurrence + 1
                chapterIdentity = NovelChapterIdentity(rawValue: "post:\(ownerPostID)#chapter:\(postOccurrence)")
            } else {
                chapterIdentity = NovelChapterIdentity(
                    rawValue: "document:\(threadURL.absoluteString)#view:\(max(1, view))#source:\(contentSource.rawValue)#chapter:\(sourceOccurrence)"
                )
                sourceOccurrence += 1
            }

            switch segment {
            case let .text(text, _):
                let textOccurrence = textOccurrenceByChapter[chapterIdentity] ?? 0
                textOccurrenceByChapter[chapterIdentity] = textOccurrence + 1
                return ReaderSegmentSemantics(
                    chapterIdentity: chapterIdentity,
                    textSegmentIdentity: NovelTextSegmentIdentity(
                        rawValue: "\(chapterIdentity.rawValue)#text:\(textOccurrence)"
                    ),
                    chapterTitleRange: legacyChapterTitleRange(chapterTitle: chapterTitle, text: text)
                )
            case .image:
                return ReaderSegmentSemantics(chapterIdentity: chapterIdentity)
            }
        }
    }

    private static func legacyChapterTitleRange(chapterTitle: String, text: String) -> ReaderCharacterRange? {
        let normalizedTitle = ReaderChapterTitleNormalizer.normalize(chapterTitle)
        guard let normalizedTitle,
              !normalizedTitle.isEmpty,
              text.hasPrefix(normalizedTitle) else {
            return nil
        }
        return ReaderCharacterRange(location: 0, length: normalizedTitle.count)
    }

    private static func validate(
        segmentSemantics: [ReaderSegmentSemantics?],
        segments: [ReaderSegment],
        requiresExplicitTextIdentities: Bool
    ) throws {
        guard segmentSemantics.count == segments.count else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Reader segment semantics count does not match segments.")
            )
        }

        for (index, segment) in segments.enumerated() {
            let semantics = segmentSemantics[index]
            switch segment {
            case let .text(text, chapterTitle):
                if requiresExplicitTextIdentities,
                   chapterTitle != nil,
                   (semantics?.chapterIdentity == nil || semantics?.textSegmentIdentity == nil) {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: [], debugDescription: "Text segment is missing explicit semantic identity.")
                    )
                }
                if let range = semantics?.chapterTitleRange {
                    guard range.location >= 0,
                          range.length >= 0,
                          range.upperBound <= text.count else {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(codingPath: [], debugDescription: "Chapter title range is outside segment text.")
                        )
                    }
                }

            case .image:
                if semantics?.textSegmentIdentity != nil {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: [], debugDescription: "Image segment cannot carry a text segment identity.")
                    )
                }
            }
        }
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
    public static let schemaVersion = 2

    public var view: Int
    public var chapterIdentity: NovelChapterIdentity?
    public var textSegmentIdentity: NovelTextSegmentIdentity?
    public var displayedTextOffset: Int
    public var chapterOrdinal: Int
    public var chapterTitle: String?
    public var segmentIndex: Int
    public var segmentOffset: Int
    public var segmentProgress: Double
    public var authorID: String?
    public var readingModeHint: ReaderReadingMode

    public init(
        view: Int,
        chapterIdentity: NovelChapterIdentity? = nil,
        textSegmentIdentity: NovelTextSegmentIdentity? = nil,
        displayedTextOffset: Int? = nil,
        chapterOrdinal: Int,
        chapterTitle: String? = nil,
        segmentIndex: Int,
        segmentOffset: Int,
        segmentProgress: Double,
        authorID: String? = nil,
        readingModeHint: ReaderReadingMode
    ) {
        self.view = max(1, view)
        self.chapterIdentity = chapterIdentity
        self.textSegmentIdentity = textSegmentIdentity
        self.displayedTextOffset = max(0, displayedTextOffset ?? segmentOffset)
        self.chapterOrdinal = max(0, chapterOrdinal)
        self.chapterTitle = chapterTitle
        self.segmentIndex = max(0, segmentIndex)
        self.segmentOffset = max(0, segmentOffset)
        self.segmentProgress = min(max(segmentProgress, 0), 1)
        self.authorID = authorID
        self.readingModeHint = readingModeHint
    }
}

extension ReaderResumePoint {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case view
        case chapterIdentity
        case textSegmentIdentity
        case displayedTextOffset
        case chapterOrdinal
        case chapterTitle
        case segmentIndex
        case segmentOffset
        case segmentProgress
        case authorID
        case readingModeHint
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let segmentOffset = try container.decode(Int.self, forKey: .segmentOffset)
        self.init(
            view: try container.decode(Int.self, forKey: .view),
            chapterIdentity: try container.decodeIfPresent(NovelChapterIdentity.self, forKey: .chapterIdentity),
            textSegmentIdentity: try container.decodeIfPresent(NovelTextSegmentIdentity.self, forKey: .textSegmentIdentity),
            displayedTextOffset: try container.decodeIfPresent(Int.self, forKey: .displayedTextOffset) ?? segmentOffset,
            chapterOrdinal: try container.decode(Int.self, forKey: .chapterOrdinal),
            chapterTitle: try container.decodeIfPresent(String.self, forKey: .chapterTitle),
            segmentIndex: try container.decode(Int.self, forKey: .segmentIndex),
            segmentOffset: segmentOffset,
            segmentProgress: try container.decode(Double.self, forKey: .segmentProgress),
            authorID: try container.decodeIfPresent(String.self, forKey: .authorID),
            readingModeHint: try container.decode(ReaderReadingMode.self, forKey: .readingModeHint)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(view, forKey: .view)
        try container.encodeIfPresent(chapterIdentity, forKey: .chapterIdentity)
        try container.encodeIfPresent(textSegmentIdentity, forKey: .textSegmentIdentity)
        try container.encode(displayedTextOffset, forKey: .displayedTextOffset)
        try container.encode(chapterOrdinal, forKey: .chapterOrdinal)
        try container.encodeIfPresent(chapterTitle, forKey: .chapterTitle)
        try container.encode(segmentIndex, forKey: .segmentIndex)
        try container.encode(segmentOffset, forKey: .segmentOffset)
        try container.encode(segmentProgress, forKey: .segmentProgress)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encode(readingModeHint, forKey: .readingModeHint)
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

struct NovelTextDisplayValue: Hashable, Sendable {
    var text: String
    var chapterTitle: String?
    var startsAtParagraphBoundary: Bool
    var semantics: NovelTextDisplaySemantics
    var ranges: [ReaderRenderedTextRange]

    init(
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

public struct NovelTextViewportIndexPage: Hashable, Sendable {
    public var pageIndex: Int
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var ranges: [ReaderRenderedTextRange]
    public var externalBlocks: [NovelTextViewportExternalBlock]
    public var frozenGeometry: NovelTextViewportFrozenGeometry?
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        pageIndex: Int,
        documentView: Int,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        ranges: [ReaderRenderedTextRange],
        externalBlocks: [NovelTextViewportExternalBlock] = [],
        frozenGeometry: NovelTextViewportFrozenGeometry? = nil,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.pageIndex = max(0, pageIndex)
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.ranges = ranges
        self.externalBlocks = externalBlocks
        self.frozenGeometry = frozenGeometry
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportFrozenGeometry: Hashable, Sendable {
    public var documentStartOffset: Int
    public var documentEndOffset: Int
    public var documentClipMinY: CGFloat
    public var documentClipMaxY: CGFloat
    public var contentHeight: CGFloat
    public var pageLocalOriginY: CGFloat

    public init(
        documentStartOffset: Int,
        documentEndOffset: Int,
        documentClipMinY: CGFloat,
        documentClipMaxY: CGFloat,
        contentHeight: CGFloat,
        pageLocalOriginY: CGFloat? = nil
    ) {
        self.documentStartOffset = max(0, documentStartOffset)
        self.documentEndOffset = max(self.documentStartOffset, documentEndOffset)
        let minY = documentClipMinY.isFinite ? documentClipMinY : 0
        let maxY = documentClipMaxY.isFinite ? documentClipMaxY : minY
        self.documentClipMinY = min(minY, maxY)
        self.documentClipMaxY = max(minY, maxY)
        self.contentHeight = max(0, contentHeight.isFinite ? contentHeight : 0)
        self.pageLocalOriginY = pageLocalOriginY ?? self.documentClipMinY
    }

    public var clipHeight: CGFloat {
        max(0, documentClipMaxY - documentClipMinY)
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

public extension NovelTextViewportIndex {
    var readerChapters: [ReaderChapter] {
        chapters.map { chapter in
            ReaderChapter(
                ordinal: chapter.ordinal,
                title: chapter.title,
                startIndex: chapter.startPageIndex,
                chapterCommentTarget: chapter.chapterCommentTarget
            )
        }
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
    public var frozenFrame: NovelTextViewportExternalBlockFrame?
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        segmentIndex: Int,
        url: URL,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        frozenFrame: NovelTextViewportExternalBlockFrame? = nil,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.segmentIndex = max(0, segmentIndex)
        self.url = url
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.frozenFrame = frozenFrame
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelTextViewportExternalBlockFrame: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.width = max(0, width.isFinite ? width : 0)
        self.height = max(0, height.isFinite ? height : 0)
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
        viewportPage: NovelTextViewportIndexPage?
    ) {
        self.indexBuildCount = viewportContext?.diagnostics.indexBuildCount ?? 0
        self.visibleSurfaceLayoutPassCount = viewportContext != nil && viewportPage?.ranges.isEmpty == false ? 1 : 0
        self.perBlockTextKitDocumentCount = 0
        self.compatibilityTextDisplayValueCount = 0
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

public struct NovelTextViewportPageLayoutMetrics: Hashable, Sendable {
    public var pageIndex: Int
    public var textHeight: CGFloat?
    public var externalBlockHeight: CGFloat
    public var spacingHeight: CGFloat

    public init(
        pageIndex: Int,
        textHeight: CGFloat? = nil,
        externalBlockHeight: CGFloat = 0,
        spacingHeight: CGFloat = 0
    ) {
        self.pageIndex = max(0, pageIndex)
        self.textHeight = textHeight
        self.externalBlockHeight = max(0, externalBlockHeight)
        self.spacingHeight = max(0, spacingHeight)
    }

    public var contentHeight: CGFloat {
        max(0, textHeight ?? 0) + externalBlockHeight + spacingHeight
    }
}

public struct NovelTextViewportLayoutMetrics: Hashable, Sendable {
    public var pageMetrics: [Int: NovelTextViewportPageLayoutMetrics]

    public init(pageMetrics: [Int: NovelTextViewportPageLayoutMetrics] = [:]) {
        self.pageMetrics = pageMetrics
    }

    public func pageHeight(for pageIndex: Int) -> CGFloat? {
        pageMetrics[max(0, pageIndex)]?.contentHeight
    }
}

public struct NovelTextLayoutResult: Hashable, Sendable {
    public var viewportContext: NovelTextViewportContext
    public var viewportIndex: NovelTextViewportIndex
    public var layoutMetrics: NovelTextViewportLayoutMetrics

    public init(
        viewportContext: NovelTextViewportContext,
        viewportIndex: NovelTextViewportIndex,
        layoutMetrics: NovelTextViewportLayoutMetrics = NovelTextViewportLayoutMetrics()
    ) {
        self.viewportContext = viewportContext
        self.viewportIndex = viewportIndex
        self.layoutMetrics = layoutMetrics
    }
}

public struct NovelReaderSurfaceIdentity: Hashable, Sendable {
    public var generation: UInt64
    public var ordinal: Int

    public init(generation: UInt64, ordinal: Int) {
        self.generation = generation
        self.ordinal = max(0, ordinal)
    }
}

public enum NovelReaderSurfaceKind: Hashable, Sendable {
    case text
    case externalBlock
}

public struct NovelReaderSurface: Hashable, Sendable {
    public var identity: NovelReaderSurfaceIdentity
    public var kind: NovelReaderSurfaceKind
    public var documentView: Int
    public var chapterTitle: String?
    public var presentationSize: CGSize
    public var presentationSpacingAfter: CGFloat
    public var viewportPage: NovelTextViewportIndexPage

    public init(
        identity: NovelReaderSurfaceIdentity,
        kind: NovelReaderSurfaceKind,
        documentView: Int,
        chapterTitle: String?,
        presentationSize: CGSize,
        presentationSpacingAfter: CGFloat = 0,
        viewportPage: NovelTextViewportIndexPage
    ) {
        self.identity = identity
        self.kind = kind
        self.documentView = max(1, documentView)
        self.chapterTitle = chapterTitle
        self.presentationSize = presentationSize
        self.presentationSpacingAfter = max(0, presentationSpacingAfter)
        self.viewportPage = viewportPage
    }
}

public struct NovelReaderPresentationSpread: Hashable, Sendable {
    public var index: Int
    public var leftSurfaceIdentity: NovelReaderSurfaceIdentity
    public var rightSurfaceIdentity: NovelReaderSurfaceIdentity?
    public var chapterTitle: String?

    public init(
        index: Int,
        leftSurfaceIdentity: NovelReaderSurfaceIdentity,
        rightSurfaceIdentity: NovelReaderSurfaceIdentity?,
        chapterTitle: String?
    ) {
        self.index = max(0, index)
        self.leftSurfaceIdentity = leftSurfaceIdentity
        self.rightSurfaceIdentity = rightSurfaceIdentity
        self.chapterTitle = chapterTitle
    }
}

public struct NovelReaderReadingState: Hashable, Sendable {
    public var currentView: Int
    public var maxView: Int
    public var currentChapterTitle: String?
    public var currentPageIntraProgress: Double

    public init(
        currentView: Int,
        maxView: Int,
        currentChapterTitle: String?,
        currentPageIntraProgress: Double
    ) {
        self.currentView = max(1, currentView)
        self.maxView = max(self.currentView, maxView)
        self.currentChapterTitle = currentChapterTitle
        self.currentPageIntraProgress = min(max(currentPageIntraProgress, 0), 1)
    }
}

public struct NovelReaderPresentation: Hashable, Sendable {
    public var generation: UInt64
    public var revision: UInt64
    public var surfaces: [NovelReaderSurface]
    public var selectedSurfaceIdentity: NovelReaderSurfaceIdentity?
    public var spreads: [NovelReaderPresentationSpread]
    public var committedSettings: ReaderAppearanceSettings
    public var readingState: NovelReaderReadingState
    public var currentContentSource: ReaderContentSource
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int

    public init(
        generation: UInt64,
        revision: UInt64,
        surfaces: [NovelReaderSurface],
        selectedSurfaceIdentity: NovelReaderSurfaceIdentity?,
        spreads: [NovelReaderPresentationSpread],
        committedSettings: ReaderAppearanceSettings,
        readingState: NovelReaderReadingState,
        currentContentSource: ReaderContentSource,
        retainedChapterCount: Int,
        filteredChapterCandidateCount: Int
    ) {
        self.generation = generation
        self.revision = revision
        self.surfaces = surfaces
        self.selectedSurfaceIdentity = selectedSurfaceIdentity
        self.spreads = spreads
        self.committedSettings = committedSettings
        self.readingState = readingState
        self.currentContentSource = currentContentSource
        self.retainedChapterCount = max(0, retainedChapterCount)
        self.filteredChapterCandidateCount = max(0, filteredChapterCandidateCount)
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

    public func novelTextBoxLayout(
        settings: ReaderAppearanceSettings,
        usesPadPresentation: Bool
    ) -> ReaderContainerLayout {
        guard settings.readingMode == .paged,
              settings.showsTwoPagesInLandscapeOnPad,
              usesPadPresentation,
              width > height else {
            return self
        }

        return ReaderContainerLayout(
            containerSize: CGSize(width: width / 2, height: height),
            safeAreaInsets: ReaderLayoutInsets(
                top: safeAreaInsets.top,
                bottom: safeAreaInsets.bottom
            ),
            contentInsets: contentInsets,
            chromeInsets: chromeInsets,
            readingMode: readingMode
        )
    }
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
