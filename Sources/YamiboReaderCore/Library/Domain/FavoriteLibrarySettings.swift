import Foundation

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            imageID: try container.decodeIfPresent(String.self, forKey: .imageID),
            scale: try container.decode(Double.self, forKey: .scale),
            offsetX: try container.decode(Double.self, forKey: .offsetX),
            offsetY: try container.decode(Double.self, forKey: .offsetY),
            blurRadius: try container.decode(Double.self, forKey: .blurRadius)
        )
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

public struct FavoriteLibrarySettings: Codable, Hashable, Sendable {
    public var appearance: FavoriteAppearanceSettings
    public var background: FavoriteBackgroundSettings
    public var layoutMode: FavoriteLibraryLayoutMode
    public var sortOrder: LocalFavoriteLibrarySortOrder
    public var sortDescending: Bool
    public var selectedCategoryID: String?
    public var selectedCollectionID: String?
    public var showsCategoryCounts: Bool
    public var remoteSyncSnapshot: FavoriteRemoteSyncSnapshot?
    public var collapsesSections: Bool

    public init(
        appearance: FavoriteAppearanceSettings = .init(),
        background: FavoriteBackgroundSettings = .init(),
        layoutMode: FavoriteLibraryLayoutMode = .rowCard,
        sortOrder: LocalFavoriteLibrarySortOrder = .organization,
        sortDescending: Bool = false,
        selectedCategoryID: String? = nil,
        selectedCollectionID: String? = nil,
        showsCategoryCounts: Bool = true,
        remoteSyncSnapshot: FavoriteRemoteSyncSnapshot? = nil,
        collapsesSections: Bool = false
    ) {
        self.appearance = appearance
        self.background = background
        self.layoutMode = layoutMode
        self.sortOrder = sortOrder
        self.sortDescending = sortDescending
        self.selectedCategoryID = Self.normalizedID(selectedCategoryID)
        self.selectedCollectionID = Self.normalizedID(selectedCollectionID)
        self.showsCategoryCounts = showsCategoryCounts
        self.remoteSyncSnapshot = remoteSyncSnapshot
        self.collapsesSections = collapsesSections
    }

    private static func normalizedID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
