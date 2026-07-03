import Foundation
import YamiboReaderCore

enum SystemSettingsAction: Equatable {
    case loading
    case clearingNovelCache
    case clearingMangaIndexCache
    case clearingImageCache
    case clearingOfflineCache
    case resettingApplication
}

struct OfflineCacheManagementRow: Hashable, Identifiable {
    var id: OfflineCacheGroupID
    var readerKind: OfflineCacheReaderKind
    var title: String
    var byteCount: Int
    var cachedCount: Int
    var pendingCount: Int
    var failedCount: Int
    var entries: [OfflineCacheManagementEntry]

    init(group: OfflineCacheManagementGroup) {
        id = group.id
        readerKind = group.id.readerKind
        title = group.title
        byteCount = group.byteCount
        cachedCount = group.cachedCount
        pendingCount = group.pendingCount
        failedCount = group.failedCount
        entries = group.entries
    }

    var byteCountLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(max(0, byteCount)))
    }

    var summaryText: String {
        var pieces = [
            L10n.string("settings.offline_cache.entry_count_format", entries.count),
            byteCountLabel
        ]
        if pendingCount > 0 {
            pieces.append(L10n.string("settings.offline_cache.pending_count_format", pendingCount))
        }
        if failedCount > 0 {
            pieces.append(L10n.string("settings.offline_cache.failed_count_format", failedCount))
        }
        return pieces.joined(separator: " · ")
    }
}

struct OfflineCacheManagementSelectionActionState: Equatable {
    let selectedGroupCount: Int
    let canDelete: Bool
}

struct OfflineCacheManagementConfirmation: Identifiable, Equatable {
    var groupIDs: [OfflineCacheGroupID]
    var entryIDs: [OfflineCacheEntryID]
    var titles: [String]

    var id: String {
        let groupPart = groupIDs.map { "\($0.readerKind.rawValue):\($0.ownerKey)" }.joined(separator: "|")
        let entryPart = entryIDs.map {
            "\($0.readerKind.rawValue):\($0.ownerKey):\($0.entryKey)"
        }.joined(separator: "|")
        return [groupPart, entryPart].filter { !$0.isEmpty }.joined(separator: "#")
    }

    init(groupIDs: [OfflineCacheGroupID] = [], entryIDs: [OfflineCacheEntryID] = [], titles: [String]) {
        self.groupIDs = groupIDs
        self.entryIDs = entryIDs
        self.titles = titles
    }

    var title: String {
        if isEntryDeletion {
            return L10n.string("settings.offline_cache.confirm_entry_title")
        }
        if groupIDs.count == 1 {
            return L10n.string("settings.offline_cache.confirm_single_title")
        }
        return L10n.string("settings.offline_cache.confirm_batch_title")
    }

    var message: String {
        if isEntryDeletion {
            if let firstTitle = titles.first, entryIDs.count == 1 {
                return L10n.string("settings.offline_cache.confirm_entry_message", firstTitle)
            }
            return L10n.string("settings.offline_cache.confirm_entry_batch_message", entryIDs.count)
        }
        if let firstTitle = titles.first, groupIDs.count == 1 {
            return L10n.string("settings.offline_cache.confirm_single_message", firstTitle)
        }
        return L10n.string("settings.offline_cache.confirm_batch_message", groupIDs.count)
    }

    private var isEntryDeletion: Bool {
        !entryIDs.isEmpty
    }
}

enum SystemSettingsConfirmation: String, Identifiable {
    case clearNovelCache
    case clearMangaIndexCache
    case clearImageCache
    case resetApplication

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearNovelCache:
            L10n.string("settings.confirm_clear_novel_cache")
        case .clearMangaIndexCache:
            L10n.string("settings.confirm_clear_manga_index_cache")
        case .clearImageCache:
            L10n.string("settings.confirm_clear_image_cache")
        case .resetApplication:
            L10n.string("settings.confirm_reset_application")
        }
    }

    var buttonTitle: String {
        switch self {
        case .clearNovelCache:
            L10n.string("common.clear")
        case .clearMangaIndexCache:
            L10n.string("common.clear")
        case .clearImageCache:
            L10n.string("common.clear")
        case .resetApplication:
            L10n.string("settings.reset")
        }
    }

    var message: String {
        switch self {
        case .clearNovelCache:
            L10n.string("settings.clear_novel_cache_message")
        case .clearMangaIndexCache:
            L10n.string("settings.clear_manga_index_cache_message")
        case .clearImageCache:
            L10n.string("settings.clear_image_cache_message")
        case .resetApplication:
            L10n.string("settings.reset_application_message")
        }
    }
}

enum FavoriteAppearanceCategory: String, CaseIterable, Identifiable {
    case collection
    case novel
    case manga
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collection:
            L10n.string("favorite_category.collection")
        case .novel:
            L10n.string("favorite_category.novel")
        case .manga:
            L10n.string("favorite_category.manga")
        case .other:
            L10n.string("favorite_category.other")
        }
    }
}

extension FavoriteAppearanceSettings {
    func color(for category: FavoriteAppearanceCategory) -> FavoriteAppearanceColor {
        switch category {
        case .collection:
            collection
        case .novel:
            novel
        case .manga:
            manga
        case .other:
            other
        }
    }

    mutating func setColor(_ color: FavoriteAppearanceColor, for category: FavoriteAppearanceCategory) {
        switch category {
        case .collection:
            collection = color
        case .novel:
            novel = color
        case .manga:
            manga = color
        case .other:
            other = color
        }
    }
}
