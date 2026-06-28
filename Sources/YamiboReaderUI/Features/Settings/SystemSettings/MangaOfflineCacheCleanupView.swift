import SwiftUI
import YamiboReaderCore

struct MangaOfflineCacheCleanupView: View {
    @ObservedObject var viewModel: SystemSettingsViewModel

    var body: some View {
        List {
            if viewModel.mangaOfflineCacheCleanupIsEmpty {
                MangaOfflineCacheCleanupEmptyState()
            } else {
                Section {
                    ForEach(viewModel.mangaOfflineCacheCleanupRows) { row in
                        MangaOfflineCacheCleanupRowView(
                            row: row,
                            isSelecting: viewModel.isMangaOfflineCacheCleanupSelectionMode,
                            isSelected: viewModel.selectedMangaOfflineCacheFavoriteIDs.contains(row.favoriteID),
                            select: {
                                viewModel.toggleMangaOfflineCacheCleanupSelection(favoriteID: row.favoriteID)
                            },
                            delete: {
                                viewModel.requestMangaOfflineCacheCleanup(favoriteID: row.favoriteID)
                            }
                        )
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(L10n.string("settings.manga_offline_cache.title"))
        .task {
            await viewModel.refreshMangaOfflineCacheCleanup()
        }
        .refreshable {
            await viewModel.refreshMangaOfflineCacheCleanup()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !viewModel.mangaOfflineCacheCleanupIsEmpty {
                    Button(
                        viewModel.isMangaOfflineCacheCleanupSelectionMode
                            ? L10n.string("common.done")
                            : L10n.string("common.select")
                    ) {
                        viewModel.setMangaOfflineCacheCleanupSelectionMode(
                            !viewModel.isMangaOfflineCacheCleanupSelectionMode
                        )
                    }
                    .disabled(viewModel.activeAction == .clearingMangaOfflineCache)
                }
            }

            if viewModel.isMangaOfflineCacheCleanupSelectionMode {
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    MangaOfflineCacheCleanupSelectAllButton(viewModel: viewModel)
                }
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    MangaOfflineCacheCleanupDeleteSelectionButton(viewModel: viewModel)
                }
                #else
                ToolbarItem(placement: .secondaryAction) {
                    MangaOfflineCacheCleanupSelectAllButton(viewModel: viewModel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    MangaOfflineCacheCleanupDeleteSelectionButton(viewModel: viewModel)
                }
                #endif
            }
        }
        .overlay {
            if viewModel.activeAction == .loading || viewModel.activeAction == .clearingMangaOfflineCache {
                ProgressView(
                    viewModel.activeAction == .clearingMangaOfflineCache
                        ? L10n.string("common.deleting")
                        : L10n.string("common.loading")
                )
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .alert(
            viewModel.pendingMangaOfflineCacheCleanupConfirmation?.title ?? "",
            isPresented: confirmationIsPresented,
            presenting: viewModel.pendingMangaOfflineCacheCleanupConfirmation
        ) { confirmation in
            Button(L10n.string("common.delete"), role: .destructive) {
                Task {
                    _ = await viewModel.confirmMangaOfflineCacheCleanup(confirmation)
                }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {
                viewModel.cancelMangaOfflineCacheCleanupConfirmation()
            }
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingMangaOfflineCacheCleanupConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    Task { @MainActor in
                        viewModel.cancelMangaOfflineCacheCleanupConfirmation()
                    }
                }
            }
        )
    }
}

private struct MangaOfflineCacheCleanupRowView: View {
    let row: MangaOfflineCacheCleanupRow
    let isSelecting: Bool
    let isSelected: Bool
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: rowAction) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(row.byteCountLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete()
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        }
    }

    private func rowAction() {
        if isSelecting {
            select()
        } else {
            delete()
        }
    }
}

private struct MangaOfflineCacheCleanupSelectAllButton: View {
    let viewModel: SystemSettingsViewModel

    var body: some View {
        Button(L10n.string("common.select_all")) {
            viewModel.selectAllMangaOfflineCacheCleanupRows()
        }
        .disabled(viewModel.mangaOfflineCacheCleanupIsEmpty)
    }
}

private struct MangaOfflineCacheCleanupDeleteSelectionButton: View {
    let viewModel: SystemSettingsViewModel

    var body: some View {
        Button(role: .destructive) {
            viewModel.requestSelectedMangaOfflineCacheCleanup()
        } label: {
            Label(
                L10n.string(
                    "settings.manga_offline_cache.delete_selected_format",
                    viewModel.selectedMangaOfflineCacheFavoriteCount
                ),
                systemImage: "trash"
            )
        }
        .disabled(
            viewModel.selectedMangaOfflineCacheFavoriteIDs.isEmpty
                || viewModel.activeAction == .clearingMangaOfflineCache
        )
    }
}

private struct MangaOfflineCacheCleanupEmptyState: View {
    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(L10n.string("settings.manga_offline_cache.empty_title"))
                    .font(.headline)

                Text(L10n.string("settings.manga_offline_cache.empty_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }
}
