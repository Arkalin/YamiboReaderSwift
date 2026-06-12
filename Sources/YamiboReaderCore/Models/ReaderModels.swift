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
    public var authorID: String?
    public var initialResumePoint: ReaderResumePoint?

    public var id: String { threadURL.absoluteString }

    public init(
        threadURL: URL,
        threadTitle: String,
        source: ReaderLaunchSource,
        initialView: Int? = nil,
        authorID: String? = nil,
        initialResumePoint: ReaderResumePoint? = nil
    ) {
        self.threadURL = threadURL
        self.threadTitle = threadTitle
        self.source = source
        self.initialView = initialView
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
    public var isAuthorReplyToOther: Bool

    public init(ownerPostID: String? = nil, isAuthorReplyToOther: Bool = false) {
        self.ownerPostID = ownerPostID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.ownerPostID?.isEmpty == true {
            self.ownerPostID = nil
        }
        self.isAuthorReplyToOther = isAuthorReplyToOther
    }

    private enum CodingKeys: String, CodingKey {
        case ownerPostID
        case isAuthorReplyToOther
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ownerPostID: try container.decodeIfPresent(String.self, forKey: .ownerPostID),
            isAuthorReplyToOther: try container.decodeIfPresent(Bool.self, forKey: .isAuthorReplyToOther) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(ownerPostID, forKey: .ownerPostID)
        try container.encode(isAuthorReplyToOther, forKey: .isAuthorReplyToOther)
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

public enum ReaderInlineTextStyle: String, Codable, Hashable, Sendable {
    case bold
}

public struct ReaderInlineTextStyleRange: Codable, Hashable, Sendable {
    public var style: ReaderInlineTextStyle
    public var range: ReaderCharacterRange

    public init(style: ReaderInlineTextStyle, range: ReaderCharacterRange) {
        self.style = style
        self.range = range
    }
}

public struct ReaderSegmentSemantics: Hashable, Sendable {
    public var chapterIdentity: NovelChapterIdentity?
    public var textSegmentIdentity: NovelTextSegmentIdentity?
    public var chapterTitleRange: ReaderCharacterRange?
    public var inlineTextStyles: [ReaderInlineTextStyleRange]

    public init(
        chapterIdentity: NovelChapterIdentity? = nil,
        textSegmentIdentity: NovelTextSegmentIdentity? = nil,
        chapterTitleRange: ReaderCharacterRange? = nil,
        inlineTextStyles: [ReaderInlineTextStyleRange] = []
    ) {
        self.chapterIdentity = chapterIdentity
        self.textSegmentIdentity = textSegmentIdentity
        self.chapterTitleRange = chapterTitleRange
        self.inlineTextStyles = inlineTextStyles
    }
}

extension ReaderSegmentSemantics: Codable {
    private enum CodingKeys: String, CodingKey {
        case chapterIdentity
        case textSegmentIdentity
        case chapterTitleRange
        case inlineTextStyles
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            chapterIdentity: try container.decodeIfPresent(NovelChapterIdentity.self, forKey: .chapterIdentity),
            textSegmentIdentity: try container.decodeIfPresent(NovelTextSegmentIdentity.self, forKey: .textSegmentIdentity),
            chapterTitleRange: try container.decodeIfPresent(ReaderCharacterRange.self, forKey: .chapterTitleRange),
            inlineTextStyles: try container.decodeIfPresent([ReaderInlineTextStyleRange].self, forKey: .inlineTextStyles) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(chapterIdentity, forKey: .chapterIdentity)
        try container.encodeIfPresent(textSegmentIdentity, forKey: .textSegmentIdentity)
        try container.encodeIfPresent(chapterTitleRange, forKey: .chapterTitleRange)
        try container.encode(inlineTextStyles, forKey: .inlineTextStyles)
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
    public static let schemaVersion = 4

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
    public var decodedSchemaVersion: Int?

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
        fetchedAt: Date = .now,
        decodedSchemaVersion: Int? = Self.schemaVersion
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
        self.decodedSchemaVersion = decodedSchemaVersion
    }

    func source(forSegmentIndex index: Int) -> ReaderSegmentSource? {
        guard segmentSources.indices.contains(index) else { return nil }
        return segmentSources[index]
    }

    func semantics(forSegmentIndex index: Int) -> ReaderSegmentSemantics? {
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
            fetchedAt: try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? .distantPast,
            decodedSchemaVersion: schemaVersion
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
                for inlineStyle in semantics?.inlineTextStyles ?? [] {
                    let range = inlineStyle.range
                    guard range.location >= 0,
                          range.length >= 0,
                          range.upperBound <= text.count else {
                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(codingPath: [], debugDescription: "Inline text style range is outside segment text.")
                        )
                    }
                }

            case .image:
                if semantics?.textSegmentIdentity != nil {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: [], debugDescription: "Image segment cannot carry a text segment identity.")
                    )
                }
                if semantics?.inlineTextStyles.isEmpty == false {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: [], debugDescription: "Image segment cannot carry inline text styles.")
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
    public static let schemaVersion = 3

    public var view: Int
    public var chapterIdentity: NovelChapterIdentity?
    public var textSegmentIdentity: NovelTextSegmentIdentity?
    public var displayedTextOffset: Int
    public var chapterOrdinal: Int
    public var chapterTitle: String?
    public var segmentProgress: Double
    public var authorID: String?
    public var readingModeHint: ReaderReadingMode
    package var legacySegmentIndex: Int?
    package var legacySegmentOffset: Int?

    public init(
        view: Int,
        chapterIdentity: NovelChapterIdentity? = nil,
        textSegmentIdentity: NovelTextSegmentIdentity? = nil,
        displayedTextOffset: Int,
        chapterOrdinal: Int,
        chapterTitle: String? = nil,
        segmentProgress: Double,
        authorID: String? = nil,
        readingModeHint: ReaderReadingMode
    ) {
        self.view = max(1, view)
        self.chapterIdentity = chapterIdentity
        self.textSegmentIdentity = textSegmentIdentity
        self.displayedTextOffset = max(0, displayedTextOffset)
        self.chapterOrdinal = max(0, chapterOrdinal)
        self.chapterTitle = chapterTitle
        self.segmentProgress = min(max(segmentProgress, 0), 1)
        self.authorID = authorID
        self.readingModeHint = readingModeHint
        self.legacySegmentIndex = nil
        self.legacySegmentOffset = nil
    }

    package init(
        view: Int,
        chapterIdentity: NovelChapterIdentity? = nil,
        textSegmentIdentity: NovelTextSegmentIdentity? = nil,
        displayedTextOffset: Int,
        chapterOrdinal: Int,
        chapterTitle: String? = nil,
        segmentProgress: Double,
        authorID: String? = nil,
        readingModeHint: ReaderReadingMode,
        legacySegmentIndex: Int?,
        legacySegmentOffset: Int?
    ) {
        self.init(
            view: view,
            chapterIdentity: chapterIdentity,
            textSegmentIdentity: textSegmentIdentity,
            displayedTextOffset: displayedTextOffset,
            chapterOrdinal: chapterOrdinal,
            chapterTitle: chapterTitle,
            segmentProgress: segmentProgress,
            authorID: authorID,
            readingModeHint: readingModeHint
        )
        self.legacySegmentIndex = legacySegmentIndex.map { max(0, $0) }
        self.legacySegmentOffset = legacySegmentOffset.map { max(0, $0) }
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
        let legacySegmentIndex = try container.decodeIfPresent(Int.self, forKey: .segmentIndex)
        let legacySegmentOffset = try container.decodeIfPresent(Int.self, forKey: .segmentOffset)
        self.init(
            view: try container.decode(Int.self, forKey: .view),
            chapterIdentity: try container.decodeIfPresent(NovelChapterIdentity.self, forKey: .chapterIdentity),
            textSegmentIdentity: try container.decodeIfPresent(NovelTextSegmentIdentity.self, forKey: .textSegmentIdentity),
            displayedTextOffset: try container.decodeIfPresent(Int.self, forKey: .displayedTextOffset) ?? legacySegmentOffset ?? 0,
            chapterOrdinal: try container.decode(Int.self, forKey: .chapterOrdinal),
            chapterTitle: try container.decodeIfPresent(String.self, forKey: .chapterTitle),
            segmentProgress: try container.decode(Double.self, forKey: .segmentProgress),
            authorID: try container.decodeIfPresent(String.self, forKey: .authorID),
            readingModeHint: try container.decode(ReaderReadingMode.self, forKey: .readingModeHint),
            legacySegmentIndex: legacySegmentIndex,
            legacySegmentOffset: legacySegmentOffset
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
        if textSegmentIdentity == nil {
            try container.encodeIfPresent(legacySegmentIndex, forKey: .segmentIndex)
            try container.encodeIfPresent(legacySegmentOffset, forKey: .segmentOffset)
        }
        try container.encode(segmentProgress, forKey: .segmentProgress)
        try container.encodeIfPresent(authorID, forKey: .authorID)
        try container.encode(readingModeHint, forKey: .readingModeHint)
    }
}

package struct ReaderRenderedTextRange: Hashable, Sendable {
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

package struct NovelTextViewportIndexSurface: Hashable, Sendable {
    public var surfaceOrdinal: Int
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var ranges: [ReaderRenderedTextRange]
    public var externalBlocks: [NovelTextViewportExternalBlock]
    public var frozenGeometry: NovelTextViewportFrozenGeometry?
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        surfaceOrdinal: Int,
        documentView: Int,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        ranges: [ReaderRenderedTextRange],
        externalBlocks: [NovelTextViewportExternalBlock] = [],
        frozenGeometry: NovelTextViewportFrozenGeometry? = nil,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.surfaceOrdinal = max(0, surfaceOrdinal)
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.ranges = ranges
        self.externalBlocks = externalBlocks
        self.frozenGeometry = frozenGeometry
        self.chapterCommentTarget = chapterCommentTarget
    }
}

package struct NovelTextViewportFrozenGeometry: Hashable, Sendable {
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

    static func surfaceContentHeight(forDocumentClipRect clipRect: CGRect) -> CGFloat {
        max(0, clipRect.height.isFinite ? clipRect.height : 0)
    }
}

package struct NovelTextViewportIndexChapter: Hashable, Sendable {
    public var ordinal: Int
    public var title: String
    public var startSurfaceOrdinal: Int
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        ordinal: Int,
        title: String,
        startSurfaceOrdinal: Int,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.ordinal = max(0, ordinal)
        self.title = title
        self.startSurfaceOrdinal = max(0, startSurfaceOrdinal)
        self.chapterCommentTarget = chapterCommentTarget
    }
}

package struct NovelTextViewportIndexSurfacePosition: Hashable, Sendable {
    public var surfaceOrdinal: Int
    public var documentView: Int
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var range: ReaderRenderedTextRange
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        surfaceOrdinal: Int,
        documentView: Int,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        range: ReaderRenderedTextRange,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.surfaceOrdinal = max(0, surfaceOrdinal)
        self.documentView = max(1, documentView)
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.range = range
        self.chapterCommentTarget = chapterCommentTarget
    }
}

package struct NovelTextViewportSemanticTextPosition: Hashable, Sendable {
    public var chapterIdentity: NovelChapterIdentity?
    public var textSegmentIdentity: NovelTextSegmentIdentity
    public var displayedTextOffset: Int
    public var progressInTextRange: Double

    public init(
        chapterIdentity: NovelChapterIdentity?,
        textSegmentIdentity: NovelTextSegmentIdentity,
        displayedTextOffset: Int,
        progressInTextRange: Double
    ) {
        self.chapterIdentity = chapterIdentity
        self.textSegmentIdentity = textSegmentIdentity
        self.displayedTextOffset = max(0, displayedTextOffset)
        self.progressInTextRange = min(max(progressInTextRange, 0), 1)
    }
}

package struct NovelTextViewportSample: Hashable, Sendable {
    public var surfaceIdentity: NovelReaderSurfaceIdentity
    public var documentView: Int
    public var textSegmentIdentity: NovelTextSegmentIdentity
    public var displayedTextOffset: Int

    public init(
        surfaceIdentity: NovelReaderSurfaceIdentity,
        documentView: Int,
        textSegmentIdentity: NovelTextSegmentIdentity,
        displayedTextOffset: Int
    ) {
        self.surfaceIdentity = surfaceIdentity
        self.documentView = max(1, documentView)
        self.textSegmentIdentity = textSegmentIdentity
        self.displayedTextOffset = max(0, displayedTextOffset)
    }
}

package struct NovelTextViewportIndex: Hashable, Sendable {
    public var documentView: Int
    public var readingMode: ReaderReadingMode
    public var surfaces: [NovelTextViewportIndexSurface]
    public var chapters: [NovelTextViewportIndexChapter]

    public init(
        documentView: Int,
        readingMode: ReaderReadingMode,
        surfaces: [NovelTextViewportIndexSurface],
        chapters: [NovelTextViewportIndexChapter]
    ) {
        self.documentView = max(1, documentView)
        self.readingMode = readingMode
        self.surfaces = surfaces
        self.chapters = chapters
    }

    public func position(
        for textSegmentIdentity: NovelTextSegmentIdentity,
        displayedTextOffset: Int,
        in document: ReaderPageDocument
    ) -> NovelTextViewportIndexSurfacePosition? {
        guard document.view == documentView,
              let segmentIndex = document.segmentSemantics.firstIndex(where: {
                  $0?.textSegmentIdentity == textSegmentIdentity
              }) else {
            return nil
        }
        let normalizedSegmentIndex = max(0, segmentIndex)
        let normalizedOffset = max(0, displayedTextOffset)
        for surface in surfaces {
            if let range = surface.ranges.first(where: { range in
                range.segmentIndex == normalizedSegmentIndex && range.contains(offset: normalizedOffset)
            }) {
                return NovelTextViewportIndexSurfacePosition(
                    surfaceOrdinal: surface.surfaceOrdinal,
                    documentView: surface.documentView,
                    chapterOrdinal: surface.chapterOrdinal,
                    chapterTitle: surface.chapterTitle,
                    range: range,
                    chapterCommentTarget: surface.chapterCommentTarget
                )
            }
        }

        let candidates = surfaces.flatMap { surface in
            surface.ranges
                .filter { $0.segmentIndex == normalizedSegmentIndex }
                .map { range in (surface: surface, range: range) }
        }
        guard let nearest = candidates.min(by: {
            $0.range.distance(toOffset: normalizedOffset) < $1.range.distance(toOffset: normalizedOffset)
        }) else {
            return nil
        }
        return NovelTextViewportIndexSurfacePosition(
            surfaceOrdinal: nearest.surface.surfaceOrdinal,
            documentView: nearest.surface.documentView,
            chapterOrdinal: nearest.surface.chapterOrdinal,
            chapterTitle: nearest.surface.chapterTitle,
            range: nearest.range,
            chapterCommentTarget: nearest.surface.chapterCommentTarget
        )
    }
}

package extension NovelTextViewportIndex {
    var readerChapters: [ReaderChapter] {
        chapters.map { chapter in
            ReaderChapter(
                ordinal: chapter.ordinal,
                title: chapter.title,
                startIndex: chapter.startSurfaceOrdinal,
                chapterCommentTarget: chapter.chapterCommentTarget
            )
        }
    }
}

package extension NovelTextViewportIndexSurface {
    var containsText: Bool {
        !ranges.isEmpty
    }

    func semanticTextPosition(
        for intraSurfaceProgress: Double,
        in document: ReaderPageDocument
    ) -> NovelTextViewportSemanticTextPosition? {
        guard let rangePosition = textRangePosition(for: intraSurfaceProgress),
              let semantics = document.semantics(forSegmentIndex: rangePosition.range.segmentIndex),
              let textSegmentIdentity = semantics.textSegmentIdentity else {
            return nil
        }
        let range = rangePosition.range
        let offsetWithinSegment = range.length > 0
            ? Int((Double(range.length) * rangePosition.progressInRange).rounded(.towardZero))
            : 0
        return NovelTextViewportSemanticTextPosition(
            chapterIdentity: semantics.chapterIdentity,
            textSegmentIdentity: textSegmentIdentity,
            displayedTextOffset: range.startOffset + min(offsetWithinSegment, range.length),
            progressInTextRange: rangePosition.progressInRange
        )
    }

    func contains(
        textSegmentIdentity: NovelTextSegmentIdentity,
        in document: ReaderPageDocument
    ) -> Bool {
        ranges.contains { range in
            document.semantics(forSegmentIndex: range.segmentIndex)?.textSegmentIdentity == textSegmentIdentity
        }
    }

    func contains(
        textSegmentIdentity: NovelTextSegmentIdentity,
        displayedTextOffset: Int,
        in document: ReaderPageDocument
    ) -> Bool {
        ranges.contains { range in
            document.semantics(forSegmentIndex: range.segmentIndex)?.textSegmentIdentity == textSegmentIdentity &&
                range.contains(offset: displayedTextOffset)
        }
    }

    func contains(
        chapterIdentity: NovelChapterIdentity,
        in document: ReaderPageDocument
    ) -> Bool {
        ranges.contains { range in
            document.semantics(forSegmentIndex: range.segmentIndex)?.chapterIdentity == chapterIdentity
        } || externalBlocks.contains { block in
            block.chapterIdentity == chapterIdentity
        }
    }

    func distance(
        from displayedTextOffset: Int,
        textSegmentIdentity: NovelTextSegmentIdentity,
        in document: ReaderPageDocument
    ) -> Int {
        let matchingRanges = ranges.filter { range in
            document.semantics(forSegmentIndex: range.segmentIndex)?.textSegmentIdentity == textSegmentIdentity
        }
        guard !matchingRanges.isEmpty else { return Int.max }
        return matchingRanges.map { $0.distance(toOffset: displayedTextOffset) }.min() ?? Int.max
    }

    func intraSurfaceProgress(
        displayedTextOffset: Int,
        textSegmentIdentity: NovelTextSegmentIdentity,
        fallbackProgress: Double,
        in document: ReaderPageDocument
    ) -> Double {
        progress(
            matching: { range in
                document.semantics(forSegmentIndex: range.segmentIndex)?.textSegmentIdentity == textSegmentIdentity
            },
            offset: displayedTextOffset,
            fallbackProgress: fallbackProgress
        )
    }

    func sample(
        displayOffset: Int,
        in document: ReaderPageDocument
    ) -> NovelTextViewportSample? {
        guard !ranges.isEmpty else { return nil }
        let normalizedOffset = max(0, displayOffset)
        var runningOffset = 0

        for range in ranges {
            let length = max(range.length, 0)
            let rangeEnd = runningOffset + length
            if normalizedOffset <= rangeEnd {
                guard let textSegmentIdentity = document
                    .semantics(forSegmentIndex: range.segmentIndex)?
                    .textSegmentIdentity else {
                    return nil
                }
                return NovelTextViewportSample(
                    surfaceIdentity: NovelReaderSurfaceIdentity(
                        generation: 0,
                        ordinal: surfaceOrdinal
                    ),
                    documentView: document.view,
                    textSegmentIdentity: textSegmentIdentity,
                    displayedTextOffset: range.startOffset + min(max(normalizedOffset - runningOffset, 0), length)
                )
            }
            runningOffset = rangeEnd + 2
        }

        guard let lastRange = ranges.last,
              let textSegmentIdentity = document
                  .semantics(forSegmentIndex: lastRange.segmentIndex)?
                  .textSegmentIdentity else {
            return nil
        }
        return NovelTextViewportSample(
            surfaceIdentity: NovelReaderSurfaceIdentity(
                generation: 0,
                ordinal: surfaceOrdinal
            ),
            documentView: document.view,
            textSegmentIdentity: textSegmentIdentity,
            displayedTextOffset: lastRange.endOffset
        )
    }

    func displayOffset(
        for textSegmentIdentity: NovelTextSegmentIdentity,
        displayedTextOffset: Int,
        in document: ReaderPageDocument
    ) -> Int? {
        guard let segmentIndex = document.segmentSemantics.firstIndex(where: {
            $0?.textSegmentIdentity == textSegmentIdentity
        }) else {
            return nil
        }

        var runningOffset = 0
        let normalizedOffset = max(0, displayedTextOffset)

        for range in ranges {
            let length = max(range.length, 0)
            defer { runningOffset += length + 2 }
            guard range.segmentIndex == segmentIndex,
                  normalizedOffset >= range.startOffset,
                  normalizedOffset <= range.endOffset else {
                continue
            }
            return runningOffset + min(max(normalizedOffset - range.startOffset, 0), length)
        }

        return nil
    }

    func containsLegacyTextSegment(index legacySegmentIndex: Int) -> Bool {
        ranges.contains { $0.segmentIndex == legacySegmentIndex }
    }

    func containsLegacyTextSegment(index legacySegmentIndex: Int, offset legacySegmentOffset: Int) -> Bool {
        ranges.contains { range in
            range.segmentIndex == legacySegmentIndex && range.contains(offset: legacySegmentOffset)
        }
    }

    func distanceFromLegacyTextSegmentOffset(_ legacySegmentOffset: Int, index legacySegmentIndex: Int) -> Int {
        let matchingRanges = ranges.filter { $0.segmentIndex == legacySegmentIndex }
        guard !matchingRanges.isEmpty else { return Int.max }
        return matchingRanges.map { $0.distance(toOffset: legacySegmentOffset) }.min() ?? Int.max
    }

    func legacyIntraSurfaceProgress(
        segmentIndex legacySegmentIndex: Int,
        segmentOffset legacySegmentOffset: Int,
        fallbackProgress: Double
    ) -> Double {
        progress(
            matching: { $0.segmentIndex == legacySegmentIndex },
            offset: legacySegmentOffset,
            fallbackProgress: fallbackProgress
        )
    }

    private func textRangePosition(
        for intraSurfaceProgress: Double
    ) -> (range: ReaderRenderedTextRange, progressInRange: Double)? {
        guard !ranges.isEmpty else { return nil }
        guard ranges.count > 1 else {
            return ranges.first.map {
                (range: $0, progressInRange: min(max(intraSurfaceProgress, 0), 1))
            }
        }

        let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
        let targetOffset = Int((Double(totalLength) * min(max(intraSurfaceProgress, 0), 1)).rounded(.towardZero))
        var runningLength = 0

        for range in ranges {
            let length = max(range.length, 1)
            if targetOffset < runningLength + length {
                let progressInRange = Double(targetOffset - runningLength) / Double(length)
                return (
                    range: range,
                    progressInRange: min(max(progressInRange, 0), 1)
                )
            }
            runningLength += length
        }

        return ranges.last.map {
            (range: $0, progressInRange: 1)
        }
    }

    private func progress(
        matching predicate: (ReaderRenderedTextRange) -> Bool,
        offset: Int,
        fallbackProgress: Double
    ) -> Double {
        guard !ranges.isEmpty else {
            return min(max(fallbackProgress, 0), 1)
        }
        let totalLength = ranges.reduce(0) { $0 + max($1.length, 1) }
        var runningLength = 0

        for range in ranges {
            let length = max(range.length, 1)
            defer { runningLength += length }
            guard predicate(range) else { continue }
            let localOffset = min(max(offset - range.startOffset, 0), length)
            let progress = Double(runningLength + localOffset) / Double(max(totalLength, 1))
            return min(max(progress, 0), 1)
        }

        return min(max(fallbackProgress, 0), 1)
    }
}

package extension ReaderPageDocument {
    func previewSourceText(from position: NovelTextViewportSemanticTextPosition) -> String {
        guard let startSegmentIndex = segmentSemantics.firstIndex(where: {
            $0?.textSegmentIdentity == position.textSegmentIdentity
        }), segments.indices.contains(startSegmentIndex) else {
            return ""
        }

        let fragments = segments[startSegmentIndex...].enumerated().compactMap { offset, segment -> String? in
            guard case let .text(text, _) = segment else { return nil }
            let previewText = offset == 0
                ? String(text.dropFirst(min(max(position.displayedTextOffset, 0), text.count)))
                : text
            let trimmed = previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return fragments.joined(separator: "\n\n")
    }
}

package extension NovelTextViewportDocument {
    func validateOffsetMap(
        expectedTextBySegment: [Int: String]
    ) -> Bool {
        guard expectedTextBySegment.count == textRangesBySegment.count else {
            return false
        }
        for (segmentIndex, range) in textRangesBySegment {
            guard let expectedText = expectedTextBySegment[segmentIndex],
                  range.endOffset <= text.count,
                  let start = text.index(
                      text.startIndex,
                      offsetBy: range.startOffset,
                      limitedBy: text.endIndex
                  ),
                  let end = text.index(
                      text.startIndex,
                      offsetBy: range.endOffset,
                      limitedBy: text.endIndex
                  ),
                  String(text[start..<end]) == expectedText else {
                return false
            }
        }
        return true
    }

    func surfaceRanges(
        for surfaceRange: NovelTextViewportDocumentSurfaceRange
    ) -> [ReaderRenderedTextRange] {
        let sliceStart = max(0, surfaceRange.startOffset)
        let sliceEnd = max(sliceStart, surfaceRange.endOffset)
        guard sliceEnd > sliceStart else { return [] }

        return textRangesBySegment
            .sorted { $0.value.startOffset < $1.value.startOffset }
            .compactMap { segmentIndex, segmentRange in
                let intersectionStart = max(sliceStart, segmentRange.startOffset)
                let intersectionEnd = min(sliceEnd, segmentRange.endOffset)
                guard intersectionEnd > intersectionStart else { return nil }
                return ReaderRenderedTextRange(
                    segmentIndex: segmentIndex,
                    startOffset: intersectionStart - segmentRange.startOffset,
                    endOffset: intersectionEnd - segmentRange.startOffset
                )
            }
    }

    func semanticTextPosition(
        containingDocumentOffset documentOffset: Int,
        in document: ReaderPageDocument
    ) -> NovelTextViewportSemanticTextPosition? {
        guard let segmentRange = textRangesBySegment.first(where: { _, range in
            documentOffset >= range.startOffset && documentOffset <= range.endOffset
        }),
        let semantics = document.semantics(forSegmentIndex: segmentRange.key),
        let textSegmentIdentity = semantics.textSegmentIdentity else {
            return nil
        }

        return NovelTextViewportSemanticTextPosition(
            chapterIdentity: semantics.chapterIdentity,
            textSegmentIdentity: textSegmentIdentity,
            displayedTextOffset: documentOffset - segmentRange.value.startOffset,
            progressInTextRange: 0
        )
    }

    func documentOffset(
        for position: ReaderResumePoint,
        in document: ReaderPageDocument
    ) -> Int? {
        guard position.view == document.view else { return nil }
        if let textSegmentIdentity = position.textSegmentIdentity,
           let segmentRange = segmentRange(for: textSegmentIdentity, in: document) {
            return segmentRange.startOffset + min(
                max(position.displayedTextOffset, 0),
                segmentRange.length
            )
        }
        guard let legacySegmentIndex = position.legacySegmentIndex,
              let segmentRange = textRangesBySegment[legacySegmentIndex] else {
            return nil
        }
        return segmentRange.startOffset + min(
            max(position.displayedTextOffset, 0),
            segmentRange.length
        )
    }

    func documentOffset(forSurfaceRange range: ReaderRenderedTextRange) -> Int? {
        guard let segmentRange = textRangesBySegment[range.segmentIndex],
              range.startOffset >= 0,
              range.startOffset <= segmentRange.length else {
            return nil
        }
        return segmentRange.startOffset + range.startOffset
    }

    func documentOffsets(forSurfaceRange range: ReaderRenderedTextRange) -> Range<Int>? {
        guard let segmentRange = textRangesBySegment[range.segmentIndex],
              range.startOffset >= 0,
              range.endOffset >= range.startOffset,
              range.endOffset <= segmentRange.length else {
            return nil
        }
        return (segmentRange.startOffset + range.startOffset)..<(segmentRange.startOffset + range.endOffset)
    }

    func text(forSurfaceRange range: ReaderRenderedTextRange) -> String? {
        guard let documentOffsets = documentOffsets(forSurfaceRange: range),
              documentOffsets.upperBound > documentOffsets.lowerBound,
              documentOffsets.upperBound <= text.count,
              let startIndex = text.index(text.startIndex, offsetBy: documentOffsets.lowerBound, limitedBy: text.endIndex),
              let endIndex = text.index(text.startIndex, offsetBy: documentOffsets.upperBound, limitedBy: text.endIndex) else {
            return nil
        }
        return String(text[startIndex..<endIndex])
    }

    func text(forSurface surface: NovelTextViewportIndexSurface) -> String? {
        var fragments: [String] = []
        for range in surface.ranges {
            guard let fragment = text(forSurfaceRange: range) else {
                return nil
            }
            fragments.append(fragment)
        }
        let text = fragments.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    func startsAtParagraphBoundary(surface: NovelTextViewportIndexSurface) -> Bool {
        guard let firstRange = surface.ranges.first,
              firstRange.startOffset > 0,
              let globalStart = documentOffset(forSurfaceRange: firstRange) else {
            return true
        }
        return isParagraphBoundary(at: globalStart)
    }

    func sample(
        containingDocumentOffset documentOffset: Int,
        surfaceIdentity: NovelReaderSurfaceIdentity,
        documentView: Int,
        in document: ReaderPageDocument
    ) -> NovelTextViewportSample? {
        guard let position = semanticTextPosition(
            containingDocumentOffset: documentOffset,
            in: document
        ) else {
            return nil
        }
        return NovelTextViewportSample(
            surfaceIdentity: surfaceIdentity,
            documentView: documentView,
            textSegmentIdentity: position.textSegmentIdentity,
            displayedTextOffset: position.displayedTextOffset
        )
    }

    private func segmentRange(
        for textSegmentIdentity: NovelTextSegmentIdentity,
        in document: ReaderPageDocument
    ) -> ReaderRenderedTextRange? {
        guard let segmentIndex = document.segmentSemantics.firstIndex(where: {
            $0?.textSegmentIdentity == textSegmentIdentity
        }) else {
            return nil
        }
        return textRangesBySegment[segmentIndex]
    }

    private func isParagraphBoundary(at offset: Int) -> Bool {
        guard offset > 0, offset <= text.count else { return offset == 0 }
        let nsText = text as NSString
        var index = offset - 1
        var newlineCount = 0

        while index >= 0 {
            let character = nsText.substring(with: NSRange(location: index, length: 1))
            if character == "\n" || character == "\r" {
                newlineCount += 1
                if newlineCount >= 2 {
                    return true
                }
            } else if character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Keep scanning through spaces between the paragraph break and the first visible character.
            } else {
                return false
            }
            index -= 1
        }
        return true
    }
}

package extension NovelTextViewportIndexSurface {
    func nearestTextSample(
        toDocumentOffset documentOffset: Int,
        surfaceIdentity: NovelReaderSurfaceIdentity,
        viewportDocument: NovelTextViewportDocument,
        sourceDocument: ReaderPageDocument
    ) -> NovelTextViewportSample? {
        let candidates = ranges.compactMap { range -> (distance: Int, sample: NovelTextViewportSample)? in
            guard let documentRange = viewportDocument.documentOffsets(forSurfaceRange: range),
                  let semantics = sourceDocument.semantics(forSegmentIndex: range.segmentIndex),
                  let textSegmentIdentity = semantics.textSegmentIdentity else {
                return nil
            }
            let nearestOffset = min(max(documentOffset, documentRange.lowerBound), documentRange.upperBound)
            return (
                abs(documentOffset - nearestOffset),
                NovelTextViewportSample(
                    surfaceIdentity: surfaceIdentity,
                    documentView: documentView,
                    textSegmentIdentity: textSegmentIdentity,
                    displayedTextOffset: nearestOffset - documentRange.lowerBound + range.startOffset
                )
            )
        }

        return candidates.min { $0.distance < $1.distance }?.sample
    }
}

package struct NovelTextViewportIdentity: Hashable, Sendable {
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

package struct NovelTextViewportDocument: Hashable, Sendable {
    public var text: String
    public var textRangesBySegment: [Int: ReaderRenderedTextRange]
    public var insertedSeparatorRanges: [ReaderRenderedTextRange]
    public var inlineTextStylesBySegment: [Int: [ReaderInlineTextStyleRange]]

    public init(
        text: String,
        textRangesBySegment: [Int: ReaderRenderedTextRange],
        insertedSeparatorRanges: [ReaderRenderedTextRange],
        inlineTextStylesBySegment: [Int: [ReaderInlineTextStyleRange]] = [:]
    ) {
        self.text = text
        self.textRangesBySegment = textRangesBySegment
        self.insertedSeparatorRanges = insertedSeparatorRanges
        self.inlineTextStylesBySegment = inlineTextStylesBySegment
    }
}

package struct NovelTextViewportExternalBlock: Hashable, Sendable {
    public var chapterIdentity: NovelChapterIdentity?
    public var url: URL
    public var chapterOrdinal: Int?
    public var chapterTitle: String?
    public var frozenFrame: NovelTextViewportExternalBlockFrame?
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        chapterIdentity: NovelChapterIdentity?,
        url: URL,
        chapterOrdinal: Int?,
        chapterTitle: String?,
        frozenFrame: NovelTextViewportExternalBlockFrame? = nil,
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.chapterIdentity = chapterIdentity
        self.url = url
        self.chapterOrdinal = chapterOrdinal
        self.chapterTitle = chapterTitle
        self.frozenFrame = frozenFrame
        self.chapterCommentTarget = chapterCommentTarget
    }
}

package struct NovelTextViewportExternalBlockFrame: Hashable, Sendable {
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

package struct NovelTextViewportDiagnostics: Hashable, Sendable {
    public var indexBuildCount: Int
    public var visibleLayoutPassCount: Int

    public init(
        indexBuildCount: Int,
        visibleLayoutPassCount: Int = 0
    ) {
        self.indexBuildCount = max(0, indexBuildCount)
        self.visibleLayoutPassCount = max(0, visibleLayoutPassCount)
    }
}

package struct NovelTextViewportContext: Hashable, Sendable {
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

package struct NovelTextViewportSurfaceLayoutMetrics: Hashable, Sendable {
    public var surfaceOrdinal: Int
    public var textHeight: CGFloat?
    public var externalBlockHeight: CGFloat
    public var spacingHeight: CGFloat

    public init(
        surfaceOrdinal: Int,
        textHeight: CGFloat? = nil,
        externalBlockHeight: CGFloat = 0,
        spacingHeight: CGFloat = 0
    ) {
        self.surfaceOrdinal = max(0, surfaceOrdinal)
        self.textHeight = textHeight
        self.externalBlockHeight = max(0, externalBlockHeight)
        self.spacingHeight = max(0, spacingHeight)
    }

    public var contentHeight: CGFloat {
        max(0, textHeight ?? 0) + externalBlockHeight + spacingHeight
    }
}

package struct NovelTextViewportLayoutMetrics: Hashable, Sendable {
    public var surfaceMetrics: [Int: NovelTextViewportSurfaceLayoutMetrics]

    public init(surfaceMetrics: [Int: NovelTextViewportSurfaceLayoutMetrics] = [:]) {
        self.surfaceMetrics = surfaceMetrics
    }

    public func surfaceHeight(for surfaceOrdinal: Int) -> CGFloat? {
        surfaceMetrics[max(0, surfaceOrdinal)]?.contentHeight
    }
}

package struct NovelTextLayoutResult: Hashable, Sendable {
    public var viewportContext: NovelTextViewportContext
    public var viewportIndex: NovelTextViewportIndex
    public var layoutMetrics: NovelTextViewportLayoutMetrics
    public var fingerprints: NovelTextLayoutFingerprints

    public init(
        viewportContext: NovelTextViewportContext,
        viewportIndex: NovelTextViewportIndex,
        layoutMetrics: NovelTextViewportLayoutMetrics = NovelTextViewportLayoutMetrics(),
        fingerprints: NovelTextLayoutFingerprints = NovelTextLayoutFingerprints()
    ) {
        self.viewportContext = viewportContext
        self.viewportIndex = viewportIndex
        self.layoutMetrics = layoutMetrics
        self.fingerprints = fingerprints
    }
}

package struct NovelTextLayoutFingerprints: Hashable, Sendable {
    public var semantic: String
    public var text: String
    public var layout: String
    public var font: String
    public var platform: String
    public var textKitImplementation: String

    public init(
        semantic: String = "",
        text: String = "",
        layout: String = "",
        font: String = "",
        platform: String = "",
        textKitImplementation: String = ""
    ) {
        self.semantic = semantic
        self.text = text
        self.layout = layout
        self.font = font
        self.platform = platform
        self.textKitImplementation = textKitImplementation
    }
}

public struct NovelReaderSurfaceIdentity: Hashable, Sendable {
    public var generation: UInt64
    package var ordinal: Int

    package init(generation: UInt64, ordinal: Int) {
        self.generation = generation
        self.ordinal = max(0, ordinal)
    }
}

public enum NovelReaderSurfaceKind: Hashable, Sendable {
    case text
    case externalBlock
}

public struct NovelReaderExternalBlock: Hashable, Sendable {
    public var url: URL
    public var frame: CGRect?

    public init(url: URL, frame: CGRect?) {
        self.url = url
        self.frame = frame
    }
}

public struct NovelReaderSurface: Hashable, Sendable {
    public var identity: NovelReaderSurfaceIdentity
    public var presentationIndex: Int
    public var kind: NovelReaderSurfaceKind
    public var documentView: Int
    public var chapterTitle: String?
    public var presentationSize: CGSize
    public var presentationSpacingAfter: CGFloat
    public var externalBlocks: [NovelReaderExternalBlock]
    public var chapterCommentTarget: ReaderChapterCommentTarget?

    public init(
        identity: NovelReaderSurfaceIdentity,
        presentationIndex: Int = 0,
        kind: NovelReaderSurfaceKind,
        documentView: Int,
        chapterTitle: String?,
        presentationSize: CGSize,
        presentationSpacingAfter: CGFloat = 0,
        externalBlocks: [NovelReaderExternalBlock] = [],
        chapterCommentTarget: ReaderChapterCommentTarget? = nil
    ) {
        self.identity = identity
        self.presentationIndex = max(0, presentationIndex)
        self.kind = kind
        self.documentView = max(1, documentView)
        self.chapterTitle = chapterTitle
        self.presentationSize = presentationSize
        self.presentationSpacingAfter = max(0, presentationSpacingAfter)
        self.externalBlocks = externalBlocks
        self.chapterCommentTarget = chapterCommentTarget
    }
}

public struct NovelReaderPresentationSpread: Hashable, Sendable {
    public var index: Int
    public var leftSurfaceIndex: Int
    public var leftSurfaceIdentity: NovelReaderSurfaceIdentity
    public var rightSurfaceIndex: Int?
    public var rightSurfaceIdentity: NovelReaderSurfaceIdentity?
    public var chapterTitle: String?

    public init(
        index: Int,
        leftSurfaceIndex: Int = 0,
        leftSurfaceIdentity: NovelReaderSurfaceIdentity,
        rightSurfaceIndex: Int? = nil,
        rightSurfaceIdentity: NovelReaderSurfaceIdentity?,
        chapterTitle: String?
    ) {
        self.index = max(0, index)
        self.leftSurfaceIndex = max(0, leftSurfaceIndex)
        self.leftSurfaceIdentity = leftSurfaceIdentity
        self.rightSurfaceIndex = rightSurfaceIndex.map { max(0, $0) }
        self.rightSurfaceIdentity = rightSurfaceIdentity
        self.chapterTitle = chapterTitle
    }
}

public struct NovelReaderReadingState: Hashable, Sendable {
    public var currentView: Int
    public var maxView: Int
    public var currentChapterTitle: String?
    public var authorID: String?
    public var currentSurfaceIntraProgress: Double

    public init(
        currentView: Int,
        maxView: Int,
        currentChapterTitle: String?,
        authorID: String?,
        currentSurfaceIntraProgress: Double
    ) {
        self.currentView = max(1, currentView)
        self.maxView = max(self.currentView, maxView)
        self.currentChapterTitle = currentChapterTitle
        self.authorID = authorID
        self.currentSurfaceIntraProgress = min(max(currentSurfaceIntraProgress, 0), 1)
    }
}

public struct NovelReaderProgressProjection: Hashable, Sendable {
    public var readingMode: ReaderReadingMode
    public var usesTwoPageSpread: Bool
    public var surfaceCount: Int
    public var selectedSurfaceIndex: Int
    public var currentSurfaceNumber: Int
    public var displayedView: Int
    public var displayedPageIndex: Int
    public var displayedPageCount: Int
    public var displayedPageLabel: String
    public var currentProgressFraction: Double
    public var currentProgressPercent: Int
    public var currentProgressPercentText: String
    public var visibleSurfaceIndexes: [Int]
    public var fallbackVisibleSurfaceIndex: Int

    public init(
        readingMode: ReaderReadingMode,
        usesTwoPageSpread: Bool,
        surfaceCount: Int,
        selectedSurfaceIndex: Int,
        currentSurfaceNumber: Int,
        displayedView: Int,
        displayedPageIndex: Int,
        displayedPageCount: Int,
        displayedPageLabel: String,
        currentProgressFraction: Double,
        currentProgressPercent: Int,
        currentProgressPercentText: String,
        visibleSurfaceIndexes: [Int],
        fallbackVisibleSurfaceIndex: Int
    ) {
        self.readingMode = readingMode
        self.usesTwoPageSpread = usesTwoPageSpread
        self.surfaceCount = max(surfaceCount, 1)
        self.selectedSurfaceIndex = max(selectedSurfaceIndex, 0)
        self.currentSurfaceNumber = min(max(currentSurfaceNumber, 1), self.surfaceCount)
        self.displayedView = max(displayedView, 1)
        self.displayedPageIndex = max(displayedPageIndex, 0)
        self.displayedPageCount = max(displayedPageCount, 1)
        self.displayedPageLabel = displayedPageLabel.isEmpty ? "1" : displayedPageLabel
        self.currentProgressFraction = min(max(currentProgressFraction, 0), 1)
        self.currentProgressPercent = min(max(currentProgressPercent, 0), 100)
        self.currentProgressPercentText = currentProgressPercentText
        self.visibleSurfaceIndexes = visibleSurfaceIndexes.map { max($0, 0) }
        self.fallbackVisibleSurfaceIndex = max(fallbackVisibleSurfaceIndex, 0)
    }

    public init(
        readingMode: ReaderReadingMode,
        usesTwoPageSpread: Bool,
        surfaces: [NovelReaderSurface],
        selectedSurfaceIndex: Int,
        spreads: [NovelReaderPresentationSpread],
        readingState: NovelReaderReadingState
    ) {
        let surfaceCount = max(surfaces.count, 1)
        let maxSurfaceIndex = max(surfaceCount - 1, 0)
        let normalizedSelectedIndex = min(max(selectedSurfaceIndex, 0), maxSurfaceIndex)
        let selectedSurface = surfaces.indices.contains(normalizedSelectedIndex) ? surfaces[normalizedSelectedIndex] : nil
        let displayedView = selectedSurface?.documentView ?? readingState.currentView
        let visibleSurfaceIndexes = surfaces.indices.filter { surfaces[$0].documentView == displayedView }
        let fallbackVisibleSurfaceIndex = visibleSurfaceIndexes.first ?? normalizedSelectedIndex
        let displayedPageIndex = visibleSurfaceIndexes.first.map {
            max(normalizedSelectedIndex - $0, 0)
        } ?? normalizedSelectedIndex
        let displayedPageCount = max(visibleSurfaceIndexes.count, 1)
        let displayedPageLabel = Self.displayedPageLabel(
            displayedPageIndex: displayedPageIndex,
            displayedPageCount: displayedPageCount,
            displayedView: displayedView,
            selectedSurfaceIndex: normalizedSelectedIndex,
            surfaces: surfaces,
            spreads: spreads,
            usesTwoPageSpread: usesTwoPageSpread
        )
        let fraction: Double = switch readingMode {
        case .vertical:
            displayedPageCount > 1 ? Double(displayedPageIndex) / Double(displayedPageCount - 1) : 0
        case .paged:
            surfaceCount > 1 ? Double(normalizedSelectedIndex) / Double(surfaceCount - 1) : 0
        }
        let percent = Int((fraction * 100).rounded())

        self.init(
            readingMode: readingMode,
            usesTwoPageSpread: usesTwoPageSpread,
            surfaceCount: surfaceCount,
            selectedSurfaceIndex: normalizedSelectedIndex,
            currentSurfaceNumber: normalizedSelectedIndex + 1,
            displayedView: displayedView,
            displayedPageIndex: displayedPageIndex,
            displayedPageCount: displayedPageCount,
            displayedPageLabel: displayedPageLabel,
            currentProgressFraction: fraction,
            currentProgressPercent: percent,
            currentProgressPercentText: "\(percent)%",
            visibleSurfaceIndexes: Array(visibleSurfaceIndexes),
            fallbackVisibleSurfaceIndex: fallbackVisibleSurfaceIndex
        )
    }

    private static func displayedPageLabel(
        displayedPageIndex: Int,
        displayedPageCount: Int,
        displayedView: Int,
        selectedSurfaceIndex: Int,
        surfaces: [NovelReaderSurface],
        spreads: [NovelReaderPresentationSpread],
        usesTwoPageSpread: Bool
    ) -> String {
        let leftSurfaceNumber = displayedPageIndex + 1
        guard usesTwoPageSpread,
              let spread = spreads.first(where: { $0.leftSurfaceIndex == selectedSurfaceIndex }),
              let rightSurfaceIndex = spread.rightSurfaceIndex,
              surfaces.indices.contains(rightSurfaceIndex),
              surfaces[rightSurfaceIndex].documentView == displayedView else {
            return "\(leftSurfaceNumber)"
        }
        let rightSurfaceNumber = displayedPageIndex + 2
        return "\(leftSurfaceNumber)-\(min(rightSurfaceNumber, displayedPageCount))"
    }
}

public struct NovelReaderPresentation: Hashable, Sendable {
    public var generation: UInt64
    public var revision: UInt64
    public var surfaces: [NovelReaderSurface]
    public var selectedSurfaceIdentity: NovelReaderSurfaceIdentity?
    public var selectedSurfaceIndex: Int?
    public var spreads: [NovelReaderPresentationSpread]
    public var chapters: [ReaderChapter]
    public var committedSettings: ReaderAppearanceSettings
    public var readingState: NovelReaderReadingState
    public var currentContentSource: ReaderContentSource
    public var retainedChapterCount: Int
    public var filteredChapterCandidateCount: Int
    public var progressProjection: NovelReaderProgressProjection

    public init(
        generation: UInt64,
        revision: UInt64,
        surfaces: [NovelReaderSurface],
        selectedSurfaceIdentity: NovelReaderSurfaceIdentity?,
        spreads: [NovelReaderPresentationSpread],
        chapters: [ReaderChapter] = [],
        committedSettings: ReaderAppearanceSettings,
        readingState: NovelReaderReadingState,
        currentContentSource: ReaderContentSource,
        retainedChapterCount: Int,
        filteredChapterCandidateCount: Int,
        selectedSurfaceIndex: Int? = nil,
        progressProjection: NovelReaderProgressProjection? = nil,
        usesTwoPageSpread: Bool = false
    ) {
        let resolvedSelectedSurfaceIndex = selectedSurfaceIndex ?? Self.surfaceIndex(
            for: selectedSurfaceIdentity,
            in: surfaces,
            generation: generation
        )
        self.generation = generation
        self.revision = revision
        self.surfaces = surfaces
        self.selectedSurfaceIdentity = selectedSurfaceIdentity
        self.selectedSurfaceIndex = resolvedSelectedSurfaceIndex
        self.spreads = spreads
        self.chapters = chapters
        self.committedSettings = committedSettings
        self.readingState = readingState
        self.currentContentSource = currentContentSource
        self.retainedChapterCount = max(0, retainedChapterCount)
        self.filteredChapterCandidateCount = max(0, filteredChapterCandidateCount)
        self.progressProjection = progressProjection ?? NovelReaderProgressProjection(
            readingMode: committedSettings.readingMode,
            usesTwoPageSpread: usesTwoPageSpread,
            surfaces: surfaces,
            selectedSurfaceIndex: resolvedSelectedSurfaceIndex ?? 0,
            spreads: spreads,
            readingState: readingState
        )
    }

    public func surfaceIndex(for identity: NovelReaderSurfaceIdentity) -> Int? {
        Self.surfaceIndex(for: identity, in: surfaces, generation: generation)
    }

    private static func surfaceIndex(
        for identity: NovelReaderSurfaceIdentity?,
        in surfaces: [NovelReaderSurface],
        generation: UInt64
    ) -> Int? {
        guard let identity,
              identity.generation == generation,
              surfaces.indices.contains(identity.ordinal),
              surfaces[identity.ordinal].identity == identity else {
            return nil
        }
        return surfaces[identity.ordinal].presentationIndex
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
