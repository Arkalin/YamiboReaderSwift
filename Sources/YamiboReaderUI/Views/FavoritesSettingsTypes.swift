import YamiboReaderCore

enum FavoritesSettingsAction: Equatable {
    case loading
    case clearingNovelCache
    case clearingMangaCache
    case resettingApplication
}

enum FavoritesSettingsConfirmation: String, Identifiable {
    case clearNovelCache
    case clearMangaCache
    case resetApplication

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearNovelCache:
            L10n.string("settings.confirm_clear_novel_cache")
        case .clearMangaCache:
            L10n.string("settings.confirm_clear_manga_cache")
        case .resetApplication:
            L10n.string("settings.confirm_reset_application")
        }
    }

    var buttonTitle: String {
        switch self {
        case .clearNovelCache, .clearMangaCache:
            L10n.string("common.clear")
        case .resetApplication:
            L10n.string("settings.reset")
        }
    }

    var message: String {
        switch self {
        case .clearNovelCache:
            L10n.string("settings.clear_novel_cache_message")
        case .clearMangaCache:
            L10n.string("settings.clear_manga_cache_message")
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
