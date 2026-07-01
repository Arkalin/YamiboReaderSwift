import SwiftUI
import UniformTypeIdentifiers
import YamiboReaderCore

#if canImport(UIKit)
import UIKit
#endif

struct FavoriteSearchModifier: ViewModifier {
    @Binding var searchText: String

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationBarTitleDisplayMode(.inline)
        #else
        content
            .searchable(text: $searchText, prompt: L10n.string("common.search"))
        #endif
    }
}

#if os(iOS)
struct FavoriteNativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = L10n.string("common.search")
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.enablesReturnKeyAutomatically = false
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        if searchBar.text != text {
            searchBar.text = text
        }
        let textColor = UIColor(hex: colorScheme == .dark ? 0xF4E7D1 : 0x2E1A0E)
        let secondaryTextColor = UIColor(hex: colorScheme == .dark ? 0xD6A083 : 0x6D3A2B).withAlphaComponent(0.72)

        searchBar.backgroundColor = .clear
        searchBar.barTintColor = .clear
        searchBar.backgroundImage = .transparentPixel
        searchBar.setSearchFieldBackgroundImage(.transparentPixel, for: .normal)
        searchBar.tintColor = secondaryTextColor

        let textField = searchBar.searchTextField
        textField.backgroundColor = .clear
        textField.background = nil
        textField.textColor = textColor
        textField.tintColor = secondaryTextColor
        textField.leftView?.tintColor = secondaryTextColor
        textField.attributedPlaceholder = NSAttributedString(
            string: L10n.string("common.search"),
            attributes: [.foregroundColor: secondaryTextColor]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(false, animated: true)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.text = ""
            text = ""
            searchBar.resignFirstResponder()
            searchBar.setShowsCancelButton(false, animated: true)
        }
    }
}

private extension UIImage {
    static var transparentPixel: UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { _ in }
    }
}
#endif

private struct FavoriteSortMenuButton: View {
    @Binding var sortRawValue: String

    var body: some View {
        Menu {
            Picker(L10n.string("favorites.sort"), selection: $sortRawValue) {
                ForEach(FavoriteSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title).tag(sortOrder.rawValue)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }
}

private struct FavoriteSelectionToggleButton: View {
    let isSelecting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelecting {
                Text(L10n.string("common.done"))
            } else {
                Image(systemName: "checkmark.circle")
            }
        }
        .accessibilityLabel(isSelecting ? L10n.string("common.done") : L10n.string("common.select"))
    }
}

private struct FavoriteToolbarMenuButton: View {
    @Binding var filterRawValue: String
    let favoriteAppearance: FavoriteAppearanceSettings
    let selectedTagCount: Int
    let allTitle: String
    let onEditTagFilter: () -> Void
    let onClearTagFilter: () -> Void

    var body: some View {
        Menu {
            Picker(L10n.string("favorites.category"), selection: $filterRawValue) {
                ForEach(FavoriteFilter.allCases) { filter in
                    Label {
                        Text(filter == .all ? allTitle : filter.title)
                    } icon: {
                        filter.menuIcon(appearance: favoriteAppearance)
                    }
                    .tag(filter.rawValue)
                }
            }

            Button(action: onEditTagFilter) {
                Label(tagFilterTitle, systemImage: "tag")
            }

            if selectedTagCount > 0 {
                Button(action: onClearTagFilter) {
                    Label(L10n.string("favorites.filter.clear_tags"), systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private var currentFilter: FavoriteFilter {
        FavoriteFilter(rawValue: filterRawValue) ?? .all
    }

    private var currentTitle: String {
        currentFilter == .all ? allTitle : currentFilter.title
    }

    private var tagFilterTitle: String {
        guard selectedTagCount > 0 else {
            return L10n.string("favorites.filter.tags")
        }
        return L10n.string("favorites.filter.tags_count", selectedTagCount)
    }
}

private extension FavoriteFilter {
    var menuIconName: String {
        switch self {
        case .all:
            "square.grid.2x2.fill"
        }
    }

    @ViewBuilder
    func menuIcon(appearance: FavoriteAppearanceSettings) -> some View {
        #if canImport(UIKit)
        if let icon = UIImage(systemName: menuIconName)?
            .withTintColor(menuUIColor(appearance: appearance), renderingMode: .alwaysOriginal) {
            Image(uiImage: icon)
        } else {
            Image(systemName: menuIconName)
                .foregroundStyle(menuColor(appearance: appearance))
        }
        #else
        Image(systemName: menuIconName)
            .foregroundStyle(menuColor(appearance: appearance))
        #endif
    }

    func menuColor(appearance: FavoriteAppearanceSettings) -> Color {
        switch self {
        case .all:
            .black
        }
    }

    #if canImport(UIKit)
    func menuUIColor(appearance: FavoriteAppearanceSettings) -> UIColor {
        switch self {
        case .all:
            .black
        }
    }
    #endif
}

struct FavoriteToolbarModifier: ViewModifier {
    @Binding var filterRawValue: String
    @Binding var sortRawValue: String
    @Binding var isSelecting: Bool
    let favoriteAppearance: FavoriteAppearanceSettings
    let showsSettingsMenu: Bool
    let selectedTagCount: Int
    let visibleSelectionIsComplete: Bool
    let canToggleVisibleSelection: Bool
    let allTitle: String
    let onFinishSelection: () -> Void
    let onToggleVisibleSelection: () -> Void
    let onEditTagFilter: () -> Void
    let onClearTagFilter: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            #if os(iOS)
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        visibleSelectionIsComplete ? L10n.string("common.invert_selection") : L10n.string("common.select_all"),
                        action: onToggleVisibleSelection
                    )
                    .disabled(!canToggleVisibleSelection)
                }
            } else if showsSettingsMenu {
                ToolbarItemGroup(placement: .topBarLeading) {
                    FavoriteSortMenuButton(sortRawValue: $sortRawValue)
                }
            }
            #else
            if showsSettingsMenu {
                ToolbarItem(placement: .automatic) {
                    FavoriteSortMenuButton(sortRawValue: $sortRawValue)
                }
            }
            #endif

            ToolbarItem(placement: .principal) {
                FavoriteToolbarMenuButton(
                    filterRawValue: $filterRawValue,
                    favoriteAppearance: favoriteAppearance,
                    selectedTagCount: selectedTagCount,
                    allTitle: allTitle,
                    onEditTagFilter: onEditTagFilter,
                    onClearTagFilter: onClearTagFilter
                )
            }

            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteSelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        onFinishSelection()
                    } else {
                        isSelecting = true
                    }
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                FavoriteSelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        onFinishSelection()
                    } else {
                        isSelecting = true
                    }
                }
            }
            #endif
        }
    }
}

struct FavoriteCollectionDialogsModifier: ViewModifier {
    @Binding var collectionNameDraft: FavoriteCollectionNameDraft?
    @Binding var pendingDeleteCollection: FavoriteCollection?
    let saveName: (FavoriteCollectionNameDraft) -> Void
    let dissolveCollection: (FavoriteCollection) -> Void

    func body(content: Content) -> some View {
        content
            .alert(L10n.string("favorites.edit_collection_name"), isPresented: collectionNameAlertBinding) {
                TextField(L10n.string("favorites.collection_name"), text: collectionNameTextBinding)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    collectionNameDraft = nil
                }
                Button(L10n.string("common.save")) {
                    guard let draft = collectionNameDraft else { return }
                    saveName(draft)
                }
                .disabled(collectionNameDraft?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            } message: {
                Text(L10n.string("favorites.collection_name_message"))
            }
            .alert(
                L10n.string("favorites.dissolve_collection"),
                isPresented: pendingCollectionDeleteAlertBinding,
                presenting: pendingDeleteCollection
            ) { collection in
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteCollection = nil
                }
                Button(L10n.string("favorites.dissolve"), role: .destructive) {
                    dissolveCollection(collection)
                }
            } message: { collection in
                Text(L10n.string("favorites.dissolve_collection_message", collection.name))
            }
    }

    private var collectionNameAlertBinding: Binding<Bool> {
        Binding(
            get: { collectionNameDraft != nil },
            set: { isPresented in
                if !isPresented {
                    collectionNameDraft = nil
                }
            }
        )
    }

    private var collectionNameTextBinding: Binding<String> {
        Binding(
            get: { collectionNameDraft?.name ?? "" },
            set: { collectionNameDraft?.name = $0 }
        )
    }

    private var pendingCollectionDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCollection != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteCollection = nil
                }
            }
        )
    }
}

struct FavoriteEntryDropDelegate: DropDelegate {
    let draggedEntryKey: String?
    let targetEntry: FavoriteListEntry?
    let column: FavoriteListColumn
    let canReorder: Bool
    let onDropOnEntry: (String, FavoriteListEntry, FavoriteDropPosition) -> Void
    let onDropToColumnBottom: (String, FavoriteListColumn) -> Void
    let onFinish: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        canReorder && draggedEntryKey != nil && info.hasItemsConforming(to: [UTType.plainText.identifier])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder, draggedEntryKey != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canReorder, let draggedEntryKey else { return false }

        if let targetEntry {
            let position: FavoriteDropPosition = info.location.y < 56 ? .before : .after
            onDropOnEntry(draggedEntryKey, targetEntry, position)
        } else {
            onDropToColumnBottom(draggedEntryKey, column)
        }

        onFinish()
        return true
    }
}
