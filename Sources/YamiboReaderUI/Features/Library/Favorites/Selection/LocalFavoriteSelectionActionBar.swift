import SwiftUI
import YamiboReaderCore

/// Bottom action bar shown while multi-selection is active.
struct LocalFavoriteSelectionActionBar: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.string("favorites.selected_count", selection.selectedEntryCount))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(L10n.string("common.done")) {
                    selection.exitSelectionMode()
                }
                .buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button {
                        organizer.selectAllVisible()
                    } label: {
                        Label(L10n.string("common.select_all"), systemImage: "checkmark.circle")
                    }
                    Button {
                        organizer.invertVisibleSelection()
                    } label: {
                        Label(L10n.string("common.invert_selection"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        routes.sheet = .selectionMove
                    } label: {
                        Label(L10n.string("common.move"), systemImage: "folder")
                    }
                    .disabled(selection.selectedEntryCount == 0)
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
                    if let collection = organizer.singleSelectedCollection, selection.selectedFavoriteCount == 0 {
                        Button {
                            routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(collection: collection))
                        } label: {
                            Label(L10n.string("common.edit"), systemImage: "pencil")
                        }
                    }
                    Button {
                        routes.dialog = .dissolveSelectedCollections
                    } label: {
                        Label(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus")
                    }
                    .disabled(selection.selectedCollectionCount == 0)
                    Button(role: .destructive) {
                        routes.dialog = .deleteSelection
                    } label: {
                        Label(L10n.string("common.delete"), systemImage: "trash")
                    }
                    .disabled(selection.selectedEntryCount == 0)
                    Button {
                        selection.clearSelection()
                    } label: {
                        Label(L10n.string("common.clear"), systemImage: "xmark.circle")
                    }
                    .disabled(selection.selectedEntryCount == 0)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
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
