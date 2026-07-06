import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct NovelReaderCachePanel: View {
    @ObservedObject var model: NovelReaderViewModel
    let onShowProgress: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedViews: Set<Int> = []
    @State private var isQueuePresented = false
    @State private var queueViewModel: MineHomeViewModel

    init(model: NovelReaderViewModel, onShowProgress: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        self.onShowProgress = onShowProgress
        _queueViewModel = State(initialValue: model.makeOfflineCacheQueueViewModel())
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.string("reader.cache_scope")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.cacheScopeTitle)
                            .font(.headline)
                        Text(model.cacheScopeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.string("reader.select_page")) {
                    Button(selectionState.isAllSelected ? L10n.string("common.deselect_all") : L10n.string("common.select_all")) {
                        if selectionState.isAllSelected {
                            selectedViews = []
                        } else {
                            selectedViews = Set(model.allCacheableViews)
                        }
                    }
                    .disabled(model.allCacheableViews.isEmpty)

                    if model.allCacheableViews.isEmpty {
                        Text(L10n.string("reader.no_cacheable_pages"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.allCacheableViews, id: \.self) { view in
                            Button {
                                toggleSelection(for: view)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedViews.contains(view) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedViews.contains(view) ? Color.accentColor : Color.secondary)
                                    Text(L10n.string("reader.page_number_spaced", view))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    cacheStateLabel(for: view)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !selectedViews.isEmpty {
                    Section(L10n.string("reader.selected_content")) {
                        Text(L10n.string("reader.selected_pages", selectedViews.count))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.string("reader.cache_management"))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(L10n.string("common.close"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NovelReaderCacheQueueToolbarButton(
                        entryCount: model.cacheState.queueEntryCount,
                        action: showQueue
                    )
                }
            }
            .task {
                await model.refreshCachedState()
            }
            .sheet(isPresented: $isQueuePresented) {
                MineOfflineCacheQueueSheet(viewModel: queueViewModel)
            }
        }
    }

    private var selectionState: NovelReaderCacheSelectionState {
        model.cacheSelectionState(for: selectedViews)
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 12) {
                Button(L10n.string("reader.cache_action.cache")) {
                    model.startCaching(views: selectionState.uncachedSelectedViews)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!selectionState.canCache)

                Button(L10n.string("reader.cache_action.update")) {
                    model.updateCachedViews(selectionState.updatableSelectedViews)
                }
                .buttonStyle(.bordered)
                .disabled(!selectionState.canUpdate)

                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        await model.deleteCachedViews(selectionState.cachedSelectedViews)
                        selectedViews.subtract(selectionState.cachedSelectedViews)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!selectionState.canDelete)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func cacheStateLabel(for view: Int) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            switch model.cacheStatus(for: view) {
            case .caching:
                Label(L10n.string("reader.caching"), systemImage: "arrow.down.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .cached:
                Label(L10n.string("reader.cached"), systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.green)
            case .uncached:
                EmptyView()
            }

            if let updateTime = model.cacheUpdateTime(for: view) {
                Text(L10n.string("reader.cache_updated_at", updateTime.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleSelection(for view: Int) {
        if selectedViews.contains(view) {
            selectedViews.remove(view)
        } else {
            selectedViews.insert(view)
        }
    }

    private func showQueue() {
        isQueuePresented = true
    }
}

private struct NovelReaderCacheQueueToolbarButton: View {
    let entryCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ReaderCacheDownloadQueueIcon(isActive: entryCount > 0)
                Text(verbatim: "\(entryCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 12, alignment: .trailing)
            }
            .frame(minWidth: 48, minHeight: 32, alignment: .center)
            .foregroundStyle(entryCount > 0 ? Color.accentColor : Color.secondary)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.string("reader.cache_queue_button_accessibility_format", entryCount)
        )
    }
}

struct NovelReaderCacheProgressSheet: View {
    @ObservedObject var model: NovelReaderViewModel
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView(value: progressValue)
                    .progressViewStyle(.linear)

                VStack(spacing: 10) {
                    Text(titleText)
                        .font(.title3.weight(.semibold))

                    Text(detailText)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if let summary = model.cacheState.operation.summaryMessage, model.cacheState.operation.isFinished {
                        Text(summary)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle(L10n.string("reader.cache_progress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if model.cacheState.operation.isFinished {
                            Button(L10n.string("common.done")) {
                                model.dismissCacheProgress()
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button(L10n.string("reader.run_in_background")) {
                                model.hideCacheProgress()
                                onClose()
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)

                            Button(L10n.string("common.stop"), role: .destructive) {
                                model.stopCaching()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var progressValue: Double {
        guard model.cacheState.operation.totalCount > 0 else { return 0 }
        return Double(model.cacheState.operation.completedCount) / Double(model.cacheState.operation.totalCount)
    }

    private var titleText: String {
        switch model.cacheState.operation.status {
        case .idle:
            return L10n.string("reader.cache_status.ready")
        case .running:
            return L10n.string("reader.cache_status.running")
        case .completed:
            return L10n.string("reader.cache_status.completed")
        case .cancelled:
            return L10n.string("reader.cache_status.cancelled")
        }
    }

    private var detailText: String {
        if model.cacheState.operation.isFinished {
            return L10n.string("reader.cache_detail.completed", model.cacheState.operation.completedCount, max(model.cacheState.operation.totalCount, 1))
        }

        if let currentView = model.cacheState.operation.currentView {
            return L10n.string("reader.cache_detail.running", currentView, model.cacheState.operation.completedCount, max(model.cacheState.operation.totalCount, 1))
        }

        return L10n.string("reader.cache_detail.ready")
    }
}
#endif
