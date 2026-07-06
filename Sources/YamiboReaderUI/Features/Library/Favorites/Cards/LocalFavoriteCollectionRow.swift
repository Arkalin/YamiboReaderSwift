import SwiftUI
import YamiboReaderCore

/// One collection row in the list layouts.
struct LocalFavoriteCollectionRow: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let isSelectionMode: Bool
    let isSelected: Bool
    let previewCoverURLs: [URL]
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMove: (CategoryMoveDirection) async -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        HStack(spacing: 12) {
            LocalFavoriteCollectionCoverPreview(
                color: collection.color.swiftUIColor,
                coverURLs: previewCoverURLs
            )
            if isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: isSelected)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.body)
                    .lineLimit(1)
                Text(L10n.string("favorites.collection_summary", itemCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !isSelectionMode {
                LocalFavoriteCollectionMenu(
                    collection: collection,
                    categories: categories,
                    onEdit: onEdit,
                    onDissolve: onDissolve,
                    onMove: onMove,
                    onMoveToCategory: onMoveToCategory
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onOpen()
            }
        }
    }
}

/// One collection card in the grid layouts.
struct LocalFavoriteCollectionCard: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let isSelectionMode: Bool
    let isSelected: Bool
    let previewCoverURLs: [URL]
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMove: (CategoryMoveDirection) async -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                LocalFavoriteCollectionCoverPreview(
                    color: collection.color.swiftUIColor,
                    coverURLs: previewCoverURLs
                )
                if isSelectionMode {
                    LocalFavoriteSelectionIndicator(isSelected: isSelected)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(L10n.string("favorites.collection_summary", itemCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !isSelectionMode {
                    LocalFavoriteCollectionMenu(
                        collection: collection,
                        categories: categories,
                        onEdit: onEdit,
                        onDissolve: onDissolve,
                        onMove: onMove,
                        onMoveToCategory: onMoveToCategory
                    )
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onOpen()
            }
        }
    }
}

/// Shared context menu for collection rows and cards.
struct LocalFavoriteCollectionMenu: View {
    let collection: LocalFavoriteCollection
    let categories: [FavoriteCategory]
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMove: (CategoryMoveDirection) async -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        Menu {
            Button(action: onEdit) {
                Label(L10n.string("common.edit"), systemImage: "pencil")
            }
            Button {
                Task { await onMove(.up) }
            } label: {
                Label(L10n.string("favorites.category.move_up"), systemImage: "arrow.up")
            }
            Button {
                Task { await onMove(.down) }
            } label: {
                Label(L10n.string("favorites.category.move_down"), systemImage: "arrow.down")
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
            Image(systemName: "ellipsis")
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(L10n.string("common.more"))
    }
}
