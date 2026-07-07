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

/// Five-phase Yamibo favorite sync, mirroring the Android reference:
/// fetch remote pages, import remote-only items, upload local-only items,
/// then reconcile the remote mapping. The local library is the source of
/// truth; sync converges both sides to their union and never deletes.
public enum FavoriteRemoteSyncPhase: String, Codable, Hashable, Sendable {
    case queued
    case preparing
    case fetching
    case importing
    case uploading
    case reconciling
    case completed
    case failed
    case interrupted
}

/// Semantic log events recorded during a remote favorite sync run.
/// The presentation layer maps these to localized text; the model never
/// stores display copy.
public enum FavoriteRemoteSyncLogEntry: Codable, Hashable, Sendable {
    case started(categoryName: String)
    case fetchedPage(page: Int, totalPages: Int, accumulatedCount: Int)
    case importingItem(index: Int, total: Int, title: String)
    case skippedSyncedItems(path: String, count: Int)
    case uploading(targetCount: Int)
    case uploadedItem(index: Int, total: Int, title: String)
    case reconciling
    case completed(importedCount: Int, uploadedCount: Int)
    case failed
    case interrupted
    case taskLost
}

/// Semantic warnings surfaced by a remote favorite sync run. Item-level
/// failures carry a truncated reason string; run-fatal errors go to
/// `FavoriteRemoteSyncSnapshot.errorMessages` instead.
public enum FavoriteRemoteSyncWarning: Codable, Hashable, Sendable {
    case interruptedByUser
    case interrupted
    case taskLost
    case backgroundExpired
    case backgroundUnavailable
    case remotePageCountChanged
    case duplicateRemoteEntry(title: String)
    case importFailedItem(title: String, reason: String)
    case uploadFailedItem(title: String, reason: String)
    case reconcileFailed(reason: String)
}

public struct FavoriteRemoteSyncSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var runID: String
    public var status: FavoriteRemoteSyncTaskStatus
    public var targetCategoryID: String
    public var targetCategoryName: String
    public var phase: FavoriteRemoteSyncPhase
    public var startedAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var currentPage: Int?
    public var totalPages: Int?
    /// Remote entries accumulated across fetched pages.
    public var scannedCount: Int
    /// Newly imported items plus existing items that gained the target
    /// category location.
    public var importedCount: Int
    /// Remote entries whose local item was already mapped; nothing to do.
    public var skippedCount: Int
    public var uploadTargetCount: Int
    public var uploadedCount: Int
    public var failedCount: Int
    public var logEntries: [FavoriteRemoteSyncLogEntry]
    public var warnings: [FavoriteRemoteSyncWarning]
    /// Raw error descriptions from failed operations; unlike logs and
    /// warnings these carry free-form error text, not display copy.
    public var errorMessages: [String]
    public var isHiddenFromFavoritePage: Bool

    public var id: String { runID }

    public init(
        runID: String = UUID().uuidString,
        status: FavoriteRemoteSyncTaskStatus = .running,
        targetCategoryID: String,
        targetCategoryName: String,
        phase: FavoriteRemoteSyncPhase,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        finishedAt: Date? = nil,
        currentPage: Int? = nil,
        totalPages: Int? = nil,
        scannedCount: Int = 0,
        importedCount: Int = 0,
        skippedCount: Int = 0,
        uploadTargetCount: Int = 0,
        uploadedCount: Int = 0,
        failedCount: Int = 0,
        logEntries: [FavoriteRemoteSyncLogEntry] = [],
        warnings: [FavoriteRemoteSyncWarning] = [],
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
        self.currentPage = currentPage
        self.totalPages = totalPages
        self.scannedCount = scannedCount
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.uploadTargetCount = uploadTargetCount
        self.uploadedCount = uploadedCount
        self.failedCount = failedCount
        self.logEntries = logEntries
        self.warnings = warnings
        self.errorMessages = errorMessages
        self.isHiddenFromFavoritePage = isHiddenFromFavoritePage
    }
}

/// How often favorite update checks run automatically (BGAppRefreshTask plus
/// a foreground catch-up). iOS decides the actual background timing; these
/// are the earliest-run intervals, mirroring the Android options.
public enum FavoriteUpdateCheckInterval: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case off
    case sixHours
    case twelveHours
    case day
    case threeDays
    case week
    /// Adaptive: checks twice a day while recent updates keep appearing,
    /// otherwise backs off to every two days.
    case smart

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: L10n.string("favorites.updates.interval.off")
        case .sixHours: L10n.string("favorites.updates.interval.six_hours")
        case .twelveHours: L10n.string("favorites.updates.interval.twelve_hours")
        case .day: L10n.string("favorites.updates.interval.day")
        case .threeDays: L10n.string("favorites.updates.interval.three_days")
        case .week: L10n.string("favorites.updates.interval.week")
        case .smart: L10n.string("favorites.updates.interval.smart")
        }
    }

    /// Seconds until the next automatic check, or nil when disabled.
    public func nextDelay(hasRecentEvents: Bool) -> TimeInterval? {
        switch self {
        case .off: nil
        case .sixHours: 6 * 3600
        case .twelveHours: 12 * 3600
        case .day: 24 * 3600
        case .threeDays: 3 * 24 * 3600
        case .week: 7 * 24 * 3600
        case .smart: hasRecentEvents ? 12 * 3600 : 48 * 3600
        }
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
    public var collapsesSections: Bool
    /// Whether adding a favorite asks about pushing it to Yamibo; once the
    /// user picks "remember", this turns off and `addSyncDefault` applies.
    public var addSyncPromptEnabled: Bool
    public var addSyncDefault: Bool
    /// Same pair for the delete flow's "also remove from Yamibo" question.
    public var removeRemotePromptEnabled: Bool
    public var removeRemoteDefault: Bool
    public var updateCheckInterval: FavoriteUpdateCheckInterval

    public init(
        appearance: FavoriteAppearanceSettings = .init(),
        background: FavoriteBackgroundSettings = .init(),
        layoutMode: FavoriteLibraryLayoutMode = .rowCard,
        sortOrder: LocalFavoriteLibrarySortOrder = .organization,
        sortDescending: Bool = false,
        selectedCategoryID: String? = nil,
        selectedCollectionID: String? = nil,
        showsCategoryCounts: Bool = true,
        collapsesSections: Bool = false,
        addSyncPromptEnabled: Bool = true,
        addSyncDefault: Bool = true,
        removeRemotePromptEnabled: Bool = true,
        removeRemoteDefault: Bool = false,
        updateCheckInterval: FavoriteUpdateCheckInterval = .off
    ) {
        self.appearance = appearance
        self.background = background
        self.layoutMode = layoutMode
        self.sortOrder = sortOrder
        self.sortDescending = sortDescending
        self.selectedCategoryID = Self.normalizedID(selectedCategoryID)
        self.selectedCollectionID = Self.normalizedID(selectedCollectionID)
        self.showsCategoryCounts = showsCategoryCounts
        self.collapsesSections = collapsesSections
        self.addSyncPromptEnabled = addSyncPromptEnabled
        self.addSyncDefault = addSyncDefault
        self.removeRemotePromptEnabled = removeRemotePromptEnabled
        self.removeRemoteDefault = removeRemoteDefault
        self.updateCheckInterval = updateCheckInterval
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appearance: try container.decodeIfPresent(FavoriteAppearanceSettings.self, forKey: .appearance) ?? .init(),
            background: try container.decodeIfPresent(FavoriteBackgroundSettings.self, forKey: .background) ?? .init(),
            layoutMode: try container.decodeIfPresent(FavoriteLibraryLayoutMode.self, forKey: .layoutMode) ?? .rowCard,
            sortOrder: try container.decodeIfPresent(LocalFavoriteLibrarySortOrder.self, forKey: .sortOrder) ?? .organization,
            sortDescending: try container.decodeIfPresent(Bool.self, forKey: .sortDescending) ?? false,
            selectedCategoryID: try container.decodeIfPresent(String.self, forKey: .selectedCategoryID),
            selectedCollectionID: try container.decodeIfPresent(String.self, forKey: .selectedCollectionID),
            showsCategoryCounts: try container.decodeIfPresent(Bool.self, forKey: .showsCategoryCounts) ?? true,
            collapsesSections: try container.decodeIfPresent(Bool.self, forKey: .collapsesSections) ?? false,
            addSyncPromptEnabled: try container.decodeIfPresent(Bool.self, forKey: .addSyncPromptEnabled) ?? true,
            addSyncDefault: try container.decodeIfPresent(Bool.self, forKey: .addSyncDefault) ?? true,
            removeRemotePromptEnabled: try container.decodeIfPresent(Bool.self, forKey: .removeRemotePromptEnabled) ?? true,
            removeRemoteDefault: try container.decodeIfPresent(Bool.self, forKey: .removeRemoteDefault) ?? false,
            updateCheckInterval: try container.decodeIfPresent(FavoriteUpdateCheckInterval.self, forKey: .updateCheckInterval) ?? .off
        )
    }

    private static func normalizedID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
