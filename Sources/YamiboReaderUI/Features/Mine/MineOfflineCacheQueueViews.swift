import SwiftUI
import YamiboReaderCore

struct MineOfflineCacheQueueSheet: View {
    let viewModel: MineHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOwnerName: String?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.offlineCacheQueueIsEmpty {
                    MineOfflineCacheQueueEmptyState()
                } else {
                    if viewModel.showsOfflineCacheQueueControls {
                        MineOfflineCacheQueueControls(viewModel: viewModel)
                    }

                    ForEach(viewModel.offlineCacheQueueGroups) { group in
                        Section {
                            MineOfflineCacheQueueOwnerRow(
                                group: group,
                                isSelecting: viewModel.isOfflineCacheQueueSelectionMode,
                                isSelected: viewModel.isOfflineCacheOwnerSelected(ownerName: group.ownerName),
                                open: {
                                    viewModel.setOfflineCacheQueueSelectionMode(false)
                                    selectedOwnerName = group.ownerName
                                },
                                toggleSelection: {
                                    viewModel.toggleOfflineCacheOwnerSelection(ownerName: group.ownerName)
                                },
                                cancel: {
                                    Task {
                                        await viewModel.cancelOfflineCacheOwnerGroup(ownerName: group.ownerName)
                                    }
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
            .navigationTitle(L10n.string("mine.download_queue"))
            .task {
                await viewModel.refreshOfflineCacheQueue()
            }
            .refreshable {
                await viewModel.refreshOfflineCacheQueue()
            }
            .sheet(isPresented: selectedOwnerIsPresented) {
                if let ownerName = selectedOwnerName {
                    MineOfflineCacheQueueOwnerSheet(
                        viewModel: viewModel,
                        ownerName: ownerName
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !viewModel.offlineCacheQueueIsEmpty {
                        Button(
                            viewModel.isOfflineCacheQueueSelectionMode
                                ? L10n.string("common.done")
                                : L10n.string("common.select")
                        ) {
                            viewModel.setOfflineCacheQueueSelectionMode(!viewModel.isOfflineCacheQueueSelectionMode)
                        }
                        .disabled(viewModel.isOfflineCacheQueueCommandRunning)
                    }
                }

                if viewModel.isOfflineCacheQueueSelectionMode {
                    #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                    }
                    #else
                    ToolbarItem(placement: .secondaryAction) {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                    }
                    #endif
                }
            }
            .overlay {
                if viewModel.isLoadingOfflineCacheQueue {
                    ProgressView()
                }
            }
        }
    }

    private var selectedOwnerIsPresented: Binding<Bool> {
        Binding(
            get: { selectedOwnerName != nil },
            set: { isPresented in
                if !isPresented {
                    selectedOwnerName = nil
                    viewModel.setOfflineCacheQueueSelectionMode(false)
                }
            }
        )
    }
}

private struct MineOfflineCacheQueueSelectAllButton: View {
    let viewModel: MineHomeViewModel
    var ownerName: String? = nil

    var body: some View {
        Button(L10n.string("common.select_all")) {
            viewModel.selectAllOfflineCacheWorks(ownerName: ownerName)
        }
        .disabled(viewModel.offlineCacheQueueIsEmpty)
    }
}

private struct MineOfflineCacheQueueCancelSelectionButton: View {
    let viewModel: MineHomeViewModel

    var body: some View {
        Button(role: .destructive) {
            Task {
                await viewModel.cancelSelectedOfflineCacheWorks()
            }
        } label: {
            Label(
                L10n.string(
                    "mine.offline_queue.cancel_selected_format",
                    viewModel.selectedOfflineCacheWorkCount
                ),
                systemImage: "xmark.circle"
            )
        }
        .disabled(
            viewModel.selectedOfflineCacheWorkIDs.isEmpty
                || viewModel.isOfflineCacheQueueCommandRunning
        )
    }
}

private struct MineOfflineCacheQueueControls: View {
    let viewModel: MineHomeViewModel

    var body: some View {
        Section {
            Button {
                Task {
                    if viewModel.offlineCacheQueueRunState == .running {
                        await viewModel.pauseOfflineCacheQueue()
                    } else {
                        await viewModel.continueOfflineCacheQueue()
                    }
                }
            } label: {
                Label(controlTitle, systemImage: controlImage)
            }
            .disabled(viewModel.isOfflineCacheQueueCommandRunning)
        }
    }

    private var controlTitle: String {
        viewModel.offlineCacheQueueRunState == .running
            ? L10n.string("mine.offline_queue.pause")
            : L10n.string("mine.offline_queue.continue")
    }

    private var controlImage: String {
        viewModel.offlineCacheQueueRunState == .running ? "pause.fill" : "play.fill"
    }
}

private struct MineOfflineCacheQueueOwnerRow: View {
    let group: MineOfflineCacheQueueOwnerGroup
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggleSelection: () -> Void
    let cancel: () -> Void

    var body: some View {
        Button(action: rowAction) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.indigo)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.ownerName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Text(L10n.string("mine.offline_queue.chapter_count_format", group.chapterCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(group.percentageText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ProgressView(value: group.progressFraction)

                    HStack(spacing: 8) {
                        Text(group.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let currentSpeedText = group.currentSpeedText {
                            Text(currentSpeedText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                if !isSelecting {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: cancel) {
                Label(L10n.string("common.cancel"), systemImage: "xmark.circle")
            }
        }
    }

    private func rowAction() {
        if isSelecting {
            toggleSelection()
        } else {
            open()
        }
    }
}

private struct MineOfflineCacheQueueOwnerSheet: View {
    let viewModel: MineHomeViewModel
    let ownerName: String
    @Environment(\.dismiss) private var dismiss

    private var group: MineOfflineCacheQueueOwnerGroup? {
        viewModel.offlineCacheQueueGroups.first { $0.ownerName == ownerName }
    }

    var body: some View {
        NavigationStack {
            List {
                if let group {
                    if viewModel.showsOfflineCacheQueueControls {
                        MineOfflineCacheQueueControls(viewModel: viewModel)
                    }

                    ForEach(group.chapters) { chapter in
                        MineOfflineCacheQueueChapterRowView(
                            chapter: chapter,
                            isSelecting: viewModel.isOfflineCacheQueueSelectionMode,
                            isSelected: viewModel.selectedOfflineCacheWorkIDs.contains(chapter.id),
                            toggleSelection: {
                                viewModel.toggleOfflineCacheWorkSelection(chapter.id)
                            },
                            cancel: {
                                Task {
                                    await viewModel.cancelOfflineCacheChapter(chapter.id)
                                    dismissIfGroupIsEmpty()
                                }
                            }
                        )
                    }
                } else {
                    MineOfflineCacheQueueEmptyState()
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle(group?.ownerName ?? L10n.string("mine.download_queue"))
            .task {
                viewModel.setOfflineCacheQueueSelectionMode(false)
                await viewModel.refreshOfflineCacheQueue()
                dismissIfGroupIsEmpty()
            }
            .refreshable {
                await viewModel.refreshOfflineCacheQueue()
                dismissIfGroupIsEmpty()
            }
            .onChange(of: viewModel.offlineCacheQueueEntryCount) {
                dismissIfGroupIsEmpty()
            }
            .onDisappear {
                viewModel.setOfflineCacheQueueSelectionMode(false)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if group != nil {
                        Button(
                            viewModel.isOfflineCacheQueueSelectionMode
                                ? L10n.string("common.done")
                                : L10n.string("common.select")
                        ) {
                            viewModel.setOfflineCacheQueueSelectionMode(!viewModel.isOfflineCacheQueueSelectionMode)
                        }
                        .disabled(viewModel.isOfflineCacheQueueCommandRunning)
                    }
                }

                if viewModel.isOfflineCacheQueueSelectionMode {
                    #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel, ownerName: ownerName)
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                    }
                    #else
                    ToolbarItem(placement: .secondaryAction) {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel, ownerName: ownerName)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                    }
                    #endif
                }
            }
            .overlay {
                if viewModel.isLoadingOfflineCacheQueue {
                    ProgressView()
                }
            }
        }
    }

    private func dismissIfGroupIsEmpty() {
        if group == nil {
            dismiss()
        }
    }
}

private struct MineOfflineCacheQueueChapterRowView: View {
    let chapter: MineOfflineCacheQueueChapterRow
    let isSelecting: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
    let cancel: () -> Void

    var body: some View {
        Button(action: rowAction) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chapter.title)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        Text(chapter.percentageText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ProgressView(value: chapter.progressFraction)

                    HStack(spacing: 8) {
                        Text(chapter.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let speedText = chapter.speedText {
                            Text(speedText)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let failureStatusText = chapter.failureStatusText {
                            Text(failureStatusText)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: cancel) {
                Label(L10n.string("common.cancel"), systemImage: "xmark.circle")
            }
        }
    }

    private func rowAction() {
        guard isSelecting else { return }
        toggleSelection()
    }
}

private struct MineOfflineCacheQueueEmptyState: View {
    var body: some View {
        Section {
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
        }
    }
}
