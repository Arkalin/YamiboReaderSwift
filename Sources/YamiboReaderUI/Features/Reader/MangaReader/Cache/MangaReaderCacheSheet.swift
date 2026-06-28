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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorMessage = model.errorMessage {
                        MangaReaderCacheErrorBanner(message: errorMessage)
                    }

                    MangaReaderCacheChapterSection(
                        rows: model.rows,
                        isSelecting: $isSelecting,
                        selectedTIDs: $selectedTIDs,
                        isAllSelected: selectionState.isAllSelected,
                        onToggleAll: toggleAll
                    )
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
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
            .sensoryFeedback(.selection, trigger: selectedTIDs)
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

    private func toggleAll() {
        if selectionState.isAllSelected {
            selectedTIDs = []
        } else {
            selectedTIDs = model.allChapterTIDs
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

private struct MangaReaderCacheErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}

private struct MangaReaderCacheChapterSection: View {
    let rows: [MangaReaderCacheRow]
    @Binding var isSelecting: Bool
    @Binding var selectedTIDs: Set<String>
    let isAllSelected: Bool
    let onToggleAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MangaReaderCacheSelectionHeader(
                isSelecting: isSelecting,
                isAllSelected: isAllSelected,
                isEmpty: rows.isEmpty,
                onToggleAll: onToggleAll,
                onToggleSelectionMode: toggleSelectionMode
            )
            .frame(height: 38, alignment: .center)

            if rows.isEmpty {
                ContentUnavailableView(L10n.string("manga.no_chapters"), systemImage: "books.vertical")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(rows) { row in
                        MangaReaderCacheRowView(
                            row: row,
                            isSelecting: isSelecting,
                            isSelected: selectedTIDs.contains(row.id),
                            onToggleSelection: {
                                toggleSelection(row.id)
                            }
                        )
                    }
                }
            }
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

    private func toggleSelection(_ tid: String) {
        guard isSelecting else { return }
        if selectedTIDs.contains(tid) {
            selectedTIDs.remove(tid)
        } else {
            selectedTIDs.insert(tid)
        }
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
                .font(.subheadline.weight(.semibold))
                .disabled(isEmpty)
            } else {
                Text(L10n.string("manga.offline_cache.chapter_section"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(isSelecting ? L10n.string("common.done") : L10n.string("common.select")) {
                onToggleSelectionMode()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .disabled(isEmpty && !isSelecting)
        }
    }
}

private struct MangaReaderCacheRowView: View {
    let row: MangaReaderCacheRow
    let isSelecting: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(MangaChapterDisplayFormatter.displayNumber(for: row.chapter))
                .font(.caption.weight(.bold))
                .foregroundStyle(numberColor)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.chapter.rawTitle)
                    .font(.subheadline)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MangaReaderCacheStateBadge(state: row.state, isDimmed: isDimmed)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelecting && isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSelected)
        .onTapGesture {
            onToggleSelection()
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isDimmed: Bool {
        isSelecting && !isSelected
    }

    private var titleColor: Color {
        isDimmed ? .secondary : .primary
    }

    private var numberColor: Color {
        isDimmed ? Color.secondary.opacity(0.55) : .secondary
    }
}

private struct MangaReaderCacheStateBadge: View {
    let state: MangaOfflineCacheState
    let isDimmed: Bool

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
        if isDimmed {
            return Color.secondary.opacity(0.55)
        }
        switch state {
        case .cached:
            return Color.green
        case .uncached:
            return Color.secondary
        case .caching:
            return Color.orange
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
