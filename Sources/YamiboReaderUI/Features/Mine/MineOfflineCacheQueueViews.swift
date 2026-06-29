import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MineOfflineCacheQueueSheet: View {
    let viewModel: MineHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOwnerName: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.offlineCacheQueueIsEmpty {
                        MineOfflineCacheQueueEmptyState()
                    } else {
                        if viewModel.showsOfflineCacheQueueControls {
                            MineOfflineCacheQueueControls(viewModel: viewModel)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.offlineCacheQueueGroups) { group in
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
                .padding(16)
            }
            .background(YamiboColors.SystemSurface.groupedBackground)
            .navigationTitle(L10n.string("mine.download_queue"))
            .task {
                await viewModel.loadOfflineCacheQueue()
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
                    if viewModel.isOfflineCacheQueueSelectionMode {
                        MineOfflineCacheQueueSelectAllButton(viewModel: viewModel)
                    } else {
                        Button(L10n.string("common.close")) {
                            dismiss()
                        }
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

                #if os(iOS)
                if viewModel.isOfflineCacheQueueSelectionMode && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueSelectionToolbar(viewModel: viewModel)
                    }
                }
                #endif
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isOfflineCacheQueueSelectionMode && !usesSystemSelectionBottomToolbar {
                    MineOfflineCacheQueueSelectionActionBar(viewModel: viewModel)
                }
            }
            .overlay {
                if viewModel.isLoadingOfflineCacheQueue {
                    ProgressView()
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.selectedOfflineCacheWorkIDs)
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
        Button(title) {
            viewModel.toggleAllOfflineCacheWorks(ownerName: ownerName)
        }
        .disabled(viewModel.offlineCacheQueueIsEmpty)
        .accessibilityLabel(title)
    }

    private var title: String {
        viewModel.isOfflineCacheWorkSelectionComplete(ownerName: ownerName)
            ? L10n.string("common.invert_selection")
            : L10n.string("common.select_all")
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
            VStack(spacing: 3) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 24, height: 22)

                Text(L10n.string("common.cancel"))
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
            .frame(width: 66)
            .foregroundStyle(Color.red)
            .opacity(canCancel ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canCancel)
        .accessibilityLabel(
            L10n.string(
                "mine.offline_queue.cancel_selected_format",
                viewModel.selectedOfflineCacheWorkCount
            )
        )
    }

    private var canCancel: Bool {
        !viewModel.selectedOfflineCacheWorkIDs.isEmpty
            && !viewModel.isOfflineCacheQueueCommandRunning
    }
}

private struct MineOfflineCacheQueueSelectionToolbar: View {
    let viewModel: MineHomeViewModel

    var body: some View {
        MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
}

private struct MineOfflineCacheQueueSelectionActionBar: View {
    let viewModel: MineHomeViewModel
    var ownerName: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer(minLength: 0)
                MineOfflineCacheQueueCancelSelectionButton(viewModel: viewModel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}

private struct MineOfflineCacheQueueControls: View {
    let viewModel: MineHomeViewModel

    var body: some View {
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
        .disabled(viewModel.isOfflineCacheQueueCommandRunning)
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

private struct MineOfflineCacheQueueOwnerSheet: View {
    let viewModel: MineHomeViewModel
    let ownerName: String
    @Environment(\.dismiss) private var dismiss

    private var group: MineOfflineCacheQueueOwnerGroup? {
        viewModel.offlineCacheQueueGroups.first { $0.ownerName == ownerName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let group {
                        if viewModel.showsOfflineCacheQueueControls {
                            MineOfflineCacheQueueControls(viewModel: viewModel)
                        }

                        LazyVStack(spacing: 10) {
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
                        }
                    } else {
                        MineOfflineCacheQueueEmptyState()
                    }
                }
                .padding(16)
            }
            .background(YamiboColors.SystemSurface.groupedBackground)
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
                    if viewModel.isOfflineCacheQueueSelectionMode {
                        MineOfflineCacheQueueSelectAllButton(
                            viewModel: viewModel,
                            ownerName: ownerName
                        )
                    } else {
                        Button(L10n.string("common.close")) {
                            dismiss()
                        }
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

                #if os(iOS)
                if viewModel.isOfflineCacheQueueSelectionMode && usesSystemSelectionBottomToolbar {
                    ToolbarItem(placement: .bottomBar) {
                        MineOfflineCacheQueueSelectionToolbar(viewModel: viewModel)
                    }
                }
                #endif
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isOfflineCacheQueueSelectionMode && !usesSystemSelectionBottomToolbar {
                    MineOfflineCacheQueueSelectionActionBar(viewModel: viewModel, ownerName: ownerName)
                }
            }
            .overlay {
                if viewModel.isLoadingOfflineCacheQueue {
                    ProgressView()
                }
            }
            .sensoryFeedback(.selection, trigger: viewModel.selectedOfflineCacheWorkIDs)
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

private struct MineOfflineCacheQueueEmptyState: View {
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
