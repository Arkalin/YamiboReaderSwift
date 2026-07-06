import SwiftUI
import YamiboReaderCore

/// Two-column staggered arrangement of grid cards.
struct LocalFavoriteStaggeredCards: View {
    let cards: [FavoriteCardProjection]
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: 12) {
                    ForEach(columnCards(column)) { card in
                        LocalFavoriteGridCard(
                            card: card,
                            fixedHeight: nil,
                            selection: selection,
                            routes: routes,
                            onOpen: onOpen
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func columnCards(_ column: Int) -> [FavoriteCardProjection] {
        cards.enumerated().compactMap { index, card in
            index % 2 == column ? card : nil
        }
    }
}

/// One favorite card in the grid layouts.
struct LocalFavoriteGridCard: View {
    let card: FavoriteCardProjection
    let fixedHeight: CGFloat?
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let routes: LocalFavoritesRoutes
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selection.isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: selection.selectedFavoriteIDs.contains(card.id))
            }
            LocalFavoriteGridCover(url: card.coverURL, fallbackColor: .yellow)
            Text(card.item.resolvedDisplayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(fixedHeight == nil ? 3 : 2)
            Text(card.sourceGroupLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            LocalFavoriteItemMetadataLine(
                progressPercent: card.progressPercent,
                chapterPageProgress: card.chapterPageProgress,
                recentReadingAt: card.recentReadingAt,
                lastUpdatedAt: card.lastUpdatedAt
            )
            LocalFavoriteTagChipRow(tags: card.tags)
            Spacer(minLength: 0)
            if !selection.isSelectionMode {
                HStack {
                    Button {
                        Task { await onOpen(card.item, .resume) }
                    } label: {
                        Image(systemName: "book")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Menu {
                        Button {
                            Task { await onOpen(card.item, .start) }
                        } label: {
                            Label(L10n.string("favorites.open_from_start"), systemImage: "text.page")
                        }
                        Button(role: .destructive) {
                            routes.dialog = .deleteItem(card.item)
                        } label: {
                            Label(L10n.string("common.delete"), systemImage: "trash")
                        }
                        Button {
                            routes.sheet = .tagSelection(.favorite(card.item.id, initialTagIDs: Set(card.item.tagIDs)))
                        } label: {
                            Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(L10n.string("common.more"))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .top)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if selection.isSelectionMode {
                selection.toggleFavoriteSelection(id: card.id)
            } else {
                Task { await onOpen(card.item, .resume) }
            }
        }
    }
}

/// Cover image sized to a 3:4 aspect ratio for grid cards.
struct LocalFavoriteGridCover: View {
    let url: URL?
    let fallbackColor: Color

    var body: some View {
        GeometryReader { proxy in
            LocalFavoriteCoverThumbnail(url: url, fallbackColor: fallbackColor)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}
