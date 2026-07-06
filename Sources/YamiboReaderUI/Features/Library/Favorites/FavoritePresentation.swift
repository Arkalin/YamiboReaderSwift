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
