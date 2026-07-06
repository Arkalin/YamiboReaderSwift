import SwiftUI
import YamiboReaderCore

struct LocalFavoriteCategoryNameDraft: Identifiable {
    enum Mode {
        case create
        case rename(String)
    }

    let id = UUID()
    var mode: Mode
    var initialName: String = ""
}

/// Name entry sheet for creating or renaming a category.
struct LocalFavoriteCategoryNameSheet: View {
    let draft: LocalFavoriteCategoryNameDraft
    let onCancel: () -> Void
    let onSave: (String) async -> Void

    @State private var name: String

    init(
        draft: LocalFavoriteCategoryNameDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) async -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: draft.initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.string("favorites.category.name"), text: $name)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        Task { await onSave(name) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch draft.mode {
        case .create:
            L10n.string("favorites.category.create")
        case .rename:
            L10n.string("favorites.category.rename")
        }
    }
}
