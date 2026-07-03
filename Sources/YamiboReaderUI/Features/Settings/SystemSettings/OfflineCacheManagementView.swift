import SwiftUI
import YamiboReaderCore

struct OfflineCacheManagementView: View {
    @ObservedObject var viewModel: SystemSettingsViewModel
    @State private var selectedGroupID: OfflineCacheGroupID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.offlineCacheManagementIsEmpty {
                    OfflineCacheManagementEmptyState()
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.offlineCacheManagementRows) { row in
                            OfflineCacheManagementGroupRowView(
                                row: row,
                                isSelecting: viewModel.isOfflineCacheManagementSelectionMode,
                                isSelected: viewModel.selectedOfflineCacheGroupIDs.contains(row.id),
                                open: {
                                    viewModel.setOfflineCacheManagementSelectionMode(false)
                                    selectedGroupID = row.id
                                },
                                select: {
                                    viewModel.toggleOfflineCacheManagementSelection(id: row.id)
                                },
                                delete: {
                                    viewModel.requestOfflineCacheGroupDeletion(id: row.id)
                                }
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(YamiboColors.SystemSurface.groupedBackground)
        .navigationTitle(L10n.string("settings.offline_cache.title"))
        .navigationBarBackButtonHidden(viewModel.isOfflineCacheManagementSelectionMode)
        .task {
            await viewModel.refreshOfflineCacheManagement()
        }
        .refreshable {
            await viewModel.refreshOfflineCacheManagement()
        }
        .sheet(isPresented: selectedGroupIsPresented) {
            if let selectedGroupID {
                OfflineCacheManagementGroupSheet(
                    viewModel: viewModel,
                    groupID: selectedGroupID
                )
            }
        }
        .toolbar {
            if viewModel.isOfflineCacheManagementSelectionMode {
                ToolbarItem(placement: .cancellationAction) {
                    OfflineCacheManagementSelectAllButton(viewModel: viewModel)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if !viewModel.offlineCacheManagementIsEmpty {
                    Button(
                        viewModel.isOfflineCacheManagementSelectionMode
                            ? L10n.string("common.done")
                            : L10n.string("common.select")
                    ) {
                        viewModel.setOfflineCacheManagementSelectionMode(
                            !viewModel.isOfflineCacheManagementSelectionMode
                        )
                    }
                    .disabled(viewModel.activeAction == .clearingOfflineCache)
                }
            }

            #if os(iOS)
            if viewModel.isOfflineCacheManagementSelectionMode && usesSystemSelectionBottomToolbar {
                ToolbarItem(placement: .bottomBar) {
                    OfflineCacheManagementSelectionToolbar(
                        actionState: viewModel.offlineCacheManagementSelectionActionState,
                        onDelete: viewModel.requestSelectedOfflineCacheGroupDeletion
                    )
                }
            }
            #endif
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isOfflineCacheManagementSelectionMode && !usesSystemSelectionBottomToolbar {
                OfflineCacheManagementSelectionActionBar(
                    actionState: viewModel.offlineCacheManagementSelectionActionState,
                    onDelete: viewModel.requestSelectedOfflineCacheGroupDeletion
                )
            }
        }
        .overlay {
            if viewModel.activeAction == .loading || viewModel.activeAction == .clearingOfflineCache {
                ProgressView(
                    viewModel.activeAction == .clearingOfflineCache
                        ? L10n.string("common.deleting")
                        : L10n.string("common.loading")
                )
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedOfflineCacheGroupIDs)
        .offlineCacheManagementAlert(viewModel: viewModel)
    }

    private var usesSystemSelectionBottomToolbar: Bool {
        #if os(iOS)
        if #available(iOS 26, *) {
            return true
        }
        #endif
        return false
    }

    private var selectedGroupIsPresented: Binding<Bool> {
        Binding(
            get: { selectedGroupID != nil },
            set: { isPresented in
                if !isPresented {
                    selectedGroupID = nil
                    viewModel.setOfflineCacheManagementSelectionMode(false)
                }
            }
        )
    }
}
