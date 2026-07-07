import SwiftUI
import YamiboReaderCore

/// Confirmation dialogs for the favorite quick actions: "sync to Yamibo?" on
/// add and "also delete from Yamibo?" on remove, each with remember-choice
/// variants. Shared by the thread reader and the detail pages.
struct FavoriteQuickActionDialogs: ViewModifier {
    @Binding var addPromptPresented: Bool
    @Binding var removePrompt: FavoriteRemovePrompt?
    let onConfirmAdd: (_ syncToRemote: Bool, _ remember: Bool) -> Void
    let onConfirmRemoval: (_ favorite: Favorite, _ removeRemote: Bool, _ remember: Bool) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                L10n.string("favorites.quick.add_prompt.title"),
                isPresented: $addPromptPresented,
                titleVisibility: .visible
            ) {
                Button(L10n.string("favorites.quick.add_prompt.sync")) {
                    onConfirmAdd(true, false)
                }
                Button(L10n.string("favorites.quick.add_prompt.local_only")) {
                    onConfirmAdd(false, false)
                }
                Button(L10n.string("favorites.quick.add_prompt.sync_remember")) {
                    onConfirmAdd(true, true)
                }
                Button(L10n.string("favorites.quick.add_prompt.local_remember")) {
                    onConfirmAdd(false, true)
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.string("favorites.quick.add_prompt.message"))
            }
            .confirmationDialog(
                L10n.string("favorites.quick.remove_prompt.title"),
                isPresented: removePromptBinding,
                titleVisibility: .visible,
                presenting: removePrompt
            ) { prompt in
                Button(L10n.string("favorites.quick.remove_prompt.both"), role: .destructive) {
                    onConfirmRemoval(prompt.favorite, true, false)
                }
                Button(L10n.string("favorites.quick.remove_prompt.local_only"), role: .destructive) {
                    onConfirmRemoval(prompt.favorite, false, false)
                }
                Button(L10n.string("favorites.quick.remove_prompt.both_remember"), role: .destructive) {
                    onConfirmRemoval(prompt.favorite, true, true)
                }
                Button(L10n.string("favorites.quick.remove_prompt.local_remember"), role: .destructive) {
                    onConfirmRemoval(prompt.favorite, false, true)
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } message: { _ in
                Text(L10n.string("favorites.quick.remove_prompt.message"))
            }
    }

    private var removePromptBinding: Binding<Bool> {
        Binding(
            get: { removePrompt != nil },
            set: { isPresented in
                if !isPresented {
                    removePrompt = nil
                }
            }
        )
    }
}

extension View {
    func favoriteQuickActionDialogs(
        addPromptPresented: Binding<Bool>,
        removePrompt: Binding<FavoriteRemovePrompt?>,
        onConfirmAdd: @escaping (_ syncToRemote: Bool, _ remember: Bool) -> Void,
        onConfirmRemoval: @escaping (_ favorite: Favorite, _ removeRemote: Bool, _ remember: Bool) -> Void
    ) -> some View {
        modifier(FavoriteQuickActionDialogs(
            addPromptPresented: addPromptPresented,
            removePrompt: removePrompt,
            onConfirmAdd: onConfirmAdd,
            onConfirmRemoval: onConfirmRemoval
        ))
    }
}
