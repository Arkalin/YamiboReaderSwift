import SwiftUI
import YamiboReaderCore

/// List section rendering the favorite item rows.
struct LocalFavoriteItemSection: View {
    let cards: [FavoriteCardProjection]
    let showsCover: Bool
    let showsCount: Bool
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    var body: some View {
        Section {
            ForEach(cards) { card in
                LocalFavoriteItemRow(
                    card: card,
                    showsCover: showsCover,
                    isSelectionMode: selection.isSelectionMode,
                    isSelected: selection.selectedFavoriteIDs.contains(card.id),
                    onToggleSelection: { selection.toggleFavoriteSelection(id: card.id) },
                    onEditTags: { routes.sheet = .tagSelection(.favorite(card.item.id, initialTagIDs: Set(card.item.tagIDs))) },
                    onOpen: onOpen,
                    onDelete: { routes.dialog = .deleteItem(card.item) }
                )
            }
        } header: {
            if showsCount {
                Text(L10n.string("favorites.items_count", cards.count))
            }
        }
    }
}

/// One favorite row in the list layouts.
struct LocalFavoriteItemRow: View {
    let card: FavoriteCardProjection
    let showsCover: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onEditTags: () -> Void
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: isSelected)
            }
            if showsCover {
                LocalFavoriteCoverThumbnail(url: card.coverURL, fallbackColor: .yellow)
                    .frame(width: 48, height: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.item.resolvedDisplayTitle)
                    .font(.body)
                    .lineLimit(2)
                Text(card.sourceGroupLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LocalFavoriteItemMetadataLine(
                    progressPercent: card.progressPercent,
                    chapterPageProgress: card.chapterPageProgress,
                    recentReadingAt: card.recentReadingAt,
                    lastUpdatedAt: card.lastUpdatedAt
                )
                LocalFavoriteTagChipRow(tags: card.tags)
            }
            Spacer(minLength: 8)
            if !isSelectionMode {
                Menu {
                    Button {
                        Task { await onOpen(card.item, .start) }
                    } label: {
                        Label(L10n.string("favorites.open_from_start"), systemImage: "text.page")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.string("common.delete"), systemImage: "trash")
                    }
                    Button(action: onEditTags) {
                        Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(L10n.string("common.more"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                Task { await onOpen(card.item, .resume) }
            }
        }
        .padding(.vertical, 4)
    }
}
