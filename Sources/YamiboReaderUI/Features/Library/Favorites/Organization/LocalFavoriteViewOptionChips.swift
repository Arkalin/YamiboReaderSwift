import SwiftUI
import YamiboReaderCore

/// Context row under the category bar (Android parity): the current scope's
/// name on the left, layout and sort menu chips on the right.
struct LocalFavoriteViewOptionChips: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer

    var body: some View {
        HStack(spacing: 8) {
            Text(scopeLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Picker(L10n.string("favorites.layout"), selection: layoutModeBinding) {
                    ForEach(FavoriteLibraryLayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImageName)
                            .tag(mode)
                    }
                }
            } label: {
                chipLabel(
                    text: L10n.string("favorites.chip.layout", organizer.display.layoutMode.title),
                    systemImage: "square.grid.2x2"
                )
            }
            Menu {
                Picker(L10n.string("favorites.sort"), selection: sortOrderBinding) {
                    ForEach(LocalFavoriteLibrarySortOrder.allCases) { order in
                        Text(order.title)
                            .tag(order)
                    }
                }
                Toggle(isOn: sortDescendingBinding) {
                    Label(L10n.string("favorites.sort.descending"), systemImage: "arrow.down")
                }
            } label: {
                chipLabel(
                    text: L10n.string(
                        "favorites.chip.sort",
                        organizer.filter.sortOrder.title,
                        organizer.filter.sortDescending ? "↓" : "↑"
                    ),
                    systemImage: "arrow.up.arrow.down"
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var scopeLabel: String {
        if let collection = organizer.selectedCollection {
            return L10n.string("favorites.collection_summary", organizer.derived.cards.count)
                + " · " + collection.name
        }
        return organizer.categories.first { $0.id == organizer.selectedCategoryID }?.displayName ?? ""
    }

    private func chipLabel(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleOnly)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.primary)
    }

    private var sortOrderBinding: Binding<LocalFavoriteLibrarySortOrder> {
        Binding(
            get: { organizer.filter.sortOrder },
            set: { organizer.updateSortOrder($0) }
        )
    }

    private var sortDescendingBinding: Binding<Bool> {
        Binding(
            get: { organizer.filter.sortDescending },
            set: { organizer.updateSortDescending($0) }
        )
    }

    private var layoutModeBinding: Binding<FavoriteLibraryLayoutMode> {
        Binding(
            get: { organizer.display.layoutMode },
            set: { organizer.updateLayoutMode($0) }
        )
    }
}
