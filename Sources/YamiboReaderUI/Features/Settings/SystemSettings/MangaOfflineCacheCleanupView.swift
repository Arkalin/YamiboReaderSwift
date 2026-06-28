import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MangaOfflineCacheCleanupView: View {
    @ObservedObject var viewModel: SystemSettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.mangaOfflineCacheCleanupIsEmpty {
                    MangaOfflineCacheCleanupEmptyState()
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.mangaOfflineCacheCleanupRows) { row in
                            MangaOfflineCacheCleanupRowView(
                                row: row,
                                isSelecting: viewModel.isMangaOfflineCacheCleanupSelectionMode,
                                isSelected: viewModel.selectedMangaOfflineCacheOwnerNames.contains(row.ownerName),
                                select: {
                                    viewModel.toggleMangaOfflineCacheCleanupSelection(ownerName: row.ownerName)
                                },
                                delete: {
                                    viewModel.requestMangaOfflineCacheCleanup(ownerName: row.ownerName)
                                }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(MangaOfflineCacheCleanupPalette.groupedBackground)
        .navigationTitle(L10n.string("settings.manga_offline_cache.title"))
        .navigationBarBackButtonHidden(viewModel.isMangaOfflineCacheCleanupSelectionMode)
        .task {
            await viewModel.refreshMangaOfflineCacheCleanup()
        }
        .refreshable {
            await viewModel.refreshMangaOfflineCacheCleanup()
        }
        .toolbar {
            if viewModel.isMangaOfflineCacheCleanupSelectionMode {
                ToolbarItem(placement: .cancellationAction) {
                    MangaOfflineCacheCleanupSelectAllButton(viewModel: viewModel)
                }
            }

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

            #if os(iOS)
            if viewModel.isMangaOfflineCacheCleanupSelectionMode && usesSystemSelectionBottomToolbar {
                ToolbarItem(placement: .bottomBar) {
                    MangaOfflineCacheCleanupSelectionToolbar(
                        actionState: viewModel.mangaOfflineCacheCleanupSelectionActionState,
                        onDelete: viewModel.requestSelectedMangaOfflineCacheCleanup
                    )
                }
            }
            #endif
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isMangaOfflineCacheCleanupSelectionMode && !usesSystemSelectionBottomToolbar {
                MangaOfflineCacheCleanupSelectionActionBar(
                    actionState: viewModel.mangaOfflineCacheCleanupSelectionActionState,
                    onDelete: viewModel.requestSelectedMangaOfflineCacheCleanup
                )
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
        .sensoryFeedback(.selection, trigger: viewModel.selectedMangaOfflineCacheOwnerNames)
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

    private var usesSystemSelectionBottomToolbar: Bool {
        #if os(iOS)
        if #available(iOS 26, *) {
            return true
        }
        #endif
        return false
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
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.55) : Color.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                Text(row.byteCountLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MangaOfflineCacheCleanupPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelecting && isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isSelected)
        .onTapGesture(perform: rowAction)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete()
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        }
    }

    private var isDimmed: Bool {
        isSelecting && !isSelected
    }

    private var titleColor: Color {
        isDimmed ? .secondary : .primary
    }

    private var secondaryColor: Color {
        isDimmed ? Color.secondary.opacity(0.55) : .secondary
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
        Button(title) {
            viewModel.toggleAllMangaOfflineCacheCleanupRows()
        }
        .disabled(viewModel.mangaOfflineCacheCleanupIsEmpty)
        .accessibilityLabel(title)
    }

    private var title: String {
        viewModel.isMangaOfflineCacheCleanupSelectionComplete
            ? L10n.string("common.invert_selection")
            : L10n.string("common.select_all")
    }
}

private struct MangaOfflineCacheCleanupDeleteSelectionButton: View {
    let actionState: MangaOfflineCacheCleanupSelectionActionState
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            VStack(spacing: 3) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 22)

                Text(L10n.string("common.delete"))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(width: 66)
            .foregroundStyle(Color.red)
            .opacity(actionState.canDelete ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actionState.canDelete)
        .accessibilityLabel(
            L10n.string(
                "settings.manga_offline_cache.delete_selected_format",
                actionState.selectedOwnerCount
            )
        )
    }
}

private struct MangaOfflineCacheCleanupSelectionToolbar: View {
    let actionState: MangaOfflineCacheCleanupSelectionActionState
    let onDelete: () -> Void

    var body: some View {
        MangaOfflineCacheCleanupDeleteSelectionButton(
            actionState: actionState,
            onDelete: onDelete
        )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

private struct MangaOfflineCacheCleanupSelectionActionBar: View {
    let actionState: MangaOfflineCacheCleanupSelectionActionState
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer(minLength: 0)
                MangaOfflineCacheCleanupDeleteSelectionButton(
                    actionState: actionState,
                    onDelete: onDelete
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}

private struct MangaOfflineCacheCleanupEmptyState: View {
    var body: some View {
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
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MangaOfflineCacheCleanupPalette.cardBackground)
        )
    }
}

private enum MangaOfflineCacheCleanupPalette {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }

    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.clear
        #endif
    }
}
