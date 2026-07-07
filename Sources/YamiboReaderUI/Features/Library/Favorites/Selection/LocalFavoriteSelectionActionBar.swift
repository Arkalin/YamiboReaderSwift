import SwiftUI
import YamiboReaderCore

/// Floating bottom action bar shown while multi-selection is active, in a
/// Liquid Glass container (material fallback below iOS 26). Select-all/invert
/// live in the top-leading toolbar menu and done in the top-trailing button;
/// this bar carries the actions, always visible and disabled when the current
/// selection cannot use them.
struct LocalFavoriteSelectionActionBar: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button {
                    routes.sheet = .selectionMove
                } label: {
                    Label(L10n.string("common.move"), systemImage: "folder")
                }
                .disabled(selection.selectedFavoriteCount == 0)

                Button {
                    routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(mode: .createFromSelection))
                } label: {
                    Label(L10n.string("favorites.create_collection"), systemImage: "folder.badge.plus")
                }
                .disabled(!selection.canCreateCollectionFromSelection)

                Button {
                    routes.sheet = .tagSelection(.selection(organizer.commonTagIDsForSelection))
                } label: {
                    Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                }
                .disabled(selection.selectedFavoriteCount == 0)

                Button {
                    if let collection = organizer.singleSelectedCollection {
                        routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(collection: collection))
                    }
                } label: {
                    Label(L10n.string("common.edit"), systemImage: "pencil")
                }
                .disabled(organizer.singleSelectedCollection == nil || selection.selectedFavoriteCount > 0)

                Button {
                    routes.dialog = .dissolveSelectedCollections
                } label: {
                    Label(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus")
                }
                .disabled(selection.selectedCollectionCount == 0 || selection.selectedFavoriteCount > 0)

                Button(role: .destructive) {
                    routes.dialog = .deleteSelection
                } label: {
                    Label(L10n.string("common.delete"), systemImage: "trash")
                }
                .disabled(selection.selectedEntryCount == 0)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .modifier(LocalFavoriteGlassBarBackground())
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

/// Liquid Glass container with a material fallback for pre-iOS-26 systems.
private struct LocalFavoriteGlassBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.quaternary, lineWidth: 0.5)
                }
        }
    }
}

/// Round check indicator shown next to rows and cards in selection mode.
struct LocalFavoriteSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 28)
            .accessibilityLabel(isSelected ? L10n.string("common.current") : L10n.string("common.select"))
    }
}
