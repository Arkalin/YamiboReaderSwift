import Foundation

public enum LikeWorkKind: String, Codable, Hashable, Sendable, CaseIterable {
    case novel
    case manga
}

/// Identifies the work (novel thread or manga title) a Like Item belongs to,
/// independent of Favorite Library membership.
public struct LikeWorkKey: Codable, Hashable, Sendable {
    public var kind: LikeWorkKind
    public var id: String

    public init(kind: LikeWorkKind, id: String) {
        self.kind = kind
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func novel(threadID: String) -> LikeWorkKey {
        LikeWorkKey(kind: .novel, id: threadID)
    }

    public static func mangaTitle(cleanBookName: String) -> LikeWorkKey {
        LikeWorkKey(kind: .manga, id: cleanBookName)
    }

    /// Normal forum threads are not capture sources, so they have no Like work key.
    public init?(target: FavoriteContentTarget) {
        switch target {
        case let .novelThread(threadID):
            self = .novel(threadID: threadID)
        case let .mangaTitle(_, cleanBookName):
            self = .mangaTitle(cleanBookName: cleanBookName)
        case .normalThread:
            return nil
        }
    }
}

public enum LikeItemKind: String, Codable, Hashable, Sendable, CaseIterable {
    case text
    case image
}

/// A single point in a novel's linear reading flow: the segment it falls in
/// (a `NovelTextSegmentIdentity`-shaped string ending in "#text:N" or
/// "#image:N") plus a character offset within that segment.
public struct NovelLikeTextEndpoint: Hashable, Sendable {
    public var segmentIdentity: String
    public var offset: Int

    public init(segmentIdentity: String, offset: Int) {
        self.segmentIdentity = segmentIdentity
        self.offset = max(0, offset)
    }
}

/// A text excerpt anchor in the persisted Novel Reading Position coordinate
/// space: chapter identity, segment identity, and displayed-text Character
/// offsets, confined to one text segment.
public struct NovelTextLikeAnchor: Codable, Hashable, Sendable {
    public var chapterIdentity: NovelChapterIdentity
    public var textSegmentIdentity: NovelTextSegmentIdentity
    public var range: NovelCharacterRange

    public init(
        chapterIdentity: NovelChapterIdentity,
        textSegmentIdentity: NovelTextSegmentIdentity,
        range: NovelCharacterRange
    ) {
        self.chapterIdentity = chapterIdentity
        self.textSegmentIdentity = textSegmentIdentity
        self.range = range
    }

    var startEndpoint: NovelLikeTextEndpoint {
        NovelLikeTextEndpoint(segmentIdentity: textSegmentIdentity.rawValue, offset: range.location)
    }

    var endEndpoint: NovelLikeTextEndpoint {
        NovelLikeTextEndpoint(segmentIdentity: textSegmentIdentity.rawValue, offset: range.upperBound)
    }
}

/// A novel illustration anchor: images are a single point in the reading flow
/// rather than a Character range, identified by their image segment identity
/// ("<chapterIdentity>#image:N", mirroring `NovelTextSegmentIdentity`'s shape).
/// The source image URL lives on `LikeItem.sourceImageURL`, not here.
public struct NovelImageLikeAnchor: Codable, Hashable, Sendable {
    public var chapterIdentity: NovelChapterIdentity
    public var imageSegmentIdentity: String

    public init(chapterIdentity: NovelChapterIdentity, imageSegmentIdentity: String) {
        self.chapterIdentity = chapterIdentity
        self.imageSegmentIdentity = imageSegmentIdentity
    }
}

/// A manga page image anchor: chapter `tid` plus the page's `localIndex`
/// within that chapter, mirroring `MangaReadingPosition`'s identity fields.
public struct MangaImageLikeAnchor: Codable, Hashable, Sendable {
    public var chapterTID: String
    public var pageLocalIndex: Int

    public init(chapterTID: String, pageLocalIndex: Int) {
        self.chapterTID = chapterTID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pageLocalIndex = max(0, pageLocalIndex)
    }
}

public enum LikeAnchorPayload: Codable, Hashable, Sendable {
    case novelText(NovelTextLikeAnchor)
    case novelImage(NovelImageLikeAnchor)
    case mangaImage(MangaImageLikeAnchor)
}

/// One liked excerpt: a text excerpt or an image captured from one owning
/// content target. Independent of Favorite Library membership.
public struct LikeItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var workKey: LikeWorkKey
    public var kind: LikeItemKind
    public var excerptText: String?
    public var sourceImageURL: URL?
    public var anchor: LikeAnchorPayload
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        workKey: LikeWorkKey,
        kind: LikeItemKind,
        excerptText: String? = nil,
        sourceImageURL: URL? = nil,
        anchor: LikeAnchorPayload,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workKey = workKey
        self.kind = kind
        self.excerptText = excerptText
        self.sourceImageURL = sourceImageURL
        self.anchor = anchor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A work-level row for the My Likes first level: one owning work plus its
/// like count and most recent like activity, used to order the works list.
public struct LikeWorkSummary: Hashable, Sendable {
    public var workKey: LikeWorkKey
    public var itemCount: Int
    public var lastLikedAt: Date

    public init(workKey: LikeWorkKey, itemCount: Int, lastLikedAt: Date) {
        self.workKey = workKey
        self.itemCount = itemCount
        self.lastLikedAt = lastLikedAt
    }
}
