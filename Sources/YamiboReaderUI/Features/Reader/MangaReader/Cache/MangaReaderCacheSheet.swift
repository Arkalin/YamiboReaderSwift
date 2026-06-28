import SwiftUI
import YamiboReaderCore

#if os(iOS)
struct MangaReaderCacheSheet: View {
    @StateObject private var model: MangaReaderCacheViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSelecting = false
    @State private var selectedTIDs: Set<String> = []

    init(
        context: MangaLaunchContext,
        panel: MangaDirectoryPanelPresentation,
        favoriteStore: any FavoriteStoring,
        offlineCacheStore: any MangaOfflineCacheStoring
    ) {
        _model = StateObject(
            wrappedValue: MangaReaderCacheViewModel(
                context: context,
                panel: panel,
                favoriteStore: favoriteStore,
                offlineCacheStore: offlineCacheStore
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    if model.rows.isEmpty {
                        ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
                    } else {
                        ForEach(model.rows) { row in
                            MangaReaderCacheRowView(
                                row: row,
                                isSelecting: isSelecting,
                                isSelected: selectedTIDs.contains(row.id),
                                onToggleSelection: {
                                    toggleSelection(row.id)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard isSelecting else { return }
                                toggleSelection(row.id)
                            }
                        }
                    }
                } header: {
                    MangaReaderCacheSelectionHeader(
                        isSelecting: isSelecting,
                        isAllSelected: selectionState.isAllSelected,
                        isEmpty: model.rows.isEmpty,
                        onToggleAll: toggleAll,
                        onToggleSelectionMode: toggleSelectionMode
                    )
                }
            }
            .navigationTitle(L10n.string("manga.offline_cache.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.string("common.close"))
                }

                if isSelecting && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        MangaReaderCacheSelectionToolbar(
                            selectionState: selectionState,
                            onCache: cacheSelection,
                            onDelete: deleteSelection
                        )
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting && !usesSystemSelectionBottomToolbar {
                    MangaReaderCacheSelectionActionBar(
                        selectionState: selectionState,
                        onCache: cacheSelection,
                        onDelete: deleteSelection
                    )
                }
            }
            .task {
                await model.load()
            }
            .refreshable {
                await model.refreshRows()
            }
            .onChange(of: model.allChapterTIDs) { _, validTIDs in
                selectedTIDs.formIntersection(validTIDs)
            }
            .alert(item: Binding(get: { model.prompt }, set: { _ in model.clearPrompt() })) { prompt in
                switch prompt {
                case let .addFavorite(title):
                    Alert(
                        title: Text(L10n.string("manga.offline_cache.add_favorite_title")),
                        message: Text(L10n.string("manga.offline_cache.add_favorite_message", title)),
                        dismissButton: .default(Text(L10n.string("common.ok"))) {
                            model.clearPrompt()
                        }
                    )
                }
            }
        }
    }

    private var selectionState: MangaReaderCacheSelectionState {
        model.selectionState(for: selectedTIDs)
    }

    private var usesSystemSelectionBottomToolbar: Bool {
        if #available(iOS 26, *) {
            return true
        }
        return false
    }

    private func toggleSelection(_ tid: String) {
        if selectedTIDs.contains(tid) {
            selectedTIDs.remove(tid)
        } else {
            selectedTIDs.insert(tid)
        }
    }

    private func toggleAll() {
        if selectionState.isAllSelected {
            selectedTIDs = []
        } else {
            selectedTIDs = model.allChapterTIDs
        }
    }

    private func toggleSelectionMode() {
        if isSelecting {
            isSelecting = false
            selectedTIDs = []
        } else {
            isSelecting = true
        }
    }

    private func cacheSelection() {
        let targets = selectedTIDs
        Task {
            await model.cacheSelected(tids: targets)
            exitSelectionModeIfActionFinished()
        }
    }

    private func deleteSelection() {
        let targets = selectedTIDs
        Task {
            await model.deleteSelected(tids: targets)
            exitSelectionModeIfActionFinished()
        }
    }

    @MainActor
    private func exitSelectionModeIfActionFinished() {
        guard model.errorMessage == nil else { return }
        isSelecting = false
        selectedTIDs = []
    }
}

private struct MangaReaderCacheSelectionHeader: View {
    let isSelecting: Bool
    let isAllSelected: Bool
    let isEmpty: Bool
    let onToggleAll: () -> Void
    let onToggleSelectionMode: () -> Void

    var body: some View {
        HStack {
            if isSelecting {
                Button(isAllSelected ? L10n.string("common.deselect_all") : L10n.string("common.select_all")) {
                    onToggleAll()
                }
                .disabled(isEmpty)
            } else {
                Text(L10n.string("manga.offline_cache.chapter_section"))
            }

            Spacer(minLength: 0)

            Button(isSelecting ? L10n.string("common.done") : L10n.string("common.select")) {
                onToggleSelectionMode()
            }
            .disabled(isEmpty && !isSelecting)
        }
        .font(.subheadline.weight(.semibold))
    }
}

private struct MangaReaderCacheRowView: View {
    let row: MangaReaderCacheRow
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? L10n.string("common.deselect_all") : L10n.string("common.select"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.chapter.rawTitle)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(MangaChapterDisplayFormatter.displayNumber(for: row.chapter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            MangaReaderCacheStateBadge(state: row.state)
        }
        .padding(.vertical, 4)
    }
}

private struct MangaReaderCacheStateBadge: View {
    let state: MangaOfflineCacheState

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var title: String {
        switch state {
        case .cached:
            L10n.string("reader.cached")
        case .uncached:
            L10n.string("manga.offline_cache.uncached")
        case .caching:
            L10n.string("manga.offline_cache.caching")
        }
    }

    private var systemImage: String {
        switch state {
        case .cached:
            "checkmark.seal.fill"
        case .uncached:
            "icloud"
        case .caching:
            "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .cached:
            .green
        case .uncached:
            .secondary
        case .caching:
            .orange
        }
    }
}

private struct MangaReaderCacheSelectionToolbar: View {
    let selectionState: MangaReaderCacheSelectionState
    let onCache: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            toolbarButton(
                title: L10n.string("reader.cache_action.cache"),
                systemImage: "square.and.arrow.down",
                role: nil,
                isEnabled: selectionState.canCache,
                action: onCache
            )
            toolbarButton(
                title: L10n.string("common.delete"),
                systemImage: "trash",
                role: .destructive,
                isEnabled: selectionState.canDelete,
                action: onDelete
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        role: ButtonRole?,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
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
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

private struct MangaReaderCacheSelectionActionBar: View {
    let selectionState: MangaReaderCacheSelectionState
    let onCache: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            MangaReaderCacheSelectionToolbar(
                selectionState: selectionState,
                onCache: onCache,
                onDelete: onDelete
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}
#endif
