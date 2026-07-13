import SwiftUI
import YamiboReaderCore

/// Floating bottom action bar shown while multi-selection is active, in a
/// Liquid Glass container (material fallback below iOS 26). Select-all/invert
/// live in the top-leading toolbar menu and done in the top-trailing button.
/// Nav/tab-bar style: icon over title, evenly distributed. Each action is
/// hidden (not merely disabled) when the current selection can't use it, and
/// the whole bar disappears once nothing is available (i.e. nothing is
/// selected — every action needs at least one selected entry).
struct LocalFavoriteSelectionActionBar: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes

    var body: some View {
        if hasAnyAvailableAction {
            HStack(spacing: 0) {
                if canMove {
                    actionButton(L10n.string("common.move"), systemImage: "folder") {
                        routes.sheet = .selectionMove
                    }
                }
                if canCreateCollection {
                    actionButton(L10n.string("favorites.create_collection"), systemImage: "folder.badge.plus") {
                        routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(mode: .createFromSelection))
                    }
                }
                if canEditTags {
                    actionButton(L10n.string("favorites.tags_action"), systemImage: "tag") {
                        routes.sheet = .tagSelection(.selection(organizer.commonTagIDsForSelection))
                    }
                }
                if let collection = editableCollection {
                    actionButton(L10n.string("common.edit"), systemImage: "pencil") {
                        routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(collection: collection))
                    }
                }
                if canDissolve {
                    actionButton(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus") {
                        routes.dialog = .dissolveSelectedCollections
                    }
                }
                if canDelete {
                    actionButton(L10n.string("common.delete"), systemImage: "trash", tint: .red, role: .destructive) {
                        routes.dialog = .deleteSelection
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .modifier(LocalFavoriteGlassBarBackground())
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        tint: Color? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(tint ?? .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Availability

    /// Move only relocates the selected favorites; a mixed selection would
    /// silently leave any selected collection untouched.
    private var canMove: Bool {
        selection.selectedFavoriteCount > 0 && selection.selectedCollectionCount == 0
    }

    private var canCreateCollection: Bool {
        selection.canCreateCollectionFromSelection
    }

    /// Tags only apply to favorites, not collections — same pure-item
    /// requirement as move.
    private var canEditTags: Bool {
        selection.selectedFavoriteCount > 0 && selection.selectedCollectionCount == 0
    }

    private var editableCollection: LocalFavoriteCollection? {
        guard selection.selectedFavoriteCount == 0 else { return nil }
        return organizer.singleSelectedCollection
    }

    private var canDissolve: Bool {
        selection.selectedCollectionCount > 0 && selection.selectedFavoriteCount == 0
    }

    /// When `FavoriteLibrarySettings.smartMangaBulkDeleteEnabled` is off, a
    /// smart card can be selected but contributes nothing to delete
    /// (`FavoriteLibraryOrganizer.deleteSelection` skips every smart-card
    /// id in that mode) — `hasDeletableSelection` accounts for that, so a
    /// selection made up entirely of smart cards hides this button instead
    /// of showing one that silently does nothing when tapped. When the
    /// setting is on, a smart-card-only selection is fully deletable (its
    /// whole archive), so the button shows.
    private var canDelete: Bool {
        organizer.hasDeletableSelection
    }

    private var hasAnyAvailableAction: Bool {
        canMove || canCreateCollection || canEditTags || editableCollection != nil || canDissolve || canDelete
    }
}

/// Liquid Glass container with a material fallback for pre-iOS-26 systems.
private struct LocalFavoriteGlassBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.quaternary, lineWidth: 0.5)
                }
        }
    }
}

/// Marks selection state on a whole row/card instead of a leading circle:
/// an unselected item dims while multi-selection is active, and a selected
/// one stays full-color with an accent-color border (Android card-selection
/// parity).
struct LocalFavoriteSelectionEmphasis: ViewModifier {
    let isSelectionMode: Bool
    let isSelected: Bool
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .overlay {
                if isSelectionMode, isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2.5)
                }
            }
            .opacity(isSelectionMode && !isSelected ? 0.45 : 1)
            .accessibilityAddTraits(isSelectionMode && isSelected ? .isSelected : [])
    }
}

extension View {
    func favoriteSelectionEmphasis(isSelectionMode: Bool, isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(LocalFavoriteSelectionEmphasis(isSelectionMode: isSelectionMode, isSelected: isSelected, cornerRadius: cornerRadius))
    }
}
