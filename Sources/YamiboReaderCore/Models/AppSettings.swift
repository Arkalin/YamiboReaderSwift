import Foundation

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

public struct ReaderAppearanceSettings: Codable, Hashable, Sendable {
    public var fontScale: Double
    public var lineHeightScale: Double
    public var horizontalPadding: Double
    public var usesNightMode: Bool
    public var showsSystemStatusBar: Bool
    public var loadsInlineImages: Bool
    public var backgroundStyle: ReaderBackgroundStyle
    public var readingMode: ReaderReadingMode
    public var translationMode: ReaderTranslationMode

    public init(
        fontScale: Double = 1.0,
        lineHeightScale: Double = 1.45,
        horizontalPadding: Double = 16,
        usesNightMode: Bool = false,
        showsSystemStatusBar: Bool = true,
        loadsInlineImages: Bool = true,
        backgroundStyle: ReaderBackgroundStyle = .system,
        readingMode: ReaderReadingMode = .paged,
        translationMode: ReaderTranslationMode = .none
    ) {
        self.fontScale = fontScale
        self.lineHeightScale = lineHeightScale
        self.horizontalPadding = horizontalPadding
        self.usesNightMode = usesNightMode
        self.showsSystemStatusBar = showsSystemStatusBar
        self.loadsInlineImages = loadsInlineImages
        self.backgroundStyle = backgroundStyle
        self.readingMode = readingMode
        self.translationMode = translationMode
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale
        case lineHeightScale
        case horizontalPadding
        case usesNightMode
        case showsSystemStatusBar
        case loadsInlineImages
        case backgroundStyle
        case readingMode
        case translationMode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontScale = try container.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1.0
        lineHeightScale = try container.decodeIfPresent(Double.self, forKey: .lineHeightScale) ?? 1.45
        horizontalPadding = try container.decodeIfPresent(Double.self, forKey: .horizontalPadding) ?? 16
        usesNightMode = try container.decodeIfPresent(Bool.self, forKey: .usesNightMode) ?? false
        showsSystemStatusBar = try container.decodeIfPresent(Bool.self, forKey: .showsSystemStatusBar) ?? true
        loadsInlineImages = try container.decodeIfPresent(Bool.self, forKey: .loadsInlineImages) ?? true
        backgroundStyle = try container.decodeIfPresent(ReaderBackgroundStyle.self, forKey: .backgroundStyle) ?? .system
        readingMode = try container.decodeIfPresent(ReaderReadingMode.self, forKey: .readingMode) ?? .paged
        translationMode = try container.decodeIfPresent(ReaderTranslationMode.self, forKey: .translationMode) ?? .none
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(lineHeightScale, forKey: .lineHeightScale)
        try container.encode(horizontalPadding, forKey: .horizontalPadding)
        try container.encode(usesNightMode, forKey: .usesNightMode)
        try container.encode(showsSystemStatusBar, forKey: .showsSystemStatusBar)
        try container.encode(loadsInlineImages, forKey: .loadsInlineImages)
        try container.encode(backgroundStyle, forKey: .backgroundStyle)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(translationMode, forKey: .translationMode)
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var reader: ReaderAppearanceSettings
    public var usesDataSaverMode: Bool
    public var collapsesFavoriteSections: Bool

    public init(
        reader: ReaderAppearanceSettings = .init(),
        usesDataSaverMode: Bool = false,
        collapsesFavoriteSections: Bool = false
    ) {
        self.reader = reader
        self.usesDataSaverMode = usesDataSaverMode
        self.collapsesFavoriteSections = collapsesFavoriteSections
    }
}
