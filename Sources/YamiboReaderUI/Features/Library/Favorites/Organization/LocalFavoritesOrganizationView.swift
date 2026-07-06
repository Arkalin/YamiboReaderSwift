import SwiftUI
import YamiboReaderCore

/// Main favorites screen: navigation scaffold, toolbar, status cards, and
/// sheet/dialog presentation. Content rendering is delegated to the list and
/// grid content views, which read the organizer and browse session directly.
struct LocalFavoritesOrganizationView: View {
    @ObservedObject var organizer: FavoriteLibraryOrganizer
    @ObservedObject var remoteSync: FavoriteRemoteSyncSession
    @ObservedObject var updateMonitor: FavoriteUpdateMonitor
    @ObservedObject private var selection: LocalFavoriteBrowseSession
    @StateObject private var routes = LocalFavoritesRoutes()
    @FocusState private var searchFieldFocused: Bool

    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void

    init(
        organizer: FavoriteLibraryOrganizer,
        remoteSync: FavoriteRemoteSyncSession,
        updateMonitor: FavoriteUpdateMonitor,
        onOpen: @escaping (FavoriteItem, FavoriteLaunchMode) async -> Void
    ) {
        self.organizer = organizer
        self.remoteSync = remoteSync
        self.updateMonitor = updateMonitor
        self.selection = organizer.selection
        self.onOpen = onOpen
    }

    var body: some View {
        NavigationStack {
            content
                .refreshable {
                    _ = await remoteSync.start(targetCategoryID: organizer.selectedCategoryID)
                }
                .overlay {
                    if organizer.derived.cards.isEmpty, organizer.derived.visibleCollections.isEmpty {
                        if hasSubmittedSearch {
                            ContentUnavailableView(L10n.string("favorites.empty.no_results"), systemImage: "magnifyingglass")
                        } else {
                            ContentUnavailableView(L10n.string("favorites.empty.favorites"), systemImage: "books.vertical")
                        }
                    }
                }
                .navigationTitle(selection.isSearchMode ? L10n.string("favorites.search.title") : L10n.string("favorites.title"))
                .toolbar { favoriteToolbarContent }
                .onChange(of: selection.isSearchMode) { _, active in
                    searchFieldFocused = active
                }
                .safeAreaInset(edge: .bottom) {
                    if selection.isSelectionMode {
                        LocalFavoriteSelectionActionBar(
                            organizer: organizer,
                            selection: selection,
                            routes: routes
                        )
                    }
                }
                .safeAreaInset(edge: .top) {
                    if showsTopStatusCards {
                        statusCards
                    }
                }
                .alert(L10n.string("favorites.delete_failed"), isPresented: errorAlertBinding) {
                    Button(L10n.string("common.ok")) {
                        clearErrorMessages()
                    }
                } message: {
                    Text(combinedErrorMessage ?? "")
                }
                .alert(
                    dialogTitle,
                    isPresented: dialogBinding,
                    presenting: routes.dialog,
                    actions: dialogActions,
                    message: dialogMessage
                )
                .sheet(item: $routes.sheet) { sheet in
                    LocalFavoritesSheetContent(
                        sheet: sheet,
                        organizer: organizer,
                        remoteSync: remoteSync,
                        updateMonitor: updateMonitor,
                        routes: routes
                    )
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch organizer.display.layoutMode {
        case .rowCard:
            LocalFavoriteListContent(
                organizer: organizer,
                selection: selection,
                routes: routes,
                showsCover: true,
                onOpen: onOpen
            )
        case .rowCardText:
            LocalFavoriteListContent(
                organizer: organizer,
                selection: selection,
                routes: routes,
                showsCover: false,
                onOpen: onOpen
            )
        case .fixedGrid:
            LocalFavoriteGridContent(
                organizer: organizer,
                selection: selection,
                routes: routes,
                isStaggered: false,
                onOpen: onOpen
            )
        case .staggered:
            LocalFavoriteGridContent(
                organizer: organizer,
                selection: selection,
                routes: routes,
                isStaggered: true,
                onOpen: onOpen
            )
        }
    }

    // MARK: - Status cards

    private var showsTopStatusCards: Bool {
        if let snapshot = remoteSync.snapshot, !snapshot.isHiddenFromFavoritePage {
            return true
        }
        return updateMonitor.snapshot != nil
    }

    private var statusCards: some View {
        VStack(spacing: 8) {
            if let snapshot = remoteSync.snapshot, !snapshot.isHiddenFromFavoritePage {
                FavoriteRemoteSyncStatusCard(
                    snapshot: snapshot,
                    onOpen: {
                        routes.sheet = .remoteSyncProgress
                    },
                    onResume: {
                        Task {
                            if await remoteSync.resume() != nil {
                                routes.sheet = .remoteSyncProgress
                            }
                        }
                    },
                    onInterrupt: {
                        Task { await remoteSync.interrupt() }
                    },
                    onHide: {
                        Task { await remoteSync.hideCard() }
                    }
                )
            }
            if let snapshot = updateMonitor.snapshot {
                FavoriteUpdateStatusCard(
                    snapshot: snapshot,
                    eventCount: updateMonitor.events.count,
                    onOpenEvents: { routes.sheet = .updateEvents },
                    onOpenFilters: { routes.sheet = .updateFilters },
                    onStart: {
                        Task { _ = await updateMonitor.startCheck() }
                    },
                    onInterrupt: {
                        Task { await updateMonitor.interrupt() }
                    }
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var favoriteToolbarContent: some ToolbarContent {
        if selection.isSearchMode {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    organizer.exitSearchMode()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string("common.back"))
            }
            ToolbarItem(placement: .principal) {
                TextField(L10n.string("favorites.search.placeholder"), text: $selection.searchDraftText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($searchFieldFocused)
                    .onSubmit { organizer.submitSearch() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    organizer.submitSearch()
                } label: {
                    Text(L10n.string("common.search"))
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteMoreMenu
            }
        }
    }

    private var favoriteMoreMenu: some View {
        Menu {
            Button {
                organizer.enterSearchMode()
            } label: {
                Label(L10n.string("common.search"), systemImage: "magnifyingglass")
            }
            Picker(L10n.string("favorites.sort"), selection: sortOrderBinding) {
                ForEach(LocalFavoriteLibrarySortOrder.allCases) { order in
                    Text(order.title)
                        .tag(order)
                }
            }
            Toggle(isOn: sortDescendingBinding) {
                Label(L10n.string("favorites.sort.descending"), systemImage: "arrow.down")
            }
            Picker(L10n.string("favorites.layout"), selection: layoutModeBinding) {
                ForEach(FavoriteLibraryLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImageName)
                        .tag(mode)
                }
            }
            Toggle(isOn: showsCategoryCountsBinding) {
                Label(L10n.string("favorites.category.show_counts"), systemImage: "number.circle")
            }
            LocalFavoriteSourceGroupPicker(
                sourceGroupFilter: $organizer.filter.sourceGroupFilter,
                sourceGroupEntryCounts: organizer.derived.sourceGroupEntryCounts,
                showsCounts: organizer.display.showsCategoryCounts
            )
            LocalFavoriteTagFilterMenu(
                tags: organizer.tags,
                selectedTagIDs: $organizer.filter.selectedTagIDs,
                onManageTags: {
                    routes.sheet = .tagSelection(.filter(organizer.filter.selectedTagIDs))
                }
            )
            Button {
                selection.enterSelectionMode()
            } label: {
                Label(L10n.string("common.select"), systemImage: "checkmark.circle")
            }
            Button {
                routes.sheet = .collectionEditor(LocalFavoriteCollectionDraft(mode: .create))
            } label: {
                Label(L10n.string("favorites.create_collection"), systemImage: "folder.badge.plus")
            }
            Button {
                routes.sheet = .remoteSyncCategory
            } label: {
                Label(L10n.string("favorites.sync.start"), systemImage: "arrow.triangle.2.circlepath")
            }
            if remoteSync.snapshot != nil {
                Button {
                    routes.sheet = .remoteSyncProgress
                } label: {
                    Label(L10n.string("favorites.sync.progress.open"), systemImage: "list.bullet.rectangle")
                }
            }
            Button {
                Task { _ = await updateMonitor.startCheck() }
            } label: {
                Label(L10n.string("favorites.updates.check"), systemImage: "arrow.clockwise.circle")
            }
            if updateMonitor.snapshot != nil {
                Button {
                    routes.sheet = .updateEvents
                } label: {
                    Label(L10n.string("favorites.updates.events"), systemImage: "bell.badge")
                }
                Button {
                    routes.sheet = .updateFilters
                } label: {
                    Label(L10n.string("favorites.updates.filters"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            Button {
                Task { _ = await remoteSync.start(targetCategoryID: organizer.selectedCategoryID) }
            } label: {
                Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L10n.string("common.more"))
    }

    // MARK: - Preference bindings

    private var sortOrderBinding: Binding<LocalFavoriteLibrarySortOrder> {
        Binding(
            get: { organizer.filter.sortOrder },
            set: { organizer.updateSortOrder($0) }
        )
    }

    private var sortDescendingBinding: Binding<Bool> {
        Binding(
            get: { organizer.filter.sortDescending },
            set: { organizer.updateSortDescending($0) }
        )
    }

    private var layoutModeBinding: Binding<FavoriteLibraryLayoutMode> {
        Binding(
            get: { organizer.display.layoutMode },
            set: { organizer.updateLayoutMode($0) }
        )
    }

    private var showsCategoryCountsBinding: Binding<Bool> {
        Binding(
            get: { organizer.display.showsCategoryCounts },
            set: { organizer.updateShowsCategoryCounts($0) }
        )
    }

    // MARK: - Dialogs

    private var dialogBinding: Binding<Bool> {
        Binding(
            get: { routes.dialog != nil },
            set: { isPresented in
                if !isPresented {
                    routes.dialog = nil
                }
            }
        )
    }

    private var dialogTitle: Text {
        switch routes.dialog {
        case .dissolveCollection, .dissolveSelectedCollections:
            Text(L10n.string("favorites.dissolve_collection"))
        case .deleteItem:
            Text(L10n.string("favorites.delete_favorite"))
        case .deleteSelection:
            Text(L10n.string("favorites.delete_selection"))
        case nil:
            Text("")
        }
    }

    @ViewBuilder
    private func dialogActions(_ dialog: LocalFavoritesRoutes.Dialog) -> some View {
        switch dialog {
        case let .dissolveCollection(collection):
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("favorites.dissolve"), role: .destructive) {
                Task { await organizer.dissolveCollection(id: collection.id) }
            }
        case let .deleteItem(item):
            Button(L10n.string("common.cancel"), role: .cancel) {}
            if item.locations.count > 1 {
                Button(L10n.string("favorites.delete_scope.current_location"), role: .destructive) {
                    Task { await organizer.deleteItem(item, scope: .currentLocation) }
                }
            }
            Button(L10n.string("favorites.delete_scope.everywhere"), role: .destructive) {
                Task { await organizer.deleteItem(item, scope: .everywhere) }
            }
        case .deleteSelection:
            Button(L10n.string("common.cancel"), role: .cancel) {}
            if organizer.selectedFavoritesCanRemoveCurrentLocation {
                Button(L10n.string("favorites.delete_scope.current_location"), role: .destructive) {
                    Task { await organizer.deleteSelection(scope: .currentLocation) }
                }
            }
            Button(L10n.string("favorites.delete_scope.everywhere"), role: .destructive) {
                Task { await organizer.deleteSelection(scope: .everywhere) }
            }
        case .dissolveSelectedCollections:
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("favorites.dissolve"), role: .destructive) {
                Task { await organizer.dissolveSelectedCollections() }
            }
        }
    }

    @ViewBuilder
    private func dialogMessage(_ dialog: LocalFavoritesRoutes.Dialog) -> some View {
        switch dialog {
        case let .dissolveCollection(collection):
            Text(L10n.string("favorites.dissolve_collection_message", collection.name))
        case let .deleteItem(item):
            if item.locations.count > 1 {
                Text(L10n.string("favorites.delete_favorite_scope_message", item.resolvedDisplayTitle))
            } else {
                Text(L10n.string("favorites.delete_favorite_message", item.resolvedDisplayTitle))
            }
        case .deleteSelection:
            Text(deleteSelectionMessage)
        case .dissolveSelectedCollections:
            Text(L10n.string("favorites.bulk_dissolve_collections_message"))
        }
    }

    private var deleteSelectionMessage: String {
        if selection.selectedCollectionCount > 0 {
            return L10n.string("favorites.bulk_delete_mixed_message")
        }
        if organizer.selectedFavoritesCanRemoveCurrentLocation {
            return L10n.string("favorites.bulk_delete_scope_message")
        }
        return L10n.string("favorites.bulk_delete_favorites_message")
    }

    // MARK: - Errors

    private var combinedErrorMessage: String? {
        organizer.errorMessage ?? remoteSync.errorMessage ?? updateMonitor.errorMessage
    }

    private func clearErrorMessages() {
        organizer.errorMessage = nil
        remoteSync.errorMessage = nil
        updateMonitor.errorMessage = nil
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { combinedErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    clearErrorMessages()
                }
            }
        )
    }

    private var hasSubmittedSearch: Bool {
        !organizer.filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
