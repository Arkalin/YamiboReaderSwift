import SwiftUI
import YamiboReaderCore

/// Source-group (forum board / manga title) filter picker for the more menu.
struct LocalFavoriteSourceGroupPicker: View {
    @Binding var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    let sourceGroupEntryCounts: [FavoriteSourceGroup: Int]
    let showsCounts: Bool

    var body: some View {
        Picker(L10n.string("favorites.source_group"), selection: $sourceGroupFilter) {
            Text(L10n.string("favorites.filter.all"))
                .tag(LocalFavoriteLibrarySourceGroupFilter.all)
            ForEach(availableSourceGroups, id: \.self) { sourceGroup in
                Text(sourceGroupTitle(sourceGroup))
                    .tag(LocalFavoriteLibrarySourceGroupFilter.group(sourceGroup))
            }
        }
    }

    private var availableSourceGroups: [FavoriteSourceGroup] {
        sourceGroupEntryCounts.keys
            .sorted { $0.displayLabel.localizedCaseInsensitiveCompare($1.displayLabel) == .orderedAscending }
    }

    private func sourceGroupTitle(_ sourceGroup: FavoriteSourceGroup) -> String {
        guard showsCounts else { return sourceGroup.displayLabel }
        return "\(sourceGroup.displayLabel) (\(sourceGroupEntryCounts[sourceGroup] ?? 0))"
    }
}
