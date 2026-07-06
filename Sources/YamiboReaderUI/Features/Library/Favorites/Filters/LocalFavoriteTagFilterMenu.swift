import SwiftUI
import YamiboReaderCore

/// Tag filter submenu for the more menu, with a shortcut into tag management.
struct LocalFavoriteTagFilterMenu: View {
    let tags: [FavoriteTag]
    @Binding var selectedTagIDs: Set<String>
    let onManageTags: () -> Void

    var body: some View {
        Menu {
            if tags.isEmpty {
                Button(action: onManageTags) {
                    Label(L10n.string("favorites.new_tag"), systemImage: "plus")
                }
            } else {
                ForEach(tags) { tag in
                    Button {
                        if selectedTagIDs.contains(tag.id) {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.insert(tag.id)
                        }
                    } label: {
                        if selectedTagIDs.contains(tag.id) {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
                Button {
                    selectedTagIDs.removeAll()
                } label: {
                    Label(L10n.string("favorites.filter.clear_tags"), systemImage: "xmark.circle")
                }
                .disabled(selectedTagIDs.isEmpty)
                Button(action: onManageTags) {
                    Label(L10n.string("favorites.edit_tags"), systemImage: "tag")
                }
            }
        } label: {
            Label(L10n.string("favorites.filter.tags_count", selectedTagIDs.count), systemImage: "tag")
        }
    }
}
