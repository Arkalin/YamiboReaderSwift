import SwiftUI
import YamiboReaderCore

/// Horizontal category pill selector. Pure pills — creation and management
/// live in the toolbar menu; long-pressing a pill offers rename and delete.
struct LocalFavoriteCategoryTabBar: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    let routes: LocalFavoritesRoutes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(organizer.categories.manualOrderSorted) { category in
                    pill(for: category)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func pill(for category: FavoriteCategory) -> some View {
        let isSelected = category.id == organizer.selectedCategoryID
        return Button {
            organizer.selectedCategoryID = category.id
        } label: {
            HStack(spacing: 6) {
                Text(category.displayName)
                    .lineLimit(1)
                if organizer.showsCategoryBadges {
                    Text("\(organizer.derived.categoryEntryCounts[category.id] ?? 0)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !category.isDefault {
                Button {
                    routes.sheet = .categoryName(LocalFavoriteCategoryNameDraft(mode: .rename(category.id)))
                } label: {
                    Label(L10n.string("favorites.category.rename"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    routes.sheet = .categoryManagement
                } label: {
                    Label(L10n.string("favorites.category.delete"), systemImage: "trash")
                }
            }
            Button {
                routes.sheet = .categoryManagement
            } label: {
                Label(L10n.string("favorites.category.manage"), systemImage: "slider.horizontal.3")
            }
        }
    }
}
