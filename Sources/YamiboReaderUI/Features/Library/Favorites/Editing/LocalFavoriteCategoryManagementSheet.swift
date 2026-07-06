import SwiftUI
import YamiboReaderCore

/// Category management sheet: select, rename, reorder, and delete categories.
struct LocalFavoriteCategoryManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeleteCategory: FavoriteCategory?

    @ObservedObject var organizer: FavoriteLibraryOrganizer
    let routes: LocalFavoritesRoutes

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedCategories) { category in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.displayName)
                            if organizer.display.showsCategoryCounts {
                                Text(L10n.string("favorites.items_count", organizer.derived.categoryEntryCounts[category.id] ?? 0))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if category.id == organizer.selectedCategoryID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        if !category.isDefault {
                            Menu {
                                Button {
                                    organizer.selectedCategoryID = category.id
                                } label: {
                                    Label(L10n.string("favorites.category.select"), systemImage: "checkmark.circle")
                                }
                                Button {
                                    routes.sheet = .categoryName(LocalFavoriteCategoryNameDraft(
                                        mode: .rename(category.id),
                                        initialName: category.displayName
                                    ))
                                } label: {
                                    Label(L10n.string("favorites.category.rename"), systemImage: "pencil")
                                }
                                Button {
                                    Task { await organizer.moveCategory(id: category.id, direction: .up) }
                                } label: {
                                    Label(L10n.string("favorites.category.move_up"), systemImage: "arrow.up")
                                }
                                .disabled(!canMove(category, direction: .up))
                                Button {
                                    Task { await organizer.moveCategory(id: category.id, direction: .down) }
                                } label: {
                                    Label(L10n.string("favorites.category.move_down"), systemImage: "arrow.down")
                                }
                                .disabled(!canMove(category, direction: .down))
                                Button(role: .destructive) {
                                    pendingDeleteCategory = category
                                } label: {
                                    Label(L10n.string("favorites.category.delete"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel(L10n.string("common.more"))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        organizer.selectedCategoryID = category.id
                    }
                }
            }
            .navigationTitle(L10n.string("favorites.category.manage"))
            .alert(
                L10n.string("favorites.category.delete"),
                isPresented: deleteCategoryAlertBinding
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteCategory = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    if let pendingDeleteCategory {
                        Task {
                            await organizer.deleteCategory(id: pendingDeleteCategory.id)
                            self.pendingDeleteCategory = nil
                        }
                    }
                }
            } message: {
                if let pendingDeleteCategory {
                    Text(
                        L10n.string(
                            "favorites.category.delete_message",
                            pendingDeleteCategory.displayName,
                            organizer.derived.categoryEntryCounts[pendingDeleteCategory.id] ?? 0
                        )
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var deleteCategoryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCategory != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteCategory = nil
                }
            }
        )
    }

    private var sortedCategories: [FavoriteCategory] {
        organizer.categories.manualOrderSorted
    }

    private var movableCategories: [FavoriteCategory] {
        sortedCategories.filter { !$0.isDefault }
    }

    private func canMove(_ category: FavoriteCategory, direction: CategoryMoveDirection) -> Bool {
        guard let index = movableCategories.firstIndex(where: { $0.id == category.id }) else { return false }
        switch direction {
        case .up:
            return index > 0
        case .down:
            return index < movableCategories.count - 1
        }
    }
}
