import SwiftUI
import YamiboXCore

/// Sheet shell for contexts without a navigation stack of their own (the
/// full-screen readers' cache sheets). The Mine tab pushes
/// `OfflineCacheQueueScreen` directly instead.
struct OfflineCacheQueueSheet: View {
    let viewModel: OfflineCacheQueueViewModel

    var body: some View {
        NavigationStack {
            OfflineCacheQueueScreen(viewModel: viewModel, showsCloseButton: true)
        }
    }
}

struct OfflineCacheQueueScreen: View {
    let viewModel: OfflineCacheQueueViewModel
    var showsCloseButton = false

    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroupID: OfflineCacheGroupID?

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isEmpty {
                        OfflineCacheQueueEmptyState()
                    } else {
                        if viewModel.showsControls {
                            OfflineCacheQueueControls(viewModel: viewModel)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.groups) { group in
                                OfflineCacheQueueOwnerRow(
                                    group: group,
                                    isSelecting: viewModel.isSelectionMode,
                                    isSelected: viewModel.isOwnerSelected(id: group.id),
                                    open: {
                                        viewModel.setSelectionMode(false)
                                        selectedGroupID = group.id
                                    },
                                    toggleSelection: {
                                        viewModel.toggleOwnerSelection(id: group.id)
                                    },
                                    cancel: {
                                        Task {
                                            await viewModel.cancelOwnerGroup(id: group.id)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(YamiboColors.SystemSurface.groupedBackground)
            .navigationTitle(
                viewModel.isSelectionMode
                    ? L10n.string("mine.offline_queue.selected_count", viewModel.selectedWorkCount)
                    : L10n.string("mine.download_queue")
            )
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .navigationDestination(item: $selectedGroupID) { groupID in
                OfflineCacheQueueOwnerScreen(
                    viewModel: viewModel,
                    groupID: groupID
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if viewModel.isSelectionMode {
                        OfflineCacheQueueSelectAllButton(viewModel: viewModel)
                    } else if showsCloseButton {
                        Button(L10n.string("common.close")) {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !viewModel.isEmpty {
                        Button(
                            viewModel.isSelectionMode
                                ? L10n.string("common.done")
                                : L10n.string("common.select")
                        ) {
                            viewModel.setSelectionMode(!viewModel.isSelectionMode)
                        }
                        .disabled(viewModel.isCommandRunning)
                    }
                }

                if viewModel.isSelectionMode && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        SelectionBottomToolbar(actions: OfflineCacheQueueSelectionActions.cancel(viewModel: viewModel))
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isSelectionMode && !usesSystemSelectionBottomToolbar {
                    SelectionBottomToolbar(actions: OfflineCacheQueueSelectionActions.cancel(viewModel: viewModel))
                        .selectionBottomToolbarCapsule()
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.selectedWorkIDs)
    }
}

private struct OfflineCacheQueueSelectAllButton: View {
    let viewModel: OfflineCacheQueueViewModel
    var groupID: OfflineCacheGroupID? = nil

    var body: some View {
        Button(title) {
            viewModel.toggleAllWorks(groupID: groupID)
        }
        .disabled(viewModel.isEmpty)
        .accessibilityLabel(title)
    }

    private var title: String {
        viewModel.isWorkSelectionComplete(groupID: groupID)
            ? L10n.string("common.invert_selection")
            : L10n.string("common.select_all")
    }
}

/// Builds the selection-mode bottom bar's single "cancel selected" action —
/// rendering is delegated to the shared `SelectionBottomToolbar`.
@MainActor
private enum OfflineCacheQueueSelectionActions {
    static func cancel(viewModel: OfflineCacheQueueViewModel) -> [SelectionToolbarAction] {
        let canCancel = !viewModel.selectedWorkIDs.isEmpty
            && !viewModel.isCommandRunning
        return [
            SelectionToolbarAction(
                id: "cancel",
                title: L10n.string("common.cancel"),
                systemImage: "xmark.circle",
                role: .destructive,
                isEnabled: canCancel,
                accessibilityLabel: L10n.string(
                    "mine.offline_queue.cancel_selected_format",
                    viewModel.selectedWorkCount
                ),
                action: {
                    Task { await viewModel.cancelSelectedWorks() }
                }
            )
        ]
    }
}

private struct OfflineCacheQueueControls: View {
    let viewModel: OfflineCacheQueueViewModel

    var body: some View {
        Button {
            Task {
                if viewModel.runState == .running {
                    await viewModel.pauseQueue()
                } else {
                    await viewModel.continueQueue()
                }
            }
        } label: {
            Label(controlTitle, systemImage: controlImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isCommandRunning)
    }

    private var controlTitle: String {
        viewModel.runState == .running
            ? L10n.string("mine.offline_queue.pause")
            : L10n.string("mine.offline_queue.continue")
    }

    private var controlImage: String {
        viewModel.runState == .running ? "pause.fill" : "play.fill"
    }
}

private struct OfflineCacheQueueOwnerRow: View {
    let group: OfflineCacheQueueOwnerGroup
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggleSelection: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.55) : Color.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.ownerName)
                            .font(.headline)
                            .foregroundStyle(titleColor)
                            .lineLimit(2)

                        Text(L10n.string("mine.offline_queue.chapter_count_format", group.chapterCount))
                            .font(.caption)
                            .foregroundStyle(secondaryColor)
                    }

                    Spacer(minLength: 8)

                    Text(group.percentageText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }

                ProgressView(value: group.progressFraction)
                    .tint(isDimmed ? Color.secondary : Color.accentColor)

                HStack(spacing: 8) {
                    Text(group.progressText)
                        .font(.caption)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)

                    if let currentSpeedText = group.currentSpeedText {
                        Text(currentSpeedText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(secondaryColor)
                            .lineLimit(1)
                    }

                    if let failureStatusText = group.failureStatusText {
                        Text(failureStatusText)
                            .font(.caption)
                            .foregroundStyle(isDimmed ? Color.secondary.opacity(0.55) : Color.red)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
                .opacity(isSelecting ? 0 : 1)
                .accessibilityHidden(isSelecting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
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
            Button(role: .destructive, action: cancel) {
                Label(L10n.string("common.cancel"), systemImage: "xmark.circle")
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
            toggleSelection()
        } else {
            open()
        }
    }
}

/// Drill-down detail for one owner's queued chapters, pushed onto the
/// enclosing navigation stack (system back replaces the old sheet-on-sheet
/// close button).
private struct OfflineCacheQueueOwnerScreen: View {
    let viewModel: OfflineCacheQueueViewModel
    let groupID: OfflineCacheGroupID
    @Environment(\.dismiss) private var dismiss

    private var group: OfflineCacheQueueOwnerGroup? {
        viewModel.groups.first { $0.id == groupID }
    }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let group {
                        if viewModel.showsControls {
                            OfflineCacheQueueControls(viewModel: viewModel)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(group.chapters) { chapter in
                                OfflineCacheQueueChapterRowView(
                                    chapter: chapter,
                                    isSelecting: viewModel.isSelectionMode,
                                    isSelected: viewModel.selectedWorkIDs.contains(chapter.id),
                                    toggleSelection: {
                                        viewModel.toggleWorkSelection(chapter.id)
                                    },
                                    cancel: {
                                        Task {
                                            await viewModel.cancelChapter(chapter.id)
                                            dismissIfGroupIsEmpty()
                                        }
                                    }
                                )
                            }
                        }
                    } else {
                        OfflineCacheQueueEmptyState()
                    }
                }
                .padding(16)
            }
            .background(YamiboColors.SystemSurface.groupedBackground)
            .navigationTitle(
                viewModel.isSelectionMode
                    ? L10n.string("mine.offline_queue.selected_count", viewModel.selectedWorkCount)
                    : (group?.title ?? L10n.string("mine.download_queue"))
            )
            .task {
                viewModel.setSelectionMode(false)
                await viewModel.refresh()
                dismissIfGroupIsEmpty()
            }
            .refreshable {
                await viewModel.refresh()
                dismissIfGroupIsEmpty()
            }
            .onChange(of: viewModel.entryCount) {
                dismissIfGroupIsEmpty()
            }
            .onDisappear {
                viewModel.setSelectionMode(false)
            }
            .toolbar {
                if viewModel.isSelectionMode {
                    ToolbarItem(placement: .cancellationAction) {
                        OfflineCacheQueueSelectAllButton(
                            viewModel: viewModel,
                            groupID: groupID
                        )
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if group != nil {
                        Button(
                            viewModel.isSelectionMode
                                ? L10n.string("common.done")
                                : L10n.string("common.select")
                        ) {
                            viewModel.setSelectionMode(!viewModel.isSelectionMode)
                        }
                        .disabled(viewModel.isCommandRunning)
                    }
                }

                if viewModel.isSelectionMode && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        SelectionBottomToolbar(actions: OfflineCacheQueueSelectionActions.cancel(viewModel: viewModel))
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isSelectionMode && !usesSystemSelectionBottomToolbar {
                    SelectionBottomToolbar(actions: OfflineCacheQueueSelectionActions.cancel(viewModel: viewModel))
                        .selectionBottomToolbarCapsule()
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.selectedWorkIDs)
    }

    private func dismissIfGroupIsEmpty() {
        if group == nil {
            dismiss()
        }
    }
}

private struct OfflineCacheQueueChapterRowView: View {
    let chapter: OfflineCacheQueueChapterRow
    let isSelecting: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chapter.title)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(chapter.percentageText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }

            ProgressView(value: chapter.progressFraction)
                .tint(isDimmed ? Color.secondary : Color.accentColor)

            HStack(spacing: 8) {
                Text(chapter.progressText)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)

                if let speedText = chapter.speedText {
                    Text(speedText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }

                if let failureStatusText = chapter.failureStatusText {
                    Text(failureStatusText)
                        .font(.caption)
                        .foregroundStyle(isDimmed ? Color.secondary.opacity(0.55) : Color.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
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
            Button(role: .destructive, action: cancel) {
                Label(L10n.string("common.cancel"), systemImage: "xmark.circle")
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
        guard isSelecting else { return }
        toggleSelection()
    }
}

private struct OfflineCacheQueueEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(L10n.string("mine.offline_queue.empty_title"))
                .font(.headline)
            Text(L10n.string("mine.offline_queue.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
        )
    }
}
