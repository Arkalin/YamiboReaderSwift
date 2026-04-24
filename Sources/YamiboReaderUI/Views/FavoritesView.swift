import SwiftUI
import UniformTypeIdentifiers
import YamiboReaderCore

public enum FavoriteFilter: String, CaseIterable, Identifiable {
    case all
    case novel
    case manga
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "全部"
        case .novel: "小说"
        case .manga: "漫画"
        case .other: "其他"
        }
    }

    fileprivate func matches(_ favorite: Favorite) -> Bool {
        switch self {
        case .all:
            true
        case .novel:
            favorite.type == .novel
        case .manga:
            favorite.type == .manga
        case .other:
            favorite.type == .other || favorite.type == .unknown
        }
    }
}

public enum FavoriteSortOrder: String, CaseIterable, Identifiable {
    case manual
    case title
    case progress
    case recentRead

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: "默认"
        case .title: "标题"
        case .progress: "进度"
        case .recentRead: "最近阅读"
        }
    }
}

public enum FavoriteScope: Hashable, Sendable {
    case root
    case collection(FavoriteCollection)

    fileprivate var collection: FavoriteCollection? {
        if case let .collection(collection) = self {
            return collection
        }
        return nil
    }
}

public enum FavoriteListEntry: Identifiable, Hashable, Sendable {
    case collection(FavoriteCollection)
    case favorite(Favorite)

    public var id: String {
        switch self {
        case let .collection(collection):
            "collection:\(collection.id)"
        case let .favorite(favorite):
            "favorite:\(favorite.id)"
        }
    }

    var moveKey: String { id }
}

struct FavoriteSelectionActionState: Equatable {
    let canCreateCollection: Bool
    let canMove: Bool
    let canDelete: Bool
}

enum FavoriteLaunchMode: Sendable {
    case start
    case resume
}

@MainActor
public final class FavoritesViewModel: ObservableObject {
    @Published public private(set) var favorites: [Favorite] = []
    @Published public private(set) var collections: [FavoriteCollection] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var resolvingFavoriteID: String?
    @Published public private(set) var deletingFavoriteID: String?
    @Published public private(set) var favoriteAppearance = FavoriteAppearanceSettings()
    @Published public var errorMessage: String?

    private let appContext: YamiboAppContext
    private let favoriteStore: FavoriteStore
    private var favoriteUpdatesTask: Task<Void, Never>?
    private var settingsUpdatesTask: Task<Void, Never>?

    public init(appContext: YamiboAppContext, favoriteStore: FavoriteStore) {
        self.appContext = appContext
        self.favoriteStore = favoriteStore
        favoriteUpdatesTask = Task { @MainActor [weak self, favoriteStore] in
            for await notification in NotificationCenter.default.notifications(named: FavoriteStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[FavoriteStore.changeIDUserInfoKey] as? String,
                      changeID == favoriteStore.changeID else {
                    continue
                }
                await self.reloadLocalFavorites()
            }
        }
        settingsUpdatesTask = Task { @MainActor [weak self, settingsStore = appContext.settingsStore] in
            for await notification in NotificationCenter.default.notifications(named: SettingsStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[SettingsStore.changeIDUserInfoKey] as? String,
                      changeID == settingsStore.changeID else {
                    continue
                }
                await self.reloadFavoriteAppearance()
            }
        }
    }

    deinit {
        favoriteUpdatesTask?.cancel()
        settingsUpdatesTask?.cancel()
    }

    public func loadCachedFavorites() async {
        await reloadFavoriteAppearance()
        await reloadLocalFavorites()
    }

    public func reloadLocalFavorites() async {
        applySnapshot(await favoriteStore.loadLibrarySnapshot())
    }

    public func reloadFavoriteAppearance() async {
        favoriteAppearance = await appContext.settingsStore.load().favoriteAppearance
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = await appContext.makeRepository()
            let remote = try await repository.fetchFavorites()
            favorites = try await favoriteStore.mergeRemoteFavorites(remote)
            collections = await favoriteStore.loadCollections()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func canReorderFavorites(sortOrder: FavoriteSortOrder, searchText: String) -> Bool {
        sortOrder == .manual &&
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isLoading &&
        deletingFavoriteID == nil
    }

    func canReorderEntries(
        scope: FavoriteScope,
        filter: FavoriteFilter,
        sortOrder: FavoriteSortOrder,
        searchText: String,
        isSelecting: Bool
    ) -> Bool {
        guard !isSelecting else { return false }
        return canReorderFavorites(sortOrder: sortOrder, searchText: searchText)
    }

    func reorderFavorites(visibleIDs: [String], fromOffsets: IndexSet, toOffset: Int) async {
        await reorderFavorites(in: nil, visibleIDs: visibleIDs, fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func reorderFavorites(
        in parentCollectionID: String?,
        visibleIDs: [String],
        fromOffsets: IndexSet,
        toOffset: Int
    ) async {
        guard !visibleIDs.isEmpty, !fromOffsets.isEmpty else { return }

        do {
            favorites = try await favoriteStore.reorderFavorites(
                in: parentCollectionID,
                visibleIDs: visibleIDs,
                fromOffsets: fromOffsets,
                toOffset: toOffset
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderRootEntries(visibleEntryKeys: [String], fromOffsets: IndexSet, toOffset: Int) async {
        guard !visibleEntryKeys.isEmpty, !fromOffsets.isEmpty else { return }

        do {
            applySnapshot(
                try await favoriteStore.reorderRootEntries(
                    visibleEntryKeys: visibleEntryKeys,
                    fromOffsets: fromOffsets,
                    toOffset: toOffset
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderFavorites(
        in parentCollectionID: String?,
        visibleIDs: [String],
        moves: [FavoriteVisibleOrderMove]
    ) async {
        guard !visibleIDs.isEmpty, !moves.isEmpty else { return }

        var workingVisibleIDs = visibleIDs

        do {
            for move in moves {
                favorites = try await favoriteStore.reorderFavorites(
                    in: parentCollectionID,
                    visibleIDs: workingVisibleIDs,
                    fromOffsets: move.fromOffsets,
                    toOffset: move.toOffset
                )
                workingVisibleIDs.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderRootEntries(visibleEntryKeys: [String], moves: [FavoriteVisibleOrderMove]) async {
        guard !visibleEntryKeys.isEmpty, !moves.isEmpty else { return }

        var workingVisibleEntryKeys = visibleEntryKeys

        do {
            for move in moves {
                applySnapshot(
                    try await favoriteStore.reorderRootEntries(
                        visibleEntryKeys: workingVisibleEntryKeys,
                        fromOffsets: move.fromOffsets,
                        toOffset: move.toOffset
                    )
                )
                workingVisibleEntryKeys.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setDisplayName(_ displayName: String?, for favorite: Favorite) async {
        await setDisplayName(displayName, forFavoriteID: favorite.id, originalTitle: favorite.title)
    }

    public func setDisplayName(_ displayName: String?, forFavoriteID favoriteID: String, originalTitle: String) async {
        do {
            let normalized = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueToPersist: String? = if let normalized, !normalized.isEmpty, normalized != originalTitle {
                normalized
            } else {
                nil
            }
            favorites = try await favoriteStore.setDisplayName(valueToPersist, for: favoriteID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setHidden(_ isHidden: Bool, for favorite: Favorite) async {
        do {
            favorites = try await favoriteStore.setHidden(isHidden, for: favorite.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createCollection(name: String, favoriteIDs: [String]) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.createCollection(name: name, favoriteIDs: favoriteIDs))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func setCollectionName(_ name: String, for collectionID: String) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.setCollectionName(name, for: collectionID))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func setCollectionHidden(_ isHidden: Bool, for collection: FavoriteCollection) async {
        do {
            applySnapshot(try await favoriteStore.setCollectionHidden(isHidden, for: collection.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func moveFavorites(ids: [String], toCollectionID: String?) async -> Bool {
        do {
            applySnapshot(try await favoriteStore.moveFavorites(ids: ids, toCollectionID: toCollectionID))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func deleteFavorite(_ favorite: Favorite) async {
        _ = await deleteSelections(favoriteIDs: [favorite.id], collectionIDs: [])
    }

    public func deleteSelections(favoriteIDs: [String], collectionIDs: [String]) async -> Bool {
        var changed = false
        var firstError: String?

        if !collectionIDs.isEmpty {
            do {
                applySnapshot(try await favoriteStore.dissolveCollections(ids: collectionIDs))
                changed = true
            } catch {
                firstError = error.localizedDescription
            }
        }

        for favoriteID in favoriteIDs {
            guard firstError == nil || changed else { break }
            guard let favorite = await favoriteStore.favorite(id: favoriteID) else { continue }
            guard let remoteFavoriteID = favorite.remoteFavoriteID, !remoteFavoriteID.isEmpty else {
                firstError = firstError ?? YamiboError.missingFavoriteDeleteID.localizedDescription
                continue
            }

            deletingFavoriteID = favorite.id
            defer { deletingFavoriteID = nil }

            do {
                let repository = await appContext.makeRepository()
                try await repository.deleteFavorite(remoteFavoriteID: remoteFavoriteID)
                applySnapshot(try await favoriteStore.deleteFavorites(ids: [favorite.id]))
                changed = true
            } catch {
                firstError = firstError ?? error.localizedDescription
            }
        }

        errorMessage = firstError
        return changed
    }

    func openTarget(for favorite: Favorite, mode: FavoriteLaunchMode = .resume) async -> FavoriteOpenTarget {
        var latestFavorite = await favoriteStore.favorite(id: favorite.id) ?? favorite
        do {
            let updatedFavorites = try await favoriteStore.markLastReadAt(for: latestFavorite.id, date: .now)
            favorites = updatedFavorites
            latestFavorite = updatedFavorites.first(where: { $0.id == latestFavorite.id }) ?? latestFavorite
        } catch {
            // Opening should not be blocked by a best-effort recency write.
        }

        switch latestFavorite.type {
        case .novel:
            return .reader(
                ReaderLaunchContext(
                    threadURL: latestFavorite.url,
                    threadTitle: latestFavorite.resolvedDisplayTitle,
                    source: .favorites,
                    initialView: mode == .start ? 1 : nil,
                    initialPage: mode == .start ? 0 : nil,
                    authorID: latestFavorite.authorID
                )
            )
        case .manga:
            return .manga(
                MangaLaunchContext(
                    originalThreadURL: latestFavorite.url,
                    chapterURL: mode == .start ? latestFavorite.url : (latestFavorite.lastMangaURL ?? latestFavorite.url),
                    displayTitle: latestFavorite.resolvedDisplayTitle,
                    source: .favorites,
                    initialPage: mode == .start ? 0 : latestFavorite.lastPage
                )
            )
        case .other:
            return .web(latestFavorite)
        case .unknown:
            resolvingFavoriteID = latestFavorite.id
            defer { resolvingFavoriteID = nil }

            do {
                let resolver = await appContext.makeThreadOpenResolver()
                let target = try await resolver.resolve(
                    threadURL: latestFavorite.url,
                    title: latestFavorite.resolvedDisplayTitle,
                    htmlOverride: nil,
                    favoriteType: .unknown,
                    favoriteChapterURL: latestFavorite.lastMangaURL,
                    initialPage: latestFavorite.lastPage
                )

                switch target {
                case let .novel(context):
                    favorites = try await favoriteStore.setType(.novel, for: latestFavorite.id)
                    return .reader(applyStartModeIfNeeded(to: context, for: latestFavorite, mode: mode))
                case let .manga(context):
                    favorites = try await favoriteStore.setType(.manga, for: latestFavorite.id)
                    return .manga(applyStartModeIfNeeded(to: context, for: latestFavorite, mode: mode))
                case .web:
                    favorites = try await favoriteStore.setType(.other, for: latestFavorite.id)
                    var updated = latestFavorite
                    updated.type = .other
                    return .web(updated)
                }
            } catch {
                errorMessage = error.localizedDescription
                return .web(latestFavorite)
            }
        }
    }

    func resolveOpenTarget(for favorite: Favorite) async -> FavoriteOpenTarget {
        await openTarget(for: favorite, mode: .resume)
    }

    private func applySnapshot(_ snapshot: FavoriteLibrarySnapshot) {
        favorites = snapshot.favorites
        collections = snapshot.collections
    }

    private func applyStartModeIfNeeded(
        to context: ReaderLaunchContext,
        for favorite: Favorite,
        mode: FavoriteLaunchMode
    ) -> ReaderLaunchContext {
        guard mode == .start else { return context }

        return ReaderLaunchContext(
            threadURL: context.threadURL,
            threadTitle: favorite.resolvedDisplayTitle,
            source: context.source,
            initialView: 1,
            initialPage: 0,
            authorID: context.authorID
        )
    }

    private func applyStartModeIfNeeded(
        to context: MangaLaunchContext,
        for favorite: Favorite,
        mode: FavoriteLaunchMode
    ) -> MangaLaunchContext {
        guard mode == .start else { return context }

        return MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: favorite.url,
            displayTitle: favorite.resolvedDisplayTitle,
            source: context.source,
            initialPage: 0,
            directoryName: context.directoryName
        )
    }
}

public enum FavoriteOpenTarget: Sendable {
    case reader(ReaderLaunchContext)
    case manga(MangaLaunchContext)
    case web(Favorite)
}

private struct FavoriteDisplayNameDraft {
    let favoriteID: String
    let originalTitle: String
    var displayName: String

    init(favorite: Favorite) {
        favoriteID = favorite.id
        originalTitle = favorite.title
        displayName = favorite.displayName ?? favorite.resolvedDisplayTitle
    }
}

private struct FavoriteCollectionNameDraft {
    let collectionID: String
    var name: String

    init(collection: FavoriteCollection) {
        collectionID = collection.id
        name = collection.name
    }
}

struct FavoriteCollectionSummary: Equatable {
    let itemCount: Int
    let hiddenCount: Int
}

enum FavoriteListColumn {
    case left
    case right
}

enum FavoriteDropPosition {
    case before
    case after
}

struct FavoriteVisibleOrderMove: Equatable {
    let fromOffsets: IndexSet
    let toOffset: Int
}

func splitAlternatingColumns<Element>(_ items: [Element]) -> (left: [Element], right: [Element]) {
    var left: [Element] = []
    var right: [Element] = []

    for (index, item) in items.enumerated() {
        if index.isMultiple(of: 2) {
            left.append(item)
        } else {
            right.append(item)
        }
    }

    return (left: left, right: right)
}

func reorderedItemsAfterDrop<Element: Equatable>(
    _ items: [Element],
    draggedItem: Element,
    targetItem: Element,
    position: FavoriteDropPosition
) -> [Element] {
    guard draggedItem != targetItem,
          let draggedIndex = items.firstIndex(of: draggedItem),
          items.contains(targetItem) else {
        return items
    }

    var reordered = items
    reordered.remove(at: draggedIndex)
    guard let targetIndex = reordered.firstIndex(of: targetItem) else { return items }

    let insertionIndex: Int
    switch position {
    case .before:
        insertionIndex = targetIndex
    case .after:
        insertionIndex = targetIndex + 1
    }

    reordered.insert(draggedItem, at: min(insertionIndex, reordered.count))
    return reordered
}

func reorderedItemsAfterDroppingAtColumnBottom<Element: Equatable>(
    _ items: [Element],
    draggedItem: Element,
    column: FavoriteListColumn
) -> [Element] {
    guard items.contains(draggedItem) else { return items }

    let columns = splitAlternatingColumns(items)
    let targetColumn = switch column {
    case .left: columns.left
    case .right: columns.right
    }

    if let lastItem = targetColumn.last {
        return reorderedItemsAfterDrop(items, draggedItem: draggedItem, targetItem: lastItem, position: .after)
    }

    var reordered = items
    guard let draggedIndex = reordered.firstIndex(of: draggedItem) else { return items }
    reordered.remove(at: draggedIndex)

    switch column {
    case .left:
        reordered.insert(draggedItem, at: 0)
    case .right:
        reordered.append(draggedItem)
    }

    return reordered
}

func makeVisibleOrderMovesToTransform<Element: Equatable>(
    from original: [Element],
    to target: [Element]
) -> [FavoriteVisibleOrderMove] {
    guard original.count == target.count else { return [] }

    var working = original
    var moves: [FavoriteVisibleOrderMove] = []

    for targetIndex in target.indices {
        guard working[targetIndex] != target[targetIndex],
              let sourceIndex = working[targetIndex...].firstIndex(of: target[targetIndex]) else {
            continue
        }

        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        let move = FavoriteVisibleOrderMove(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        working.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
        moves.append(move)
    }

    return working == target ? moves : []
}

func applyingVisibleOrderMoves<Element>(
    _ items: [Element],
    moves: [FavoriteVisibleOrderMove]
) -> [Element] {
    var working = items
    for move in moves {
        working.move(fromOffsets: move.fromOffsets, toOffset: move.toOffset)
    }
    return working
}

private struct FavoriteSearchModifier: ViewModifier {
    @Binding var searchText: String

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "搜索"
            )
        #else
        content
            .searchable(text: $searchText, prompt: "搜索")
        #endif
    }
}

private struct FavoriteSettingsMenuButton: View {
    @Binding var showingSettingsSheet: Bool
    @Binding var showingAboutSheet: Bool

    var body: some View {
        Menu {
            Button {
                showingSettingsSheet = true
            } label: {
                Label("设置", systemImage: "gearshape")
            }

            Button {
                showingAboutSheet = true
            } label: {
                Label("关于", systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}

private struct FavoriteSelectionToggleButton: View {
    let isSelecting: Bool
    let action: () -> Void

    var body: some View {
        Button(isSelecting ? "完成" : "选择", action: action)
    }
}

private struct FavoriteToolbarMenuButton: View {
    @Binding var filterRawValue: String
    @Binding var sortRawValue: String
    @Binding var showsHidden: Bool
    let allTitle: String

    var body: some View {
        Menu {
            Picker("分类", selection: $filterRawValue) {
                ForEach(FavoriteFilter.allCases) { filter in
                    Text(filter == .all ? allTitle : filter.title).tag(filter.rawValue)
                }
            }

            Picker("排序", selection: $sortRawValue) {
                ForEach(FavoriteSortOrder.allCases) { sortOrder in
                    Text(sortOrder.title).tag(sortOrder.rawValue)
                }
            }

            Toggle("显示隐藏项", isOn: $showsHidden)
        } label: {
            HStack(spacing: 6) {
                Text(currentTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
    }

    private var currentFilter: FavoriteFilter {
        FavoriteFilter(rawValue: filterRawValue) ?? .all
    }

    private var currentTitle: String {
        currentFilter == .all ? allTitle : currentFilter.title
    }
}

private struct FavoriteToolbarModifier: ViewModifier {
    @Binding var showingSettingsSheet: Bool
    @Binding var showingAboutSheet: Bool
    @Binding var filterRawValue: String
    @Binding var sortRawValue: String
    @Binding var showsHidden: Bool
    @Binding var isSelecting: Bool
    let showsSettingsMenu: Bool
    let allTitle: String
    let onFinishSelection: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if showsSettingsMenu {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    FavoriteSettingsMenuButton(
                        showingSettingsSheet: $showingSettingsSheet,
                        showingAboutSheet: $showingAboutSheet
                    )
                }
                #else
                ToolbarItem(placement: .automatic) {
                    FavoriteSettingsMenuButton(
                        showingSettingsSheet: $showingSettingsSheet,
                        showingAboutSheet: $showingAboutSheet
                    )
                }
                #endif
            }

            ToolbarItem(placement: .principal) {
                FavoriteToolbarMenuButton(
                    filterRawValue: $filterRawValue,
                    sortRawValue: $sortRawValue,
                    showsHidden: $showsHidden,
                    allTitle: allTitle
                )
            }

            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteSelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        onFinishSelection()
                    } else {
                        isSelecting = true
                    }
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                FavoriteSelectionToggleButton(isSelecting: isSelecting) {
                    if isSelecting {
                        onFinishSelection()
                    } else {
                        isSelecting = true
                    }
                }
            }
            #endif
        }
    }
}

private struct FavoriteCollectionNavigationDestinationModifier: ViewModifier {
    let isEnabled: Bool
    let appContext: YamiboAppContext
    let appModel: YamiboAppModel

    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationDestination(for: FavoriteCollection.self) { collection in
                FavoritesView(
                    favoriteStore: appContext.favoriteStore,
                    appContext: appContext,
                    appModel: appModel,
                    scope: .collection(collection)
                )
            }
        } else {
            content
        }
    }
}

private struct FavoriteCollectionDialogsModifier: ViewModifier {
    @Binding var collectionNameDraft: FavoriteCollectionNameDraft?
    @Binding var pendingDeleteCollection: FavoriteCollection?
    let saveName: (FavoriteCollectionNameDraft) -> Void
    let dissolveCollection: (FavoriteCollection) -> Void

    func body(content: Content) -> some View {
        content
            .alert("编辑合集名称", isPresented: collectionNameAlertBinding) {
                TextField("合集名称", text: collectionNameTextBinding)
                Button("取消", role: .cancel) {
                    collectionNameDraft = nil
                }
                Button("保存") {
                    guard let draft = collectionNameDraft else { return }
                    saveName(draft)
                }
                .disabled(collectionNameDraft?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            } message: {
                Text("合集名称会保存在本地。")
            }
            .alert(
                "解散合集",
                isPresented: pendingCollectionDeleteAlertBinding,
                presenting: pendingDeleteCollection
            ) { collection in
                Button("取消", role: .cancel) {
                    pendingDeleteCollection = nil
                }
                Button("解散", role: .destructive) {
                    dissolveCollection(collection)
                }
            } message: { collection in
                Text("确定要解散“\(collection.name)”吗？其中的收藏会返回根页，不会被删除。")
            }
    }

    private var collectionNameAlertBinding: Binding<Bool> {
        Binding(
            get: { collectionNameDraft != nil },
            set: { isPresented in
                if !isPresented {
                    collectionNameDraft = nil
                }
            }
        )
    }

    private var collectionNameTextBinding: Binding<String> {
        Binding(
            get: { collectionNameDraft?.name ?? "" },
            set: { collectionNameDraft?.name = $0 }
        )
    }

    private var pendingCollectionDeleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCollection != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteCollection = nil
                }
            }
        )
    }
}

private struct FavoriteEntryDropDelegate: DropDelegate {
    let draggedEntryKey: String?
    let targetEntry: FavoriteListEntry?
    let column: FavoriteListColumn
    let canReorder: Bool
    let onDropOnEntry: (String, FavoriteListEntry, FavoriteDropPosition) -> Void
    let onDropToColumnBottom: (String, FavoriteListColumn) -> Void
    let onFinish: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        canReorder && draggedEntryKey != nil && info.hasItemsConforming(to: [UTType.plainText.identifier])
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder, draggedEntryKey != nil else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canReorder, let draggedEntryKey else { return false }

        if let targetEntry {
            let position: FavoriteDropPosition = info.location.y < 56 ? .before : .after
            onDropOnEntry(draggedEntryKey, targetEntry, position)
        } else {
            onDropToColumnBottom(draggedEntryKey, column)
        }

        onFinish()
        return true
    }
}

public struct FavoritesView: View {
    @StateObject private var viewModel: FavoritesViewModel
    @AppStorage("yamibo.favorite.filter") private var filterRawValue = FavoriteFilter.all.rawValue
    @AppStorage("yamibo.favorite.sort") private var sortRawValue = FavoriteSortOrder.manual.rawValue
    @AppStorage("yamibo.favorite.showHidden") private var showsHidden = false
    @State private var searchText = ""
    @State private var selectedFavorite: Favorite?
    @State private var showingSettingsSheet = false
    @State private var showingAboutSheet = false
    @State private var displayNameDraft: FavoriteDisplayNameDraft?
    @State private var collectionNameDraft: FavoriteCollectionNameDraft?
    @State private var pendingDeleteFavorite: Favorite?
    @State private var pendingDeleteCollection: FavoriteCollection?
    @State private var isSelecting = false
    @State private var selectedFavoriteIDs: Set<String> = []
    @State private var selectedCollectionIDs: Set<String> = []
    @State private var showingCreateCollectionPrompt = false
    @State private var createCollectionName = ""
    @State private var showingMoveDialog = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var didLoadInitialFavorites = false
    @State private var draggedEntryKey: String?

    private let scope: FavoriteScope
    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(
        favoriteStore: FavoriteStore,
        appContext: YamiboAppContext,
        appModel: YamiboAppModel,
        scope: FavoriteScope = .root
    ) {
        _viewModel = StateObject(wrappedValue: FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore))
        self.scope = scope
        self.appContext = appContext
        self.appModel = appModel
    }

    public var body: some View {
        if case .root = scope {
            NavigationStack {
                favoritesContent
            }
        } else {
            favoritesContent
        }
    }

    private var favoritesContent: some View {
        let content = favoritesChromeContent

        return Group {
            if isSelecting {
                content.safeAreaInset(edge: .bottom, spacing: 0) {
                    selectionActionBar
                }
            } else {
                content
            }
        }
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
                    showingSettingsSheet: $showingSettingsSheet,
                    showingAboutSheet: $showingAboutSheet,
                    filterRawValue: $filterRawValue,
                    sortRawValue: $sortRawValue,
                    showsHidden: $showsHidden,
                    isSelecting: $isSelecting,
                    showsSettingsMenu: isRootScope,
                    allTitle: filterLabel(for: .all),
                    onFinishSelection: exitSelectionMode
                )
            )
            .modifier(
                FavoriteCollectionNavigationDestinationModifier(
                    isEnabled: isRootScope,
                    appContext: appContext,
                    appModel: appModel
                )
            )
    }

    private var favoritesListLayout: some View {
        GeometryReader { geometry in
            ZStack {
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
            .refreshable {
                await viewModel.refresh()
            }
    }

    private var favoritesDialogContent: some View {
        favoritesLifecycleContent
            .alert("加载失败", isPresented: .constant(viewModel.errorMessage != nil), actions: {
                Button("确定") {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
            .alert("编辑显示名称", isPresented: editNameAlertBinding) {
                TextField("显示名称", text: displayNameTextBinding)
                Button("取消", role: .cancel) {
                    displayNameDraft = nil
                }
                Button("保存") {
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
                Text("留空后将恢复显示原标题。")
            }
            .alert("创建合集", isPresented: $showingCreateCollectionPrompt) {
                TextField("合集名称", text: $createCollectionName)
                Button("取消", role: .cancel) {
                    createCollectionName = ""
                }
                Button("创建") {
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
                Text("创建后会把当前选中的收藏移入新合集。")
            }
            .alert(
                "删除收藏",
                isPresented: pendingDeleteAlertBinding,
                presenting: pendingDeleteFavorite
            ) { favorite in
                Button("取消", role: .cancel) {
                    pendingDeleteFavorite = nil
                }
                Button("删除", role: .destructive) {
                    Task {
                        await viewModel.deleteFavorite(favorite)
                    }
                    pendingDeleteFavorite = nil
                }
            } message: { favorite in
                Text("确定要删除“\(favorite.resolvedDisplayTitle)”吗？这会同步删除远端收藏，但会保留本地缓存和阅读进度。")
            }
            .alert("删除所选内容", isPresented: $showingBulkDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
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
            .confirmationDialog("移动到合集", isPresented: $showingMoveDialog, titleVisibility: .visible) {
                Button("<全部>") {
                    moveSelectedFavorites(to: nil)
                }
                ForEach(moveTargets) { collection in
                    Button(collection.name) {
                        moveSelectedFavorites(to: collection.id)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("选择目标合集。")
            }
            .sheet(item: $selectedFavorite) { favorite in
                ForumBrowserView(url: favorite.url, appContext: appContext, appModel: appModel)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showingSettingsSheet) {
                FavoritesSettingsView(appContext: appContext) {
                    filterRawValue = FavoriteFilter.all.rawValue
                    sortRawValue = FavoriteSortOrder.manual.rawValue
                    showsHidden = false
                    searchText = ""
                    await appModel.bootstrap()
                }
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
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
            HStack(alignment: .top, spacing: 20) {
                twoColumnFavoritesColumn(entries: leftColumnEntries, column: .left)
                twoColumnFavoritesColumn(entries: rightColumnEntries, column: .right)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
    }

    @ViewBuilder
    private func overlayContent() -> some View {
        if viewModel.isLoading {
            ProgressView("同步收藏中…")
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
            isSelecting: isSelecting
        )
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
            searchText: searchText
        )
    }

    private var moveTargets: [FavoriteCollection] {
        let targetCollections = orderedCollections(viewModel.collections)
        guard let currentCollection else { return targetCollections }
        return targetCollections.filter { $0.id != currentCollection.id }
    }

    private var bulkDeleteMessage: String {
        if selectedCollectionIDs.isEmpty {
            return "确定要删除已选中的收藏吗？这会同步删除远端收藏，但会保留本地缓存和阅读进度。"
        }
        if selectedFavoriteIDs.isEmpty {
            return "确定要解散已选中的合集吗？其中的收藏会返回根页，不会被删除。"
        }
        return "确定要删除已选中的内容吗？合集会被解散，收藏会同步删除远端收藏。"
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
            ContentUnavailableView("没有匹配结果", systemImage: "magnifyingglass")
        } else if currentCollection != nil {
            ContentUnavailableView("合集为空", systemImage: "folder")
        } else {
            ContentUnavailableView("暂无收藏", systemImage: "books.vertical")
        }
    }

    private var selectionActionBar: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 12) {
                Button("创建合集") {
                    showingCreateCollectionPrompt = true
                }
                .buttonStyle(.bordered)
                .disabled(!selectionActionState.canCreateCollection)

                Button("移动到合集") {
                    showingMoveDialog = true
                }
                .buttonStyle(.bordered)
                .disabled(!selectionActionState.canMove)

                Button("删除", role: .destructive) {
                    showingBulkDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(!selectionActionState.canDelete)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)

            Text("已选择 \(selectedFavoriteIDs.count + selectedCollectionIDs.count) 项")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
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
                    favoriteRow
                }
                .buttonStyle(.plain)
            } else {
                favoriteRow
                    .overlay(alignment: .topTrailing) {
                        favoriteActionMenuButton(favorite)
                    }
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
                        accentColor: favoriteCollectionAccentColor(for: viewModel.favoriteAppearance)
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingDeleteCollection = collection
                    } label: {
                        swipeActionLabel(title: "删除", systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        Task {
                            await viewModel.setCollectionHidden(!collection.isHidden, for: collection)
                        }
                    } label: {
                        swipeActionLabel(
                            title: collection.isHidden ? "取消隐藏" : "隐藏",
                            systemImage: collection.isHidden ? "eye" : "eye.slash"
                        )
                    }
                    .tint(.orange)

                    Button {
                        collectionNameDraft = FavoriteCollectionNameDraft(collection: collection)
                    } label: {
                        swipeActionLabel(title: "编辑", systemImage: "pencil")
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
                        ShareLink(item: favorite.url) {
                            swipeActionLabel(title: "分享", systemImage: "square.and.arrow.up")
                        }
                        .tint(.teal)
                        .disabled(viewModel.deletingFavoriteID != nil)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            pendingDeleteFavorite = favorite
                        } label: {
                            swipeActionLabel(
                                title: viewModel.deletingFavoriteID == favorite.id ? "删除中" : "删除",
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
                                title: favorite.isHidden ? "取消隐藏" : "隐藏",
                                systemImage: favorite.isHidden ? "eye" : "eye.slash"
                            )
                        }
                        .tint(.orange)
                        .disabled(viewModel.deletingFavoriteID != nil)

                        Button {
                            displayNameDraft = FavoriteDisplayNameDraft(favorite: favorite)
                        } label: {
                            swipeActionLabel(title: "编辑", systemImage: "pencil")
                        }
                        .tint(.indigo)
                        .disabled(viewModel.deletingFavoriteID != nil)
                    }
            }
        }
    }

    private func favoriteActionMenuButton(_ favorite: Favorite) -> some View {
        Menu {
            ShareLink(item: favorite.url) {
                Label("分享", systemImage: "square.and.arrow.up")
            }

            Button {
                displayNameDraft = FavoriteDisplayNameDraft(favorite: favorite)
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setHidden(!favorite.isHidden, for: favorite)
                }
            } label: {
                Label(favorite.isHidden ? "取消隐藏" : "隐藏", systemImage: favorite.isHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                pendingDeleteFavorite = favorite
            } label: {
                Label(viewModel.deletingFavoriteID == favorite.id ? "删除中" : "删除", systemImage: "trash")
            }
            .disabled(viewModel.deletingFavoriteID != nil)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.deletingFavoriteID != nil)
    }

    private func collectionActionMenuButton(_ collection: FavoriteCollection) -> some View {
        Menu {
            Button {
                collectionNameDraft = FavoriteCollectionNameDraft(collection: collection)
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button {
                Task {
                    await viewModel.setCollectionHidden(!collection.isHidden, for: collection)
                }
            } label: {
                Label(collection.isHidden ? "取消隐藏" : "隐藏", systemImage: collection.isHidden ? "eye" : "eye.slash")
            }

            Button(role: .destructive) {
                pendingDeleteCollection = collection
            } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            let target = await viewModel.openTarget(for: favorite, mode: mode)
            switch target {
            case let .reader(context):
                appModel.presentReader(context)
            case let .manga(context):
                await appModel.openManga(context)
            case let .web(resolvedFavorite):
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

    private func moveSelectedFavorites(to collectionID: String?) {
        let ids = Array(selectedFavoriteIDs)
        Task {
            if await viewModel.moveFavorites(ids: ids, toCollectionID: collectionID) {
                exitSelectionMode()
            }
        }
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
            searchText: searchText
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

struct FavoriteRow: View {
    let favorite: Favorite
    let isResolving: Bool
    let isDeleting: Bool
    let isSelected: Bool
    let accentColor: Color
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accentColor)
                .frame(width: 5)
                .padding(.vertical, 14)
                .padding(.leading, 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(favorite.resolvedDisplayTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isResolving || isDeleting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.top, 2)
                    } else if isSelected {
                        selectionIndicator
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(favoriteDetailLines(for: favorite), id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if favorite.isHidden {
                        Label("已隐藏", systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.leading, 16)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : accentColor.opacity(0.18),
                    lineWidth: isSelected ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }

    private var selectionIndicator: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.top, 1)
    }
}

struct FavoriteCollectionRow: View {
    let collection: FavoriteCollection
    let summary: FavoriteCollectionSummary
    let isSelected: Bool
    let accentColor: Color

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(accentColor)
                .frame(width: 7)
                .padding(.vertical, 14)
                .padding(.leading, 10)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "folder.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(collection.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("合集")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(accentColor)

                        if collection.isHidden {
                            Label("已隐藏", systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 18)
            .padding(.leading, 16)
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : accentColor.opacity(0.32), lineWidth: isSelected ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var summaryText: String {
        if summary.hiddenCount > 0 {
            return "\(summary.itemCount) 项 · \(summary.hiddenCount) 项已隐藏"
        }
        return "\(summary.itemCount) 项"
    }
}

func makeFavoriteSelectionActionState(
    scope: FavoriteScope,
    selectedFavoriteCount: Int,
    selectedCollectionCount: Int
) -> FavoriteSelectionActionState {
    let hasFavorites = selectedFavoriteCount > 0
    let hasCollections = selectedCollectionCount > 0
    let hasSelection = hasFavorites || hasCollections

    switch scope {
    case .root:
        return FavoriteSelectionActionState(
            canCreateCollection: hasFavorites && !hasCollections,
            canMove: hasFavorites && !hasCollections,
            canDelete: hasSelection
        )
    case .collection:
        return FavoriteSelectionActionState(
            canCreateCollection: false,
            canMove: hasFavorites,
            canDelete: hasFavorites
        )
    }
}

func favoriteProgressScore(for favorite: Favorite) -> Int {
    favorite.lastView * 1000 + favorite.lastPage
}

func progressScore(for favorite: Favorite) -> Int {
    favoriteProgressScore(for: favorite)
}

func makeFilteredFavorites(
    from favorites: [Favorite],
    scope: FavoriteScope = .root,
    showsHidden: Bool,
    filter: FavoriteFilter,
    sortOrder: FavoriteSortOrder,
    searchText: String
) -> [Favorite] {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let parentCollectionID = scope.collection?.id

    let filtered = favorites
        .filter { $0.parentCollectionID == parentCollectionID }
        .filter { showsHidden || !$0.isHidden }
        .filter { filter.matches($0) }
        .filter { favorite in
            guard !trimmedSearchText.isEmpty else { return true }
            return favorite.resolvedDisplayTitle.localizedCaseInsensitiveContains(trimmedSearchText)
        }

    switch sortOrder {
    case .manual:
        return filtered.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    case .title:
        return filtered.sorted { lhs, rhs in
            lhs.resolvedDisplayTitle.localizedCompare(rhs.resolvedDisplayTitle) == .orderedAscending
        }
    case .progress:
        return filtered.sorted { lhs, rhs in
            progressScore(for: lhs) > progressScore(for: rhs)
        }
    case .recentRead:
        return filtered.sorted(by: compareRecentReadFavorites)
    }
}

func makeFavoriteListEntries(
    scope: FavoriteScope,
    favorites: [Favorite],
    collections: [FavoriteCollection],
    showsHidden: Bool,
    filter: FavoriteFilter,
    sortOrder: FavoriteSortOrder,
    searchText: String
) -> [FavoriteListEntry] {
    switch scope {
    case .root:
        let rootFavorites = makeFilteredFavorites(
            from: favorites,
            scope: .root,
            showsHidden: showsHidden,
            filter: filter,
            sortOrder: sortOrder,
            searchText: searchText
        )

        let visibleCollections = orderedCollections(collections).filter { collection in
            rootCollectionMatches(
                collection,
                favorites: favorites,
                showsHidden: showsHidden,
                filter: filter,
                searchText: searchText
            )
        }

        if sortOrder == .manual {
            return (visibleCollections.map(FavoriteListEntry.collection) + rootFavorites.map(FavoriteListEntry.favorite))
                .sorted { lhs, rhs in
                    if entryManualOrder(lhs) != entryManualOrder(rhs) {
                        return entryManualOrder(lhs) < entryManualOrder(rhs)
                    }
                    return lhs.id < rhs.id
                }
        }

        if sortOrder == .recentRead {
            return (visibleCollections.map(FavoriteListEntry.collection) + rootFavorites.map(FavoriteListEntry.favorite))
                .sorted { lhs, rhs in
                    compareRecentReadEntries(lhs, rhs, favorites: favorites, showsHidden: showsHidden, filter: filter, searchText: searchText)
                }
        }

        return visibleCollections.map(FavoriteListEntry.collection) + rootFavorites.map(FavoriteListEntry.favorite)
    case let .collection(collection):
        return makeFilteredFavorites(
            from: favorites,
            scope: .collection(collection),
            showsHidden: showsHidden,
            filter: filter,
            sortOrder: sortOrder,
            searchText: searchText
        ).map(FavoriteListEntry.favorite)
    }
}

func rootCollectionMatches(
    _ collection: FavoriteCollection,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String
) -> Bool {
    guard showsHidden || !collection.isHidden else {
        return false
    }

    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let matchedFavorites = makeFilteredFavorites(
        from: favorites,
        scope: .collection(collection),
        showsHidden: showsHidden,
        filter: filter,
        sortOrder: .manual,
        searchText: searchText
    )

    guard filter == .all else {
        return !matchedFavorites.isEmpty
    }

    guard !trimmedSearchText.isEmpty else {
        return true
    }

    return collection.name.localizedCaseInsensitiveContains(trimmedSearchText) || !matchedFavorites.isEmpty
}

func makeFavoriteCollectionSummary(
    for collection: FavoriteCollection,
    favorites: [Favorite],
    scope: FavoriteScope,
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String
) -> FavoriteCollectionSummary {
    let allItems = favorites.filter { $0.parentCollectionID == collection.id }

    guard case .root = scope else {
        return FavoriteCollectionSummary(
            itemCount: allItems.count,
            hiddenCount: allItems.filter(\.isHidden).count
        )
    }

    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if filter == .all, trimmedSearchText.isEmpty || collection.name.localizedCaseInsensitiveContains(trimmedSearchText) {
        return FavoriteCollectionSummary(
            itemCount: allItems.count,
            hiddenCount: allItems.filter(\.isHidden).count
        )
    }

    let matchingItems = makeFilteredFavorites(
        from: favorites,
        scope: .collection(collection),
        showsHidden: true,
        filter: filter,
        sortOrder: .manual,
        searchText: searchText
    )
    return FavoriteCollectionSummary(
        itemCount: matchingItems.count,
        hiddenCount: matchingItems.filter(\.isHidden).count
    )
}

func favoriteProgressText(for favorite: Favorite) -> String? {
    if favorite.type == .novel,
       let chapterTitle = favorite.novelResumePoint?.chapterTitle,
       !chapterTitle.isEmpty {
        return chapterTitle
    }
    if let lastChapter = favorite.lastChapter, !lastChapter.isEmpty {
        if favorite.type == .manga, favorite.lastPage > 0 {
            if let chapterLabel = favoriteMangaChapterLabel(from: lastChapter) {
                return "读至第 \(favorite.lastPage + 1) 页 · \(chapterLabel)"
            }
            return "读至第 \(favorite.lastPage + 1) 页"
        }
        return lastChapter
    }
    if favorite.type == .manga, favorite.lastPage > 0 {
        return "读至第 \(favorite.lastPage + 1) 页"
    }
    if favorite.lastPage > 0 || favorite.lastView > 1 {
        return "第\(favorite.lastPage + 1)页 / 网页第\(favorite.lastView)页"
    }
    return nil
}

func favoriteMangaChapterLabel(from rawTitle: String) -> String? {
    let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedTitle.isEmpty else { return nil }

    let chapterNumber = MangaTitleCleaner.extractChapterNumber(trimmedTitle)
    let displayNumber = MangaChapterDisplayFormatter.displayNumber(
        rawTitle: trimmedTitle,
        chapterNumber: chapterNumber
    )

    guard !displayNumber.isEmpty else { return nil }
    return "第\(displayNumber)话"
}

func favoriteDetailLines(for favorite: Favorite) -> [String] {
    var lines: [String] = []

    if favorite.type == .manga {
        if let progressText = favoriteProgressText(for: favorite) {
            lines.append(progressText)
        } else if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !lastChapter.isEmpty {
            lines.append(lastChapter)
        }

        if lines.isEmpty {
            lines.append(favorite.type.title)
        }

        return Array(lines.prefix(1))
    }

    if let lastChapter = favorite.lastChapter?.trimmingCharacters(in: .whitespacesAndNewlines),
       !lastChapter.isEmpty {
        lines.append(lastChapter)
    }

    if favorite.type == .novel {
        if favorite.lastPage > 0 || favorite.lastView > 1 {
            lines.append("读至第 \(favorite.lastPage + 1) 页 · 网页第 \(favorite.lastView) 页")
        }
    } else if let progressText = favoriteProgressText(for: favorite),
              !lines.contains(progressText) {
        lines.append(progressText)
    }

    if lines.isEmpty {
        lines.append(favorite.type.title)
    }

    return Array(lines.prefix(2))
}

func favoriteAccentAppearanceColor(
    for type: FavoriteType,
    appearance: FavoriteAppearanceSettings
) -> FavoriteAppearanceColor {
    switch type {
    case .novel:
        appearance.novel
    case .manga:
        appearance.manga
    case .other:
        appearance.other
    case .unknown:
        .gray
    }
}

func favoriteAccentColor(for type: FavoriteType, appearance: FavoriteAppearanceSettings) -> Color {
    favoriteAccentAppearanceColor(for: type, appearance: appearance).swiftUIColor
}

func favoriteCollectionAccentColor(for appearance: FavoriteAppearanceSettings) -> Color {
    appearance.collection.swiftUIColor
}

func favoriteCollectionAccentAppearanceColor(for appearance: FavoriteAppearanceSettings) -> FavoriteAppearanceColor {
    appearance.collection
}

func favoriteAccentColor(for type: FavoriteType) -> Color {
    favoriteAccentColor(for: type, appearance: .init())
}

func favoriteCollectionAccentColor() -> Color {
    favoriteCollectionAccentColor(for: .init())
}

func orderedCollections(_ collections: [FavoriteCollection]) -> [FavoriteCollection] {
    collections.sorted { lhs, rhs in
        if lhs.manualOrder != rhs.manualOrder {
            return lhs.manualOrder < rhs.manualOrder
        }
        return lhs.id < rhs.id
    }
}

private func entryManualOrder(_ entry: FavoriteListEntry) -> Int {
    switch entry {
    case let .collection(collection):
        collection.manualOrder
    case let .favorite(favorite):
        favorite.manualOrder
    }
}

private func compareRecentReadFavorites(_ lhs: Favorite, _ rhs: Favorite) -> Bool {
    switch (lhs.lastReadAt, rhs.lastReadAt) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        if lhs.manualOrder != rhs.manualOrder {
            return lhs.manualOrder < rhs.manualOrder
        }
        return lhs.id < rhs.id
    }
}

private func compareRecentReadEntries(
    _ lhs: FavoriteListEntry,
    _ rhs: FavoriteListEntry,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String
) -> Bool {
    switch (entryLastReadAt(lhs, favorites: favorites, showsHidden: showsHidden, filter: filter, searchText: searchText), entryLastReadAt(rhs, favorites: favorites, showsHidden: showsHidden, filter: filter, searchText: searchText)) {
    case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
        return lhsDate > rhsDate
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        if entryManualOrder(lhs) != entryManualOrder(rhs) {
            return entryManualOrder(lhs) < entryManualOrder(rhs)
        }
        return lhs.id < rhs.id
    }
}

private func entryLastReadAt(
    _ entry: FavoriteListEntry,
    favorites: [Favorite],
    showsHidden: Bool,
    filter: FavoriteFilter,
    searchText: String
) -> Date? {
    switch entry {
    case let .favorite(favorite):
        return favorite.lastReadAt
    case let .collection(collection):
        return makeFilteredFavorites(
            from: favorites,
            scope: .collection(collection),
            showsHidden: showsHidden,
            filter: filter,
            sortOrder: .recentRead,
            searchText: searchText
        )
        .compactMap(\.lastReadAt)
        .max()
    }
}

private extension View {
    @ViewBuilder
    func onDragIf(_ condition: Bool, value: String, onStart: @escaping () -> Void) -> some View {
        if condition {
            onDrag {
                onStart()
                return NSItemProvider(object: value as NSString)
            }
        } else {
            self
        }
    }
}
