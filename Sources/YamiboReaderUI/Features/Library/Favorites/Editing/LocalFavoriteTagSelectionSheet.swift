import SwiftUI
import YamiboReaderCore

struct LocalFavoriteTagSelectionDraft: Identifiable {
    enum Mode {
        case filter
        case favorite(String)
        case selection
    }

    let id = UUID()
    var mode: Mode
    var initialTagIDs: Set<String>

    static func filter(_ tagIDs: Set<String>) -> LocalFavoriteTagSelectionDraft {
        LocalFavoriteTagSelectionDraft(mode: .filter, initialTagIDs: tagIDs)
    }

    static func favorite(_ itemID: String, initialTagIDs: Set<String>) -> LocalFavoriteTagSelectionDraft {
        LocalFavoriteTagSelectionDraft(mode: .favorite(itemID), initialTagIDs: initialTagIDs)
    }

    static func selection(_ initialTagIDs: Set<String>) -> LocalFavoriteTagSelectionDraft {
        LocalFavoriteTagSelectionDraft(mode: .selection, initialTagIDs: initialTagIDs)
    }
}

/// Tag picker sheet used for filtering, editing one favorite's tags, or bulk
/// tagging the current selection. Also hosts tag create/edit/delete.
struct LocalFavoriteTagSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var organizer: FavoriteLibraryOrganizer
    let draft: LocalFavoriteTagSelectionDraft

    @State private var selectedTagIDs: Set<String>
    @State private var editorDraft: LocalFavoriteTagEditorDraft?
    @State private var pendingDeleteTag: FavoriteTag?

    init(organizer: FavoriteLibraryOrganizer, draft: LocalFavoriteTagSelectionDraft) {
        self.organizer = organizer
        self.draft = draft
        _selectedTagIDs = State(initialValue: draft.initialTagIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                if organizer.tags.isEmpty {
                    ContentUnavailableView(L10n.string("favorites.tags.empty"), systemImage: "tag")
                }
                ForEach(organizer.tags) { tag in
                    Button {
                        toggle(tag.id)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(tag.color.swiftUIColor)
                                .frame(width: 16, height: 16)
                            Text(tag.name)
                            Spacer()
                            if selectedTagIDs.contains(tag.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            editorDraft = LocalFavoriteTagEditorDraft(tag: tag)
                        } label: {
                            Label(L10n.string("common.edit"), systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDeleteTag = tag
                        } label: {
                            Label(L10n.string("common.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("favorites.select_tags"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorDraft = LocalFavoriteTagEditorDraft()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.string("favorites.new_tag"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        Task { await confirm() }
                    }
                }
            }
            .sheet(item: $editorDraft) { draft in
                LocalFavoriteTagEditorSheet(
                    draft: draft,
                    onCancel: {
                        editorDraft = nil
                    },
                    onSave: { name, color in
                        if let tagID = draft.tagID {
                            await organizer.updateTag(id: tagID, name: name, color: color)
                        } else if let tag = await organizer.createTag(name: name, color: color) {
                            selectedTagIDs.insert(tag.id)
                        }
                        editorDraft = nil
                    }
                )
            }
            .alert(
                L10n.string("favorites.delete_tag"),
                isPresented: deleteTagAlertBinding
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteTag = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    if let pendingDeleteTag {
                        Task {
                            await organizer.deleteTag(id: pendingDeleteTag.id)
                            selectedTagIDs.remove(pendingDeleteTag.id)
                            self.pendingDeleteTag = nil
                        }
                    }
                }
            } message: {
                if let pendingDeleteTag {
                    Text(L10n.string("favorites.delete_tag_message", pendingDeleteTag.name))
                }
            }
        }
    }

    private func confirm() async {
        switch draft.mode {
        case .filter:
            organizer.filter.selectedTagIDs = selectedTagIDs
        case let .favorite(itemID):
            await organizer.updateTags(for: itemID, tagIDs: selectedTagIDs)
        case .selection:
            await organizer.updateTagsForSelection(selectedTagIDs)
        }
        dismiss()
    }

    private var deleteTagAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTag != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteTag = nil
                }
            }
        )
    }

    private func toggle(_ tagID: String) {
        if selectedTagIDs.contains(tagID) {
            selectedTagIDs.remove(tagID)
        } else {
            selectedTagIDs.insert(tagID)
        }
    }
}

struct LocalFavoriteTagEditorDraft: Identifiable {
    let id = UUID()
    var tagID: String?
    var initialName: String
    var initialColor: FavoriteTagColor

    init(tag: FavoriteTag? = nil) {
        tagID = tag?.id
        initialName = tag?.name ?? ""
        initialColor = tag?.color ?? .gray
    }
}

/// Name and color entry sheet for creating or editing a tag.
struct LocalFavoriteTagEditorSheet: View {
    let draft: LocalFavoriteTagEditorDraft
    let onCancel: () -> Void
    let onSave: (String, FavoriteTagColor) async -> Void

    @State private var name: String
    @State private var color: FavoriteTagColor

    init(
        draft: LocalFavoriteTagEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, FavoriteTagColor) async -> Void
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
                TextField(L10n.string("favorites.tag_name"), text: $name)
                Picker(L10n.string("common.select"), selection: $color) {
                    ForEach(FavoriteTagColor.allCases, id: \.self) { color in
                        Label(color.localizedTitle, systemImage: "circle.fill")
                            .foregroundStyle(color.swiftUIColor)
                            .tag(color)
                    }
                }
            }
            .navigationTitle(draft.tagID == nil ? L10n.string("favorites.new_tag") : L10n.string("favorites.edit_tag"))
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
}
