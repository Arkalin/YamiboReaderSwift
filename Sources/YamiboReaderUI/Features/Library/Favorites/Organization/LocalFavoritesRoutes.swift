import Foundation
import YamiboReaderCore

/// Presentation router for the favorites screen: which sheet and which
/// confirmation dialog are currently shown. Child views trigger presentations
/// by assigning to `sheet` or `dialog`; `LocalFavoritesOrganizationView`
/// renders them.
@MainActor
final class LocalFavoritesRoutes: ObservableObject {
    enum Sheet: Identifiable {
        case categoryName(LocalFavoriteCategoryNameDraft)
        case categoryManagement
        case collectionEditor(LocalFavoriteCollectionDraft)
        case tagSelection(LocalFavoriteTagSelectionDraft)
        case selectionMove
        case filters
        case remoteSyncCategory
        case updateFilters

        var id: String {
            switch self {
            case let .categoryName(draft):
                "categoryName-\(draft.id)"
            case .categoryManagement:
                "categoryManagement"
            case let .collectionEditor(draft):
                "collectionEditor-\(draft.id)"
            case let .tagSelection(draft):
                "tagSelection-\(draft.id)"
            case .selectionMove:
                "selectionMove"
            case .filters:
                "filters"
            case .remoteSyncCategory:
                "remoteSyncCategory"
            case .updateFilters:
                "updateFilters"
            }
        }
    }

    enum Dialog: Identifiable {
        case dissolveCollection(LocalFavoriteCollection)
        case deleteItem(FavoriteItem)
        /// A merged (`FavoriteCardProjection.isMergedGroup`) card's delete
        /// confirmation — smart-comic-mode decision #6: no per-chapter
        /// removal UI, unfavoriting removes every member, so the dialog
        /// carries the full member list to display their titles before the
        /// user confirms (not just a count).
        case deleteMergedGroup(members: [FavoriteItem])
        case deleteSelection
        case dissolveSelectedCollections

        var id: String {
            switch self {
            case let .dissolveCollection(collection):
                "dissolveCollection-\(collection.id)"
            case let .deleteItem(item):
                "deleteItem-\(item.id)"
            case let .deleteMergedGroup(members):
                "deleteMergedGroup-\(members.map(\.id).joined(separator: ","))"
            case .deleteSelection:
                "deleteSelection"
            case .dissolveSelectedCollections:
                "dissolveSelectedCollections"
            }
        }
    }

    @Published var sheet: Sheet?
    @Published var dialog: Dialog?
    /// The sync progress page is pushed (a full screen, not a sheet).
    @Published var isSyncProgressPushed = false
    /// The favorite-updates page is pushed (toolbar bell entry).
    @Published var isUpdatesPagePushed = false
}
