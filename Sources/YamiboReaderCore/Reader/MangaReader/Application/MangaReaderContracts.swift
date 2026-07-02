import Foundation

public enum MangaLaunchSource: String, Codable, Hashable, Sendable {
    case forum
    case favorites
    case resume
}

public struct MangaLaunchContext: Hashable, Identifiable, Sendable {
    public var originalThreadURL: URL
    public var chapterURL: URL
    public var displayTitle: String
    public var source: MangaLaunchSource
    public var initialPage: Int
    public var directoryName: String?
    public var offlineCacheFavoriteID: String?

    public var id: String {
        "\(originalThreadURL.absoluteString)#\(chapterURL.absoluteString)"
    }

    public init(
        originalThreadURL: URL,
        chapterURL: URL,
        displayTitle: String,
        source: MangaLaunchSource,
        initialPage: Int = 0,
        directoryName: String? = nil,
        offlineCacheFavoriteID: String? = nil
    ) {
        self.originalThreadURL = originalThreadURL
        self.chapterURL = chapterURL
        self.displayTitle = displayTitle
        self.source = source
        self.initialPage = max(0, initialPage)
        self.directoryName = directoryName
        self.offlineCacheFavoriteID = offlineCacheFavoriteID?.mangaReaderTrimmedNonEmpty
    }
}

extension MangaLaunchContext: Codable {
    private enum CodingKeys: String, CodingKey {
        case originalThreadID
        case chapterTID
        case displayTitle
        case source
        case initialPage
        case directoryName
        case offlineCacheFavoriteID
        case originalThreadURL
        case chapterURL
    }

    public func encode(to encoder: any Encoder) throws {
        guard let originalThreadID = Self.threadID(from: originalThreadURL),
              let chapterTID = Self.threadID(from: chapterURL) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Manga launch context requires thread IDs for persistence"
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalThreadID, forKey: .originalThreadID)
        try container.encode(chapterTID, forKey: .chapterTID)
        try container.encode(displayTitle, forKey: .displayTitle)
        try container.encode(source, forKey: .source)
        try container.encode(initialPage, forKey: .initialPage)
        try container.encodeIfPresent(directoryName, forKey: .directoryName)
        try container.encodeIfPresent(offlineCacheFavoriteID, forKey: .offlineCacheFavoriteID)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let originalThreadURL = try Self.threadURL(
            threadID: container.decodeIfPresent(String.self, forKey: .originalThreadID),
            legacyURL: container.decodeIfPresent(URL.self, forKey: .originalThreadURL)
        )
        let chapterURL = try Self.threadURL(
            threadID: container.decodeIfPresent(String.self, forKey: .chapterTID),
            legacyURL: container.decodeIfPresent(URL.self, forKey: .chapterURL)
        )
        self.init(
            originalThreadURL: originalThreadURL,
            chapterURL: chapterURL,
            displayTitle: try container.decode(String.self, forKey: .displayTitle),
            source: try container.decode(MangaLaunchSource.self, forKey: .source),
            initialPage: try container.decodeIfPresent(Int.self, forKey: .initialPage) ?? 0,
            directoryName: try container.decodeIfPresent(String.self, forKey: .directoryName),
            offlineCacheFavoriteID: try container.decodeIfPresent(String.self, forKey: .offlineCacheFavoriteID)
        )
    }

    private static func threadID(from url: URL) -> String? {
        MangaTitleCleaner.extractTid(from: url.absoluteString)?.mangaReaderTrimmedNonEmpty
    }

    private static func threadURL(threadID: String?, legacyURL: URL?) throws -> URL {
        if let threadID = threadID?.mangaReaderTrimmedNonEmpty,
           let url = YamiboRoute.chapterURL(forTID: threadID) {
            return url
        }
        if let legacyURL,
           let threadID = Self.threadID(from: legacyURL),
           let url = YamiboRoute.chapterURL(forTID: threadID) {
            return url
        }
        if let legacyURL {
            return legacyURL
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Manga launch context is missing thread identity"
            )
        )
    }
}

public struct MangaWebContext: Hashable, Identifiable, Sendable {
    public var currentURL: URL
    public var originalThreadURL: URL
    public var source: MangaLaunchSource
    public var initialPage: Int
    public var autoOpenNative: Bool
    public var waitingForNativeReturn: Bool

    public var id: String {
        "\(originalThreadURL.absoluteString)#\(currentURL.absoluteString)#\(initialPage)"
    }

    public init(
        currentURL: URL,
        originalThreadURL: URL,
        source: MangaLaunchSource,
        initialPage: Int = 0,
        autoOpenNative: Bool = false,
        waitingForNativeReturn: Bool = false
    ) {
        self.currentURL = currentURL
        self.originalThreadURL = originalThreadURL
        self.source = source
        self.initialPage = max(0, initialPage)
        self.autoOpenNative = autoOpenNative
        self.waitingForNativeReturn = waitingForNativeReturn
    }

    public func updating(
        currentURL: URL? = nil,
        initialPage: Int? = nil,
        autoOpenNative: Bool? = nil,
        waitingForNativeReturn: Bool? = nil
    ) -> MangaWebContext {
        MangaWebContext(
            currentURL: currentURL ?? self.currentURL,
            originalThreadURL: originalThreadURL,
            source: source,
            initialPage: initialPage ?? self.initialPage,
            autoOpenNative: autoOpenNative ?? self.autoOpenNative,
            waitingForNativeReturn: waitingForNativeReturn ?? self.waitingForNativeReturn
        )
    }
}

extension MangaWebContext: Codable {
    private enum CodingKeys: String, CodingKey {
        case currentTID
        case currentPage
        case originalThreadID
        case source
        case initialPage
        case autoOpenNative
        case waitingForNativeReturn
        case currentURL
        case originalThreadURL
    }

    public func encode(to encoder: any Encoder) throws {
        guard let currentTID = Self.threadID(from: currentURL),
              let originalThreadID = Self.threadID(from: originalThreadURL) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Manga web context requires thread IDs for persistence"
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currentTID, forKey: .currentTID)
        try container.encode(Self.page(from: currentURL), forKey: .currentPage)
        try container.encode(originalThreadID, forKey: .originalThreadID)
        try container.encode(source, forKey: .source)
        try container.encode(initialPage, forKey: .initialPage)
        try container.encode(autoOpenNative, forKey: .autoOpenNative)
        try container.encode(waitingForNativeReturn, forKey: .waitingForNativeReturn)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currentURL = try Self.threadURL(
            threadID: container.decodeIfPresent(String.self, forKey: .currentTID),
            page: container.decodeIfPresent(Int.self, forKey: .currentPage) ?? 1,
            legacyURL: container.decodeIfPresent(URL.self, forKey: .currentURL)
        )
        let originalThreadURL = try Self.threadURL(
            threadID: container.decodeIfPresent(String.self, forKey: .originalThreadID),
            page: 1,
            legacyURL: container.decodeIfPresent(URL.self, forKey: .originalThreadURL)
        )
        self.init(
            currentURL: currentURL,
            originalThreadURL: originalThreadURL,
            source: try container.decode(MangaLaunchSource.self, forKey: .source),
            initialPage: try container.decodeIfPresent(Int.self, forKey: .initialPage) ?? 0,
            autoOpenNative: try container.decodeIfPresent(Bool.self, forKey: .autoOpenNative) ?? false,
            waitingForNativeReturn: try container.decodeIfPresent(Bool.self, forKey: .waitingForNativeReturn) ?? false
        )
    }

    private static func threadID(from url: URL) -> String? {
        MangaTitleCleaner.extractTid(from: url.absoluteString)?.mangaReaderTrimmedNonEmpty
    }

    private static func page(from url: URL) -> Int {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
            .flatMap(Int.init) ?? 1
        return max(1, page)
    }

    private static func threadURL(threadID: String?, page: Int, legacyURL: URL?) throws -> URL {
        if let threadID = threadID?.mangaReaderTrimmedNonEmpty {
            return YamiboRoute.threadByID(tid: threadID, page: page, authorID: nil, reverse: false).url
        }
        if let legacyURL,
           let threadID = Self.threadID(from: legacyURL) {
            return YamiboRoute.threadByID(tid: threadID, page: Self.page(from: legacyURL), authorID: nil, reverse: false).url
        }
        if let legacyURL {
            return legacyURL
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Manga web context is missing thread identity"
            )
        )
    }
}

public enum MangaPresentationRoute: Hashable, Sendable {
    case native(MangaLaunchContext)
    case web(MangaWebContext)
}

extension MangaPresentationRoute: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case nativeContext
        case webContext
    }

    private enum Kind: String, Codable {
        case native
        case web
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .native(context):
            try container.encode(Kind.native, forKey: .kind)
            try container.encode(context, forKey: .nativeContext)
        case let .web(context):
            try container.encode(Kind.web, forKey: .kind)
            try container.encode(context, forKey: .webContext)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .native:
            self = .native(try container.decode(MangaLaunchContext.self, forKey: .nativeContext))
        case .web:
            self = .web(try container.decode(MangaWebContext.self, forKey: .webContext))
        }
    }
}

public enum MangaReadingMode: String, Codable, Hashable, CaseIterable, Sendable {
    case paged
    case vertical

    public var title: String {
        switch self {
        case .paged: L10n.string("reading_mode.paged")
        case .vertical: L10n.string("reading_mode.vertical")
        }
    }
}

public enum MangaPageTurnDirection: String, Codable, Hashable, CaseIterable, Sendable {
    case rightToLeft
    case leftToRight

    public var title: String {
        switch self {
        case .rightToLeft: L10n.string("manga.page_turn_direction.right_to_left")
        case .leftToRight: L10n.string("manga.page_turn_direction.left_to_right")
        }
    }
}

public enum MangaPageScaleMode: String, Codable, Hashable, CaseIterable, Sendable {
    case fitHeight
    case fitWidth

    public var title: String {
        switch self {
        case .fitHeight: L10n.string("manga.page_scale_mode.fit_height")
        case .fitWidth: L10n.string("manga.page_scale_mode.fit_width")
        }
    }
}

public enum MangaPageEdgeFillStyle: String, Codable, Hashable, CaseIterable, Sendable {
    case white
    case black
    case system

    public var title: String {
        switch self {
        case .white: L10n.string("manga.page_edge_fill.white")
        case .black: L10n.string("manga.page_edge_fill.black")
        case .system: L10n.string("manga.page_edge_fill.system")
        }
    }
}

public enum MangaDirectorySortOrder: String, Codable, Hashable, CaseIterable, Sendable {
    case ascending
    case descending

    public var title: String {
        switch self {
        case .ascending: L10n.string("sort.ascending")
        case .descending: L10n.string("sort.descending")
        }
    }
}

public struct MangaReaderSettings: Codable, Hashable, Sendable {
    public var readingMode: MangaReadingMode
    public var pagedTurnStyle: ReaderPagedTurnStyle
    public var pageTurnDirection: MangaPageTurnDirection
    public var pageScaleMode: MangaPageScaleMode
    public var pageEdgeFillStyle: MangaPageEdgeFillStyle
    public var brightness: Double
    public var zoomEnabled: Bool
    public var showsTwoPagesInLandscapeOnPad: Bool
    public var directorySortOrder: MangaDirectorySortOrder

    public init(
        readingMode: MangaReadingMode = .vertical,
        pagedTurnStyle: ReaderPagedTurnStyle = .slide,
        pageTurnDirection: MangaPageTurnDirection = .leftToRight,
        pageScaleMode: MangaPageScaleMode = .fitWidth,
        pageEdgeFillStyle: MangaPageEdgeFillStyle = .black,
        brightness: Double = 1,
        zoomEnabled: Bool = true,
        showsTwoPagesInLandscapeOnPad: Bool = false,
        directorySortOrder: MangaDirectorySortOrder = .ascending
    ) {
        self.readingMode = readingMode
        self.pagedTurnStyle = pagedTurnStyle
        self.pageTurnDirection = pageTurnDirection
        self.pageScaleMode = pageScaleMode
        self.pageEdgeFillStyle = pageEdgeFillStyle
        self.brightness = brightness
        self.zoomEnabled = zoomEnabled
        self.showsTwoPagesInLandscapeOnPad = showsTwoPagesInLandscapeOnPad
        self.directorySortOrder = directorySortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case readingMode
        case pagedTurnStyle
        case pageTurnDirection
        case pageScaleMode
        case pageEdgeFillStyle
        case brightness
        case zoomEnabled
        case showsTwoPagesInLandscapeOnPad
        case directorySortOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readingMode = try container.decodeIfPresent(MangaReadingMode.self, forKey: .readingMode) ?? .vertical
        pagedTurnStyle = try container.decodeIfPresent(ReaderPagedTurnStyle.self, forKey: .pagedTurnStyle) ?? .slide
        pageTurnDirection = try container.decodeIfPresent(MangaPageTurnDirection.self, forKey: .pageTurnDirection) ?? .leftToRight
        pageScaleMode = try container.decodeIfPresent(MangaPageScaleMode.self, forKey: .pageScaleMode) ?? .fitWidth
        pageEdgeFillStyle = try container.decodeIfPresent(MangaPageEdgeFillStyle.self, forKey: .pageEdgeFillStyle) ?? .black
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
        zoomEnabled = try container.decodeIfPresent(Bool.self, forKey: .zoomEnabled) ?? true
        showsTwoPagesInLandscapeOnPad = try container.decodeIfPresent(Bool.self, forKey: .showsTwoPagesInLandscapeOnPad) ?? false
        directorySortOrder = try container.decodeIfPresent(MangaDirectorySortOrder.self, forKey: .directorySortOrder) ?? .ascending
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(pagedTurnStyle, forKey: .pagedTurnStyle)
        try container.encode(pageTurnDirection, forKey: .pageTurnDirection)
        try container.encode(pageScaleMode, forKey: .pageScaleMode)
        try container.encode(pageEdgeFillStyle, forKey: .pageEdgeFillStyle)
        try container.encode(brightness, forKey: .brightness)
        try container.encode(zoomEnabled, forKey: .zoomEnabled)
        try container.encode(showsTwoPagesInLandscapeOnPad, forKey: .showsTwoPagesInLandscapeOnPad)
        try container.encode(directorySortOrder, forKey: .directorySortOrder)
    }
}

public enum ThreadOpenTarget: Hashable, Sendable {
    case novel(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case web(URL)
}
