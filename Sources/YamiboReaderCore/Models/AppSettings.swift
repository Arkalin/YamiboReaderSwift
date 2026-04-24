import Foundation

public enum AppHomePage: String, Codable, Hashable, CaseIterable, Sendable {
    case favorites
    case forum

    public var title: String {
        switch self {
        case .favorites: "收藏"
        case .forum: "论坛"
        }
    }

    public var systemImageName: String {
        switch self {
        case .favorites: "heart.text.square"
        case .forum: "globe.asia.australia"
        }
    }
}

public enum ReaderBackgroundStyle: String, Codable, Hashable, CaseIterable, Sendable {
    case system
    case paper
    case mint
    case sakura

    public var title: String {
        switch self {
        case .system: "系统"
        case .paper: "纸张"
        case .mint: "薄荷"
        case .sakura: "樱粉"
        }
    }
}

public enum ReaderReadingMode: String, Codable, Hashable, CaseIterable, Sendable {
    case paged
    case vertical

    public var title: String {
        switch self {
        case .paged: "横向分页"
        case .vertical: "纵向滚动"
        }
    }
}

public enum ReaderTranslationMode: String, Codable, Hashable, CaseIterable, Sendable {
    case none
    case simplified
    case traditional

    public var title: String {
        switch self {
        case .none: "原文"
        case .simplified: "简体"
        case .traditional: "繁体"
        }
    }
}

public enum ReaderFontFamily: String, Codable, Hashable, CaseIterable, Sendable {
    case systemSans
    case systemSerif
    case rounded

    public var title: String {
        switch self {
        case .systemSans: "苹方"
        case .systemSerif: "宋体"
        case .rounded: "圆角"
        }
    }

    public var paginationWidthFactor: Double {
        switch self {
        case .systemSans: 0.9
        case .systemSerif: 0.98
        case .rounded: 0.94
        }
    }
}

public struct ReaderAppearanceSettings: Codable, Hashable, Sendable {
    public var fontScale: Double
    public var fontFamily: ReaderFontFamily
    public var lineHeightScale: Double
    public var characterSpacingScale: Double
    public var horizontalPadding: Double
    public var usesJustifiedText: Bool
    public var loadsInlineImages: Bool
    public var showsTwoPagesInLandscapeOnPad: Bool
    public var backgroundStyle: ReaderBackgroundStyle
    public var readingMode: ReaderReadingMode
    public var translationMode: ReaderTranslationMode

    public init(
        fontScale: Double = 1.0,
        fontFamily: ReaderFontFamily = .systemSans,
        lineHeightScale: Double = 1.45,
        characterSpacingScale: Double = 0,
        horizontalPadding: Double = 16,
        usesJustifiedText: Bool = false,
        loadsInlineImages: Bool = true,
        showsTwoPagesInLandscapeOnPad: Bool = false,
        backgroundStyle: ReaderBackgroundStyle = .system,
        readingMode: ReaderReadingMode = .paged,
        translationMode: ReaderTranslationMode = .none
    ) {
        self.fontScale = fontScale
        self.fontFamily = fontFamily
        self.lineHeightScale = lineHeightScale
        self.characterSpacingScale = characterSpacingScale
        self.horizontalPadding = horizontalPadding
        self.usesJustifiedText = usesJustifiedText
        self.loadsInlineImages = loadsInlineImages
        self.showsTwoPagesInLandscapeOnPad = showsTwoPagesInLandscapeOnPad
        self.backgroundStyle = backgroundStyle
        self.readingMode = readingMode
        self.translationMode = translationMode
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale
        case fontFamily
        case lineHeightScale
        case characterSpacingScale
        case horizontalPadding
        case usesJustifiedText
        case loadsInlineImages
        case showsTwoPagesInLandscapeOnPad
        case backgroundStyle
        case readingMode
        case translationMode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
        fontFamily = try container.decodeIfPresent(ReaderFontFamily.self, forKey: .fontFamily) ?? .systemSans
        lineHeightScale = try container.decodeIfPresent(Double.self, forKey: .lineHeightScale) ?? 1.45
        characterSpacingScale = try container.decodeIfPresent(Double.self, forKey: .characterSpacingScale) ?? 0
        horizontalPadding = try container.decodeIfPresent(Double.self, forKey: .horizontalPadding) ?? 16
        usesJustifiedText = try container.decodeIfPresent(Bool.self, forKey: .usesJustifiedText) ?? false
        loadsInlineImages = try container.decodeIfPresent(Bool.self, forKey: .loadsInlineImages) ?? true
        showsTwoPagesInLandscapeOnPad = try container.decodeIfPresent(Bool.self, forKey: .showsTwoPagesInLandscapeOnPad) ?? false
        backgroundStyle = try container.decodeIfPresent(ReaderBackgroundStyle.self, forKey: .backgroundStyle) ?? .system
        readingMode = try container.decodeIfPresent(ReaderReadingMode.self, forKey: .readingMode) ?? .paged
        translationMode = try container.decodeIfPresent(ReaderTranslationMode.self, forKey: .translationMode) ?? .none
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(lineHeightScale, forKey: .lineHeightScale)
        try container.encode(characterSpacingScale, forKey: .characterSpacingScale)
        try container.encode(horizontalPadding, forKey: .horizontalPadding)
        try container.encode(usesJustifiedText, forKey: .usesJustifiedText)
        try container.encode(loadsInlineImages, forKey: .loadsInlineImages)
        try container.encode(showsTwoPagesInLandscapeOnPad, forKey: .showsTwoPagesInLandscapeOnPad)
        try container.encode(backgroundStyle, forKey: .backgroundStyle)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(translationMode, forKey: .translationMode)
    }
}

public struct WebBrowserSettings: Codable, Hashable, Sendable {
    public var showsNavigationBar: Bool

    public init(showsNavigationBar: Bool = true) {
        self.showsNavigationBar = showsNavigationBar
    }

    private enum CodingKeys: String, CodingKey {
        case showsNavigationBar
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsNavigationBar = try container.decodeIfPresent(Bool.self, forKey: .showsNavigationBar) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsNavigationBar, forKey: .showsNavigationBar)
    }
}

public enum FavoriteAppearanceColor: String, Codable, Hashable, CaseIterable, Sendable {
    case red
    case pink
    case orange
    case yellow
    case green
    case mint
    case cyan
    case blue
    case purple
    case gray

    public var title: String {
        switch self {
        case .red: "红色"
        case .pink: "粉色"
        case .orange: "橙色"
        case .yellow: "黄色"
        case .green: "绿色"
        case .mint: "薄荷"
        case .cyan: "青色"
        case .blue: "蓝色"
        case .purple: "紫色"
        case .gray: "灰色"
        }
    }
}

public struct FavoriteAppearanceSettings: Codable, Hashable, Sendable {
    public var collection: FavoriteAppearanceColor
    public var novel: FavoriteAppearanceColor
    public var manga: FavoriteAppearanceColor
    public var other: FavoriteAppearanceColor

    public init(
        collection: FavoriteAppearanceColor = .orange,
        novel: FavoriteAppearanceColor = .pink,
        manga: FavoriteAppearanceColor = .blue,
        other: FavoriteAppearanceColor = .cyan
    ) {
        self.collection = collection
        self.novel = novel
        self.manga = manga
        self.other = other
    }

    private enum CodingKeys: String, CodingKey {
        case collection
        case novel
        case manga
        case other
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collection = try container.decodeIfPresent(FavoriteAppearanceColor.self, forKey: .collection) ?? .orange
        novel = try container.decodeIfPresent(FavoriteAppearanceColor.self, forKey: .novel) ?? .pink
        manga = try container.decodeIfPresent(FavoriteAppearanceColor.self, forKey: .manga) ?? .blue
        other = try container.decodeIfPresent(FavoriteAppearanceColor.self, forKey: .other) ?? .cyan
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(collection, forKey: .collection)
        try container.encode(novel, forKey: .novel)
        try container.encode(manga, forKey: .manga)
        try container.encode(other, forKey: .other)
    }
}

public enum ApplePencilPageTurnGesture: Hashable, Sendable {
    case doubleTap
    case squeeze
}

public enum ApplePencilPageTurnBehavior: String, Codable, Hashable, CaseIterable, Sendable {
    case doubleTapPreviousSqueezeNext
    case doubleTapNextSqueezePrevious

    public var title: String {
        switch self {
        case .doubleTapPreviousSqueezeNext: "双击上一页，按压下一页"
        case .doubleTapNextSqueezePrevious: "双击下一页，按压上一页"
        }
    }

    public var doubleTapPageDelta: Int {
        pageDelta(for: .doubleTap)
    }

    public var squeezePageDelta: Int {
        pageDelta(for: .squeeze)
    }

    public func pageDelta(for gesture: ApplePencilPageTurnGesture) -> Int {
        switch (self, gesture) {
        case (.doubleTapPreviousSqueezeNext, .doubleTap),
             (.doubleTapNextSqueezePrevious, .squeeze):
            -1
        case (.doubleTapPreviousSqueezeNext, .squeeze),
             (.doubleTapNextSqueezePrevious, .doubleTap):
            1
        }
    }
}

public struct ApplePencilPageTurnSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var behavior: ApplePencilPageTurnBehavior

    public init(
        isEnabled: Bool = false,
        behavior: ApplePencilPageTurnBehavior = .doubleTapPreviousSqueezeNext
    ) {
        self.isEnabled = isEnabled
        self.behavior = behavior
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case behavior
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        behavior = try container.decodeIfPresent(ApplePencilPageTurnBehavior.self, forKey: .behavior)
            ?? .doubleTapPreviousSqueezeNext
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(behavior, forKey: .behavior)
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var reader: ReaderAppearanceSettings
    public var manga: MangaReaderSettings
    public var webBrowser: WebBrowserSettings
    public var favoriteAppearance: FavoriteAppearanceSettings
    public var applePencilPageTurn: ApplePencilPageTurnSettings
    public var homePage: AppHomePage
    public var usesDataSaverMode: Bool
    public var collapsesFavoriteSections: Bool

    public init(
        reader: ReaderAppearanceSettings = .init(),
        manga: MangaReaderSettings = .init(),
        webBrowser: WebBrowserSettings = .init(),
        favoriteAppearance: FavoriteAppearanceSettings = .init(),
        applePencilPageTurn: ApplePencilPageTurnSettings = .init(),
        homePage: AppHomePage = .forum,
        usesDataSaverMode: Bool = false,
        collapsesFavoriteSections: Bool = false
    ) {
        self.reader = reader
        self.manga = manga
        self.webBrowser = webBrowser
        self.favoriteAppearance = favoriteAppearance
        self.applePencilPageTurn = applePencilPageTurn
        self.homePage = homePage
        self.usesDataSaverMode = usesDataSaverMode
        self.collapsesFavoriteSections = collapsesFavoriteSections
    }

    private enum CodingKeys: String, CodingKey {
        case reader
        case manga
        case webBrowser
        case favoriteAppearance
        case applePencilPageTurn
        case homePage
        case usesDataSaverMode
        case collapsesFavoriteSections
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reader = try container.decodeIfPresent(ReaderAppearanceSettings.self, forKey: .reader) ?? .init()
        manga = try container.decodeIfPresent(MangaReaderSettings.self, forKey: .manga) ?? .init()
        webBrowser = try container.decodeIfPresent(WebBrowserSettings.self, forKey: .webBrowser) ?? .init()
        favoriteAppearance = try container.decodeIfPresent(FavoriteAppearanceSettings.self, forKey: .favoriteAppearance) ?? .init()
        applePencilPageTurn = try container.decodeIfPresent(ApplePencilPageTurnSettings.self, forKey: .applePencilPageTurn) ?? .init()
        homePage = try container.decodeIfPresent(AppHomePage.self, forKey: .homePage) ?? .forum
        usesDataSaverMode = try container.decodeIfPresent(Bool.self, forKey: .usesDataSaverMode) ?? false
        collapsesFavoriteSections = try container.decodeIfPresent(Bool.self, forKey: .collapsesFavoriteSections) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reader, forKey: .reader)
        try container.encode(manga, forKey: .manga)
        try container.encode(webBrowser, forKey: .webBrowser)
        try container.encode(favoriteAppearance, forKey: .favoriteAppearance)
        try container.encode(applePencilPageTurn, forKey: .applePencilPageTurn)
        try container.encode(homePage, forKey: .homePage)
        try container.encode(usesDataSaverMode, forKey: .usesDataSaverMode)
        try container.encode(collapsesFavoriteSections, forKey: .collapsesFavoriteSections)
    }
}
