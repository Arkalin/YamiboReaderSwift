import SwiftUI
import UniformTypeIdentifiers
import YamiboReaderCore

public struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @AppStorage("yamibo.favorite.filter") private var filterRawValue = FavoriteFilter.all.rawValue
    @AppStorage("yamibo.favorite.sort") private var sortRawValue = FavoriteSortOrder.manual.rawValue
    @AppStorage("yamibo.favorite.showHidden") private var showsHidden = false
    @State private var searchText = ""
    @State private var selectedFavorite: Favorite?
    @State private var displayNameDraft: FavoriteDisplayNameDraft?
    @State private var pendingEditFavorite: Favorite?
    @State private var tagPickerContext: FavoriteTagPickerContext?
    @State private var collectionNameDraft: FavoriteCollectionNameDraft?
    @State private var pendingDeleteFavorite: Favorite?
    @State private var pendingDeleteCollection: FavoriteCollection?
    @Binding private var isSelecting: Bool
    @State private var selectedFavoriteIDs: Set<String> = []
    @State private var selectedCollectionIDs: Set<String> = []
    @State private var selectedFilterTagIDs: Set<String> = []
    @State private var showingCreateCollectionPrompt = false
    @State private var createCollectionName = ""
    @State private var showingMoveDialog = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var didLoadInitialFavorites = false
    @State private var draggedEntryKey: String?
    @State private var sharingFavorite: Favorite?
    @State private var openingMangaFavoriteID: String?

    private let scope: FavoriteScope
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(
        favoriteStore: FavoriteStore,
        appContext: YamiboAppContext,
        appModel: YamiboAppModel,
        scope: FavoriteScope = .root,
        isSelecting: Binding<Bool>
    ) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore))
        _isSelecting = isSelecting
        self.scope = scope
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        favoritesContent
    }

    private var favoritesContent: some View {
        let content = favoritesChromeContent

        return Group {
            #if os(iOS)
            content
            #else
            if isSelecting {
                content.safeAreaInset(edge: .bottom, spacing: 0) {
                    selectionActionBar
                }
            } else {
                content
            }
            #endif
        }
        .disabled(isOpeningManga)
        .overlay {
            if isOpeningManga {
                mangaOpeningOverlay
            }
        }
        #if os(iOS)
        .toolbar {
            if isSelecting {
                selectionBottomToolbar
            }
        }
        #endif
    }

    private var favoritesChromeContent: some View {
        favoritesDialogContent
    }

    private var favoritesNavigationContent: some View {
        favoritesListLayout
            .navigationTitle("")
            .modifier(FavoriteSearchModifier(searchText: $searchText))
            .modifier(
                FavoriteToolbarModifier(
                    filterRawValue: $filterRawValue,
                    sortRawValue: $sortRawValue,
                    showsHidden: $showsHidden,
                    isSelecting: $isSelecting,
                    favoriteAppearance: viewModel.favoriteAppearance,
                    showsSettingsMenu: isRootScope,
                    selectedTagCount: selectedFilterTagIDs.count,
                    visibleSelectionIsComplete: visibleSelectionIsComplete,
                    canToggleVisibleSelection: !visibleEntries.isEmpty,
                    allTitle: filterLabel(for: .all),
                    onFinishSelection: exitSelectionMode,
                    onToggleVisibleSelection: toggleVisibleSelection,
                    onEditTagFilter: presentFilterTagPicker,
                    onClearTagFilter: {
                        selectedFilterTagIDs.removeAll()
                    }
                )
            )
            .forumNavigationBarStyle()
    }

    private var favoritesListLayout: some View {
        GeometryReader { geometry in
            ZStack {
                ForumColors.creamBackground
                    .ignoresSafeArea()

                FavoriteBackgroundLayer(
                    settings: viewModel.favoriteBackground,
                    imageData: viewModel.favoriteBackgroundImageData
                )
                .ignoresSafeArea()

                if shouldUseTwoColumnLayout(in: geometry.size) {
                    twoColumnFavoritesList
                } else {
                    singleColumnFavoritesList(entries: visibleEntries)
                }
            }
            .overlay(content: overlayContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var favoritesLifecycleContent: some View {
        favoritesNavigationContent
            .task {
                await loadInitialFavorites()
            }
            .onChange(of: filterRawValue) { _, _ in
                searchText = ""
            }
            .onChange(of: isSelecting) { _, isSelecting in
                if !isSelecting {
                    selectedFavoriteIDs.removeAll()
                    selectedCollectionIDs.removeAll()
                }
            }
            .onChange(of: viewModel.favorites.map(\.id)) { _, _ in
                pruneSelections()
            }
            .onChange(of: viewModel.collections.map(\.id)) { _, _ in
                pruneSelections()
            }
            .onChange(of: viewModel.tags.map(\.id)) { _, tagIDs in
                selectedFilterTagIDs.formIntersection(Set(tagIDs))
            }
            .sensoryFeedback(.selection, trigger: selectedFavoriteIDs)
            .sensoryFeedback(.selection, trigger: selectedCollectionIDs)
            .refreshable {
                await viewModel.refresh()
            }
    }

    private var favoritesDialogContent: some View {
        favoritesLifecycleContent
            .alert(L10n.string("common.load_failed"), isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button(L10n.string("common.ok")) {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .alert(L10n.string("favorites.edit_display_name"), isPresented: editNameAlertBinding) {
                TextField(L10n.string("favorites.display_name"), text: displayNameTextBinding)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    displayNameDraft = nil
                }
                Button(L10n.string("common.save")) {
                    guard let draft = displayNameDraft else { return }
                    Task {
                        await viewModel.setDisplayName(
                            draft.displayName,
                            forFavoriteID: draft.favoriteID,
                            originalTitle: draft.originalTitle
                        )
                    }
                    displayNameDraft = nil
                }
            } message: {
                Text(L10n.string("favorites.display_name_message"))
            }
            .alert("", isPresented: editActionAlertBinding, presenting: pendingEditFavorite) { favorite in
                Button(L10n.string("favorites.edit_display_name")) {
                    displayNameDraft = FavoriteDisplayNameDraft(favorite: favorite)
                    pendingEditFavorite = nil
                }
                Button(L10n.string("favorites.edit_tags")) {
                    tagPickerContext = FavoriteTagPickerContext(
                        favoriteID: favorite.id,
                        initialTagIDs: Set(favorite.tagIDs)
                    )
                    pendingEditFavorite = nil
                }
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingEditFavorite = nil
                }
            }
            .alert(L10n.string("favorites.create_collection"), isPresented: $showingCreateCollectionPrompt) {
                TextField(L10n.string("favorites.collection_name"), text: $createCollectionName)
                Button(L10n.string("common.cancel"), role: .cancel) {
                    createCollectionName = ""
                }
                Button(L10n.string("common.create")) {
                    let selectedIDs = Array(selectedFavoriteIDs)
                    let targetName = createCollectionName
                    createCollectionName = ""
                    Task {
                        if await viewModel.createCollection(name: targetName, favoriteIDs: selectedIDs) {
                            exitSelectionMode()
                        }
                    }
                }
                .disabled(createCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text(L10n.string("favorites.create_collection_message"))
            }
            .alert(
                L10n.string("favorites.delete_favorite"),
                isPresented: pendingDeleteAlertBinding,
                presenting: pendingDeleteFavorite
            ) { favorite in
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteFavorite = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        await viewModel.deleteFavorite(favorite)
                    }
                    pendingDeleteFavorite = nil
                }
            } message: { favorite in
                Text(L10n.string("favorites.delete_favorite_message", favorite.resolvedDisplayTitle))
            }
            .alert(L10n.string("favorites.delete_selection"), isPresented: $showingBulkDeleteConfirmation) {
                Button(L10n.string("common.cancel"), role: .cancel) {}
                Button(L10n.string("common.delete"), role: .destructive) {
                    let favoriteIDs = Array(selectedFavoriteIDs)
                    let collectionIDs = Array(selectedCollectionIDs)
                    Task {
                        let changed = await viewModel.deleteSelections(favoriteIDs: favoriteIDs, collectionIDs: collectionIDs)
                        if changed {
                            exitSelectionMode()
                        }
                    }
                }
            } message: {
                Text(bulkDeleteMessage)
            }
            .sheet(item: $selectedFavorite) { favorite in
                NavigationStack {
                    ForumBrowserView(url: favorite.url, appContext: appContext, appModel: appModel)
                }
            }
            .sheet(item: $tagPickerContext) { context in
                FavoriteTagPickerView(
                    tags: viewModel.tags,
                    favorites: viewModel.favorites,
                    initialSelection: context.initialTagIDs,
                    showsOverwriteWarning: context.showsOverwriteWarning,
                    onCancel: {
                        tagPickerContext = nil
                    },
                    onConfirm: { selectedTagIDs in
                        if context.isFilter {
                            selectedFilterTagIDs = selectedTagIDs
                            tagPickerContext = nil
                            return true
                        }

                        let orderedTagIDs = viewModel.tags
                            .map(\.id)
                            .filter { selectedTagIDs.contains($0) }
                        if await viewModel.setTagIDs(orderedTagIDs, forFavoriteIDs: context.favoriteIDs) {
                            tagPickerContext = nil
                            if context.exitsSelectionModeOnConfirm {
                                exitSelectionMode()
                            }
                            return true
                        }
                        return false
                    },
                    onCreateTag: { name, color in
                        await viewModel.createTag(name: name, color: color)
                    },
                    onUpdateTag: { tagID, name, color in
                        await viewModel.updateTag(id: tagID, name: name, color: color)
                    },
                    onDeleteTag: { tagID in
                        await viewModel.deleteTag(id: tagID)
                    },
                    onReorderTags: { visibleIDs, fromOffsets, toOffset in
                        await viewModel.reorderTags(
                            visibleIDs: visibleIDs,
                            fromOffsets: fromOffsets,
                            toOffset: toOffset
                        )
                    }
                )
            }
            .modifier(FavoriteSharePresenter(favorite: $sharingFavorite))
            .modifier(
                FavoriteCollectionDialogsModifier(
                    collectionNameDraft: $collectionNameDraft,
                    pendingDeleteCollection: $pendingDeleteCollection,
                    saveName: saveCollectionName,
                    dissolveCollection: dissolveCollection
                )
            )
    }

    private var leftColumnEntries: [FavoriteListEntry] {
        splitAlternatingColumns(visibleEntries).left
    }

    private var rightColumnEntries: [FavoriteListEntry] {
        splitAlternatingColumns(visibleEntries).right
    }

    private var twoColumnFavoritesList: some View {
        ScrollView {
            VStack(spacing: 10) {
                #if os(iOS)
                favoriteSearchHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                #endif

                HStack(alignment: .top, spacing: 20) {
                    twoColumnFavoritesColumn(entries: leftColumnEntries, column: .left)
                    twoColumnFavoritesColumn(entries: rightColumnEntries, column: .right)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private func twoColumnFavoritesColumn(
        entries: [FavoriteListEntry],
        column: FavoriteListColumn
    ) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(entries) { entry in
                twoColumnRow(for: entry)
                    .onDrop(
                        of: [UTType.plainText.identifier],
                        delegate: FavoriteEntryDropDelegate(
                            draggedEntryKey: draggedEntryKey,
                            targetEntry: entry,
                            column: column,
                            canReorder: canReorderEntries,
                            onDropOnEntry: handleDrop,
                            onDropToColumnBottom: handleDropToColumnBottom,
                            onFinish: { draggedEntryKey = nil }
                        )
                    )
                    .onDragIf(canReorderEntries, value: entry.moveKey) {
                        draggedEntryKey = entry.moveKey
                    }
            }

            Color.clear
                .frame(height: 88)
                .contentShape(Rectangle())
                .onDrop(
                    of: [UTType.plainText.identifier],
                    delegate: FavoriteEntryDropDelegate(
                        draggedEntryKey: draggedEntryKey,
                        targetEntry: nil,
                        column: column,
                        canReorder: canReorderEntries,
                        onDropOnEntry: handleDrop,
                        onDropToColumnBottom: handleDropToColumnBottom,
                        onFinish: { draggedEntryKey = nil }
                    )
                )
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func singleColumnFavoritesList(entries: [FavoriteListEntry]) -> some View {
        List {
            #if os(iOS)
            favoriteSearchHeader
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            #endif

            ForEach(entries) { entry in
                row(for: entry)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: handleMove)
            .moveDisabled(!canReorderEntries)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    #if os(iOS)
    private var favoriteSearchHeader: some View {
        FavoriteNativeSearchBar(text: $searchText)
            .frame(height: 46)
            .padding(.horizontal, 8)
            .favoriteSearchGlassSurface()
    }
    #endif

    @ViewBuilder
    private func overlayContent() -> some View {
        if viewModel.isLoading {
            ProgressView(L10n.string("favorites.syncing"))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)
        } else if visibleEntries.isEmpty {
            emptyStateView
        }
    }

    private var mangaOpeningOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            ProgressView(L10n.string("manga.loading"))
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.12), radius: 18, y: 6)
        }
        .allowsHitTesting(true)
    }

    private var currentCollection: FavoriteCollection? {
        guard let scopedCollection = scope.collection else { return nil }
        return viewModel.collections.first(where: { $0.id == scopedCollection.id }) ?? scopedCollection
    }

    private var isRootScope: Bool {
        if case .root = scope {
            return true
        }
        return false
    }

    private var usesIPadSharePresenter: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        false
        #endif
    }

    private var currentFilter: FavoriteFilter {
        FavoriteFilter(rawValue: filterRawValue) ?? .all
    }

    private var currentSortOrder: FavoriteSortOrder {
        FavoriteSortOrder(rawValue: sortRawValue) ?? .manual
    }

    private var canReorderEntries: Bool {
        viewModel.canReorderEntries(
            scope: scope,
            filter: currentFilter,
            sortOrder: currentSortOrder,
            searchText: searchText,
            selectedTagIDs: selectedFilterTagIDs,
            isSelecting: isSelecting
        )
    }

    private var isOpeningManga: Bool {
        shouldBlockFavoriteInteractions(openingMangaFavoriteID: openingMangaFavoriteID)
    }

    private var selectionActionState: FavoriteSelectionActionState {
        makeFavoriteSelectionActionState(
            scope: scope,
            selectedFavoriteCount: selectedFavoriteIDs.count,
            selectedCollectionCount: selectedCollectionIDs.count
        )
    }

    private var visibleEntries: [FavoriteListEntry] {
        makeFavoriteListEntries(
            scope: scope,
            favorites: viewModel.favorites,
            collections: viewModel.collections,
            showsHidden: showsHidden,
            filter: currentFilter,
            sortOrder: currentSortOrder,
            searchText: searchText,
            selectedTagIDs: selectedFilterTagIDs
        )
    }

    private var visibleSelectionIsComplete: Bool {
        guard !visibleEntries.isEmpty else { return false }
        return visibleEntries.allSatisfy { entry in
            switch entry {
            case let .collection(collection):
                selectedCollectionIDs.contains(collection.id)
            case let .favorite(favorite):
                selectedFavoriteIDs.contains(favorite.id)
            }
        }
    }

    private var moveTargets: [FavoriteCollection] {
        let targetCollections = orderedCollections(viewModel.collections)
        guard let currentCollection else { return targetCollections }
        return targetCollections.filter { $0.id != currentCollection.id }
    }

    private var bulkDeleteMessage: String {
        if selectedCollectionIDs.isEmpty {
            return L10n.string("favorites.bulk_delete_favorites_message")
        }
        if selectedFavoriteIDs.isEmpty {
            return L10n.string("favorites.bulk_dissolve_collections_message")
        }
        return L10n.string("favorites.bulk_delete_mixed_message")
    }

    private var editNameAlertBinding: Binding<Bool> {
        Binding(
            get: { displayNameDraft != nil },
            set: { isPresented in
                if !isPresented {
                    displayNameDraft = nil
                }
            }
        )
    }

    private var editActionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingEditFavorite != nil },
            set: { isPresented in
                if !isPresented {
                    pendingEditFavorite = nil
                }
            }
        )
    }

    private var displayNameTextBinding: Binding<String> {
        Binding(
            get: { displayNameDraft?.displayName ?? "" },
            set: { displayNameDraft?.displayName = $0 }
        )
    }

    private var pendingDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteFavorite != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteFavorite = nil
                }
            }
        )
    }

    @ViewBuilder
    private var emptyStateView: some View {
        if viewModel.isLoading {
            EmptyView()
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(L10n.string("favorites.empty.no_results"), systemImage: "magnifyingglass")
        } else if !selectedFilterTagIDs.isEmpty {
            ContentUnavailableView(L10n.string("favorites.empty.no_results"), systemImage: "tag")
        } else if currentCollection != nil {
            ContentUnavailableView(L10n.string("favorites.empty.collection"), systemImage: "folder")
        } else {
            ContentUnavailableView(L10n.string("favorites.empty.favorites"), systemImage: "books.vertical")
        }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 0) {
                selectionActionButton(
                    title: L10n.string("favorites.tags_action"),
                    systemImage: "tag",
                    isEnabled: selectionActionState.canTag
                ) {
                    presentBatchTagPicker()
                }
                .disabled(!selectionActionState.canTag)

                selectionActionButton(
                    title: L10n.string("favorites.create_collection"),
                    systemImage: "folder.badge.plus",
                    isEnabled: selectionActionState.canCreateCollection
                ) {
                    showingCreateCollectionPrompt = true
                }
                .disabled(!selectionActionState.canCreateCollection)

                selectionActionButton(
                    title: L10n.string("common.move"),
                    systemImage: "doc.on.doc",
                    isEnabled: selectionActionState.canMove
                ) {
                    showingMoveDialog = true
                }
                .disabled(!selectionActionState.canMove)
                .confirmationDialog(
                    L10n.string("favorites.move_to_collection"),
                    isPresented: $showingMoveDialog,
                    titleVisibility: .visible
                ) {
                    Button(L10n.string("favorites.move_to_root")) {
                        moveSelectedFavorites(to: nil)
                    }
                    ForEach(moveTargets) { collection in
                        Button(collection.name) {
                            moveSelectedFavorites(to: collection.id)
                        }
                    }
                    Button(L10n.string("common.cancel"), role: .cancel) {}
                } message: {
                    Text(L10n.string("favorites.select_target_collection"))
                }

                selectionActionButton(
                    title: L10n.string("common.delete"),
                    systemImage: "trash",
                    role: .destructive,
                    isEnabled: selectionActionState.canDelete
                ) {
                    showingBulkDeleteConfirmation = true
                }
                .disabled(!selectionActionState.canDelete)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(selectionActionBarBackground)
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var selectionBottomToolbar: some ToolbarContent {
        ToolbarItem(placement: .bottomBar) {
            selectionToolbarCapsule
        }
    }

    @ViewBuilder
    private var selectionToolbarCapsule: some View {
        if #available(iOS 26, *) {
            selectionToolbarCapsuleContent
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            selectionToolbarCapsuleContent
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var selectionToolbarCapsuleContent: some View {
        HStack(spacing: 8) {
            selectionToolbarButton(
                title: L10n.string("favorites.tags_action"),
                systemImage: "tag",
                isEnabled: selectionActionState.canTag
            ) {
                presentBatchTagPicker()
            }
            .disabled(!selectionActionState.canTag)

            selectionToolbarButton(
                title: L10n.string("favorites.create_collection"),
                systemImage: "folder.badge.plus",
                isEnabled: selectionActionState.canCreateCollection
            ) {
                showingCreateCollectionPrompt = true
            }
            .disabled(!selectionActionState.canCreateCollection)

            selectionToolbarButton(
                title: L10n.string("common.move"),
                systemImage: "doc.on.doc",
                isEnabled: selectionActionState.canMove
            ) {
                showingMoveDialog = true
            }
            .disabled(!selectionActionState.canMove)
            .confirmationDialog(
                L10n.string("favorites.move_to_collection"),
                isPresented: $showingMoveDialog,
                titleVisibility: .visible
            ) {
                Button(L10n.string("favorites.move_to_root")) {
                    moveSelectedFavorites(to: nil)
                }
                ForEach(moveTargets) { collection in
                    Button(collection.name) {
                        moveSelectedFavorites(to: collection.id)
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.string("favorites.select_target_collection"))
            }

            selectionToolbarButton(
                title: L10n.string("common.delete"),
                systemImage: "trash",
                role: .destructive,
                isEnabled: selectionActionState.canDelete
            ) {
                showingBulkDeleteConfirmation = true
            }
            .disabled(!selectionActionState.canDelete)
        }
    }

    private func selectionToolbarButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            selectionToolbarLabel(title: title, systemImage: systemImage, role: role)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private func selectionToolbarLabel(
        title: String,
        systemImage: String,
        role: ButtonRole?
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .frame(width: 24, height: 22)

            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: 66)
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        .contentShape(Rectangle())
    }
    #endif

    private var selectionActionBarBackground: Color {
        YamiboColors.SystemSurface.selectionBarBackground
    }

    private func selectionActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 23, weight: .regular))
                    .frame(width: 28, height: 27)

                Text(title)
                    .font(.caption)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(role == .destructive ? Color.red : Color.primary)
            .opacity(isEnabled ? 1 : 0.28)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func twoColumnRow(for entry: FavoriteListEntry) -> some View {
        switch entry {
        case let .collection(collection):
            let summary = collectionSummary(for: collection)
            if isSelecting {
                Button {
                    toggleCollectionSelection(collection)
                } label: {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: selectedCollectionIDs.contains(collection.id),
                        isSelecting: true,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: collection) {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: false,
                        isSelecting: false,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    collectionActionMenuButton(collection)
                }
            }
        case let .favorite(favorite):
            let favoriteRow = FavoriteRow(
                favorite: favorite,
                isResolving: viewModel.resolvingFavoriteID == favorite.id,
                isDeleting: viewModel.deletingFavoriteID == favorite.id,
                isSelected: selectedFavoriteIDs.contains(favorite.id),
                isSelecting: isSelecting,
                tags: viewModel.tags,
                tagSearchText: searchText,
                prioritizedTagIDs: selectedFilterTagIDs,
                accentColor: favoriteAccentColor(for: favorite.type, appearance: viewModel.favoriteAppearance),
                actionMenu: isSelecting ? nil : AnyView(favoriteActionMenuButton(favorite)),
                onOpen: {
                    if isSelecting {
                        toggleFavoriteSelection(favorite)
                    } else {
                        open(favorite, mode: .resume)
                    }
                }
            )

            if isSelecting {
                Button {
                    toggleFavoriteSelection(favorite)
                } label: {
                    favoriteRow
                }
                .buttonStyle(.plain)
            } else {
                favoriteRow
            }
        }
    }

    @ViewBuilder
    private func row(for entry: FavoriteListEntry) -> some View {
        switch entry {
        case let .collection(collection):
            let summary = collectionSummary(for: collection)
            if isSelecting {
                Button {
                    toggleCollectionSelection(collection)
                } label: {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: selectedCollectionIDs.contains(collection.id),
                        isSelecting: true,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: collection) {
                    FavoriteCollectionRow(
                        collection: collection,
                        summary: summary,
                        isSelected: false,
                        isSelecting: false,
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDeleteCollection = collection
                    } label: {
                        swipeActionLabel(title: L10n.string("common.delete"), systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        Task {
                            await viewModel.setCollectionHidden(!collection.isHidden, for: collection)
                        }
                    } label: {
                        swipeActionLabel(
                            title: collection.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"),
                            systemImage: collection.isHidden ? "eye" : "eye.slash"
                        )
                    }
                    .tint(.orange)

                    Button {
                        collectionNameDraft = FavoriteCollectionNameDraft(collection: collection)
                    } label: {
                        swipeActionLabel(title: L10n.string("common.edit"), systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
            }
        case let .favorite(favorite):
            let row = FavoriteRow(
                favorite: favorite,
                isResolving: viewModel.resolvingFavoriteID == favorite.id,
                isDeleting: viewModel.deletingFavoriteID == favorite.id,
                isSelected: selectedFavoriteIDs.contains(favorite.id),
                isSelecting: isSelecting,
                tags: viewModel.tags,
                tagSearchText: searchText,
                prioritizedTagIDs: selectedFilterTagIDs,
                accentColor: favoriteAccentColor(for: favorite.type, appearance: viewModel.favoriteAppearance),
                onOpen: {
                    if isSelecting {
                        toggleFavoriteSelection(favorite)
                    } else {
                        open(favorite, mode: .resume)
                    }
                }
            )

            if isSelecting {
                Button {
                    toggleFavoriteSelection(favorite)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        favoriteSwipeShareButton(favorite)
                        .tint(.teal)
                        .disabled(viewModel.deletingFavoriteID != nil)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDeleteFavorite = favorite
                        } label: {
                            swipeActionLabel(
                                title: viewModel.deletingFavoriteID == favorite.id ? L10n.string("common.deleting") : L10n.string("common.delete"),
                                systemImage: "trash"
                            )
                        }
                        .tint(.red)
                        .disabled(viewModel.deletingFavoriteID != nil)

                        Button {
                            Task {
                                await viewModel.setHidden(!favorite.isHidden, for: favorite)
                            }
                        } label: {
                            swipeActionLabel(
                                title: favorite.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"),
                                systemImage: favorite.isHidden ? "eye" : "eye.slash"
                            )
                        }
                        .tint(.orange)
                        .disabled(viewModel.deletingFavoriteID != nil)

                        Button {
                            pendingEditFavorite = favorite
                        } label: {
                            swipeActionLabel(title: L10n.string("common.edit"), systemImage: "pencil")
                        }
                        .tint(.indigo)
                        .disabled(viewModel.deletingFavoriteID != nil)
                    }
            }
        }
    }

    private func favoriteActionMenuButton(_ favorite: Favorite) -> some View {
        Menu {
            favoriteMenuShareButton(favorite)

            Button {
                pendingEditFavorite = favorite
            } label: {
                Label(L10n.string("common.edit"), systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setHidden(!favorite.isHidden, for: favorite)
                }
            } label: {
                Label(favorite.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"), systemImage: favorite.isHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                pendingDeleteFavorite = favorite
            } label: {
                Label(viewModel.deletingFavoriteID == favorite.id ? L10n.string("common.deleting") : L10n.string("common.delete"), systemImage: "trash")
            }
            .disabled(viewModel.deletingFavoriteID != nil)
        } label: {
            favoriteActionMenuIcon
        }
        .buttonStyle(.plain)
        .disabled(viewModel.deletingFavoriteID != nil)
    }

    @ViewBuilder
    private func favoriteSwipeShareButton(_ favorite: Favorite) -> some View {
        #if canImport(UIKit)
        if usesIPadSharePresenter {
            Button {
                sharingFavorite = favorite
            } label: {
                swipeActionLabel(title: L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: favorite.url) {
                swipeActionLabel(title: L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        }
        #else
        ShareLink(item: favorite.url) {
            swipeActionLabel(title: L10n.string("common.share"), systemImage: "square.and.arrow.up")
        }
        #endif
    }

    @ViewBuilder
    private func favoriteMenuShareButton(_ favorite: Favorite) -> some View {
        #if canImport(UIKit)
        if usesIPadSharePresenter {
            Button {
                sharingFavorite = favorite
            } label: {
                Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: favorite.url) {
                Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
            }
        }
        #else
        ShareLink(item: favorite.url) {
            Label(L10n.string("common.share"), systemImage: "square.and.arrow.up")
        }
        #endif
    }

    private func collectionActionMenuButton(_ collection: FavoriteCollection) -> some View {
        Menu {
            Button {
                collectionNameDraft = FavoriteCollectionNameDraft(collection: collection)
            } label: {
                Label(L10n.string("common.edit"), systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setCollectionHidden(!collection.isHidden, for: collection)
                }
            } label: {
                Label(collection.isHidden ? L10n.string("common.unhide") : L10n.string("common.hide"), systemImage: collection.isHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                pendingDeleteCollection = collection
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        } label: {
            favoriteActionMenuIcon
        }
        .buttonStyle(.plain)
    }

    private var favoriteActionMenuIcon: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)

            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.primary.opacity(0.82))
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }

    private func shouldUseTwoColumnLayout(in size: CGSize) -> Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && size.width > size.height
        #else
        false
        #endif
    }

    private func handleMove(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard canReorderEntries else { return }

        switch scope {
        case .root:
            Task {
                await viewModel.reorderRootEntries(
                    visibleEntryKeys: visibleEntries.map(\.moveKey),
                    fromOffsets: source,
                    toOffset: destination
                )
            }
        case let .collection(collection):
            let visibleIDs = visibleEntries.compactMap { entry -> String? in
                guard case let .favorite(favorite) = entry else { return nil }
                return favorite.id
            }
            Task {
                await viewModel.reorderFavorites(
                    in: collection.id,
                    visibleIDs: visibleIDs,
                    fromOffsets: source,
                    toOffset: destination
                )
            }
        }
    }

    private func handleDrop(
        draggedEntryKey: String,
        onto targetEntry: FavoriteListEntry,
        position: FavoriteDropPosition
    ) {
        let reorderedKeys = reorderedItemsAfterDrop(
            visibleEntries.map(\.moveKey),
            draggedItem: draggedEntryKey,
            targetItem: targetEntry.moveKey,
            position: position
        )
        applyReorderedVisibleEntries(for: reorderedKeys)
    }

    private func handleDropToColumnBottom(
        draggedEntryKey: String,
        column: FavoriteListColumn
    ) {
        let reorderedKeys = reorderedItemsAfterDroppingAtColumnBottom(
            visibleEntries.map(\.moveKey),
            draggedItem: draggedEntryKey,
            column: column
        )
        applyReorderedVisibleEntries(for: reorderedKeys)
    }

    private func applyReorderedVisibleEntries(for reorderedKeys: [String]) {
        let originalKeys = visibleEntries.map(\.moveKey)
        guard reorderedKeys != originalKeys else { return }
        let moves = makeVisibleOrderMovesToTransform(from: originalKeys, to: reorderedKeys)
        guard !moves.isEmpty else { return }

        switch scope {
        case .root:
            Task {
                await viewModel.reorderRootEntries(visibleEntryKeys: originalKeys, moves: moves)
            }
        case let .collection(collection):
            let originalFavoriteIDs = visibleEntries.compactMap { entry -> String? in
                guard case let .favorite(favorite) = entry else { return nil }
                return favorite.id
            }
            Task {
                await viewModel.reorderFavorites(
                    in: collection.id,
                    visibleIDs: originalFavoriteIDs,
                    moves: moves
                )
            }
        }
    }

    private func open(_ favorite: Favorite, mode: FavoriteLaunchMode) {
        Task {
            if favoriteLaunchNeedsMangaProbeBlocker(favorite) {
                openingMangaFavoriteID = favorite.id
            }

            let target = await viewModel.openTarget(for: favorite, mode: mode)
            switch target {
            case let .reader(context):
                openingMangaFavoriteID = nil
                appModel.presentReader(context)
            case let .manga(context):
                openingMangaFavoriteID = nil
                appModel.presentManga(context)
            case let .web(resolvedFavorite):
                openingMangaFavoriteID = nil
                selectedFavorite = resolvedFavorite
            }
        }
    }

    private func toggleFavoriteSelection(_ favorite: Favorite) {
        if selectedFavoriteIDs.contains(favorite.id) {
            selectedFavoriteIDs.remove(favorite.id)
        } else {
            selectedFavoriteIDs.insert(favorite.id)
        }
    }

    private func toggleCollectionSelection(_ collection: FavoriteCollection) {
        if selectedCollectionIDs.contains(collection.id) {
            selectedCollectionIDs.remove(collection.id)
        } else {
            selectedCollectionIDs.insert(collection.id)
        }
    }

    private func toggleVisibleSelection() {
        if visibleSelectionIsComplete {
            for entry in visibleEntries {
                switch entry {
                case let .collection(collection):
                    selectedCollectionIDs.remove(collection.id)
                case let .favorite(favorite):
                    selectedFavoriteIDs.remove(favorite.id)
                }
            }
        } else {
            for entry in visibleEntries {
                switch entry {
                case let .collection(collection):
                    selectedCollectionIDs.insert(collection.id)
                case let .favorite(favorite):
                    selectedFavoriteIDs.insert(favorite.id)
                }
            }
        }
    }

    private func moveSelectedFavorites(to collectionID: String?) {
        let ids = Array(selectedFavoriteIDs)
        Task {
            if await viewModel.moveFavorites(ids: ids, toCollectionID: collectionID) {
                exitSelectionMode()
            }
        }
    }

    private func presentBatchTagPicker() {
        let tagSelectionState = makeBatchTagSelectionState(
            favorites: viewModel.favorites,
            selectedFavoriteIDs: selectedFavoriteIDs
        )
        tagPickerContext = FavoriteTagPickerContext(
            favoriteIDs: Array(selectedFavoriteIDs),
            initialTagIDs: tagSelectionState.initialTagIDs,
            showsOverwriteWarning: tagSelectionState.showsOverwriteWarning,
            exitsSelectionModeOnConfirm: true
        )
    }

    private func presentFilterTagPicker() {
        tagPickerContext = FavoriteTagPickerContext(filterTagIDs: selectedFilterTagIDs)
    }

    private func loadInitialFavorites() async {
        guard !didLoadInitialFavorites else { return }
        didLoadInitialFavorites = true

        await viewModel.loadCachedFavorites()
        if case .root = scope {
            await viewModel.refresh()
        }
    }

    private func saveCollectionName(_ draft: FavoriteCollectionNameDraft) {
        Task {
            if await viewModel.setCollectionName(draft.name, for: draft.collectionID) {
                collectionNameDraft = nil
            }
        }
    }

    private func dissolveCollection(_ collection: FavoriteCollection) {
        Task {
            _ = await viewModel.deleteSelections(favoriteIDs: [], collectionIDs: [collection.id])
        }
        pendingDeleteCollection = nil
    }

    private func pruneSelections() {
        let validFavoriteIDs = Set(viewModel.favorites.map(\.id))
        let validCollectionIDs = Set(viewModel.collections.map(\.id))
        selectedFavoriteIDs = selectedFavoriteIDs.intersection(validFavoriteIDs)
        selectedCollectionIDs = selectedCollectionIDs.intersection(validCollectionIDs)
        if isSelecting, selectedFavoriteIDs.isEmpty, selectedCollectionIDs.isEmpty {
            // Keep selection mode active so the toolbar can still be used consistently.
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedFavoriteIDs.removeAll()
        selectedCollectionIDs.removeAll()
    }

    private func filterLabel(for filter: FavoriteFilter) -> String {
        guard filter == .all else { return filter.title }
        return currentCollection?.name ?? filter.title
    }

    private func collectionSummary(for collection: FavoriteCollection) -> FavoriteCollectionSummary {
        makeFavoriteCollectionSummary(
            for: collection,
            favorites: viewModel.favorites,
            scope: scope,
            showsHidden: showsHidden,
            filter: currentFilter,
            searchText: searchText,
            selectedTagIDs: selectedFilterTagIDs
        )
    }

    @ViewBuilder
    private func swipeActionLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
    }
}

private extension View {
    @ViewBuilder
    func favoriteSearchGlassSurface() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            glassEffect(
                .regular
                    .tint(ForumColors.creamSurface.opacity(0.18))
                    .interactive(),
                in: .rect(cornerRadius: 23)
            )
        } else {
            favoriteSearchMaterialFallback()
        }
        #else
        favoriteSearchMaterialFallback()
        #endif
    }

    private func favoriteSearchMaterialFallback() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(ForumColors.border, lineWidth: 1)
            }
    }
}
