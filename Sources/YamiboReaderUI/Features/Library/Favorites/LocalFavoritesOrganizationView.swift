import SwiftUI
import YamiboReaderCore

struct LocalFavoriteSelectionState {
    var isActive: Bool
    var selectedFavoriteIDs: Set<String>
    var selectedCollectionIDs: Set<String>
    var selectedFavoriteCount: Int
    var selectedCollectionCount: Int
    var selectedEntryCount: Int
    var canCreateCollection: Bool
    var editableCollection: LocalFavoriteCollection?
}

struct LocalFavoritesRootView: View {
    @StateObject private var viewModel: LocalFavoritesViewModel
    @State private var webRoute: LocalFavoriteWebRoute?

    let appModel: YamiboAppModel

    init(appContext: YamiboAppContext, appModel: YamiboAppModel) {
        _viewModel = StateObject(wrappedValue: LocalFavoritesViewModel(appContext: appContext))
        self.appModel = appModel
    }

    var body: some View {
        LocalFavoritesOrganizationView(
            categories: viewModel.categories,
            collections: viewModel.collections,
            tags: viewModel.tags,
            cards: viewModel.cards,
            categoryEntryCounts: viewModel.categoryEntryCounts,
            collectionEntryCounts: viewModel.collectionEntryCounts,
            selectedCollection: viewModel.selectedCollection,
            selectionState: LocalFavoriteSelectionState(
                isActive: viewModel.isSelectionMode,
                selectedFavoriteIDs: viewModel.selectedFavoriteIDs,
                selectedCollectionIDs: viewModel.selectedCollectionIDs,
                selectedFavoriteCount: viewModel.selectedFavoriteCount,
                selectedCollectionCount: viewModel.selectedCollectionCount,
                selectedEntryCount: viewModel.selectedEntryCount,
                canCreateCollection: viewModel.canCreateCollectionFromSelection,
                editableCollection: viewModel.singleSelectedCollection
            ),
            selectedCategoryID: $viewModel.selectedCategoryID,
            sourceGroupFilter: $viewModel.sourceGroupFilter,
            selectedTagIDs: $viewModel.selectedTagIDs,
            sortOrder: Binding(
                get: { viewModel.sortOrder },
                set: { viewModel.updateSortOrder($0) }
            ),
            sortDescending: Binding(
                get: { viewModel.sortDescending },
                set: { viewModel.updateSortDescending($0) }
            ),
            layoutMode: Binding(
                get: { viewModel.layoutMode },
                set: { viewModel.updateLayoutMode($0) }
            ),
            showsCategoryCounts: Binding(
                get: { viewModel.showsCategoryCounts },
                set: { viewModel.updateShowsCategoryCounts($0) }
            ),
            isSearchMode: viewModel.isSearchMode,
            searchDraftText: $viewModel.searchDraftText,
            submittedSearchText: viewModel.searchText,
            availableSourceGroups: viewModel.availableSourceGroups,
            sourceGroupEntryCounts: viewModel.sourceGroupEntryCounts,
            isLoading: viewModel.isLoading,
            remoteSyncSnapshot: viewModel.remoteSyncSnapshot,
            favoriteUpdateSnapshot: viewModel.favoriteUpdateSnapshot,
            favoriteUpdateEvents: viewModel.favoriteUpdateEvents,
            favoriteUpdateFidFilters: viewModel.favoriteUpdateFidFilters,
            favoriteUpdateCategoryFilters: viewModel.favoriteUpdateCategoryFilters,
            errorMessage: $viewModel.errorMessage,
            sourceGroupLabel: viewModel.sourceGroupLabel(_:),
            onRefresh: {
                await viewModel.refreshRemoteFavorites()
            },
            onStartRemoteSync: { categoryID in
                await viewModel.startRemoteFavoriteSync(targetCategoryID: categoryID)
            },
            onResumeRemoteSync: {
                await viewModel.resumeRemoteFavoriteSync()
            },
            onInterruptRemoteSync: {
                await viewModel.interruptRemoteFavoriteSync()
            },
            onHideRemoteSyncCard: {
                await viewModel.hideRemoteFavoriteSyncCard()
            },
            onStartFavoriteUpdateCheck: {
                await viewModel.startFavoriteUpdateCheck()
            },
            onInterruptFavoriteUpdateCheck: {
                await viewModel.interruptFavoriteUpdateCheck()
            },
            onMarkFavoriteUpdateEventRead: { eventID in
                await viewModel.markFavoriteUpdateEventRead(eventID)
            },
            onDismissFavoriteUpdateEvent: { eventID in
                await viewModel.dismissFavoriteUpdateEvent(eventID)
            },
            onDismissAllFavoriteUpdateEvents: {
                await viewModel.dismissAllFavoriteUpdateEvents()
            },
            onSetFavoriteUpdateFidFilter: { fid, enabled in
                await viewModel.setFavoriteUpdateFidFilter(fid, enabled: enabled)
            },
            onSetFavoriteUpdateCategoryFilter: { categoryID, enabled in
                await viewModel.setFavoriteUpdateCategoryFilter(categoryID, enabled: enabled)
            },
            onCreateCategory: { name in
                await viewModel.createCategory(name: name)
            },
            onRenameCategory: { categoryID, name in
                await viewModel.renameCategory(id: categoryID, name: name)
            },
            onDeleteCategory: { categoryID in
                await viewModel.deleteCategory(id: categoryID)
            },
            onMoveCategory: { categoryID, direction in
                await viewModel.moveCategory(id: categoryID, direction: direction)
            },
            onOpenCollection: { collectionID in
                viewModel.openCollection(id: collectionID)
            },
            onCloseCollection: {
                viewModel.closeCollection()
            },
            onCreateCollection: { name, color in
                await viewModel.createCollection(name: name, color: color)
            },
            onUpdateCollection: { collectionID, name, color in
                await viewModel.updateCollection(id: collectionID, name: name, color: color)
            },
            onDissolveCollection: { collectionID in
                await viewModel.dissolveCollection(id: collectionID)
            },
            onMoveCollection: { collectionID, direction in
                await viewModel.moveCollection(id: collectionID, direction: direction)
            },
            onMoveCollectionToCategory: { collectionID, categoryID in
                await viewModel.moveCollection(id: collectionID, toCategoryID: categoryID)
            },
            onEnterSelectionMode: {
                viewModel.enterSelectionMode()
            },
            onExitSelectionMode: {
                viewModel.exitSelectionMode()
            },
            onClearSelection: {
                viewModel.clearSelection()
            },
            onSelectAllVisible: {
                viewModel.selectAllVisible()
            },
            onInvertVisibleSelection: {
                viewModel.invertVisibleSelection()
            },
            onEnterSearchMode: {
                viewModel.enterSearchMode()
            },
            onSubmitSearch: {
                viewModel.submitSearch()
            },
            onExitSearchMode: {
                viewModel.exitSearchMode()
            },
            onToggleFavoriteSelection: { favoriteID in
                viewModel.toggleFavoriteSelection(id: favoriteID)
            },
            onToggleCollectionSelection: { collectionID in
                viewModel.toggleCollectionSelection(id: collectionID)
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
            onUpdateFavoriteTags: { itemID, tagIDs in
                await viewModel.updateTags(for: itemID, tagIDs: tagIDs)
            },
            onUpdateSelectionTags: { tagIDs in
                await viewModel.updateTagsForSelection(tagIDs)
            },
            onCreateCollectionFromSelection: { name, color in
                await viewModel.createCollectionFromSelection(name: name, color: color)
            },
            onMoveSelectionToCategory: { categoryID in
                await viewModel.moveSelectionToCategory(id: categoryID)
            },
            onMoveSelectionToCollection: { collectionID in
                await viewModel.moveSelectionToCollection(id: collectionID)
            },
            onAddSelectionToCategory: { categoryID in
                await viewModel.addSelectionToCategory(id: categoryID)
            },
            onAddSelectionToCollection: { collectionID in
                await viewModel.addSelectionToCollection(id: collectionID)
            },
            onRemoveSelectionFromCurrentLocation: {
                await viewModel.removeSelectionFromCurrentLocation()
            },
            onDissolveSelectedCollections: {
                await viewModel.dissolveSelectedCollections()
            },
            onDeleteSelection: { scope in
                await viewModel.deleteSelection(scope: scope)
            },
            onOpen: { item, mode in
                await open(item, mode: mode)
            },
            onDelete: { item, scope in
                await viewModel.deleteItem(item, scope: scope)
            }
        )
        .task {
            await viewModel.load()
        }
        .sheet(item: $webRoute) { route in
            NavigationStack {
                ForumBrowserView(url: route.url, appContext: appModel.appContext, appModel: appModel)
            }
        }
    }

    private func open(_ item: FavoriteItem, mode: FavoriteLaunchMode) async {
        guard let target = await viewModel.openTarget(for: item, mode: mode) else { return }
        switch target {
        case let .novelReader(context):
            appModel.presentNovelReader(context)
        case let .mangaReader(context):
            appModel.presentMangaReader(context)
        case let .nativeThread(url, title):
            appModel.openNativeForumThread(url: url, title: title)
        case let .web(url):
            webRoute = LocalFavoriteWebRoute(url: url)
        }
    }
}

private struct LocalFavoriteWebRoute: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}

struct FavoriteRemoteSyncProgressSheet: View {
    let snapshot: FavoriteRemoteSyncSnapshot?
    var onResume: (() async -> String?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    var onHide: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let snapshot {
                Section {
                    FavoriteRemoteSyncSummary(snapshot: snapshot)
                }

                Section(L10n.string("favorites.sync.progress.metrics")) {
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.target"), value: snapshot.targetCategoryName)
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.scanned"), value: "\(snapshot.scannedCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.imported"), value: "\(snapshot.importedCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.failed"), value: "\(snapshot.failedCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.marked_missing"), value: "\(snapshot.markedMissingCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.upload_pending"), value: "\(snapshot.uploadTargetCount)")
                }

                FavoriteRemoteSyncMessageSection(
                    title: L10n.string("favorites.sync.progress.logs"),
                    messages: snapshot.logMessages,
                    fallback: L10n.string("favorites.sync.progress.no_logs")
                )
                FavoriteRemoteSyncMessageSection(
                    title: L10n.string("favorites.sync.progress.warnings"),
                    messages: snapshot.warningMessages,
                    fallback: L10n.string("favorites.sync.progress.no_warnings")
                )
                FavoriteRemoteSyncMessageSection(
                    title: L10n.string("favorites.sync.progress.errors"),
                    messages: snapshot.errorMessages,
                    fallback: L10n.string("favorites.sync.progress.no_errors")
                )
            } else {
                ContentUnavailableView(L10n.string("favorites.sync.progress.empty"), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .navigationTitle(L10n.string("favorites.sync.progress.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("common.close")) {
                    dismiss()
                }
            }
            if let snapshot, hasActions {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if snapshot.status == .running, let onInterrupt {
                            Button(role: .destructive) {
                                Task { await onInterrupt() }
                            } label: {
                                Label(L10n.string("favorites.sync.interrupt"), systemImage: "stop.circle")
                            }
                        } else if let onResume {
                            Button {
                                Task { _ = await onResume() }
                            } label: {
                                Label(L10n.string("favorites.sync.resume"), systemImage: "play.circle")
                            }
                        }
                        if let onHide {
                            Button {
                                Task {
                                    await onHide()
                                    dismiss()
                                }
                            } label: {
                                Label(L10n.string("favorites.sync.hide_card"), systemImage: "eye.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var hasActions: Bool {
        onResume != nil || onInterrupt != nil || onHide != nil
    }
}

private struct FavoriteRemoteSyncStatusCard: View {
    let snapshot: FavoriteRemoteSyncSnapshot
    let onOpen: () -> Void
    let onResume: () -> Void
    let onInterrupt: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusImageName)
                    .foregroundStyle(statusColor)
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(snapshot.phase)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button(action: onHide) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.sync.hide_card"))
            }

            ProgressView(value: progressValue)
                .opacity(snapshot.status == .running ? 1 : 0.65)

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label(L10n.string("favorites.sync.progress.open"), systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)

                if snapshot.status == .running {
                    Button(role: .destructive, action: onInterrupt) {
                        Label(L10n.string("favorites.sync.interrupt"), systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onResume) {
                        Label(L10n.string("favorites.sync.resume"), systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressValue: Double {
        guard let total = snapshot.totalRemoteCount, total > 0 else {
            return snapshot.status == .running ? 0.1 : 1
        }
        return min(1, Double(snapshot.scannedCount) / Double(total))
    }

    private var statusTitle: String {
        switch snapshot.status {
        case .running:
            L10n.string("favorites.sync.status.running")
        case .completed:
            L10n.string("favorites.sync.status.completed")
        case .failed:
            L10n.string("favorites.sync.status.failed")
        case .interrupted:
            L10n.string("favorites.sync.status.interrupted")
        }
    }

    private var statusImageName: String {
        switch snapshot.status {
        case .running:
            "arrow.triangle.2.circlepath"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .interrupted:
            "pause.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .running:
            .accentColor
        case .completed:
            .green
        case .failed:
            .red
        case .interrupted:
            .orange
        }
    }
}

private struct FavoriteUpdateStatusCard: View {
    let snapshot: FavoriteUpdateRunSnapshot
    let eventCount: Int
    let onOpenEvents: () -> Void
    let onOpenFilters: () -> Void
    let onStart: () -> Void
    let onInterrupt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusImageName)
                    .foregroundStyle(statusColor)
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: onOpenFilters) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.updates.filters"))
            }

            ProgressView(value: progressValue)
                .opacity(snapshot.status == .running ? 1 : 0.65)

            HStack(spacing: 8) {
                Button(action: onOpenEvents) {
                    Label(L10n.string("favorites.updates.events_count", eventCount), systemImage: "bell")
                }
                .buttonStyle(.bordered)

                if snapshot.status == .running {
                    Button(role: .destructive, action: onInterrupt) {
                        Label(L10n.string("favorites.updates.interrupt"), systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onStart) {
                        Label(L10n.string("favorites.updates.check"), systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressValue: Double {
        guard snapshot.totalCount > 0 else {
            return snapshot.status == .running ? 0.1 : 1
        }
        return min(1, Double(snapshot.completedCount + snapshot.skippedCount + snapshot.failedCount) / Double(snapshot.totalCount))
    }

    private var detailText: String {
        if let currentItem = snapshot.currentItem, !currentItem.isEmpty {
            return currentItem
        }
        return phaseTitle
    }

    private var phaseTitle: String {
        switch snapshot.phase {
        case .preparing:
            L10n.string("favorites.updates.preparing")
        case .checking:
            L10n.string("favorites.updates.checking")
        case .interrupted:
            L10n.string("favorites.updates.interrupted")
        case .failed:
            L10n.string("favorites.updates.failed")
        case .completed:
            L10n.string("favorites.updates.completed")
        case .canceled:
            L10n.string("favorites.updates.canceled")
        }
    }

    private var statusTitle: String {
        switch snapshot.status {
        case .running:
            L10n.string("favorites.updates.status.running")
        case .completed:
            L10n.string("favorites.updates.status.completed")
        case .failed:
            L10n.string("favorites.updates.status.failed")
        case .interrupted:
            L10n.string("favorites.updates.status.interrupted")
        case .canceled:
            L10n.string("favorites.updates.status.canceled")
        }
    }

    private var statusImageName: String {
        switch snapshot.status {
        case .running:
            "arrow.clockwise.circle"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .interrupted:
            "pause.circle"
        case .canceled:
            "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .running:
            .accentColor
        case .completed:
            .green
        case .failed:
            .red
        case .interrupted, .canceled:
            .orange
        }
    }
}

private struct FavoriteUpdateEventsSheet: View {
    let events: [FavoriteUpdateEvent]
    let onMarkRead: (String) async -> Void
    let onDismiss: (String) async -> Void
    let onDismissAll: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(L10n.string("favorites.updates.no_events"), systemImage: "bell")
            } else {
                ForEach(events) { event in
                    FavoriteUpdateEventRow(
                        event: event,
                        onMarkRead: {
                            await onMarkRead(event.id)
                        },
                        onDismiss: {
                            await onDismiss(event.id)
                        }
                    )
                }
            }
        }
        .navigationTitle(L10n.string("favorites.updates.events"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("common.close")) {
                    dismiss()
                }
            }
            if !events.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        Task { await onDismissAll() }
                    } label: {
                        Label(L10n.string("favorites.updates.dismiss_all"), systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }
}

private struct FavoriteUpdateEventRow: View {
    let event: FavoriteUpdateEvent
    let onMarkRead: () async -> Void
    let onDismiss: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: event.readAt == nil ? "bell.badge" : "bell")
                    .foregroundStyle(event.readAt == nil ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                    Text(event.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let forumName = event.forumName {
                        Text(forumName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                Text(event.detectedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if event.readAt == nil {
                    Button {
                        Task { await onMarkRead() }
                    } label: {
                        Label(L10n.string("favorites.updates.mark_read"), systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    Task { await onDismiss() }
                } label: {
                    Label(L10n.string("favorites.updates.dismiss"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private struct FavoriteUpdateFilterSheet: View {
    let fidFilters: [FavoriteUpdateFidFilter]
    let categoryFilters: [FavoriteUpdateCategoryFilter]
    let onSetFidEnabled: (String, Bool) async -> Void
    let onSetCategoryEnabled: (String, Bool) async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section(L10n.string("favorites.updates.filters.fids")) {
                if fidFilters.isEmpty {
                    Text(L10n.string("favorites.updates.filters.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fidFilters) { filter in
                        FavoriteUpdateFilterToggleRow(
                            title: filter.forumName,
                            subtitle: L10n.string("favorites.updates.filters.item_count", filter.itemCount),
                            isOn: filter.enabled,
                            onChange: { enabled in
                                await onSetFidEnabled(filter.fid, enabled)
                            }
                        )
                    }
                }
            }

            Section(L10n.string("favorites.updates.filters.categories")) {
                if categoryFilters.isEmpty {
                    Text(L10n.string("favorites.updates.filters.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categoryFilters) { filter in
                        FavoriteUpdateFilterToggleRow(
                            title: filter.categoryName,
                            subtitle: L10n.string("favorites.updates.filters.item_count", filter.itemCount),
                            isOn: filter.enabled,
                            onChange: { enabled in
                                await onSetCategoryEnabled(filter.categoryID, enabled)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(L10n.string("favorites.updates.filters"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("common.close")) {
                    dismiss()
                }
            }
        }
    }
}

private struct FavoriteUpdateFilterToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let onChange: (Bool) async -> Void

    var body: some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { enabled in
                Task { await onChange(enabled) }
            }
        )
    }
}

private struct FavoriteRemoteSyncCategorySheet: View {
    let categories: [FavoriteCategory]
    let selectedCategoryID: String
    let onCancel: () -> Void
    let onStart: (String) async -> Void

    var body: some View {
        NavigationStack {
            List(categories) { category in
                Button {
                    Task { await onStart(category.id) }
                } label: {
                    HStack {
                        Label(category.displayName, systemImage: category.isDefault ? "tray" : "folder")
                        Spacer()
                        if category.id == selectedCategoryID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("favorites.sync.category.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: onCancel)
                }
            }
        }
    }
}

private struct FavoriteRemoteSyncSummary: View {
    let snapshot: FavoriteRemoteSyncSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusTitle)
                    .font(.headline)
                Spacer()
                Text(snapshot.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.phase)
                .foregroundStyle(.secondary)
            if let total = snapshot.totalRemoteCount {
                ProgressView(value: Double(snapshot.scannedCount), total: Double(max(total, 1)))
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        switch snapshot.status {
        case .running:
            L10n.string("favorites.sync.status.running")
        case .completed:
            L10n.string("favorites.sync.status.completed")
        case .failed:
            L10n.string("favorites.sync.status.failed")
        case .interrupted:
            L10n.string("favorites.sync.status.interrupted")
        }
    }
}

private struct FavoriteRemoteSyncMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FavoriteRemoteSyncMessageSection: View {
    let title: String
    let messages: [String]
    let fallback: String

    var body: some View {
        Section(title) {
            if messages.isEmpty {
                Text(fallback)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                }
            }
        }
    }
}

struct LocalFavoritesOrganizationView: View {
    @State private var categoryNameDraft: LocalFavoriteCategoryNameDraft?
    @State private var collectionDraft: LocalFavoriteCollectionDraft?
    @State private var tagSelectionDraft: LocalFavoriteTagSelectionDraft?
    @State private var pendingDissolveCollection: LocalFavoriteCollection?
    @State private var pendingDeleteItem: FavoriteItem?
    @State private var movesSelection = false
    @State private var confirmsDeleteSelection = false
    @State private var confirmsDissolveSelection = false
    @State private var managesCategories = false
    @State private var selectsRemoteSyncCategory = false
    @State private var remoteSyncProgressRunID: String?
    @State private var showsFavoriteUpdateEvents = false
    @State private var showsFavoriteUpdateFilters = false
    @FocusState private var searchFieldFocused: Bool

    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let tags: [FavoriteTag]
    let cards: [FavoriteCardProjection]
    let categoryEntryCounts: [String: Int]
    let collectionEntryCounts: [String: Int]
    let selectedCollection: LocalFavoriteCollection?
    let selectionState: LocalFavoriteSelectionState
    @Binding var selectedCategoryID: String
    @Binding var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    @Binding var selectedTagIDs: Set<String>
    @Binding var sortOrder: LocalFavoriteLibrarySortOrder
    @Binding var sortDescending: Bool
    @Binding var layoutMode: FavoriteLibraryLayoutMode
    @Binding var showsCategoryCounts: Bool
    let isSearchMode: Bool
    @Binding var searchDraftText: String
    let submittedSearchText: String
    let availableSourceGroups: [FavoriteSourceGroup]
    let sourceGroupEntryCounts: [FavoriteSourceGroup: Int]
    let isLoading: Bool
    let remoteSyncSnapshot: FavoriteRemoteSyncSnapshot?
    let favoriteUpdateSnapshot: FavoriteUpdateRunSnapshot?
    let favoriteUpdateEvents: [FavoriteUpdateEvent]
    let favoriteUpdateFidFilters: [FavoriteUpdateFidFilter]
    let favoriteUpdateCategoryFilters: [FavoriteUpdateCategoryFilter]
    @Binding var errorMessage: String?
    let sourceGroupLabel: (FavoriteSourceGroup) -> String
    let onRefresh: () async -> Void
    let onStartRemoteSync: (String) async -> String?
    let onResumeRemoteSync: () async -> String?
    let onInterruptRemoteSync: () async -> Void
    let onHideRemoteSyncCard: () async -> Void
    let onStartFavoriteUpdateCheck: () async -> String?
    let onInterruptFavoriteUpdateCheck: () async -> Void
    let onMarkFavoriteUpdateEventRead: (String) async -> Void
    let onDismissFavoriteUpdateEvent: (String) async -> Void
    let onDismissAllFavoriteUpdateEvents: () async -> Void
    let onSetFavoriteUpdateFidFilter: (String, Bool) async -> Void
    let onSetFavoriteUpdateCategoryFilter: (String, Bool) async -> Void
    let onCreateCategory: (String) async -> Void
    let onRenameCategory: (String, String) async -> Void
    let onDeleteCategory: (String) async -> Void
    let onMoveCategory: (String, CategoryMoveDirection) async -> Void
    let onOpenCollection: (String) -> Void
    let onCloseCollection: () -> Void
    let onCreateCollection: (String, FavoriteCollectionColor) async -> Void
    let onUpdateCollection: (String, String, FavoriteCollectionColor) async -> Void
    let onDissolveCollection: (String) async -> Void
    let onMoveCollection: (String, CategoryMoveDirection) async -> Void
    let onMoveCollectionToCategory: (String, String) async -> Void
    let onEnterSelectionMode: () -> Void
    let onExitSelectionMode: () -> Void
    let onClearSelection: () -> Void
    let onSelectAllVisible: () -> Void
    let onInvertVisibleSelection: () -> Void
    let onEnterSearchMode: () -> Void
    let onSubmitSearch: () -> Void
    let onExitSearchMode: () -> Void
    let onToggleFavoriteSelection: (String) -> Void
    let onToggleCollectionSelection: (String) -> Void
    let onCreateTag: (String, FavoriteTagColor) async -> FavoriteTag?
    let onUpdateTag: (String, String, FavoriteTagColor) async -> Void
    let onDeleteTag: (String) async -> Void
    let onUpdateFavoriteTags: (String, Set<String>) async -> Void
    let onUpdateSelectionTags: (Set<String>) async -> Void
    let onCreateCollectionFromSelection: (String, FavoriteCollectionColor) async -> Void
    let onMoveSelectionToCategory: (String) async -> Void
    let onMoveSelectionToCollection: (String) async -> Void
    let onAddSelectionToCategory: (String) async -> Void
    let onAddSelectionToCollection: (String) async -> Void
    let onRemoveSelectionFromCurrentLocation: () async -> Void
    let onDissolveSelectedCollections: () async -> Void
    let onDeleteSelection: (LocalFavoriteDeleteScope) async -> Void
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem, LocalFavoriteDeleteScope) async -> Void

    init(
        categories: [FavoriteCategory],
        collections: [LocalFavoriteCollection],
        tags: [FavoriteTag] = [],
        cards: [FavoriteCardProjection],
        categoryEntryCounts: [String: Int] = [:],
        collectionEntryCounts: [String: Int] = [:],
        selectedCollection: LocalFavoriteCollection? = nil,
        selectionState: LocalFavoriteSelectionState = LocalFavoriteSelectionState(
            isActive: false,
            selectedFavoriteIDs: [],
            selectedCollectionIDs: [],
            selectedFavoriteCount: 0,
            selectedCollectionCount: 0,
            selectedEntryCount: 0,
            canCreateCollection: false,
            editableCollection: nil
        ),
        selectedCategoryID: Binding<String>,
        sourceGroupFilter: Binding<LocalFavoriteLibrarySourceGroupFilter> = .constant(.all),
        selectedTagIDs: Binding<Set<String>> = .constant([]),
        sortOrder: Binding<LocalFavoriteLibrarySortOrder> = .constant(.organization),
        sortDescending: Binding<Bool> = .constant(false),
        layoutMode: Binding<FavoriteLibraryLayoutMode> = .constant(.rowCard),
        showsCategoryCounts: Binding<Bool> = .constant(true),
        isSearchMode: Bool = false,
        searchDraftText: Binding<String> = .constant(""),
        submittedSearchText: String = "",
        availableSourceGroups: [FavoriteSourceGroup] = [],
        sourceGroupEntryCounts: [FavoriteSourceGroup: Int] = [:],
        isLoading: Bool = false,
        remoteSyncSnapshot: FavoriteRemoteSyncSnapshot? = nil,
        favoriteUpdateSnapshot: FavoriteUpdateRunSnapshot? = nil,
        favoriteUpdateEvents: [FavoriteUpdateEvent] = [],
        favoriteUpdateFidFilters: [FavoriteUpdateFidFilter] = [],
        favoriteUpdateCategoryFilters: [FavoriteUpdateCategoryFilter] = [],
        errorMessage: Binding<String?> = .constant(nil),
        sourceGroupLabel: @escaping (FavoriteSourceGroup) -> String = { sourceGroup in
            switch sourceGroup {
            case let .forumBoard(_, label):
                label
            case let .mangaTitle(_, cleanBookName):
                cleanBookName
            case .unknown:
                L10n.string("favorites.source_group.unknown")
            }
        },
        onRefresh: @escaping () async -> Void = {},
        onStartRemoteSync: @escaping (String) async -> String? = { _ in nil },
        onResumeRemoteSync: @escaping () async -> String? = { nil },
        onInterruptRemoteSync: @escaping () async -> Void = {},
        onHideRemoteSyncCard: @escaping () async -> Void = {},
        onStartFavoriteUpdateCheck: @escaping () async -> String? = { nil },
        onInterruptFavoriteUpdateCheck: @escaping () async -> Void = {},
        onMarkFavoriteUpdateEventRead: @escaping (String) async -> Void = { _ in },
        onDismissFavoriteUpdateEvent: @escaping (String) async -> Void = { _ in },
        onDismissAllFavoriteUpdateEvents: @escaping () async -> Void = {},
        onSetFavoriteUpdateFidFilter: @escaping (String, Bool) async -> Void = { _, _ in },
        onSetFavoriteUpdateCategoryFilter: @escaping (String, Bool) async -> Void = { _, _ in },
        onCreateCategory: @escaping (String) async -> Void = { _ in },
        onRenameCategory: @escaping (String, String) async -> Void = { _, _ in },
        onDeleteCategory: @escaping (String) async -> Void = { _ in },
        onMoveCategory: @escaping (String, CategoryMoveDirection) async -> Void = { _, _ in },
        onOpenCollection: @escaping (String) -> Void = { _ in },
        onCloseCollection: @escaping () -> Void = {},
        onCreateCollection: @escaping (String, FavoriteCollectionColor) async -> Void = { _, _ in },
        onUpdateCollection: @escaping (String, String, FavoriteCollectionColor) async -> Void = { _, _, _ in },
        onDissolveCollection: @escaping (String) async -> Void = { _ in },
        onMoveCollection: @escaping (String, CategoryMoveDirection) async -> Void = { _, _ in },
        onMoveCollectionToCategory: @escaping (String, String) async -> Void = { _, _ in },
        onEnterSelectionMode: @escaping () -> Void = {},
        onExitSelectionMode: @escaping () -> Void = {},
        onClearSelection: @escaping () -> Void = {},
        onSelectAllVisible: @escaping () -> Void = {},
        onInvertVisibleSelection: @escaping () -> Void = {},
        onEnterSearchMode: @escaping () -> Void = {},
        onSubmitSearch: @escaping () -> Void = {},
        onExitSearchMode: @escaping () -> Void = {},
        onToggleFavoriteSelection: @escaping (String) -> Void = { _ in },
        onToggleCollectionSelection: @escaping (String) -> Void = { _ in },
        onCreateTag: @escaping (String, FavoriteTagColor) async -> FavoriteTag? = { _, _ in nil },
        onUpdateTag: @escaping (String, String, FavoriteTagColor) async -> Void = { _, _, _ in },
        onDeleteTag: @escaping (String) async -> Void = { _ in },
        onUpdateFavoriteTags: @escaping (String, Set<String>) async -> Void = { _, _ in },
        onUpdateSelectionTags: @escaping (Set<String>) async -> Void = { _ in },
        onCreateCollectionFromSelection: @escaping (String, FavoriteCollectionColor) async -> Void = { _, _ in },
        onMoveSelectionToCategory: @escaping (String) async -> Void = { _ in },
        onMoveSelectionToCollection: @escaping (String) async -> Void = { _ in },
        onAddSelectionToCategory: @escaping (String) async -> Void = { _ in },
        onAddSelectionToCollection: @escaping (String) async -> Void = { _ in },
        onRemoveSelectionFromCurrentLocation: @escaping () async -> Void = {},
        onDissolveSelectedCollections: @escaping () async -> Void = {},
        onDeleteSelection: @escaping (LocalFavoriteDeleteScope) async -> Void = { _ in },
        onOpen: @escaping (FavoriteItem, FavoriteLaunchMode) async -> Void = { _, _ in },
        onDelete: @escaping (FavoriteItem, LocalFavoriteDeleteScope) async -> Void = { _, _ in }
    ) {
        self.categories = categories
        self.collections = collections
        self.tags = tags
        self.cards = cards
        self.categoryEntryCounts = categoryEntryCounts
        self.collectionEntryCounts = collectionEntryCounts
        self.selectedCollection = selectedCollection
        self.selectionState = selectionState
        _selectedCategoryID = selectedCategoryID
        _sourceGroupFilter = sourceGroupFilter
        _selectedTagIDs = selectedTagIDs
        _sortOrder = sortOrder
        _sortDescending = sortDescending
        _layoutMode = layoutMode
        _showsCategoryCounts = showsCategoryCounts
        self.isSearchMode = isSearchMode
        _searchDraftText = searchDraftText
        self.submittedSearchText = submittedSearchText
        self.availableSourceGroups = availableSourceGroups
        self.sourceGroupEntryCounts = sourceGroupEntryCounts
        self.isLoading = isLoading
        self.remoteSyncSnapshot = remoteSyncSnapshot
        self.favoriteUpdateSnapshot = favoriteUpdateSnapshot
        self.favoriteUpdateEvents = favoriteUpdateEvents
        self.favoriteUpdateFidFilters = favoriteUpdateFidFilters
        self.favoriteUpdateCategoryFilters = favoriteUpdateCategoryFilters
        _errorMessage = errorMessage
        self.sourceGroupLabel = sourceGroupLabel
        self.onRefresh = onRefresh
        self.onStartRemoteSync = onStartRemoteSync
        self.onResumeRemoteSync = onResumeRemoteSync
        self.onInterruptRemoteSync = onInterruptRemoteSync
        self.onHideRemoteSyncCard = onHideRemoteSyncCard
        self.onStartFavoriteUpdateCheck = onStartFavoriteUpdateCheck
        self.onInterruptFavoriteUpdateCheck = onInterruptFavoriteUpdateCheck
        self.onMarkFavoriteUpdateEventRead = onMarkFavoriteUpdateEventRead
        self.onDismissFavoriteUpdateEvent = onDismissFavoriteUpdateEvent
        self.onDismissAllFavoriteUpdateEvents = onDismissAllFavoriteUpdateEvents
        self.onSetFavoriteUpdateFidFilter = onSetFavoriteUpdateFidFilter
        self.onSetFavoriteUpdateCategoryFilter = onSetFavoriteUpdateCategoryFilter
        self.onCreateCategory = onCreateCategory
        self.onRenameCategory = onRenameCategory
        self.onDeleteCategory = onDeleteCategory
        self.onMoveCategory = onMoveCategory
        self.onOpenCollection = onOpenCollection
        self.onCloseCollection = onCloseCollection
        self.onCreateCollection = onCreateCollection
        self.onUpdateCollection = onUpdateCollection
        self.onDissolveCollection = onDissolveCollection
        self.onMoveCollection = onMoveCollection
        self.onMoveCollectionToCategory = onMoveCollectionToCategory
        self.onEnterSelectionMode = onEnterSelectionMode
        self.onExitSelectionMode = onExitSelectionMode
        self.onClearSelection = onClearSelection
        self.onSelectAllVisible = onSelectAllVisible
        self.onInvertVisibleSelection = onInvertVisibleSelection
        self.onEnterSearchMode = onEnterSearchMode
        self.onSubmitSearch = onSubmitSearch
        self.onExitSearchMode = onExitSearchMode
        self.onToggleFavoriteSelection = onToggleFavoriteSelection
        self.onToggleCollectionSelection = onToggleCollectionSelection
        self.onCreateTag = onCreateTag
        self.onUpdateTag = onUpdateTag
        self.onDeleteTag = onDeleteTag
        self.onUpdateFavoriteTags = onUpdateFavoriteTags
        self.onUpdateSelectionTags = onUpdateSelectionTags
        self.onCreateCollectionFromSelection = onCreateCollectionFromSelection
        self.onMoveSelectionToCategory = onMoveSelectionToCategory
        self.onMoveSelectionToCollection = onMoveSelectionToCollection
        self.onAddSelectionToCategory = onAddSelectionToCategory
        self.onAddSelectionToCollection = onAddSelectionToCollection
        self.onRemoveSelectionFromCurrentLocation = onRemoveSelectionFromCurrentLocation
        self.onDissolveSelectedCollections = onDissolveSelectedCollections
        self.onDeleteSelection = onDeleteSelection
        self.onOpen = onOpen
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            content
            .refreshable {
                await onRefresh()
            }
            .overlay {
                if isLoading {
                    ProgressView(L10n.string("favorites.syncing"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if cards.isEmpty, visibleCollections.isEmpty, hasSubmittedSearch {
                    ContentUnavailableView(L10n.string("favorites.empty.no_results"), systemImage: "magnifyingglass")
                } else if cards.isEmpty, visibleCollections.isEmpty {
                    ContentUnavailableView(L10n.string("favorites.empty.favorites"), systemImage: "books.vertical")
                }
            }
            .navigationTitle(isSearchMode ? L10n.string("favorites.search.title") : L10n.string("favorites.title"))
            .toolbar { favoriteToolbarContent }
            .onChange(of: isSearchMode) { _, active in
                searchFieldFocused = active
            }
            .safeAreaInset(edge: .bottom) {
                if selectionState.isActive {
                    LocalFavoriteSelectionActionBar(
                        selectionState: selectionState,
                        onSelectAll: onSelectAllVisible,
                        onInvert: onInvertVisibleSelection,
                        onMove: { movesSelection = true },
                        onCreateCollection: {
                            collectionDraft = LocalFavoriteCollectionDraft(mode: .createFromSelection)
                        },
                        onEditTags: {
                            tagSelectionDraft = .selection(initialTagIDsForSelection)
                        },
                        onEditCollection: { collection in
                            collectionDraft = LocalFavoriteCollectionDraft(collection: collection)
                        },
                        onDissolveCollections: { confirmsDissolveSelection = true },
                        onDelete: { confirmsDeleteSelection = true },
                        onClear: onClearSelection,
                        onDone: onExitSelectionMode
                    )
                }
            }
            .safeAreaInset(edge: .top) {
                if showsTopStatusCards {
                    VStack(spacing: 8) {
                        if let remoteSyncSnapshot, !remoteSyncSnapshot.isHiddenFromFavoritePage {
                            FavoriteRemoteSyncStatusCard(
                                snapshot: remoteSyncSnapshot,
                                onOpen: {
                                    remoteSyncProgressRunID = remoteSyncSnapshot.runID
                                },
                                onResume: {
                                    Task {
                                        remoteSyncProgressRunID = await onResumeRemoteSync()
                                    }
                                },
                                onInterrupt: {
                                    Task { await onInterruptRemoteSync() }
                                },
                                onHide: {
                                    Task { await onHideRemoteSyncCard() }
                                }
                            )
                        }
                        if let favoriteUpdateSnapshot {
                            FavoriteUpdateStatusCard(
                                snapshot: favoriteUpdateSnapshot,
                                eventCount: favoriteUpdateEvents.count,
                                onOpenEvents: { showsFavoriteUpdateEvents = true },
                                onOpenFilters: { showsFavoriteUpdateFilters = true },
                                onStart: {
                                    Task { _ = await onStartFavoriteUpdateCheck() }
                                },
                                onInterrupt: {
                                    Task { await onInterruptFavoriteUpdateCheck() }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
            .alert(L10n.string("favorites.delete_failed"), isPresented: errorAlertBinding) {
                Button(L10n.string("common.ok")) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $categoryNameDraft) { draft in
                LocalFavoriteCategoryNameSheet(
                    draft: draft,
                    onCancel: {
                        categoryNameDraft = nil
                    },
                    onSave: { name in
                        categoryNameDraft = nil
                        switch draft.mode {
                        case .create:
                            await onCreateCategory(name)
                        case let .rename(categoryID):
                            await onRenameCategory(categoryID, name)
                        }
                    }
                )
            }
            .sheet(isPresented: $managesCategories) {
                LocalFavoriteCategoryManagementSheet(
                    categories: categories,
                    categoryEntryCounts: categoryEntryCounts,
                    showsCategoryCounts: showsCategoryCounts,
                    selectedCategoryID: $selectedCategoryID,
                    onEdit: { category in
                        managesCategories = false
                        categoryNameDraft = LocalFavoriteCategoryNameDraft(
                            mode: .rename(category.id),
                            initialName: category.displayName
                        )
                    },
                    onDelete: { category in
                        await onDeleteCategory(category.id)
                    },
                    onMove: { category, direction in
                        await onMoveCategory(category.id, direction)
                    }
                )
            }
            .sheet(isPresented: $selectsRemoteSyncCategory) {
                FavoriteRemoteSyncCategorySheet(
                    categories: categories,
                    selectedCategoryID: selectedCategoryID,
                    onCancel: {
                        selectsRemoteSyncCategory = false
                    },
                    onStart: { categoryID in
                        selectsRemoteSyncCategory = false
                        remoteSyncProgressRunID = await onStartRemoteSync(categoryID)
                    }
                )
            }
            .sheet(isPresented: remoteSyncProgressBinding) {
                NavigationStack {
                    FavoriteRemoteSyncProgressSheet(
                        snapshot: remoteSyncSnapshot,
                        onResume: {
                            let runID = await onResumeRemoteSync()
                            remoteSyncProgressRunID = runID
                            return runID
                        },
                        onInterrupt: onInterruptRemoteSync,
                        onHide: onHideRemoteSyncCard
                    )
                }
            }
            .sheet(isPresented: $showsFavoriteUpdateEvents) {
                NavigationStack {
                    FavoriteUpdateEventsSheet(
                        events: favoriteUpdateEvents,
                        onMarkRead: onMarkFavoriteUpdateEventRead,
                        onDismiss: onDismissFavoriteUpdateEvent,
                        onDismissAll: onDismissAllFavoriteUpdateEvents
                    )
                }
            }
            .sheet(isPresented: $showsFavoriteUpdateFilters) {
                NavigationStack {
                    FavoriteUpdateFilterSheet(
                        fidFilters: favoriteUpdateFidFilters,
                        categoryFilters: favoriteUpdateCategoryFilters,
                        onSetFidEnabled: onSetFavoriteUpdateFidFilter,
                        onSetCategoryEnabled: onSetFavoriteUpdateCategoryFilter
                    )
                }
            }
            .sheet(item: $collectionDraft) { draft in
                LocalFavoriteCollectionEditorSheet(
                    draft: draft,
                    onCancel: {
                        collectionDraft = nil
                    },
                    onSave: { name, color in
                        collectionDraft = nil
                        switch draft.mode {
                        case .create:
                            await onCreateCollection(name, color)
                        case .createFromSelection:
                            await onCreateCollectionFromSelection(name, color)
                        case let .edit(collectionID):
                            await onUpdateCollection(collectionID, name, color)
                        }
                    }
                )
            }
            .sheet(item: $tagSelectionDraft) { draft in
                LocalFavoriteTagSelectionSheet(
                    tags: tags,
                    draft: draft,
                    onCancel: {
                        tagSelectionDraft = nil
                    },
                    onConfirm: { tagIDs in
                        switch draft.mode {
                        case .filter:
                            selectedTagIDs = tagIDs
                        case let .favorite(itemID):
                            await onUpdateFavoriteTags(itemID, tagIDs)
                        case .selection:
                            await onUpdateSelectionTags(tagIDs)
                        }
                        tagSelectionDraft = nil
                    },
                    onCreateTag: onCreateTag,
                    onUpdateTag: onUpdateTag,
                    onDeleteTag: onDeleteTag
                )
            }
            .sheet(isPresented: $movesSelection) {
                LocalFavoriteSelectionMoveSheet(
                    categories: categories,
                    collections: collections,
                    selectedFavoriteCount: selectionState.selectedFavoriteCount,
                    selectedCollectionCount: selectionState.selectedCollectionCount,
                    selectedCategoryID: selectedCategoryID,
                    selectedCollectionID: selectedCollection?.id,
                    onMoveToCategory: { categoryID in
                        movesSelection = false
                        await onMoveSelectionToCategory(categoryID)
                    },
                    onMoveToCollection: { collectionID in
                        movesSelection = false
                        await onMoveSelectionToCollection(collectionID)
                    },
                    onAddToCategory: { categoryID in
                        movesSelection = false
                        await onAddSelectionToCategory(categoryID)
                    },
                    onAddToCollection: { collectionID in
                        movesSelection = false
                        await onAddSelectionToCollection(collectionID)
                    },
                    onRemoveFromCurrentLocation: {
                        movesSelection = false
                        await onRemoveSelectionFromCurrentLocation()
                    }
                )
            }
            .alert(
                L10n.string("favorites.dissolve_collection"),
                isPresented: dissolveCollectionAlertBinding
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDissolveCollection = nil
                }
                Button(L10n.string("favorites.dissolve"), role: .destructive) {
                    if let pendingDissolveCollection {
                        Task {
                            await onDissolveCollection(pendingDissolveCollection.id)
                            self.pendingDissolveCollection = nil
                        }
                    }
                }
            } message: {
                if let pendingDissolveCollection {
                    Text(L10n.string("favorites.dissolve_collection_message", pendingDissolveCollection.name))
                }
            }
            .alert(
                L10n.string("favorites.delete_selection"),
                isPresented: $confirmsDeleteSelection
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {}
                if selectedFavoritesCanRemoveCurrentLocation {
                    Button(L10n.string("favorites.delete_scope.current_location"), role: .destructive) {
                        Task { await onDeleteSelection(.currentLocation) }
                    }
                }
                Button(L10n.string("favorites.delete_scope.everywhere"), role: .destructive) {
                    Task { await onDeleteSelection(.everywhere) }
                }
            } message: {
                Text(deleteSelectionMessage)
            }
            .alert(
                L10n.string("favorites.delete_favorite"),
                isPresented: deleteItemAlertBinding
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteItem = nil
                }
                if pendingDeleteItem?.locations.count ?? 0 > 1 {
                    Button(L10n.string("favorites.delete_scope.current_location"), role: .destructive) {
                        if let pendingDeleteItem {
                            Task {
                                await onDelete(pendingDeleteItem, .currentLocation)
                                self.pendingDeleteItem = nil
                            }
                        }
                    }
                }
                Button(L10n.string("favorites.delete_scope.everywhere"), role: .destructive) {
                    if let pendingDeleteItem {
                        Task {
                            await onDelete(pendingDeleteItem, .everywhere)
                            self.pendingDeleteItem = nil
                        }
                    }
                }
            } message: {
                if let pendingDeleteItem {
                    Text(deleteMessage(for: pendingDeleteItem))
                }
            }
            .alert(
                L10n.string("favorites.dissolve_collection"),
                isPresented: $confirmsDissolveSelection
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {}
                Button(L10n.string("favorites.dissolve"), role: .destructive) {
                    Task { await onDissolveSelectedCollections() }
                }
            } message: {
                Text(L10n.string("favorites.bulk_dissolve_collections_message"))
            }
        }
    }

    @ToolbarContentBuilder
    private var favoriteToolbarContent: some ToolbarContent {
        if isSearchMode {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: onExitSearchMode) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string("common.back"))
            }
            ToolbarItem(placement: .principal) {
                TextField(L10n.string("favorites.search.placeholder"), text: $searchDraftText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($searchFieldFocused)
                    .onSubmit(onSubmitSearch)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: onSubmitSearch) {
                    Text(L10n.string("common.search"))
                }
            }
        } else {
            ToolbarItem(placement: LocalFavoriteToolbarPlacement.trailing) {
                favoriteMoreMenu
            }
        }
    }

    private var favoriteMoreMenu: some View {
        Menu {
            Button {
                onEnterSearchMode()
            } label: {
                Label(L10n.string("common.search"), systemImage: "magnifyingglass")
            }
            Picker(L10n.string("favorites.sort"), selection: $sortOrder) {
                ForEach(LocalFavoriteLibrarySortOrder.allCases) { order in
                    Text(sortTitle(order))
                        .tag(order)
                }
            }
            Toggle(isOn: $sortDescending) {
                Label(L10n.string("favorites.sort.descending"), systemImage: "arrow.down")
            }
            Picker(L10n.string("favorites.layout"), selection: $layoutMode) {
                ForEach(FavoriteLibraryLayoutMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImageName)
                        .tag(mode)
                }
            }
            Toggle(isOn: $showsCategoryCounts) {
                Label(L10n.string("favorites.category.show_counts"), systemImage: "number.circle")
            }
            LocalFavoriteSourceGroupPicker(
                sourceGroupFilter: $sourceGroupFilter,
                availableSourceGroups: availableSourceGroups,
                sourceGroupEntryCounts: sourceGroupEntryCounts,
                showsCounts: showsCategoryCounts,
                sourceGroupLabel: sourceGroupLabel
            )
            LocalFavoriteTagFilterMenu(
                tags: tags,
                selectedTagIDs: $selectedTagIDs,
                onManageTags: {
                    tagSelectionDraft = .filter(selectedTagIDs)
                }
            )
            Button {
                onEnterSelectionMode()
            } label: {
                Label(L10n.string("common.select"), systemImage: "checkmark.circle")
            }
            Button {
                collectionDraft = LocalFavoriteCollectionDraft(mode: .create)
            } label: {
                Label(L10n.string("favorites.create_collection"), systemImage: "folder.badge.plus")
            }
            Button {
                selectsRemoteSyncCategory = true
            } label: {
                Label(L10n.string("favorites.sync.start"), systemImage: "arrow.triangle.2.circlepath")
            }
            if remoteSyncSnapshot != nil {
                Button {
                    remoteSyncProgressRunID = remoteSyncSnapshot?.runID
                } label: {
                    Label(L10n.string("favorites.sync.progress.open"), systemImage: "list.bullet.rectangle")
                }
            }
            Button {
                Task { _ = await onStartFavoriteUpdateCheck() }
            } label: {
                Label(L10n.string("favorites.updates.check"), systemImage: "arrow.clockwise.circle")
            }
            if favoriteUpdateSnapshot != nil {
                Button {
                    showsFavoriteUpdateEvents = true
                } label: {
                    Label(L10n.string("favorites.updates.events"), systemImage: "bell.badge")
                }
                Button {
                    showsFavoriteUpdateFilters = true
                } label: {
                    Label(L10n.string("favorites.updates.filters"), systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            Button {
                Task { await onRefresh() }
            } label: {
                Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(L10n.string("common.more"))
    }

    @ViewBuilder
    private var content: some View {
        switch layoutMode {
        case .rowCard:
            LocalFavoriteListContent(
                categories: categories,
                collections: visibleCollections,
                cards: cards,
                categoryEntryCounts: categoryEntryCounts,
                collectionEntryCounts: collectionEntryCounts,
                showsCategoryCounts: showsCategoryBadges,
                selectedCollection: selectedCollection,
                selectionState: selectionState,
                sourceGroupFilter: sourceGroupFilter,
                selectedTagIDs: selectedTagIDs,
                tags: tags,
                sourceGroupLabel: sourceGroupLabel,
                onClearSourceGroupFilter: { sourceGroupFilter = .all },
                onClearTagFilter: { selectedTagIDs.removeAll() },
                selectedCategoryID: $selectedCategoryID,
                onCreateCategory: { categoryNameDraft = LocalFavoriteCategoryNameDraft(mode: .create) },
                onManageCategories: { managesCategories = true },
                onOpenCollection: onOpenCollection,
                onCloseCollection: onCloseCollection,
                onEditCollection: { collection in collectionDraft = LocalFavoriteCollectionDraft(collection: collection) },
                onDissolveCollection: { collection in pendingDissolveCollection = collection },
                onMoveCollection: onMoveCollection,
                onMoveCollectionToCategory: onMoveCollectionToCategory,
                onToggleFavoriteSelection: onToggleFavoriteSelection,
                onToggleCollectionSelection: onToggleCollectionSelection,
                onEditFavoriteTags: { item in
                    tagSelectionDraft = .favorite(item.id, initialTagIDs: Set(item.tagIDs))
                },
                showsCover: true,
                onOpen: onOpen,
                onDelete: { item in pendingDeleteItem = item }
            )
        case .rowCardText:
            LocalFavoriteListContent(
                categories: categories,
                collections: visibleCollections,
                cards: cards,
                categoryEntryCounts: categoryEntryCounts,
                collectionEntryCounts: collectionEntryCounts,
                showsCategoryCounts: showsCategoryBadges,
                selectedCollection: selectedCollection,
                selectionState: selectionState,
                sourceGroupFilter: sourceGroupFilter,
                selectedTagIDs: selectedTagIDs,
                tags: tags,
                sourceGroupLabel: sourceGroupLabel,
                onClearSourceGroupFilter: { sourceGroupFilter = .all },
                onClearTagFilter: { selectedTagIDs.removeAll() },
                selectedCategoryID: $selectedCategoryID,
                onCreateCategory: { categoryNameDraft = LocalFavoriteCategoryNameDraft(mode: .create) },
                onManageCategories: { managesCategories = true },
                onOpenCollection: onOpenCollection,
                onCloseCollection: onCloseCollection,
                onEditCollection: { collection in collectionDraft = LocalFavoriteCollectionDraft(collection: collection) },
                onDissolveCollection: { collection in pendingDissolveCollection = collection },
                onMoveCollection: onMoveCollection,
                onMoveCollectionToCategory: onMoveCollectionToCategory,
                onToggleFavoriteSelection: onToggleFavoriteSelection,
                onToggleCollectionSelection: onToggleCollectionSelection,
                onEditFavoriteTags: { item in
                    tagSelectionDraft = .favorite(item.id, initialTagIDs: Set(item.tagIDs))
                },
                showsCover: false,
                onOpen: onOpen,
                onDelete: { item in pendingDeleteItem = item }
            )
        case .fixedGrid:
            LocalFavoriteGridContent(
                categories: categories,
                collections: visibleCollections,
                cards: cards,
                categoryEntryCounts: categoryEntryCounts,
                collectionEntryCounts: collectionEntryCounts,
                showsCategoryCounts: showsCategoryBadges,
                selectedCollection: selectedCollection,
                selectionState: selectionState,
                sourceGroupFilter: sourceGroupFilter,
                selectedTagIDs: selectedTagIDs,
                tags: tags,
                sourceGroupLabel: sourceGroupLabel,
                onClearSourceGroupFilter: { sourceGroupFilter = .all },
                onClearTagFilter: { selectedTagIDs.removeAll() },
                selectedCategoryID: $selectedCategoryID,
                onCreateCategory: { categoryNameDraft = LocalFavoriteCategoryNameDraft(mode: .create) },
                onManageCategories: { managesCategories = true },
                onOpenCollection: onOpenCollection,
                onCloseCollection: onCloseCollection,
                onEditCollection: { collection in collectionDraft = LocalFavoriteCollectionDraft(collection: collection) },
                onDissolveCollection: { collection in pendingDissolveCollection = collection },
                onMoveCollection: onMoveCollection,
                onMoveCollectionToCategory: onMoveCollectionToCategory,
                onToggleFavoriteSelection: onToggleFavoriteSelection,
                onToggleCollectionSelection: onToggleCollectionSelection,
                onEditFavoriteTags: { item in
                    tagSelectionDraft = .favorite(item.id, initialTagIDs: Set(item.tagIDs))
                },
                isStaggered: false,
                onOpen: onOpen,
                onDelete: { item in pendingDeleteItem = item }
            )
        case .staggered:
            LocalFavoriteGridContent(
                categories: categories,
                collections: visibleCollections,
                cards: cards,
                categoryEntryCounts: categoryEntryCounts,
                collectionEntryCounts: collectionEntryCounts,
                showsCategoryCounts: showsCategoryBadges,
                selectedCollection: selectedCollection,
                selectionState: selectionState,
                sourceGroupFilter: sourceGroupFilter,
                selectedTagIDs: selectedTagIDs,
                tags: tags,
                sourceGroupLabel: sourceGroupLabel,
                onClearSourceGroupFilter: { sourceGroupFilter = .all },
                onClearTagFilter: { selectedTagIDs.removeAll() },
                selectedCategoryID: $selectedCategoryID,
                onCreateCategory: { categoryNameDraft = LocalFavoriteCategoryNameDraft(mode: .create) },
                onManageCategories: { managesCategories = true },
                onOpenCollection: onOpenCollection,
                onCloseCollection: onCloseCollection,
                onEditCollection: { collection in collectionDraft = LocalFavoriteCollectionDraft(collection: collection) },
                onDissolveCollection: { collection in pendingDissolveCollection = collection },
                onMoveCollection: onMoveCollection,
                onMoveCollectionToCategory: onMoveCollectionToCategory,
                onToggleFavoriteSelection: onToggleFavoriteSelection,
                onToggleCollectionSelection: onToggleCollectionSelection,
                onEditFavoriteTags: { item in
                    tagSelectionDraft = .favorite(item.id, initialTagIDs: Set(item.tagIDs))
                },
                isStaggered: true,
                onOpen: onOpen,
                onDelete: { item in pendingDeleteItem = item }
            )
        }
    }

    private var visibleCollections: [LocalFavoriteCollection] {
        let trimmedSearch = submittedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let nonSearchFiltersAreActive = sourceGroupFilter != .all || !selectedTagIDs.isEmpty
        let filtersAreActive = nonSearchFiltersAreActive || !trimmedSearch.isEmpty
        return collections
            .filter { collection in
                guard collection.categoryID == selectedCategoryID else { return false }
                guard filtersAreActive else { return true }
                let hasMatchingFilteredCard = cards.contains { card in
                    card.item.locations.contains(.collection(categoryID: collection.categoryID, collectionID: collection.id))
                }
                if !trimmedSearch.isEmpty,
                   collection.name.localizedCaseInsensitiveContains(trimmedSearch) {
                    return !nonSearchFiltersAreActive || hasMatchingFilteredCard
                }
                return hasMatchingFilteredCard
            }
            .sorted { lhs, rhs in
                if lhs.manualOrder != rhs.manualOrder {
                    return lhs.manualOrder < rhs.manualOrder
                }
                return lhs.id < rhs.id
            }
    }

    private var initialTagIDsForSelection: Set<String> {
        let selectedItems = cards
            .map(\.item)
            .filter { selectionState.selectedFavoriteIDs.contains($0.id) }
        guard let first = selectedItems.first else { return [] }
        return selectedItems.dropFirst().reduce(Set(first.tagIDs)) { partialResult, item in
            partialResult.intersection(Set(item.tagIDs))
        }
    }

    private var hasSubmittedSearch: Bool {
        !submittedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsCategoryBadges: Bool {
        showsCategoryCounts || hasSubmittedSearch
    }

    private var showsTopStatusCards: Bool {
        if let remoteSyncSnapshot, !remoteSyncSnapshot.isHiddenFromFavoritePage {
            return true
        }
        return favoriteUpdateSnapshot != nil
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private var remoteSyncProgressBinding: Binding<Bool> {
        Binding(
            get: { remoteSyncProgressRunID != nil },
            set: { isPresented in
                if !isPresented {
                    remoteSyncProgressRunID = nil
                }
            }
        )
    }

    private var dissolveCollectionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDissolveCollection != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDissolveCollection = nil
                }
            }
        )
    }

    private var deleteItemAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteItem != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteItem = nil
                }
            }
        )
    }

    private var selectedFavoritesCanRemoveCurrentLocation: Bool {
        guard selectionState.selectedCollectionCount == 0 else { return false }
        return cards.contains { card in
            selectionState.selectedFavoriteIDs.contains(card.id) && card.item.locations.count > 1
        }
    }

    private var deleteSelectionMessage: String {
        if selectionState.selectedCollectionCount > 0 {
            return L10n.string("favorites.bulk_delete_mixed_message")
        }
        if selectedFavoritesCanRemoveCurrentLocation {
            return L10n.string("favorites.bulk_delete_scope_message")
        }
        return L10n.string("favorites.bulk_delete_favorites_message")
    }

    private func deleteMessage(for item: FavoriteItem) -> String {
        if item.locations.count > 1 {
            return L10n.string("favorites.delete_favorite_scope_message", item.resolvedDisplayTitle)
        }
        return L10n.string("favorites.delete_favorite_message", item.resolvedDisplayTitle)
    }

    private func sortTitle(_ sortOrder: LocalFavoriteLibrarySortOrder) -> String {
        sortOrder.title
    }
}

private struct LocalFavoriteListContent: View {
    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let cards: [FavoriteCardProjection]
    let categoryEntryCounts: [String: Int]
    let collectionEntryCounts: [String: Int]
    let showsCategoryCounts: Bool
    let selectedCollection: LocalFavoriteCollection?
    let selectionState: LocalFavoriteSelectionState
    let sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    let selectedTagIDs: Set<String>
    let tags: [FavoriteTag]
    let sourceGroupLabel: (FavoriteSourceGroup) -> String
    let onClearSourceGroupFilter: () -> Void
    let onClearTagFilter: () -> Void
    @Binding var selectedCategoryID: String
    let onCreateCategory: () -> Void
    let onManageCategories: () -> Void
    let onOpenCollection: (String) -> Void
    let onCloseCollection: () -> Void
    let onEditCollection: (LocalFavoriteCollection) -> Void
    let onDissolveCollection: (LocalFavoriteCollection) -> Void
    let onMoveCollection: (String, CategoryMoveDirection) async -> Void
    let onMoveCollectionToCategory: (String, String) async -> Void
    let onToggleFavoriteSelection: (String) -> Void
    let onToggleCollectionSelection: (String) -> Void
    let onEditFavoriteTags: (FavoriteItem) -> Void
    let showsCover: Bool
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem) async -> Void

    var body: some View {
        List {
            if let selectedCollection {
                LocalFavoriteCollectionScopeSection(
                    collection: selectedCollection,
                    itemCount: collectionEntryCounts[selectedCollection.id] ?? cards.count,
                    categories: categories,
                    onBack: onCloseCollection,
                    onEdit: { onEditCollection(selectedCollection) },
                    onDissolve: { onDissolveCollection(selectedCollection) },
                    onMoveToCategory: { categoryID in
                        await onMoveCollectionToCategory(selectedCollection.id, categoryID)
                    }
                )
            } else {
                LocalFavoriteCategorySection(
                    categories: categories,
                    categoryEntryCounts: categoryEntryCounts,
                    showsCategoryCounts: showsCategoryCounts,
                    selectedCategoryID: $selectedCategoryID,
                    onCreateCategory: onCreateCategory,
                    onManageCategories: onManageCategories
                )
                LocalFavoriteActiveFilterSection(
                    sourceGroupFilter: sourceGroupFilter,
                    selectedTagIDs: selectedTagIDs,
                    tags: tags,
                    sourceGroupLabel: sourceGroupLabel,
                    onClearSourceGroupFilter: onClearSourceGroupFilter,
                    onClearTagFilter: onClearTagFilter
                )
                LocalFavoriteCollectionSection(
                    categories: categories,
                    collections: collections,
                    cards: cards,
                    collectionEntryCounts: collectionEntryCounts,
                    selectionState: selectionState,
                    onOpenCollection: onOpenCollection,
                    onEditCollection: onEditCollection,
                    onDissolveCollection: onDissolveCollection,
                    onMoveCollection: onMoveCollection,
                    onMoveCollectionToCategory: onMoveCollectionToCategory,
                    onToggleCollectionSelection: onToggleCollectionSelection
                )
            }
            LocalFavoriteItemSection(
                cards: cards,
                showsCover: showsCover,
                showsCount: showsCategoryCounts,
                selectionState: selectionState,
                onToggleSelection: onToggleFavoriteSelection,
                onEditTags: onEditFavoriteTags,
                onOpen: onOpen,
                onDelete: onDelete
            )
        }
        .modifier(LocalFavoriteListStyleModifier())
    }
}

private struct LocalFavoriteSourceGroupPicker: View {
    @Binding var sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    let availableSourceGroups: [FavoriteSourceGroup]
    let sourceGroupEntryCounts: [FavoriteSourceGroup: Int]
    let showsCounts: Bool
    let sourceGroupLabel: (FavoriteSourceGroup) -> String

    var body: some View {
        Picker(L10n.string("favorites.source_group"), selection: $sourceGroupFilter) {
            Text(L10n.string("favorites.filter.all"))
                .tag(LocalFavoriteLibrarySourceGroupFilter.all)
            ForEach(availableSourceGroups, id: \.self) { sourceGroup in
                Text(sourceGroupTitle(sourceGroup))
                    .tag(LocalFavoriteLibrarySourceGroupFilter.group(sourceGroup))
            }
        }
    }

    private func sourceGroupTitle(_ sourceGroup: FavoriteSourceGroup) -> String {
        guard showsCounts else { return sourceGroupLabel(sourceGroup) }
        return "\(sourceGroupLabel(sourceGroup)) (\(sourceGroupEntryCounts[sourceGroup] ?? 0))"
    }
}

private struct LocalFavoriteActiveFilterSection: View {
    let sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    let selectedTagIDs: Set<String>
    let tags: [FavoriteTag]
    let sourceGroupLabel: (FavoriteSourceGroup) -> String
    let onClearSourceGroupFilter: () -> Void
    let onClearTagFilter: () -> Void

    var body: some View {
        if hasActiveFilters {
            Section {
                LocalFavoriteActiveFilterStrip(
                    sourceGroupFilter: sourceGroupFilter,
                    selectedTagIDs: selectedTagIDs,
                    tags: tags,
                    sourceGroupLabel: sourceGroupLabel,
                    onClearSourceGroupFilter: onClearSourceGroupFilter,
                    onClearTagFilter: onClearTagFilter
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private var hasActiveFilters: Bool {
        if case .group = sourceGroupFilter { return true }
        return !selectedTagIDs.isEmpty
    }
}

private struct LocalFavoriteActiveFilterStrip: View {
    let sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    let selectedTagIDs: Set<String>
    let tags: [FavoriteTag]
    let sourceGroupLabel: (FavoriteSourceGroup) -> String
    let onClearSourceGroupFilter: () -> Void
    let onClearTagFilter: () -> Void

    var body: some View {
        if hasActiveFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if case let .group(sourceGroup) = sourceGroupFilter {
                        LocalFavoriteFilterChip(
                            title: sourceGroupLabel(sourceGroup),
                            systemImage: "line.3.horizontal.decrease.circle",
                            onClear: onClearSourceGroupFilter
                        )
                    }
                    let selectedTags = tags.filter { selectedTagIDs.contains($0.id) }
                    ForEach(selectedTags) { tag in
                        LocalFavoriteFilterChip(
                            title: tag.name,
                            systemImage: "tag",
                            tint: tag.color.swiftUIColor,
                            onClear: onClearTagFilter
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    private var hasActiveFilters: Bool {
        if case .group = sourceGroupFilter { return true }
        return !selectedTagIDs.isEmpty
    }
}

private struct LocalFavoriteFilterChip: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    let onClear: () -> Void

    var body: some View {
        Button(action: onClear) {
            Label {
                HStack(spacing: 4) {
                    Text(title)
                        .lineLimit(1)
                    Image(systemName: "xmark.circle.fill")
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LocalFavoriteGridContent: View {
    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let cards: [FavoriteCardProjection]
    let categoryEntryCounts: [String: Int]
    let collectionEntryCounts: [String: Int]
    let showsCategoryCounts: Bool
    let selectedCollection: LocalFavoriteCollection?
    let selectionState: LocalFavoriteSelectionState
    let sourceGroupFilter: LocalFavoriteLibrarySourceGroupFilter
    let selectedTagIDs: Set<String>
    let tags: [FavoriteTag]
    let sourceGroupLabel: (FavoriteSourceGroup) -> String
    let onClearSourceGroupFilter: () -> Void
    let onClearTagFilter: () -> Void
    @Binding var selectedCategoryID: String
    let onCreateCategory: () -> Void
    let onManageCategories: () -> Void
    let onOpenCollection: (String) -> Void
    let onCloseCollection: () -> Void
    let onEditCollection: (LocalFavoriteCollection) -> Void
    let onDissolveCollection: (LocalFavoriteCollection) -> Void
    let onMoveCollection: (String, CategoryMoveDirection) async -> Void
    let onMoveCollectionToCategory: (String, String) async -> Void
    let onToggleFavoriteSelection: (String) -> Void
    let onToggleCollectionSelection: (String) -> Void
    let onEditFavoriteTags: (FavoriteItem) -> Void
    let isStaggered: Bool
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem) async -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 158), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let selectedCollection {
                    LocalFavoriteCollectionScopeHeader(
                        collection: selectedCollection,
                        itemCount: collectionEntryCounts[selectedCollection.id] ?? cards.count,
                        categories: categories,
                        onBack: onCloseCollection,
                        onEdit: { onEditCollection(selectedCollection) },
                        onDissolve: { onDissolveCollection(selectedCollection) },
                        onMoveToCategory: { categoryID in
                            await onMoveCollectionToCategory(selectedCollection.id, categoryID)
                        }
                    )
                    .padding(.horizontal)
                } else {
                    LocalFavoriteCategoryStrip(
                        categories: categories,
                        categoryEntryCounts: categoryEntryCounts,
                        showsCategoryCounts: showsCategoryCounts,
                        selectedCategoryID: $selectedCategoryID,
                        onCreateCategory: onCreateCategory,
                        onManageCategories: onManageCategories
                    )
                    LocalFavoriteActiveFilterStrip(
                        sourceGroupFilter: sourceGroupFilter,
                        selectedTagIDs: selectedTagIDs,
                        tags: tags,
                        sourceGroupLabel: sourceGroupLabel,
                        onClearSourceGroupFilter: onClearSourceGroupFilter,
                        onClearTagFilter: onClearTagFilter
                    )
                    .padding(.horizontal)
                    LocalFavoriteCollectionGridSection(
                        categories: categories,
                        collections: collections,
                        cards: cards,
                        collectionEntryCounts: collectionEntryCounts,
                        selectionState: selectionState,
                        onOpenCollection: onOpenCollection,
                        onEditCollection: onEditCollection,
                        onDissolveCollection: onDissolveCollection,
                        onMoveCollection: onMoveCollection,
                        onMoveCollectionToCategory: onMoveCollectionToCategory,
                        onToggleCollectionSelection: onToggleCollectionSelection
                    )
                }
                if showsCategoryCounts {
                    Text(L10n.string("favorites.items_count", cards.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                if isStaggered {
                    LocalFavoriteStaggeredCards(
                        cards: cards,
                        selectionState: selectionState,
                        onToggleSelection: onToggleFavoriteSelection,
                        onEditTags: onEditFavoriteTags,
                        onOpen: onOpen,
                        onDelete: onDelete
                    )
                    .padding(.horizontal)
                } else {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                        ForEach(cards) { card in
                            LocalFavoriteGridCard(
                                card: card,
                                fixedHeight: 236,
                                selectionState: selectionState,
                                onToggleSelection: onToggleFavoriteSelection,
                                onEditTags: onEditFavoriteTags,
                                onOpen: onOpen,
                                onDelete: onDelete
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 12)
        }
    }
}

private struct LocalFavoriteCategoryStrip: View {
    let categories: [FavoriteCategory]
    let categoryEntryCounts: [String: Int]
    let showsCategoryCounts: Bool
    @Binding var selectedCategoryID: String
    let onCreateCategory: () -> Void
    let onManageCategories: () -> Void

    var body: some View {
        LocalFavoriteCategoryTabBar(
            categories: categories,
            categoryEntryCounts: categoryEntryCounts,
            showsCategoryCounts: showsCategoryCounts,
            selectedCategoryID: $selectedCategoryID,
            onCreateCategory: onCreateCategory,
            onManageCategories: onManageCategories
        )
    }
}

private struct LocalFavoriteCollectionGridSection: View {
    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let cards: [FavoriteCardProjection]
    let collectionEntryCounts: [String: Int]
    let selectionState: LocalFavoriteSelectionState
    let onOpenCollection: (String) -> Void
    let onEditCollection: (LocalFavoriteCollection) -> Void
    let onDissolveCollection: (LocalFavoriteCollection) -> Void
    let onMoveCollection: (String, CategoryMoveDirection) async -> Void
    let onMoveCollectionToCategory: (String, String) async -> Void
    let onToggleCollectionSelection: (String) -> Void

    var body: some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("favorites.collections"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(collections) { collection in
                            LocalFavoriteCollectionCard(
                                collection: collection,
                                itemCount: collectionEntryCounts[collection.id] ?? 0,
                                categories: categories,
                                isSelectionMode: selectionState.isActive,
                                isSelected: selectionState.selectedCollectionIDs.contains(collection.id),
                                previewCoverURLs: previewCoverURLs(for: collection),
                                onOpen: { onOpenCollection(collection.id) },
                                onToggleSelection: { onToggleCollectionSelection(collection.id) },
                                onEdit: { onEditCollection(collection) },
                                onDissolve: { onDissolveCollection(collection) },
                                onMove: { direction in
                                    await onMoveCollection(collection.id, direction)
                                },
                                onMoveToCategory: { categoryID in
                                    await onMoveCollectionToCategory(collection.id, categoryID)
                                }
                            )
                            .frame(width: 190, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func previewCoverURLs(for collection: LocalFavoriteCollection) -> [URL] {
        cards
            .filter { card in
                card.item.locations.contains(.collection(categoryID: collection.categoryID, collectionID: collection.id))
            }
            .compactMap(\.coverURL)
            .prefix(4)
            .map { $0 }
    }
}

private struct LocalFavoriteListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
    }
}

private struct LocalFavoriteSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 28)
            .accessibilityLabel(isSelected ? L10n.string("common.current") : L10n.string("common.select"))
    }
}

private struct LocalFavoriteSelectionActionBar: View {
    let selectionState: LocalFavoriteSelectionState
    let onSelectAll: () -> Void
    let onInvert: () -> Void
    let onMove: () -> Void
    let onCreateCollection: () -> Void
    let onEditTags: () -> Void
    let onEditCollection: (LocalFavoriteCollection) -> Void
    let onDissolveCollections: () -> Void
    let onDelete: () -> Void
    let onClear: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.string("favorites.selected_count", selectionState.selectedEntryCount))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(L10n.string("common.done"), action: onDone)
                    .buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button(action: onSelectAll) {
                        Label(L10n.string("common.select_all"), systemImage: "checkmark.circle")
                    }
                    Button(action: onInvert) {
                        Label(L10n.string("common.invert_selection"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(action: onMove) {
                        Label(L10n.string("common.move"), systemImage: "folder")
                    }
                    .disabled(selectionState.selectedEntryCount == 0)
                    Button(action: onCreateCollection) {
                        Label(L10n.string("favorites.create_collection"), systemImage: "folder.badge.plus")
                    }
                    .disabled(!selectionState.canCreateCollection)
                    Button(action: onEditTags) {
                        Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                    }
                    .disabled(selectionState.selectedFavoriteCount == 0)
                    if let collection = selectionState.editableCollection, selectionState.selectedFavoriteCount == 0 {
                        Button {
                            onEditCollection(collection)
                        } label: {
                            Label(L10n.string("common.edit"), systemImage: "pencil")
                        }
                    }
                    Button(action: onDissolveCollections) {
                        Label(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus")
                    }
                    .disabled(selectionState.selectedCollectionCount == 0)
                    Button(role: .destructive, action: onDelete) {
                        Label(L10n.string("common.delete"), systemImage: "trash")
                    }
                    .disabled(selectionState.selectedEntryCount == 0)
                    Button(action: onClear) {
                        Label(L10n.string("common.clear"), systemImage: "xmark.circle")
                    }
                    .disabled(selectionState.selectedEntryCount == 0)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

private struct LocalFavoriteSelectionMoveSheet: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let selectedFavoriteCount: Int
    let selectedCollectionCount: Int
    let selectedCategoryID: String
    let selectedCollectionID: String?
    let onMoveToCategory: (String) async -> Void
    let onMoveToCollection: (String) async -> Void
    let onAddToCategory: (String) async -> Void
    let onAddToCollection: (String) async -> Void
    let onRemoveFromCurrentLocation: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.string("favorites.location.move_to_category")) {
                    ForEach(sortedCategories) { category in
                        Button {
                            Task {
                                await onMoveToCategory(category.id)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(category.displayName)
                                Spacer()
                                if category.id == selectedCategoryID && selectedCollectionID == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                if selectedFavoriteCount > 0 && selectedCollectionCount == 0 {
                    Section(L10n.string("favorites.location.move_to_collection")) {
                        ForEach(sortedCollections) { collection in
                            Button {
                                Task {
                                    await onMoveToCollection(collection.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    LocalFavoriteCollectionCoverPreview(
                                        color: collection.color.swiftUIColor,
                                        coverURLs: []
                                    )
                                    .frame(width: 32, height: 32)
                                    Text(collection.name)
                                    Spacer()
                                    if collection.id == selectedCollectionID {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if selectedFavoriteCount > 0 {
                    Section(L10n.string("favorites.location.add_to_category")) {
                        ForEach(sortedCategories) { category in
                            Button {
                                Task {
                                    await onAddToCategory(category.id)
                                    dismiss()
                                }
                            } label: {
                                Text(category.displayName)
                            }
                        }
                    }
                    Section(L10n.string("favorites.location.add_to_collection")) {
                        ForEach(sortedCollections) { collection in
                            Button {
                                Task {
                                    await onAddToCollection(collection.id)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    LocalFavoriteCollectionCoverPreview(
                                        color: collection.color.swiftUIColor,
                                        coverURLs: []
                                    )
                                    .frame(width: 32, height: 32)
                                    Text(collection.name)
                                }
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await onRemoveFromCurrentLocation()
                                dismiss()
                            }
                        } label: {
                            Label(L10n.string("favorites.location.remove_current"), systemImage: "minus.circle")
                        }
                    }
                }
            }
            .navigationTitle(L10n.string("favorites.location.manage"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var sortedCategories: [FavoriteCategory] {
        categories.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private var sortedCollections: [LocalFavoriteCollection] {
        collections.sorted { lhs, rhs in
            if lhs.categoryID != rhs.categoryID {
                return lhs.categoryID < rhs.categoryID
            }
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }
}

private struct LocalFavoriteTagFilterMenu: View {
    let tags: [FavoriteTag]
    @Binding var selectedTagIDs: Set<String>
    let onManageTags: () -> Void

    var body: some View {
        Menu {
            if tags.isEmpty {
                Button(action: onManageTags) {
                    Label(L10n.string("favorites.new_tag"), systemImage: "plus")
                }
            } else {
                ForEach(tags) { tag in
                    Button {
                        if selectedTagIDs.contains(tag.id) {
                            selectedTagIDs.remove(tag.id)
                        } else {
                            selectedTagIDs.insert(tag.id)
                        }
                    } label: {
                        if selectedTagIDs.contains(tag.id) {
                            Label(tag.name, systemImage: "checkmark")
                        } else {
                            Text(tag.name)
                        }
                    }
                }
                Button {
                    selectedTagIDs.removeAll()
                } label: {
                    Label(L10n.string("favorites.filter.clear_tags"), systemImage: "xmark.circle")
                }
                .disabled(selectedTagIDs.isEmpty)
                Button(action: onManageTags) {
                    Label(L10n.string("favorites.edit_tags"), systemImage: "tag")
                }
            }
        } label: {
            Label(L10n.string("favorites.filter.tags_count", selectedTagIDs.count), systemImage: "tag")
        }
    }
}

private struct LocalFavoriteTagChipRow: View {
    let tags: [FavoriteTag]

    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags.prefix(4)) { tag in
                        Text(tag.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tag.color.iconTextColor)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tag.color.swiftUIColor, in: Capsule())
                    }
                }
            }
            .scrollDisabled(true)
        }
    }
}

private struct LocalFavoriteTagSelectionDraft: Identifiable {
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

private struct LocalFavoriteTagSelectionSheet: View {
    let tags: [FavoriteTag]
    let draft: LocalFavoriteTagSelectionDraft
    let onCancel: () -> Void
    let onConfirm: (Set<String>) async -> Void
    let onCreateTag: (String, FavoriteTagColor) async -> FavoriteTag?
    let onUpdateTag: (String, String, FavoriteTagColor) async -> Void
    let onDeleteTag: (String) async -> Void

    @State private var selectedTagIDs: Set<String>
    @State private var editorDraft: LocalFavoriteTagEditorDraft?
    @State private var pendingDeleteTag: FavoriteTag?

    init(
        tags: [FavoriteTag],
        draft: LocalFavoriteTagSelectionDraft,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (Set<String>) async -> Void,
        onCreateTag: @escaping (String, FavoriteTagColor) async -> FavoriteTag?,
        onUpdateTag: @escaping (String, String, FavoriteTagColor) async -> Void,
        onDeleteTag: @escaping (String) async -> Void
    ) {
        self.tags = tags
        self.draft = draft
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.onCreateTag = onCreateTag
        self.onUpdateTag = onUpdateTag
        self.onDeleteTag = onDeleteTag
        _selectedTagIDs = State(initialValue: draft.initialTagIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                if tags.isEmpty {
                    ContentUnavailableView(L10n.string("favorites.tags.empty"), systemImage: "tag")
                }
                ForEach(tags) { tag in
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
                    Button(L10n.string("common.cancel"), action: onCancel)
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
                        Task { await onConfirm(selectedTagIDs) }
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
                            await onUpdateTag(tagID, name, color)
                        } else if let tag = await onCreateTag(name, color) {
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
                            await onDeleteTag(pendingDeleteTag.id)
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

private struct LocalFavoriteTagEditorDraft: Identifiable {
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

private struct LocalFavoriteTagEditorSheet: View {
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

private enum LocalFavoriteToolbarPlacement {
    static var trailing: ToolbarItemPlacement {
        .topBarTrailing
    }
}

private struct LocalFavoriteCategorySection: View {
    let categories: [FavoriteCategory]
    let categoryEntryCounts: [String: Int]
    let showsCategoryCounts: Bool
    @Binding var selectedCategoryID: String
    let onCreateCategory: () -> Void
    let onManageCategories: () -> Void

    var body: some View {
        Section {
            LocalFavoriteCategoryTabBar(
                categories: categories,
                categoryEntryCounts: categoryEntryCounts,
                showsCategoryCounts: showsCategoryCounts,
                selectedCategoryID: $selectedCategoryID,
                onCreateCategory: onCreateCategory,
                onManageCategories: onManageCategories
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}

private struct LocalFavoriteCategoryTabBar: View {
    let categories: [FavoriteCategory]
    let categoryEntryCounts: [String: Int]
    let showsCategoryCounts: Bool
    @Binding var selectedCategoryID: String
    let onCreateCategory: () -> Void
    let onManageCategories: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedCategories) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        HStack(spacing: 6) {
                            Text(category.displayName)
                                .lineLimit(1)
                            if showsCategoryCounts {
                                Text("\(categoryEntryCounts[category.id] ?? 0)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(category.id == selectedCategoryID ? .white.opacity(0.78) : .secondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            category.id == selectedCategoryID ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .foregroundStyle(category.id == selectedCategoryID ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onCreateCategory) {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.category.create"))
                Button(action: onManageCategories) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 34, height: 34)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.category.manage"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var sortedCategories: [FavoriteCategory] {
        categories.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }
}

private struct LocalFavoriteCategoryNameDraft: Identifiable {
    enum Mode {
        case create
        case rename(String)
    }

    let id = UUID()
    var mode: Mode
    var initialName: String = ""
}

private struct LocalFavoriteCategoryNameSheet: View {
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

private struct LocalFavoriteCollectionDraft: Identifiable {
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

private struct LocalFavoriteCollectionEditorSheet: View {
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
                        Label(color.localizedTitle, systemImage: "circle.fill")
                            .foregroundStyle(color.swiftUIColor)
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

private struct LocalFavoriteCategoryManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeleteCategory: FavoriteCategory?

    let categories: [FavoriteCategory]
    let categoryEntryCounts: [String: Int]
    let showsCategoryCounts: Bool
    @Binding var selectedCategoryID: String
    let onEdit: (FavoriteCategory) -> Void
    let onDelete: (FavoriteCategory) async -> Void
    let onMove: (FavoriteCategory, CategoryMoveDirection) async -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedCategories) { category in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.displayName)
                            if showsCategoryCounts {
                                Text(L10n.string("favorites.items_count", categoryEntryCounts[category.id] ?? 0))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if category.id == selectedCategoryID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        if !category.isDefault {
                            Menu {
                                Button {
                                    selectedCategoryID = category.id
                                } label: {
                                    Label(L10n.string("favorites.category.select"), systemImage: "checkmark.circle")
                                }
                                Button {
                                    onEdit(category)
                                } label: {
                                    Label(L10n.string("favorites.category.rename"), systemImage: "pencil")
                                }
                                Button {
                                    Task { await onMove(category, .up) }
                                } label: {
                                    Label(L10n.string("favorites.category.move_up"), systemImage: "arrow.up")
                                }
                                .disabled(!canMove(category, direction: .up))
                                Button {
                                    Task { await onMove(category, .down) }
                                } label: {
                                    Label(L10n.string("favorites.category.move_down"), systemImage: "arrow.down")
                                }
                                .disabled(!canMove(category, direction: .down))
                                Button(role: .destructive) {
                                    pendingDeleteCategory = category
                                } label: {
                                    Label(L10n.string("favorites.category.delete"), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel(L10n.string("common.more"))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCategoryID = category.id
                    }
                }
            }
            .navigationTitle(L10n.string("favorites.category.manage"))
            .alert(
                L10n.string("favorites.category.delete"),
                isPresented: deleteCategoryAlertBinding
            ) {
                Button(L10n.string("common.cancel"), role: .cancel) {
                    pendingDeleteCategory = nil
                }
                Button(L10n.string("common.delete"), role: .destructive) {
                    if let pendingDeleteCategory {
                        Task {
                            await onDelete(pendingDeleteCategory)
                            self.pendingDeleteCategory = nil
                        }
                    }
                }
            } message: {
                if let pendingDeleteCategory {
                    Text(
                        L10n.string(
                            "favorites.category.delete_message",
                            pendingDeleteCategory.displayName,
                            categoryEntryCounts[pendingDeleteCategory.id] ?? 0
                        )
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("common.done")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var deleteCategoryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCategory != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteCategory = nil
                }
            }
        )
    }

    private var sortedCategories: [FavoriteCategory] {
        categories.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }

    private var movableCategories: [FavoriteCategory] {
        sortedCategories.filter { !$0.isDefault }
    }

    private func canMove(_ category: FavoriteCategory, direction: CategoryMoveDirection) -> Bool {
        guard let index = movableCategories.firstIndex(where: { $0.id == category.id }) else { return false }
        switch direction {
        case .up:
            return index > 0
        case .down:
            return index < movableCategories.count - 1
        }
    }
}

private struct LocalFavoriteCollectionSection: View {
    let categories: [FavoriteCategory]
    let collections: [LocalFavoriteCollection]
    let cards: [FavoriteCardProjection]
    let collectionEntryCounts: [String: Int]
    let selectionState: LocalFavoriteSelectionState
    let onOpenCollection: (String) -> Void
    let onEditCollection: (LocalFavoriteCollection) -> Void
    let onDissolveCollection: (LocalFavoriteCollection) -> Void
    let onMoveCollection: (String, CategoryMoveDirection) async -> Void
    let onMoveCollectionToCategory: (String, String) async -> Void
    let onToggleCollectionSelection: (String) -> Void

    var body: some View {
        if !collections.isEmpty {
            Section {
                ForEach(collections) { collection in
                    LocalFavoriteCollectionRow(
                        collection: collection,
                        itemCount: collectionEntryCounts[collection.id] ?? 0,
                        categories: categories,
                        isSelectionMode: selectionState.isActive,
                        isSelected: selectionState.selectedCollectionIDs.contains(collection.id),
                        previewCoverURLs: previewCoverURLs(for: collection),
                        onOpen: { onOpenCollection(collection.id) },
                        onToggleSelection: { onToggleCollectionSelection(collection.id) },
                        onEdit: { onEditCollection(collection) },
                        onDissolve: { onDissolveCollection(collection) },
                        onMove: { direction in
                            await onMoveCollection(collection.id, direction)
                        },
                        onMoveToCategory: { categoryID in
                            await onMoveCollectionToCategory(collection.id, categoryID)
                        }
                    )
                }
            } header: {
                Text(L10n.string("favorites.collections"))
            }
        }
    }

    private func previewCoverURLs(for collection: LocalFavoriteCollection) -> [URL] {
        cards
            .filter { card in
                card.item.locations.contains(.collection(categoryID: collection.categoryID, collectionID: collection.id))
            }
            .compactMap(\.coverURL)
            .prefix(4)
            .map { $0 }
    }
}

private struct LocalFavoriteCollectionRow: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let isSelectionMode: Bool
    let isSelected: Bool
    let previewCoverURLs: [URL]
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMove: (CategoryMoveDirection) async -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        HStack(spacing: 12) {
            LocalFavoriteCollectionCoverPreview(
                color: swiftUIColor,
                coverURLs: previewCoverURLs
            )
            if isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: isSelected)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.body)
                    .lineLimit(1)
                Text(L10n.string("favorites.collection_summary", itemCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if !isSelectionMode {
                LocalFavoriteCollectionMenu(
                    collection: collection,
                    categories: categories,
                    onEdit: onEdit,
                    onDissolve: onDissolve,
                    onMove: onMove,
                    onMoveToCategory: onMoveToCategory
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onOpen()
            }
        }
    }

    private var swiftUIColor: Color {
        collection.color.swiftUIColor
    }
}

private struct LocalFavoriteCollectionCard: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let isSelectionMode: Bool
    let isSelected: Bool
    let previewCoverURLs: [URL]
    let onOpen: () -> Void
    let onToggleSelection: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMove: (CategoryMoveDirection) async -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                LocalFavoriteCollectionCoverPreview(
                    color: collection.color.swiftUIColor,
                    coverURLs: previewCoverURLs
                )
                if isSelectionMode {
                    LocalFavoriteSelectionIndicator(isSelected: isSelected)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(L10n.string("favorites.collection_summary", itemCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !isSelectionMode {
                    LocalFavoriteCollectionMenu(
                        collection: collection,
                        categories: categories,
                        onEdit: onEdit,
                        onDissolve: onDissolve,
                        onMove: onMove,
                        onMoveToCategory: onMoveToCategory
                    )
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onOpen()
            }
        }
    }
}

private struct LocalFavoriteCollectionMenu: View {
    let collection: LocalFavoriteCollection
    let categories: [FavoriteCategory]
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMove: (CategoryMoveDirection) async -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        Menu {
            Button(action: onEdit) {
                Label(L10n.string("common.edit"), systemImage: "pencil")
            }
            Button {
                Task { await onMove(.up) }
            } label: {
                Label(L10n.string("favorites.category.move_up"), systemImage: "arrow.up")
            }
            Button {
                Task { await onMove(.down) }
            } label: {
                Label(L10n.string("favorites.category.move_down"), systemImage: "arrow.down")
            }
            Menu {
                ForEach(sortedCategories) { category in
                    Button {
                        Task { await onMoveToCategory(category.id) }
                    } label: {
                        if category.id == collection.categoryID {
                            Label(category.displayName, systemImage: "checkmark")
                        } else {
                            Text(category.displayName)
                        }
                    }
                    .disabled(category.id == collection.categoryID)
                }
            } label: {
                Label(L10n.string("favorites.category.select"), systemImage: "folder")
            }
            Button(role: .destructive, action: onDissolve) {
                Label(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(L10n.string("common.more"))
    }

    private var sortedCategories: [FavoriteCategory] {
        categories.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }
}

private struct LocalFavoriteCollectionScopeSection: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        Section {
            LocalFavoriteCollectionScopeHeader(
                collection: collection,
                itemCount: itemCount,
                categories: categories,
                onBack: onBack,
                onEdit: onEdit,
                onDissolve: onDissolve,
                onMoveToCategory: onMoveToCategory
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}

private struct LocalFavoriteCollectionScopeHeader: View {
    let collection: LocalFavoriteCollection
    let itemCount: Int
    let categories: [FavoriteCategory]
    let onBack: () -> Void
    let onEdit: () -> Void
    let onDissolve: () -> Void
    let onMoveToCategory: (String) async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("common.back"))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(collection.color.swiftUIColor)
                .frame(width: 10, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(L10n.string("favorites.collection_summary", itemCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button(action: onEdit) {
                    Label(L10n.string("common.edit"), systemImage: "pencil")
                }
                Menu {
                    ForEach(sortedCategories) { category in
                        Button {
                            Task { await onMoveToCategory(category.id) }
                        } label: {
                            if category.id == collection.categoryID {
                                Label(category.displayName, systemImage: "checkmark")
                            } else {
                                Text(category.displayName)
                            }
                        }
                        .disabled(category.id == collection.categoryID)
                    }
                } label: {
                    Label(L10n.string("favorites.category.select"), systemImage: "folder")
                }
                Button(role: .destructive, action: onDissolve) {
                    Label(L10n.string("favorites.dissolve"), systemImage: "folder.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(L10n.string("common.more"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sortedCategories: [FavoriteCategory] {
        categories.sorted { lhs, rhs in
            if lhs.manualOrder != rhs.manualOrder {
                return lhs.manualOrder < rhs.manualOrder
            }
            return lhs.id < rhs.id
        }
    }
}

private extension FavoriteCollectionColor {
    var swiftUIColor: Color {
        switch self {
        case .red:
            .red
        case .orange:
            .orange
        case .yellow:
            .yellow
        case .green:
            .green
        case .blue:
            .blue
        case .purple:
            .purple
        case .pink:
            .pink
        case .gray:
            .gray
        }
    }

    var localizedTitle: String {
        switch self {
        case .red:
            L10n.string("color.red")
        case .orange:
            L10n.string("color.orange")
        case .yellow:
            L10n.string("color.yellow")
        case .green:
            L10n.string("color.green")
        case .blue:
            L10n.string("color.blue")
        case .purple:
            L10n.string("color.purple")
        case .pink:
            L10n.string("color.pink")
        case .gray:
            L10n.string("color.gray")
        }
    }
}

private extension FavoriteTagColor {
    var localizedTitle: String {
        switch self {
        case .red:
            L10n.string("color.red")
        case .orange:
            L10n.string("color.orange")
        case .yellow:
            L10n.string("color.yellow")
        case .green:
            L10n.string("color.green")
        case .blue:
            L10n.string("color.blue")
        case .purple:
            L10n.string("color.purple")
        case .pink:
            L10n.string("color.pink")
        case .gray:
            L10n.string("color.gray")
        }
    }
}

private struct LocalFavoriteCollectionCoverPreview: View {
    let color: Color
    let coverURLs: [URL]

    private let cellSize: CGFloat = 23

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(cellSize), spacing: 2),
                GridItem(.fixed(cellSize), spacing: 2)
            ],
            spacing: 2
        ) {
            ForEach(0..<4, id: \.self) { index in
                if index < coverURLs.count {
                    LocalFavoriteCoverThumbnail(url: coverURLs[index], fallbackColor: color)
                        .frame(width: cellSize, height: cellSize)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(index == 0 ? 0.8 : 0.18))
                        .frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct LocalFavoriteItemSection: View {
    let cards: [FavoriteCardProjection]
    let showsCover: Bool
    let showsCount: Bool
    let selectionState: LocalFavoriteSelectionState
    let onToggleSelection: (String) -> Void
    let onEditTags: (FavoriteItem) -> Void
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem) async -> Void

    var body: some View {
        Section {
            ForEach(cards) { card in
                LocalFavoriteItemRow(
                    item: card.item,
                    title: card.item.resolvedDisplayTitle,
                    sourceGroupLabel: card.sourceGroupLabel,
                    progressPercent: card.progressPercent,
                    chapterPageProgress: card.chapterPageProgress,
                    recentReadingAt: card.recentReadingAt,
                    lastUpdatedAt: card.lastUpdatedAt,
                    coverURL: card.coverURL,
                    tags: card.tags,
                    showsCover: showsCover,
                    isSelectionMode: selectionState.isActive,
                    isSelected: selectionState.selectedFavoriteIDs.contains(card.id),
                    onToggleSelection: { onToggleSelection(card.id) },
                    onEditTags: { onEditTags(card.item) },
                    onOpen: onOpen,
                    onDelete: onDelete
                )
            }
        } header: {
            if showsCount {
                Text(L10n.string("favorites.items_count", cards.count))
            }
        }
    }
}

private struct LocalFavoriteItemRow: View {
    let item: FavoriteItem
    let title: String
    let sourceGroupLabel: String
    let progressPercent: Int?
    let chapterPageProgress: String?
    let recentReadingAt: Date?
    let lastUpdatedAt: Date?
    let coverURL: URL?
    let tags: [FavoriteTag]
    let showsCover: Bool
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onEditTags: () -> Void
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem) async -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                LocalFavoriteSelectionIndicator(isSelected: isSelected)
            }
            if showsCover {
                LocalFavoriteCoverThumbnail(url: coverURL, fallbackColor: .yellow)
                    .frame(width: 48, height: 64)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .lineLimit(2)
                Text(sourceGroupLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                LocalFavoriteItemMetadataLine(
                    progressPercent: progressPercent,
                    chapterPageProgress: chapterPageProgress,
                    recentReadingAt: recentReadingAt,
                    lastUpdatedAt: lastUpdatedAt
                )
                LocalFavoriteTagChipRow(tags: tags)
            }
            Spacer(minLength: 8)
            if !isSelectionMode {
                Menu {
                    Button {
                        Task { await onOpen(item, .start) }
                    } label: {
                        Label(L10n.string("favorites.open_from_start"), systemImage: "text.page")
                    }
                    Button(role: .destructive) {
                        Task { await onDelete(item) }
                    } label: {
                        Label(L10n.string("common.delete"), systemImage: "trash")
                    }
                    Button(action: onEditTags) {
                        Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(L10n.string("common.more"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                Task { await onOpen(item, .resume) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LocalFavoriteStaggeredCards: View {
    let cards: [FavoriteCardProjection]
    let selectionState: LocalFavoriteSelectionState
    let onToggleSelection: (String) -> Void
    let onEditTags: (FavoriteItem) -> Void
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem) async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<2, id: \.self) { column in
                LazyVStack(spacing: 12) {
                    ForEach(columnCards(column)) { card in
                        LocalFavoriteGridCard(
                            card: card,
                            fixedHeight: nil,
                            selectionState: selectionState,
                            onToggleSelection: onToggleSelection,
                            onEditTags: onEditTags,
                            onOpen: onOpen,
                            onDelete: onDelete
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func columnCards(_ column: Int) -> [FavoriteCardProjection] {
        cards.enumerated().compactMap { index, card in
            index % 2 == column ? card : nil
        }
    }
}

private struct LocalFavoriteGridCard: View {
    let card: FavoriteCardProjection
    let fixedHeight: CGFloat?
    let selectionState: LocalFavoriteSelectionState
    let onToggleSelection: (String) -> Void
    let onEditTags: (FavoriteItem) -> Void
    let onOpen: (FavoriteItem, FavoriteLaunchMode) async -> Void
    let onDelete: (FavoriteItem) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if selectionState.isActive {
                LocalFavoriteSelectionIndicator(isSelected: selectionState.selectedFavoriteIDs.contains(card.id))
            }
            LocalFavoriteGridCover(url: card.coverURL, fallbackColor: .yellow)
            Text(card.item.resolvedDisplayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(fixedHeight == nil ? 3 : 2)
            Text(card.sourceGroupLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            LocalFavoriteItemMetadataLine(
                progressPercent: card.progressPercent,
                chapterPageProgress: card.chapterPageProgress,
                recentReadingAt: card.recentReadingAt,
                lastUpdatedAt: card.lastUpdatedAt
            )
            LocalFavoriteTagChipRow(tags: card.tags)
            Spacer(minLength: 0)
            if !selectionState.isActive {
                HStack {
                    Button {
                        Task { await onOpen(card.item, .resume) }
                    } label: {
                        Image(systemName: "book")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Menu {
                        Button {
                            Task { await onOpen(card.item, .start) }
                        } label: {
                            Label(L10n.string("favorites.open_from_start"), systemImage: "text.page")
                        }
                        Button(role: .destructive) {
                            Task { await onDelete(card.item) }
                        } label: {
                            Label(L10n.string("common.delete"), systemImage: "trash")
                        }
                        Button {
                            onEditTags(card.item)
                        } label: {
                            Label(L10n.string("favorites.tags_action"), systemImage: "tag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(L10n.string("common.more"))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .top)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            if selectionState.isActive {
                onToggleSelection(card.id)
            } else {
                Task { await onOpen(card.item, .resume) }
            }
        }
    }
}

private struct LocalFavoriteGridCover: View {
    let url: URL?
    let fallbackColor: Color

    var body: some View {
        GeometryReader { proxy in
            LocalFavoriteCoverThumbnail(url: url, fallbackColor: fallbackColor)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}

private struct LocalFavoriteCoverThumbnail: View {
    let url: URL?
    let fallbackColor: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fallbackColor.opacity(0.16))
            if let url {
                YamiboRemoteImage(source: YamiboImageSource(url: url)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } placeholder: {
                    ProgressView()
                } failure: { _ in
                    fallbackIcon
                }
            } else {
                fallbackIcon
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(fallbackColor)
    }
}

private struct LocalFavoriteItemMetadataLine: View {
    let progressPercent: Int?
    let chapterPageProgress: String?
    let recentReadingAt: Date?
    let lastUpdatedAt: Date?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                metadataContent
            }
            VStack(alignment: .leading, spacing: 2) {
                metadataContent
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var metadataContent: some View {
        if let progressPercent {
            Label("\(progressPercent)%", systemImage: "chart.line.uptrend.xyaxis")
        }
        if let chapterPageProgress {
            Label(chapterPageProgress, systemImage: "book.pages")
        }
        if let recentReadingAt {
            Label {
                Text(recentReadingAt, format: .dateTime.month().day())
            } icon: {
                Image(systemName: "clock")
            }
        }
        if let lastUpdatedAt {
            Label {
                Text(lastUpdatedAt, format: .dateTime.month().day())
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
    }
}
