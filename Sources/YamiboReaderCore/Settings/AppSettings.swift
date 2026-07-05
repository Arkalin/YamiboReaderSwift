import Foundation

public enum AppHomePage: String, Codable, Hashable, CaseIterable, Sendable {
    case favorites
    case forum

    public var title: String {
        switch self {
        case .favorites: L10n.string("app.home.favorites")
        case .forum: L10n.string("app.home.forum")
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
        case .system: L10n.string("reader.background.system")
        case .paper: L10n.string("reader.background.paper")
        case .mint: L10n.string("color.mint")
        case .sakura: L10n.string("reader.background.sakura")
        }
    }
}

public enum ReaderReadingMode: String, Codable, Hashable, CaseIterable, Sendable {
    case paged
    case vertical

    public var title: String {
        switch self {
        case .paged: L10n.string("reading_mode.paged")
        case .vertical: L10n.string("reading_mode.vertical")
        }
    }
}

public enum ReaderPagedTurnStyle: String, Codable, Hashable, CaseIterable, Sendable {
    case slide
    case pageCurl
    case quickFade

    public var title: String {
        switch self {
        case .slide: L10n.string("reading_mode.slide")
        case .pageCurl: L10n.string("reading_mode.page_curl")
        case .quickFade: L10n.string("reading_mode.quick_fade")
        }
    }
}

public enum ReaderPageTurnDirection: String, Codable, Hashable, CaseIterable, Sendable {
    case leftToRight
    case rightToLeft

    public var title: String {
        switch self {
        case .leftToRight: L10n.string("reader.page_turn_direction.left_to_right")
        case .rightToLeft: L10n.string("reader.page_turn_direction.right_to_left")
        }
    }
}

public enum ReaderTranslationMode: String, Codable, Hashable, CaseIterable, Sendable {
    case none
    case simplified
    case traditional

    public var title: String {
        switch self {
        case .none: L10n.string("translation.original")
        case .simplified: L10n.string("translation.simplified")
        case .traditional: L10n.string("translation.traditional")
        }
    }
}

public enum ReaderFontFamily: String, Codable, Hashable, CaseIterable, Sendable {
    case systemSans
    case systemSerif
    case rounded

    public var title: String {
        switch self {
        case .systemSans: L10n.string("reader.font.system_sans")
        case .systemSerif: L10n.string("reader.font.system_serif")
        case .rounded: L10n.string("reader.font.rounded")
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

public struct NovelReaderAppearanceSettings: Codable, Hashable, Sendable {
    public var fontScale: Double
    public var fontFamily: ReaderFontFamily
    public var lineHeightScale: Double
    public var characterSpacingScale: Double
    public var horizontalPadding: Double
    public var usesJustifiedText: Bool
    public var indentsParagraphFirstLine: Bool
    public var loadsInlineImages: Bool
    public var showsAuthorRepliesToOthers: Bool
    public var showsTwoPagesInLandscapeOnPad: Bool
    public var backgroundStyle: ReaderBackgroundStyle
    public var readingMode: ReaderReadingMode
    public var pagedTurnStyle: ReaderPagedTurnStyle
    public var pageTurnDirection: ReaderPageTurnDirection
    public var translationMode: ReaderTranslationMode

    public init(
        fontScale: Double = 1.0,
        fontFamily: ReaderFontFamily = .systemSans,
        lineHeightScale: Double = 1.45,
        characterSpacingScale: Double = 0,
        horizontalPadding: Double = 16,
        usesJustifiedText: Bool = false,
        indentsParagraphFirstLine: Bool = false,
        loadsInlineImages: Bool = true,
        showsAuthorRepliesToOthers: Bool = true,
        showsTwoPagesInLandscapeOnPad: Bool = false,
        backgroundStyle: ReaderBackgroundStyle = .system,
        readingMode: ReaderReadingMode = .paged,
        pagedTurnStyle: ReaderPagedTurnStyle = .slide,
        pageTurnDirection: ReaderPageTurnDirection = .leftToRight,
        translationMode: ReaderTranslationMode = .none
    ) {
        self.fontScale = fontScale
        self.fontFamily = fontFamily
        self.lineHeightScale = lineHeightScale
        self.characterSpacingScale = characterSpacingScale
        self.horizontalPadding = horizontalPadding
        self.usesJustifiedText = usesJustifiedText
        self.indentsParagraphFirstLine = indentsParagraphFirstLine
        self.loadsInlineImages = loadsInlineImages
        self.showsAuthorRepliesToOthers = showsAuthorRepliesToOthers
        self.showsTwoPagesInLandscapeOnPad = showsTwoPagesInLandscapeOnPad
        self.backgroundStyle = backgroundStyle
        self.readingMode = readingMode
        self.pagedTurnStyle = pagedTurnStyle
        self.pageTurnDirection = pageTurnDirection
        self.translationMode = translationMode
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale
        case fontFamily
        case lineHeightScale
        case characterSpacingScale
        case horizontalPadding
        case usesJustifiedText
        case indentsParagraphFirstLine
        case loadsInlineImages
        case showsAuthorRepliesToOthers
        case showsTwoPagesInLandscapeOnPad
        case backgroundStyle
        case readingMode
        case pagedTurnStyle
        case pageTurnDirection
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
        indentsParagraphFirstLine = try container.decodeIfPresent(Bool.self, forKey: .indentsParagraphFirstLine) ?? false
        loadsInlineImages = try container.decodeIfPresent(Bool.self, forKey: .loadsInlineImages) ?? true
        showsAuthorRepliesToOthers = try container.decodeIfPresent(Bool.self, forKey: .showsAuthorRepliesToOthers) ?? true
        showsTwoPagesInLandscapeOnPad = try container.decodeIfPresent(Bool.self, forKey: .showsTwoPagesInLandscapeOnPad) ?? false
        backgroundStyle = try container.decodeIfPresent(ReaderBackgroundStyle.self, forKey: .backgroundStyle) ?? .system
        readingMode = try container.decodeIfPresent(ReaderReadingMode.self, forKey: .readingMode) ?? .paged
        pagedTurnStyle = try container.decodeIfPresent(ReaderPagedTurnStyle.self, forKey: .pagedTurnStyle) ?? .slide
        pageTurnDirection = try container.decodeIfPresent(ReaderPageTurnDirection.self, forKey: .pageTurnDirection) ?? .leftToRight
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
        try container.encode(indentsParagraphFirstLine, forKey: .indentsParagraphFirstLine)
        try container.encode(loadsInlineImages, forKey: .loadsInlineImages)
        try container.encode(showsAuthorRepliesToOthers, forKey: .showsAuthorRepliesToOthers)
        try container.encode(showsTwoPagesInLandscapeOnPad, forKey: .showsTwoPagesInLandscapeOnPad)
        try container.encode(backgroundStyle, forKey: .backgroundStyle)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(pagedTurnStyle, forKey: .pagedTurnStyle)
        try container.encode(pageTurnDirection, forKey: .pageTurnDirection)
        try container.encode(translationMode, forKey: .translationMode)
    }
}

public struct NovelOfflineCacheSettings: Codable, Hashable, Sendable {
    public var retainsInlineImages: Bool
    public var isAutoRefreshEnabled: Bool

    public init(
        retainsInlineImages: Bool = false,
        isAutoRefreshEnabled: Bool = true
    ) {
        self.retainsInlineImages = retainsInlineImages
        self.isAutoRefreshEnabled = isAutoRefreshEnabled
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
        case .red: L10n.string("color.red")
        case .pink: L10n.string("color.pink")
        case .orange: L10n.string("color.orange")
        case .yellow: L10n.string("color.yellow")
        case .green: L10n.string("color.green")
        case .mint: L10n.string("color.mint")
        case .cyan: L10n.string("color.cyan")
        case .blue: L10n.string("color.blue")
        case .purple: L10n.string("color.purple")
        case .gray: L10n.string("color.gray")
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

public struct FavoriteBackgroundSettings: Codable, Hashable, Sendable {
    public static let minimumScale = 1.0
    public static let maximumScale = 3.0
    public static let minimumOffset = -1.0
    public static let maximumOffset = 1.0
    public static let minimumBlurRadius = 0.0
    public static let maximumBlurRadius = 30.0

    public var isEnabled: Bool
    public var imageID: String?
    public var scale: Double
    public var offsetX: Double
    public var offsetY: Double
    public var blurRadius: Double

    public init(
        isEnabled: Bool = false,
        imageID: String? = nil,
        scale: Double = 1.0,
        offsetX: Double = 0,
        offsetY: Double = 0,
        blurRadius: Double = 0
    ) {
        self.isEnabled = isEnabled
        self.imageID = imageID
        self.scale = Self.clampScale(scale)
        self.offsetX = Self.clampOffset(offsetX)
        self.offsetY = Self.clampOffset(offsetY)
        self.blurRadius = Self.clampBlurRadius(blurRadius)
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case imageID
        case scale
        case offsetX
        case offsetY
        case blurRadius
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        imageID = try container.decodeIfPresent(String.self, forKey: .imageID)
        scale = Self.clampScale(try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0)
        offsetX = Self.clampOffset(try container.decodeIfPresent(Double.self, forKey: .offsetX) ?? 0)
        offsetY = Self.clampOffset(try container.decodeIfPresent(Double.self, forKey: .offsetY) ?? 0)
        blurRadius = Self.clampBlurRadius(try container.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(imageID, forKey: .imageID)
        try container.encode(Self.clampScale(scale), forKey: .scale)
        try container.encode(Self.clampOffset(offsetX), forKey: .offsetX)
        try container.encode(Self.clampOffset(offsetY), forKey: .offsetY)
        try container.encode(Self.clampBlurRadius(blurRadius), forKey: .blurRadius)
    }

    public static func clampScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(maximumScale, max(minimumScale, value))
    }

    public static func clampOffset(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(maximumOffset, max(minimumOffset, value))
    }

    public static func clampBlurRadius(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(maximumBlurRadius, max(minimumBlurRadius, value))
    }
}

public enum FavoriteLibraryLayoutMode: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case fixedGrid
    case staggered
    case rowCard
    case rowCardText

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fixedGrid:
            L10n.string("favorites.layout.fixed_grid")
        case .staggered:
            L10n.string("favorites.layout.staggered")
        case .rowCard:
            L10n.string("favorites.layout.row_card")
        case .rowCardText:
            L10n.string("favorites.layout.row_card_text")
        }
    }

    public var systemImageName: String {
        switch self {
        case .fixedGrid:
            "square.grid.2x2"
        case .staggered:
            "rectangle.grid.2x2"
        case .rowCard:
            "list.bullet.rectangle"
        case .rowCardText:
            "list.bullet"
        }
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
        case .doubleTapPreviousSqueezeNext: L10n.string("apple_pencil.behavior.double_tap_previous_squeeze_next")
        case .doubleTapNextSqueezePrevious: L10n.string("apple_pencil.behavior.double_tap_next_squeeze_previous")
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

public enum FavoriteRemoteSyncTaskStatus: String, Codable, Hashable, Sendable {
    case running
    case completed
    case failed
    case interrupted
}

public struct FavoriteRemoteSyncSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var runID: String
    public var status: FavoriteRemoteSyncTaskStatus
    public var targetCategoryID: String
    public var targetCategoryName: String
    public var phase: String
    public var startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var totalRemoteCount: Int?
    public var scannedCount: Int
    public var importedCount: Int
    public var failedCount: Int
    public var markedMissingCount: Int
    public var uploadTargetCount: Int
    public var logMessages: [String]
    public var warningMessages: [String]
    public var errorMessages: [String]
    public var isHiddenFromFavoritePage: Bool

    public var id: String { runID }

    public init(
        runID: String = UUID().uuidString,
        status: FavoriteRemoteSyncTaskStatus = .running,
        targetCategoryID: String,
        targetCategoryName: String,
        phase: String,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        finishedAt: Date? = nil,
        totalRemoteCount: Int? = nil,
        scannedCount: Int = 0,
        importedCount: Int = 0,
        failedCount: Int = 0,
        markedMissingCount: Int = 0,
        uploadTargetCount: Int = 0,
        logMessages: [String] = [],
        warningMessages: [String] = [],
        errorMessages: [String] = [],
        isHiddenFromFavoritePage: Bool = false
    ) {
        self.runID = runID
        self.status = status
        self.targetCategoryID = targetCategoryID
        self.targetCategoryName = targetCategoryName
        self.phase = phase
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
        self.totalRemoteCount = totalRemoteCount
        self.scannedCount = scannedCount
        self.importedCount = importedCount
        self.failedCount = failedCount
        self.markedMissingCount = markedMissingCount
        self.uploadTargetCount = uploadTargetCount
        self.logMessages = logMessages
        self.warningMessages = warningMessages
        self.errorMessages = errorMessages
        self.isHiddenFromFavoritePage = isHiddenFromFavoritePage
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public var novelReader: NovelReaderAppearanceSettings
    public var manga: MangaReaderSettings
    public var novelOfflineCache: NovelOfflineCacheSettings
    public var webBrowser: WebBrowserSettings
    public var favoriteAppearance: FavoriteAppearanceSettings
    public var favoriteBackground: FavoriteBackgroundSettings
    public var favoriteLayoutMode: FavoriteLibraryLayoutMode
    public var favoriteSortOrder: LocalFavoriteLibrarySortOrder
    public var favoriteSortDescending: Bool
    public var favoriteSelectedCategoryID: String?
    public var favoriteSelectedCollectionID: String?
    public var favoriteShowsCategoryCounts: Bool
    public var favoriteRemoteSyncSnapshot: FavoriteRemoteSyncSnapshot?
    public var applePencilPageTurn: ApplePencilPageTurnSettings
    public var homePage: AppHomePage
    public var usesDataSaverMode: Bool
    public var collapsesFavoriteSections: Bool

    public init(
        novelReader: NovelReaderAppearanceSettings = .init(),
        manga: MangaReaderSettings = .init(),
        novelOfflineCache: NovelOfflineCacheSettings = .init(),
        webBrowser: WebBrowserSettings = .init(),
        favoriteAppearance: FavoriteAppearanceSettings = .init(),
        favoriteBackground: FavoriteBackgroundSettings = .init(),
        favoriteLayoutMode: FavoriteLibraryLayoutMode = .rowCard,
        favoriteSortOrder: LocalFavoriteLibrarySortOrder = .organization,
        favoriteSortDescending: Bool = false,
        favoriteSelectedCategoryID: String? = nil,
        favoriteSelectedCollectionID: String? = nil,
        favoriteShowsCategoryCounts: Bool = true,
        favoriteRemoteSyncSnapshot: FavoriteRemoteSyncSnapshot? = nil,
        applePencilPageTurn: ApplePencilPageTurnSettings = .init(),
        homePage: AppHomePage = .forum,
        usesDataSaverMode: Bool = false,
        collapsesFavoriteSections: Bool = false
    ) {
        self.novelReader = novelReader
        self.manga = manga
        self.novelOfflineCache = novelOfflineCache
        self.webBrowser = webBrowser
        self.favoriteAppearance = favoriteAppearance
        self.favoriteBackground = favoriteBackground
        self.favoriteLayoutMode = favoriteLayoutMode
        self.favoriteSortOrder = favoriteSortOrder
        self.favoriteSortDescending = favoriteSortDescending
        self.favoriteSelectedCategoryID = favoriteSelectedCategoryID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.favoriteSelectedCollectionID = favoriteSelectedCollectionID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.favoriteShowsCategoryCounts = favoriteShowsCategoryCounts
        self.favoriteRemoteSyncSnapshot = favoriteRemoteSyncSnapshot
        self.applePencilPageTurn = applePencilPageTurn
        self.homePage = homePage
        self.usesDataSaverMode = usesDataSaverMode
        self.collapsesFavoriteSections = collapsesFavoriteSections
    }

    private enum CodingKeys: String, CodingKey {
        case novelReader
        case manga
        case novelOfflineCache
        case webBrowser
        case favoriteAppearance
        case favoriteBackground
        case favoriteLayoutMode
        case favoriteSortOrder
        case favoriteSortDescending
        case favoriteSelectedCategoryID
        case favoriteSelectedCollectionID
        case favoriteShowsCategoryCounts
        case favoriteRemoteSyncSnapshot
        case applePencilPageTurn
        case homePage
        case usesDataSaverMode
        case collapsesFavoriteSections
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        novelReader = try container.decodeIfPresent(NovelReaderAppearanceSettings.self, forKey: .novelReader) ?? .init()
        manga = try container.decodeIfPresent(MangaReaderSettings.self, forKey: .manga) ?? .init()
        novelOfflineCache = try container.decodeIfPresent(
            NovelOfflineCacheSettings.self,
            forKey: .novelOfflineCache
        ) ?? .init()
        webBrowser = try container.decodeIfPresent(WebBrowserSettings.self, forKey: .webBrowser) ?? .init()
        favoriteAppearance = try container.decodeIfPresent(FavoriteAppearanceSettings.self, forKey: .favoriteAppearance) ?? .init()
        favoriteBackground = try container.decodeIfPresent(FavoriteBackgroundSettings.self, forKey: .favoriteBackground) ?? .init()
        favoriteLayoutMode = try container.decodeIfPresent(FavoriteLibraryLayoutMode.self, forKey: .favoriteLayoutMode) ?? .rowCard
        favoriteSortOrder = try container.decodeIfPresent(LocalFavoriteLibrarySortOrder.self, forKey: .favoriteSortOrder) ?? .organization
        favoriteSortDescending = try container.decodeIfPresent(Bool.self, forKey: .favoriteSortDescending) ?? false
        favoriteSelectedCategoryID = try container.decodeIfPresent(String.self, forKey: .favoriteSelectedCategoryID)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        favoriteSelectedCollectionID = try container.decodeIfPresent(String.self, forKey: .favoriteSelectedCollectionID)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        favoriteShowsCategoryCounts = try container.decodeIfPresent(Bool.self, forKey: .favoriteShowsCategoryCounts) ?? true
        favoriteRemoteSyncSnapshot = try container.decodeIfPresent(FavoriteRemoteSyncSnapshot.self, forKey: .favoriteRemoteSyncSnapshot)
        applePencilPageTurn = try container.decodeIfPresent(ApplePencilPageTurnSettings.self, forKey: .applePencilPageTurn) ?? .init()
        homePage = try container.decodeIfPresent(AppHomePage.self, forKey: .homePage) ?? .forum
        usesDataSaverMode = try container.decodeIfPresent(Bool.self, forKey: .usesDataSaverMode) ?? false
        collapsesFavoriteSections = try container.decodeIfPresent(Bool.self, forKey: .collapsesFavoriteSections) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(novelReader, forKey: .novelReader)
        try container.encode(manga, forKey: .manga)
        try container.encode(novelOfflineCache, forKey: .novelOfflineCache)
        try container.encode(webBrowser, forKey: .webBrowser)
        try container.encode(favoriteAppearance, forKey: .favoriteAppearance)
        try container.encode(favoriteBackground, forKey: .favoriteBackground)
        try container.encode(favoriteLayoutMode, forKey: .favoriteLayoutMode)
        try container.encode(favoriteSortOrder, forKey: .favoriteSortOrder)
        try container.encode(favoriteSortDescending, forKey: .favoriteSortDescending)
        try container.encodeIfPresent(favoriteSelectedCategoryID, forKey: .favoriteSelectedCategoryID)
        try container.encodeIfPresent(favoriteSelectedCollectionID, forKey: .favoriteSelectedCollectionID)
        try container.encode(favoriteShowsCategoryCounts, forKey: .favoriteShowsCategoryCounts)
        try container.encodeIfPresent(favoriteRemoteSyncSnapshot, forKey: .favoriteRemoteSyncSnapshot)
        try container.encode(applePencilPageTurn, forKey: .applePencilPageTurn)
        try container.encode(homePage, forKey: .homePage)
        try container.encode(usesDataSaverMode, forKey: .usesDataSaverMode)
        try container.encode(collapsesFavoriteSections, forKey: .collapsesFavoriteSections)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
