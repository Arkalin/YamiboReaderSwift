import Foundation
import YamiboReaderCore

enum SystemSettingsAction: Equatable {
    case loading
    case clearingNovelCache
    case clearingMangaIndexCache
    case clearingImageCache
    case clearingMangaOfflineCache
    case resettingApplication
}

struct MangaOfflineCacheCleanupRow: Hashable, Identifiable {
    var ownerName: String
    var title: String
    var byteCount: Int

    var id: String { ownerName }

    var byteCountLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(max(0, byteCount)))
    }
}

struct MangaOfflineCacheCleanupSelectionActionState: Equatable {
    let selectedOwnerCount: Int
    let canDelete: Bool
}

struct MangaOfflineCacheCleanupConfirmation: Identifiable, Equatable {
    var ownerNames: [String]
    var ownerTitles: [String]

    var id: String { ownerNames.joined(separator: "|") }

    init(ownerNames: [String], ownerTitles: [String]) {
        self.ownerNames = ownerNames
        self.ownerTitles = ownerTitles
    }

    var title: String {
        if ownerNames.count == 1 {
            return L10n.string("settings.manga_offline_cache.confirm_single_title")
        }
        return L10n.string("settings.manga_offline_cache.confirm_batch_title")
    }

    var message: String {
        if let firstTitle = ownerTitles.first, ownerNames.count == 1 {
            return L10n.string("settings.manga_offline_cache.confirm_single_message", firstTitle)
        }
        return L10n.string("settings.manga_offline_cache.confirm_batch_message", ownerNames.count)
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
