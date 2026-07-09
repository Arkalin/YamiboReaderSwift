import Foundation

public enum MangaLaunchSource: String, Codable, Hashable, Sendable {
    case forum
    case favorites
    case resume
    case like
}

public struct MangaLaunchContext: Hashable, Identifiable, Sendable {
    public var originalThreadID: String
    public var chapterTID: String
    public var chapterView: Int
    public var displayTitle: String
    public var source: MangaLaunchSource
    public var initialPage: Int
    public var directoryName: String?
    public var offlineCacheFavoriteID: String?
    /// Whether the forum board this chapter belongs to currently has Smart
    /// Comic Mode on. Computed by the caller (forum routing or the
    /// favorites open-target resolver — both know the `forumID`) at launch
    /// time; the reader itself never looks this up independently
    /// (smart-comic-mode design decision #15). Defaults to `true` so every
    /// pre-Phase-B call site (tests, previews, and callers not yet updated
    /// for this feature) keeps today's unconditional directory-resolution
    /// behavior unless it explicitly opts out.
    public var isSmartModeEnabled: Bool

    public var id: String {
        originalThreadID
    }

    public init(
        originalThreadID: String,
        chapterTID: String,
        displayTitle: String,
        source: MangaLaunchSource,
        chapterView: Int = 1,
        initialPage: Int = 0,
        directoryName: String? = nil,
        offlineCacheFavoriteID: String? = nil,
        isSmartModeEnabled: Bool = true
    ) {
        self.originalThreadID = Self.normalizedThreadID(originalThreadID, field: "originalThreadID")
        self.chapterTID = Self.normalizedThreadID(chapterTID, field: "chapterTID")
        self.chapterView = max(1, chapterView)
        self.displayTitle = displayTitle
        self.source = source
        self.initialPage = max(0, initialPage)
        self.directoryName = directoryName
        self.offlineCacheFavoriteID = offlineCacheFavoriteID?.mangaReaderTrimmedNonEmpty
        self.isSmartModeEnabled = isSmartModeEnabled
    }

    private static func normalizedThreadID(_ value: String, field: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalized.isEmpty, "MangaLaunchContext requires \(field)")
        return normalized
    }
}

extension MangaLaunchContext: Codable {
    private enum CodingKeys: String, CodingKey {
        case originalThreadID
        case chapterTID
        case chapterView
        case displayTitle
        case source
        case initialPage
        case directoryName
        case offlineCacheFavoriteID
        case isSmartModeEnabled
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalThreadID, forKey: .originalThreadID)
        try container.encode(chapterTID, forKey: .chapterTID)
        try container.encode(chapterView, forKey: .chapterView)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(source, forKey: .source)
        try container.encode(initialPage, forKey: .initialPage)
        try container.encodeIfPresent(directoryName, forKey: .directoryName)
        try container.encodeIfPresent(offlineCacheFavoriteID, forKey: .offlineCacheFavoriteID)
        try container.encode(isSmartModeEnabled, forKey: .isSmartModeEnabled)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            originalThreadID: try container.decode(String.self, forKey: .originalThreadID),
            chapterTID: try container.decode(String.self, forKey: .chapterTID),
            displayTitle: try container.decode(String.self, forKey: .displayTitle),
            source: try container.decode(MangaLaunchSource.self, forKey: .source),
            chapterView: try container.decodeIfPresent(Int.self, forKey: .chapterView) ?? 1,
            initialPage: try container.decodeIfPresent(Int.self, forKey: .initialPage) ?? 0,
            directoryName: try container.decodeIfPresent(String.self, forKey: .directoryName),
            offlineCacheFavoriteID: try container.decodeIfPresent(String.self, forKey: .offlineCacheFavoriteID),
            // Existing persisted routes (reader-resume route store) predate
            // this field; treat them as mode-on, matching the field's own
            // default and every pre-Phase-B launch context.
            isSmartModeEnabled: try container.decodeIfPresent(Bool.self, forKey: .isSmartModeEnabled) ?? true
        )
    }
}

