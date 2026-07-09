import SwiftUI
import YamiboReaderCore

/// One favorite row in the list layouts: cover thumbnail, two-line title,
/// source, plain time lines, and tag chips. No visible buttons — tap resumes
/// reading, long-press opens the context menu, swipes carry delete and tags.
struct LocalFavoriteItemRow: View {
    let card: FavoriteCardProjection
    let showsCover: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let actions: LocalFavoriteCardActions

    var body: some View {
        Button {
            if isSelectionMode {
                onToggleSelection()
            } else {
                actions.open(card.item, .resume)
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !isSelectionMode {
                LocalFavoriteCardContextMenu(card: card, actions: actions)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelectionMode {
                Button(role: .destructive) {
                    actions.delete(card)
                } label: {
                    Label(L10n.string("common.delete"), systemImage: "trash")
                }
                Button {
                    actions.editTags(card.item)
                } label: {
                    Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                }
                .tint(.indigo)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: isSelected)
            }
            if showsCover {
                // Android row cards use a 92dp-wide 0.72-ratio cover.
                LocalFavoriteCoverThumbnail(url: card.coverURL, title: card.item.resolvedDisplayTitle)
                    .frame(width: 92, height: 128)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(card.item.resolvedDisplayTitle)
                    .font(.body)
                    .lineLimit(2)
                Text(card.sourceGroupLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                LocalFavoriteCardTimeLines(card: card)
                LocalFavoriteTagChipRow(tags: card.tags)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
