import SwiftUI
import YamiboReaderCore

/// List-section wrapper around the scope header shown while browsing inside
/// a collection.
struct LocalFavoriteCollectionScopeSection: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        Section {
            LocalFavoriteCollectionScopeHeader(
                collection: collection,
                itemCount: itemCount,
                categories: categories,
                onBack: onBack,
                onEdit: onEdit,
                onDissolve: onDissolve,
                onMoveToCategory: onMoveToCategory
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}

/// Header with back button and collection actions while browsing inside a
/// collection.
struct LocalFavoriteCollectionScopeHeader: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("common.back"))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(collection.color.swiftUIColor)
                .frame(width: 10, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(L10n.string("favorites.collection_summary", itemCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button(action: onEdit) {
                    Label(L10n.string("common.edit"), systemImage: "pencil")
                }
                Menu {
                    ForEach(categories.manualOrderSorted) { category in
                        Button {
                            Task { await onMoveToCategory(category.id) }
                        } label: {
                            if category.id == collection.categoryID {
                                Label(category.displayName, systemImage: "checkmark")
                            } else {
                                Text(category.displayName)
                            }
                        }
                        .disabled(category.id == collection.categoryID)
                    }
                } label: {
                    Label(L10n.string("favorites.category.select"), systemImage: "folder")
                }
                Button(role: .destructive, action: onDissolve) {
                    Label(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(L10n.string("common.more"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
