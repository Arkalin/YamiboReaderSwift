import SwiftUI
import YamiboReaderCore

struct FavoriteTagPickerView: View {
    let tags: [FavoriteTag]
    let favorites: [Favorite]
    let initialSelection: Set<String>
    let showsOverwriteWarning: Bool
    let onCancel: () -> Void
    let onConfirm: (Set<String>) async -> Bool
    let onCreateTag: (String, FavoriteTagColor) async -> FavoriteTag?
    let onUpdateTag: (String, String, FavoriteTagColor) async -> Bool
    let onDeleteTag: (String) async -> Bool
    let onReorderTags: ([String], IndexSet, Int) async -> Bool

    @AppStorage("yamibo.favorite.tag.sort") private var sortRawValue = FavoriteTagSortOrder.manual.rawValue
    @State private var selectionDraft: FavoriteTagSelectionDraft
    @State private var searchText = ""
    @State private var selectionErrorMessage: String?
    @State private var editorDraft: FavoriteTagEditorDraft?
    @State private var pendingDeleteTag: FavoriteTag?
    @State private var isConfirming = false

    init(
        tags: [FavoriteTag],
        favorites: [Favorite],
        initialSelection: Set<String>,
        showsOverwriteWarning: Bool = false,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (Set<String>) async -> Bool,
        onCreateTag: @escaping (String, FavoriteTagColor) async -> FavoriteTag?,
        onUpdateTag: @escaping (String, String, FavoriteTagColor) async -> Bool,
        onDeleteTag: @escaping (String) async -> Bool,
        onReorderTags: @escaping ([String], IndexSet, Int) async -> Bool
    ) {
        self.tags = tags
        self.favorites = favorites
        self.initialSelection = initialSelection
        self.showsOverwriteWarning = showsOverwriteWarning
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onCreateTag = onCreateTag
        self.onUpdateTag = onUpdateTag
        self.onDeleteTag = onDeleteTag
        self.onReorderTags = onReorderTags
        _selectionDraft = State(initialValue: FavoriteTagSelectionDraft(selectedTagIDs: initialSelection))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    tagSelectionHeader
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    if showsOverwriteWarning {
                        Text(L10n.string("favorites.tags_overwrite_warning"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    ForEach(visibleTags) { tag in
                        let isSelected = selectionDraft.selectedTagIDs.contains(tag.id)

                        Button {
                            toggle(tag)
                        } label: {
                            FavoriteTagPickerRow(
                                tag: tag,
                                isSelected: isSelected,
                                includesReorderHandle: canReorderCurrentTags
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button {
                                editorDraft = FavoriteTagEditorDraft(tag: tag, defaultColor: nextDefaultColor)
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
                    .onMove(perform: moveTags)
                }
                .overlay {
                    if tags.isEmpty {
                        ContentUnavailableView(L10n.string("favorites.tags.empty"), systemImage: "tag")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                tagSelectionFooter
            }
            .favoriteTagPickerSearch(text: $searchText)
            .navigationTitle(L10n.string("favorites.select_tags"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(visibleTagsAreFullySelected ? L10n.string("favorites.tags_deselect_all") : L10n.string("favorites.tags_select_all")) {
                        toggleVisibleTagsSelection()
                    }
                    .disabled(visibleTags.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorDraft = FavoriteTagEditorDraft(tag: nil, defaultColor: nextDefaultColor)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selectionDraft.selectedTagIDs)
            .sheet(item: $editorDraft) { draft in
                FavoriteTagEditorView(draft: draft) { name, color in
                    if let tagID = draft.tag?.id {
                        if await onUpdateTag(tagID, name, color) {
                            editorDraft = nil
                            return true
                        }
                        return false
                    }

                    guard let tag = await onCreateTag(name, color) else {
                        return false
                    }
                    searchText = ""
                    handleSelectionResult(selectionDraft.select(tag.id))
                    editorDraft = nil
                    return true
                } onCancel: {
                    editorDraft = nil
                }
            }
            .alert(
                L10n.string("favorites.delete_tag"),
                isPresented: pendingDeleteTagBinding,
                presenting: pendingDeleteTag
            ) { tag in
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteTag = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        if await onDeleteTag(tag.id) {
                            selectionDraft.selectedTagIDs.remove(tag.id)
                            pendingDeleteTag = nil
                        }
                    }
                }
            } message: { tag in
                Text(L10n.string("favorites.delete_tag_message", tag.name))
            }
            #if os(iOS)
            .environment(\.editMode, .constant(canReorderCurrentTags ? .active : .inactive))
            #endif
        }
    }

    private var tagSelectionHeader: some View {
        tagSortMenu
    }

    private var tagSortMenu: some View {
        Menu {
            Picker(L10n.string("favorites.sort"), selection: $sortRawValue) {
                ForEach(FavoriteTagSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title).tag(sortOrder.rawValue)
                }
            }
        } label: {
            VStack(spacing: 0) {
                Divider()

                HStack {
                    Text(L10n.string("favorites.sort"))
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(currentSortOrder.title)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)

                Divider()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tagSelectionFooter: some View {
        HStack {
            Button(L10n.string("common.cancel"), action: onCancel)
                .font(.headline)
                .foregroundStyle(.red)

            Spacer()

            Text(selectionPrompt)
                .font(.headline)
                .foregroundStyle(selectionErrorMessage == nil ? Color.secondary : Color.red)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Spacer()

            Button(L10n.string("common.ok")) {
                Task {
                    isConfirming = true
                    _ = await onConfirm(selectionDraft.selectedTagIDs)
                    isConfirming = false
                }
            }
            .font(.headline)
            .disabled(isConfirming)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var pendingDeleteTagBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteTag != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteTag = nil
                }
            }
        )
    }

    private var nextDefaultColor: FavoriteTagColor {
        let colors = FavoriteTagColor.allCases
        guard !colors.isEmpty else { return .gray }
        return colors[tags.count % colors.count]
    }

    private var orderedTags: [FavoriteTag] {
        sortedFavoriteTags(tags, favorites: favorites, sortOrder: currentSortOrder)
    }

    private var visibleTags: [FavoriteTag] {
        filteredFavoriteTags(orderedTags, searchText: searchText)
    }

    private var currentSortOrder: FavoriteTagSortOrder {
        FavoriteTagSortOrder(rawValue: sortRawValue) ?? .manual
    }

    private var canReorderCurrentTags: Bool {
        canReorderFavoriteTags(sortOrder: currentSortOrder, searchText: searchText)
    }

    private var visibleTagIDs: [String] {
        visibleTags.map(\.id)
    }

    private var visibleTagsAreFullySelected: Bool {
        let ids = Set(visibleTagIDs)
        return !ids.isEmpty && ids.isSubset(of: selectionDraft.selectedTagIDs)
    }

    private var selectionPrompt: String {
        selectionErrorMessage ?? L10n.string("favorites.tags_selected_count", selectionDraft.selectedTagIDs.count)
    }

    private func toggle(_ tag: FavoriteTag) {
        handleSelectionResult(selectionDraft.toggle(tag.id))
    }

    private func toggleVisibleTagsSelection() {
        let ids = visibleTagIDs
        if visibleTagsAreFullySelected {
            handleSelectionResult(selectionDraft.deselectAll(visibleTagIDs: ids))
        } else {
            handleSelectionResult(selectionDraft.selectAll(visibleTagIDs: ids))
        }
    }

    private func moveTags(fromOffsets: IndexSet, toOffset: Int) {
        guard canReorderCurrentTags else { return }
        let visibleIDs = visibleTags.map(\.id)
        Task {
            _ = await onReorderTags(visibleIDs, fromOffsets, toOffset)
        }
    }

    private func handleSelectionResult(_ result: FavoriteTagSelectionDraftResult) {
        switch result {
        case .changed:
            selectionErrorMessage = nil
        case .unchanged:
            break
        case let .selectionLimitExceeded(max):
            selectionErrorMessage = L10n.string("favorites.tags_limit_message", max)
        }
    }
}

private struct FavoriteTagPickerRow: View {
    let tag: FavoriteTag
    let isSelected: Bool
    let includesReorderHandle: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tag.color.swiftUIColor)
                    .frame(width: isSelected ? 31 : 28, height: isSelected ? 31 : 28)

                Text(tagInitial)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(tag.color.iconTextColor)
            }
            .frame(width: 34, height: 34)
            .shadow(color: tag.color.swiftUIColor.opacity(isSelected ? 0.28 : 0.18), radius: 8, y: 4)

            Text(tag.name)
                .font(isSelected ? .body.weight(.semibold) : .body)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer()

            ZStack {
                if isSelected {
                    Circle()
                        .fill(tag.color.swiftUIColor)
                        .frame(width: 24, height: 24)

                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(.secondary.opacity(0.55), lineWidth: 2.25)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 26, height: 26)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tag.color.swiftUIColor.opacity(0.10) : .clear)
                .padding(.trailing, -selectionOutlineTrailingExtension)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? tag.color.swiftUIColor : .clear, lineWidth: 2)
                .padding(.trailing, -selectionOutlineTrailingExtension)
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private var tagInitial: String {
        let trimmedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.first.map(String.init) ?? "#"
    }

    private var selectionOutlineTrailingExtension: CGFloat {
        includesReorderHandle ? 52 : 0
    }
}

private extension View {
    @ViewBuilder
    func favoriteTagPickerSearch(text: Binding<String>) -> some View {
        #if os(iOS)
        self
            .searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.string("favorites.search_tags")
            )
        #else
        self
            .searchable(text: text, prompt: L10n.string("favorites.search_tags"))
        #endif
    }
}

private struct FavoriteTagEditorView: View {
    let draft: FavoriteTagEditorDraft
    let onSave: (String, FavoriteTagColor) async -> Bool
    let onCancel: () -> Void

    @State private var name: String
    @State private var color: FavoriteTagColor
    @State private var isSaving = false

    init(
        draft: FavoriteTagEditorDraft,
        onSave: @escaping (String, FavoriteTagColor) async -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: draft.name)
        _color = State(initialValue: draft.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("favorites.tag_name"), text: $name)
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                        ForEach(FavoriteTagColor.allCases, id: \.self) { tagColor in
                            Button {
                                color = tagColor
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(tagColor.swiftUIColor)
                                        .frame(width: 32, height: 32)
                                    if color == tagColor {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .disabled(isSaving)
            .navigationTitle(draft.tag == nil ? L10n.string("favorites.new_tag") : L10n.string("favorites.edit_tag"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        Task {
                            isSaving = true
                            let didSave = await onSave(name, color)
                            isSaving = false
                            if didSave {
                                onCancel()
                            }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }
}

extension FavoriteTagColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }

    var iconTextColor: Color {
        relativeLuminance > 0.52 ? .black : .white
    }

    private var relativeLuminance: Double {
        let components: (red: Double, green: Double, blue: Double) = switch self {
        case .red: (1.00, 0.23, 0.19)
        case .orange: (1.00, 0.58, 0.00)
        case .yellow: (1.00, 0.80, 0.00)
        case .green: (0.20, 0.78, 0.35)
        case .blue: (0.00, 0.48, 1.00)
        case .purple: (0.69, 0.32, 0.87)
        case .pink: (1.00, 0.18, 0.33)
        case .gray: (0.56, 0.56, 0.58)
        }

        return 0.2126 * components.red + 0.7152 * components.green + 0.0722 * components.blue
    }
}

