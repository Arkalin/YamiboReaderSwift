import SwiftUI
import YamiboXCore

struct LocalFavoriteCollectionDraft: Identifiable {
    enum Mode {
        case create
        case createFromSelection
        case edit(String)
    }

    let id = UUID()
    var mode: Mode
    var initialName: String = ""
    var initialColor: FavoriteCollectionColor = .gray

    init(mode: Mode, initialName: String = "", initialColor: FavoriteCollectionColor = .gray) {
        self.mode = mode
        self.initialName = initialName
        self.initialColor = initialColor
    }

    init(collection: LocalFavoriteCollection) {
        mode = .edit(collection.id)
        initialName = collection.name
        initialColor = collection.color
    }
}

/// Name and color entry sheet for creating or editing a collection.
struct LocalFavoriteCollectionEditorSheet: View {
    let draft: LocalFavoriteCollectionDraft
    let onCancel: () -> Void
    let onSave: (String, FavoriteCollectionColor) async -> Void

    @State private var name: String
    @State private var color: FavoriteCollectionColor

    init(
        draft: LocalFavoriteCollectionDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, FavoriteCollectionColor) async -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: draft.initialName)
        _color = State(initialValue: draft.initialColor)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.string("favorites.collection_name"), text: $name)
                Picker(L10n.string("common.select"), selection: $color) {
                    ForEach(FavoriteCollectionColor.allCases, id: \.self) { color in
                        Label {
                            Text(color.localizedTitle)
                        } icon: {
                            color.pickerIcon
                        }
                        .tag(color)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        Task { await onSave(name, color) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var title: String {
        switch draft.mode {
        case .create, .createFromSelection:
            L10n.string("favorites.create_collection")
        case .edit:
            L10n.string("favorites.edit_collection_name")
        }
    }
}
