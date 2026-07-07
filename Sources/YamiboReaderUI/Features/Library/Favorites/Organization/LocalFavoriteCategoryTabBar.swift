import SwiftUI
import YamiboReaderCore

/// Horizontal category pill selector. A trailing circular "+" creates a new
/// category; rename/reorder/delete live only in the "管理分类" sheet
/// (toolbar overflow menu). Deliberately no per-pill `.contextMenu` — List
/// can't correctly bridge several independent context menus packed into one
/// row/header (a long-press anywhere fires an arbitrary pill's menu instead
/// of the one under the finger), and the management sheet already covers the
/// same actions plus reordering, so there is no functionality to preserve by
/// working around that.
struct LocalFavoriteCategoryTabBar: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    let routes: LocalFavoritesRoutes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(organizer.categories.manualOrderSorted) { category in
                    pill(for: category)
                }
                createButton
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var createButton: some View {
        Button {
            routes.sheet = .categoryName(LocalFavoriteCategoryNameDraft(mode: .create))
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: Circle())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("favorites.category.create"))
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
    }
}
