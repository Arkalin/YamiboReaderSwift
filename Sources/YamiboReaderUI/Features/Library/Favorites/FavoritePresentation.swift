import SwiftUI
import YamiboReaderCore

/// Presentation mapping for favorite domain values: user-facing labels and
/// colors live here, not in the library models.
extension FavoriteSourceGroup {
    var displayLabel: String {
        switch self {
        case let .forumBoard(_, label):
            label
        case let .mangaTitle(_, cleanBookName):
            cleanBookName
        case .unknown:
            L10n.string("favorites.source_group.unknown")
        }
    }
}

extension FavoriteCollectionColor {
    var swiftUIColor: Color {
        switch self {
        case .red:
            .red
        case .orange:
            .orange
        case .yellow:
            .yellow
        case .green:
            .green
        case .blue:
            .blue
        case .purple:
            .purple
        case .pink:
            .pink
        case .gray:
            .gray
        }
    }

    var localizedTitle: String {
        switch self {
        case .red:
            L10n.string("color.red")
        case .orange:
            L10n.string("color.orange")
        case .yellow:
            L10n.string("color.yellow")
        case .green:
            L10n.string("color.green")
        case .blue:
            L10n.string("color.blue")
        case .purple:
            L10n.string("color.purple")
        case .pink:
            L10n.string("color.pink")
        case .gray:
            L10n.string("color.gray")
        }
    }
}

extension FavoriteTagColor {
    var localizedTitle: String {
        switch self {
        case .red:
            L10n.string("color.red")
        case .orange:
            L10n.string("color.orange")
        case .yellow:
            L10n.string("color.yellow")
        case .green:
            L10n.string("color.green")
        case .blue:
            L10n.string("color.blue")
        case .purple:
            L10n.string("color.purple")
        case .pink:
            L10n.string("color.pink")
        case .gray:
            L10n.string("color.gray")
        }
    }
}

extension [FavoriteCategory] {
    /// Categories in the user's manual order with a stable ID tiebreaker.
    var manualOrderSorted: [FavoriteCategory] {
        sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }
}

extension LocalFavoriteOpenError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .mangaTitleUnresolved:
            L10n.string("favorite_library.manga_title_resolution_failed")
        }
    }
}

extension FavoriteRemoteSyncPhase {
    var displayTitle: String {
        switch self {
        case .queued:
            L10n.string("favorites.sync.phase.queued")
        case .fetching:
            L10n.string("favorites.sync.phase.fetching")
        case .importing:
            L10n.string("favorites.sync.phase.importing")
        case .completed:
            L10n.string("favorites.sync.phase.completed")
        case .failed:
            L10n.string("favorites.sync.phase.failed")
        case .interrupted:
            L10n.string("favorites.sync.phase.interrupted")
        }
    }
}

extension FavoriteRemoteSyncLogEntry {
    var displayText: String {
        switch self {
        case let .started(categoryName):
            L10n.string("favorites.sync.log.started", categoryName)
        case .fetching:
            L10n.string("favorites.sync.log.fetching")
        case let .fetched(count):
            L10n.string("favorites.sync.log.fetched", count)
        case let .completed(importedCount):
            L10n.string("favorites.sync.log.completed", importedCount)
        case .failed:
            L10n.string("favorites.sync.log.failed")
        case .interrupted:
            L10n.string("favorites.sync.log.interrupted")
        case .taskLost:
            L10n.string("favorites.sync.log.task_lost")
        }
    }
}

extension FavoriteRemoteSyncWarning {
    var displayText: String {
        switch self {
        case .interruptedByUser:
            L10n.string("favorites.sync.warning.interrupted_by_user")
        case .interrupted:
            L10n.string("favorites.sync.warning.interrupted")
        case .taskLost:
            L10n.string("favorites.sync.warning.task_lost")
        case .backgroundExpired:
            L10n.string("favorites.sync.warning.background_expired")
        case .backgroundUnavailable:
            L10n.string("favorites.sync.warning.background_unavailable")
        case let .failedItems(count):
            L10n.string("favorites.sync.warning.failed_items", count)
        case let .uploadPending(count):
            L10n.string("favorites.sync.warning.upload_pending", count)
        }
    }
}

extension FavoriteUpdateRunProgress {
    var displayText: String {
        switch self {
        case let .loadedTargets(count):
            L10n.string("favorites.updates.loaded_targets", count)
        case let .checking(index, total, title):
            L10n.string("favorites.updates.checking_item", index, total, title)
        }
    }
}

extension FavoriteUpdateSummary {
    var displayText: String {
        switch self {
        case let .newReplies(count):
            L10n.string("favorites.updates.summary.replies", count)
        case let .newPages(count):
            L10n.string("favorites.updates.summary.pages", count)
        case .changed:
            L10n.string("favorites.updates.summary.changed")
        }
    }
}
