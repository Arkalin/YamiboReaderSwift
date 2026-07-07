import SwiftUI
import YamiboReaderCore

/// One favorite card in the grid layouts: 3:4 cover, two-line title, source,
/// plain time lines, tag chips. No visible buttons — tap resumes reading,
/// long-press opens the context menu.
struct LocalFavoriteGridCard: View {
    let card: FavoriteCardProjection
    @ObservedObject var selection: LocalFavoriteBrowseSession
    let actions: LocalFavoriteCardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selection.isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: selection.selectedFavoriteIDs.contains(card.id))
            }
            LocalFavoriteGridCover(url: card.coverURL, title: card.item.resolvedDisplayTitle)
            Text(card.item.resolvedDisplayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            Text(card.sourceGroupLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            LocalFavoriteCardTimeLines(card: card)
            LocalFavoriteTagChipRow(tags: card.tags)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if selection.isSelectionMode {
                selection.toggleFavoriteSelection(id: card.id)
            } else {
                actions.open(card.item, .resume)
            }
        }
        .contextMenu {
            if !selection.isSelectionMode {
                LocalFavoriteCardContextMenu(card: card, actions: actions)
            }
        }
    }
}

/// Cover image sized to a 3:4 aspect ratio for grid cards.
struct LocalFavoriteGridCover: View {
    let url: URL?
    let title: String

    var body: some View {
        // Width-driven 3:4 box; the thumbnail fills and clips inside it.
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                LocalFavoriteCoverThumbnail(url: url, title: title)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(maxWidth: .infinity)
    }
}
