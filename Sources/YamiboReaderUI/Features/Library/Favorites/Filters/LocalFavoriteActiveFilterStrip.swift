import SwiftUI
import YamiboReaderCore

/// Horizontal chips showing the active source-group and tag filters, with
/// one-tap clearing.
struct LocalFavoriteActiveFilterStrip: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer

    var body: some View {
        if organizer.filter.hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if case let .group(sourceGroup) = organizer.filter.sourceGroupFilter {
                        LocalFavoriteFilterChip(
                            title: sourceGroup.displayLabel,
                            systemImage: "line.3.horizontal.decrease.circle",
                            onClear: { organizer.filter.sourceGroupFilter = .all }
                        )
                    }
                    let selectedTags = organizer.tags.filter { organizer.filter.selectedTagIDs.contains($0.id) }
                    ForEach(selectedTags) { tag in
                        LocalFavoriteFilterChip(
                            title: tag.name,
                            systemImage: "tag",
                            tint: tag.color.swiftUIColor,
                            onClear: { organizer.filter.selectedTagIDs.removeAll() }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct LocalFavoriteFilterChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            Label {
                HStack(spacing: 4) {
                    Text(title)
                        .lineLimit(1)
                    Image(systemName: "xmark.circle.fill")
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
