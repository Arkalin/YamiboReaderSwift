import SwiftUI
import YamiboReaderCore

/// Item actions reachable from a card's context menu and swipe actions.
/// Cards carry no visible buttons: tap continues reading, long-press opens
/// the menu (mirroring the Android cards, expressed as the iOS context menu).
struct LocalFavoriteCardActions {
    let open: (FavoriteItem, FavoriteLaunchMode) -> Void
    let select: (FavoriteItem) -> Void
    let move: (FavoriteItem) -> Void
    let editTags: (FavoriteItem) -> Void
    let toggleTextCover: (FavoriteItem) -> Void
    let syncToRemote: (FavoriteItem) -> Void
    /// Takes the whole card projection (not just `card.item`) so it can tell
    /// a merged group apart from a standalone favorite (smart-comic-mode
    /// decision #6) and route to the right confirmation dialog.
    let delete: (FavoriteCardProjection) -> Void

    /// Standard wiring shared by the list and grid containers.
    @MainActor
    static func standard(
        organizer: FavoriteLibraryOrganizer,
        selection: LocalFavoriteBrowseSession,
        routes: LocalFavoritesRoutes,
        onOpen: @escaping (FavoriteItem, FavoriteLaunchMode) async -> Void
    ) -> LocalFavoriteCardActions {
        LocalFavoriteCardActions(
            open: { item, mode in
                Task { await onOpen(item, mode) }
            },
            select: { item in
                selection.toggleFavoriteSelection(id: item.id)
            },
            move: { item in
                selection.toggleFavoriteSelection(id: item.id)
                routes.sheet = .selectionMove
            },
            editTags: { item in
                routes.sheet = .tagSelection(.favorite(item.id, initialTagIDs: Set(item.tagIDs)))
            },
            toggleTextCover: { item in
                Task { await organizer.toggleTextCover(for: item) }
            },
            syncToRemote: { item in
                Task { await organizer.syncItemToYamibo(item) }
            },
            delete: { card in
                if let members = card.mergedMembers {
                    routes.dialog = .deleteMergedGroup(members: members)
                } else {
                    routes.dialog = .deleteItem(card.item)
                }
            }
        )
    }
}

/// Shared context-menu content for a favorite item card.
struct LocalFavoriteCardContextMenu: View {
    let card: FavoriteCardProjection
    let actions: LocalFavoriteCardActions

    var body: some View {
        Button {
            actions.open(card.item, .resume)
        } label: {
            Label(L10n.string("favorites.open_resume"), systemImage: "book")
        }
        Button {
            actions.open(card.item, .start)
        } label: {
            Label(L10n.string("favorites.open_from_start"), systemImage: "text.page")
        }
        Divider()
        Button {
            actions.select(card.item)
        } label: {
            Label(L10n.string("common.select"), systemImage: "checkmark.circle")
        }
        Button {
            actions.move(card.item)
        } label: {
            Label(L10n.string("favorites.move_action"), systemImage: "folder")
        }
        Button {
            actions.editTags(card.item)
        } label: {
            Label(L10n.string("favorites.tags_action"), systemImage: "tag")
        }
        Button {
            actions.toggleTextCover(card.item)
        } label: {
            if card.textCoverForced {
                Label(L10n.string("cover.use_image_cover"), systemImage: "photo")
            } else {
                Label(L10n.string("cover.use_text_cover"), systemImage: "textformat")
            }
        }
        if card.item.target.threadID != nil, card.item.remoteMapping?.yamiboFavoriteID == nil {
            Button {
                actions.syncToRemote(card.item)
            } label: {
                Label(L10n.string("favorites.quick.add_prompt.sync"), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        Divider()
        Button(role: .destructive) {
            actions.delete(card)
        } label: {
            Label(L10n.string("common.delete"), systemImage: "trash")
        }
    }
}
