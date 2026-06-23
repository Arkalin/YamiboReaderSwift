import Foundation

public enum MangaLaunchSource: String, Codable, Hashable, Sendable {
    case forum
    case favorites
    case resume
}

public struct MangaLaunchContext: Codable, Hashable, Identifiable, Sendable {
    public var originalThreadURL: URL
    public var chapterURL: URL
    public var displayTitle: String
    public var source: MangaLaunchSource
    public var initialPage: Int
    public var directoryName: String?

    public var id: String {
        "\(originalThreadURL.absoluteString)#\(chapterURL.absoluteString)"
    }

    public init(
        originalThreadURL: URL,
        chapterURL: URL,
        displayTitle: String,
        source: MangaLaunchSource,
        initialPage: Int = 0,
        directoryName: String? = nil
    ) {
        self.originalThreadURL = originalThreadURL
        self.chapterURL = chapterURL
        self.displayTitle = displayTitle
        self.source = source
        self.initialPage = max(0, initialPage)
        self.directoryName = directoryName
    }
}

public struct MangaWebContext: Codable, Hashable, Identifiable, Sendable {
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
    public var brightness: Double
    public var zoomEnabled: Bool
    public var showsTwoPagesInLandscapeOnPad: Bool
    public var directorySortOrder: MangaDirectorySortOrder

    public init(
        readingMode: MangaReadingMode = .vertical,
        pagedTurnStyle: ReaderPagedTurnStyle = .slide,
        pageTurnDirection: MangaPageTurnDirection = .rightToLeft,
        pageScaleMode: MangaPageScaleMode = .fitWidth,
        brightness: Double = 1,
        zoomEnabled: Bool = true,
        showsTwoPagesInLandscapeOnPad: Bool = false,
        directorySortOrder: MangaDirectorySortOrder = .ascending
    ) {
        self.readingMode = readingMode
        self.pagedTurnStyle = pagedTurnStyle
        self.pageTurnDirection = pageTurnDirection
        self.pageScaleMode = pageScaleMode
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
        case brightness
        case zoomEnabled
        case showsTwoPagesInLandscapeOnPad
        case directorySortOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readingMode = try container.decodeIfPresent(MangaReadingMode.self, forKey: .readingMode) ?? .vertical
        pagedTurnStyle = try container.decodeIfPresent(ReaderPagedTurnStyle.self, forKey: .pagedTurnStyle) ?? .slide
        pageTurnDirection = try container.decodeIfPresent(MangaPageTurnDirection.self, forKey: .pageTurnDirection) ?? .rightToLeft
        pageScaleMode = try container.decodeIfPresent(MangaPageScaleMode.self, forKey: .pageScaleMode) ?? .fitWidth
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
