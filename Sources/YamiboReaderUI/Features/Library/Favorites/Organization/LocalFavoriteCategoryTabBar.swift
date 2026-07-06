import SwiftUI
import YamiboReaderCore

/// Horizontal category selector with create and manage shortcuts.
struct LocalFavoriteCategoryTabBar: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    let routes: LocalFavoritesRoutes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(organizer.categories.manualOrderSorted) { category in
                    Button {
                        organizer.selectedCategoryID = category.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(category.displayName)
                                .lineLimit(1)
                            if organizer.showsCategoryBadges {
                                Text("\(organizer.derived.categoryEntryCounts[category.id] ?? 0)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(category.id == organizer.selectedCategoryID ? .white.opacity(0.78) : .secondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            category.id == organizer.selectedCategoryID ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundStyle(category.id == organizer.selectedCategoryID ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    routes.sheet = .categoryName(LocalFavoriteCategoryNameDraft(mode: .create))
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.category.create"))
                Button {
                    routes.sheet = .categoryManagement
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.category.manage"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
