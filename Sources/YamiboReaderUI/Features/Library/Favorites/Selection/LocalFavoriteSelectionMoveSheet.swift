import SwiftUI
import YamiboReaderCore

/// Sheet for moving or adding the current selection into categories and
/// collections, or removing it from the current location.
struct LocalFavoriteSelectionMoveSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var selection: LocalFavoriteBrowseSession

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.string("favorites.location.move_to_category")) {
                    ForEach(organizer.categories.manualOrderSorted) { category in
                        Button {
                            Task {
                                await organizer.moveSelectionToCategory(id: category.id)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(category.displayName)
                                Spacer()
                                if category.id == organizer.selectedCategoryID && organizer.selectedCollection == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                if selection.selectedFavoriteCount > 0 && selection.selectedCollectionCount == 0 {
                    Section(L10n.string("favorites.location.move_to_collection")) {
                        ForEach(sortedCollections) { collection in
                            Button {
                                Task {
                                    await organizer.moveSelectionToCollection(id: collection.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    LocalFavoriteCollectionCoverPreview(
                                        color: collection.color.swiftUIColor,
                                        coverURLs: []
                                    )
                                    .frame(width: 32, height: 32)
                                    Text(collection.name)
                                    Spacer()
                                    if collection.id == organizer.selectedCollection?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if selection.selectedFavoriteCount > 0 {
                    Section(L10n.string("favorites.location.add_to_category")) {
                        ForEach(organizer.categories.manualOrderSorted) { category in
                            Button {
                                Task {
                                    await organizer.addSelectionToCategory(id: category.id)
                                    dismiss()
                                }
                            } label: {
                                Text(category.displayName)
                            }
                        }
                    }
                    Section(L10n.string("favorites.location.add_to_collection")) {
                        ForEach(sortedCollections) { collection in
                            Button {
                                Task {
                                    await organizer.addSelectionToCollection(id: collection.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    LocalFavoriteCollectionCoverPreview(
                                        color: collection.color.swiftUIColor,
                                        coverURLs: []
                                    )
                                    .frame(width: 32, height: 32)
                                    Text(collection.name)
                                }
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await organizer.removeSelectionFromCurrentLocation()
                                dismiss()
                            }
                        } label: {
                            Label(L10n.string("favorites.location.remove_current"), systemImage: "minus.circle")
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("favorites.location.manage"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var sortedCollections: [LocalFavoriteCollection] {
        organizer.collections.sorted { lhs, rhs in
            if lhs.categoryID != rhs.categoryID {
                return lhs.categoryID < rhs.categoryID
            }
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }
}
