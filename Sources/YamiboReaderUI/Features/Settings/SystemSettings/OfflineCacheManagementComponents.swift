import SwiftUI
import YamiboReaderCore

struct OfflineCacheManagementGroupSheet: View {
    @ObservedObject var viewModel: SystemSettingsViewModel
    let groupID: OfflineCacheGroupID
    @Environment(\.dismiss) private var dismiss

    private var row: OfflineCacheManagementRow? {
        viewModel.offlineCacheManagementRow(id: groupID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let row {
                        ForEach(row.entries) { entry in
                            OfflineCacheManagementEntryRowView(entry: entry) {
                                viewModel.requestOfflineCacheEntryDeletion(id: entry.id)
                            }
                        }
                    } else {
                        OfflineCacheManagementEmptyState()
                    }
                }
                .padding(16)
            }
            .background(YamiboColors.SystemSurface.groupedBackground)
            .navigationTitle(row?.title ?? L10n.string("settings.offline_cache.title"))
            .task {
                await viewModel.refreshOfflineCacheManagement()
                dismissIfGroupMissing()
            }
            .refreshable {
                await viewModel.refreshOfflineCacheManagement()
                dismissIfGroupMissing()
            }
            .onChange(of: viewModel.offlineCacheManagementRows) {
                dismissIfGroupMissing()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if viewModel.activeAction == .loading || viewModel.activeAction == .clearingOfflineCache {
                    ProgressView()
                }
            }
            .offlineCacheManagementAlert(viewModel: viewModel)
        }
    }

    private func dismissIfGroupMissing() {
        if row == nil {
            dismiss()
        }
    }
}

struct OfflineCacheManagementGroupRowView: View {
    let row: OfflineCacheManagementRow
    let isSelecting: Bool
    let isSelected: Bool
    let open: () -> Void
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.readerKind == .manga ? "photo.on.rectangle.angled" : "text.book.closed.fill")
                .foregroundStyle(isDimmed ? Color.secondary.opacity(0.55) : Color.indigo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .foregroundStyle(titleColor)
                    .lineLimit(2)

                Text(row.summaryText)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(2)
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
            open()
        }
    }
}

private struct OfflineCacheManagementEntryRowView: View {
    let entry: OfflineCacheManagementEntry
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.image")
                .foregroundStyle(entry.state == .failed ? Color.red : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(entrySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(YamiboColors.SystemSurface.secondaryGroupedBackground)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete()
            } label: {
                Label(L10n.string("common.delete"), systemImage: "trash")
            }
        }
    }

    private var entrySummary: String {
        [
            stateTitle,
            byteCountLabel
        ].joined(separator: " · ")
    }

    private var byteCountLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(max(0, entry.byteCount)))
    }

    private var stateTitle: String {
        switch entry.state {
        case .cached:
            L10n.string("settings.offline_cache.state.cached")
        case .queued:
            L10n.string("settings.offline_cache.state.queued")
        case .running:
            L10n.string("settings.offline_cache.state.running")
        case .paused:
            L10n.string("settings.offline_cache.state.paused")
        case .failed:
            L10n.string("settings.offline_cache.state.failed")
        }
    }
}

struct OfflineCacheManagementSelectAllButton: View {
    let viewModel: SystemSettingsViewModel

    var body: some View {
        Button(title) {
            viewModel.toggleAllOfflineCacheManagementRows()
        }
        .disabled(viewModel.offlineCacheManagementIsEmpty)
        .accessibilityLabel(title)
    }

    private var title: String {
        viewModel.isOfflineCacheManagementSelectionComplete
            ? L10n.string("common.invert_selection")
            : L10n.string("common.select_all")
    }
}

private struct OfflineCacheManagementDeleteSelectionButton: View {
    let actionState: OfflineCacheManagementSelectionActionState
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
                "settings.offline_cache.delete_selected_format",
                actionState.selectedGroupCount
            )
        )
    }
}

struct OfflineCacheManagementSelectionToolbar: View {
    let actionState: OfflineCacheManagementSelectionActionState
    let onDelete: () -> Void

    var body: some View {
        OfflineCacheManagementDeleteSelectionButton(
            actionState: actionState,
            onDelete: onDelete
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct OfflineCacheManagementSelectionActionBar: View {
    let actionState: OfflineCacheManagementSelectionActionState
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Spacer(minLength: 0)
                OfflineCacheManagementDeleteSelectionButton(
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

struct OfflineCacheManagementEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(L10n.string("settings.offline_cache.empty_title"))
                .font(.headline)

            Text(L10n.string("settings.offline_cache.empty_message"))
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

private struct OfflineCacheManagementAlertModifier: ViewModifier {
    @ObservedObject var viewModel: SystemSettingsViewModel

    func body(content: Content) -> some View {
        content
            .alert(
                viewModel.pendingOfflineCacheManagementConfirmation?.title ?? "",
                isPresented: confirmationIsPresented,
                presenting: viewModel.pendingOfflineCacheManagementConfirmation
            ) { confirmation in
                Button(L10n.string("common.delete"), role: .destructive) {
                    Task {
                        _ = await viewModel.confirmOfflineCacheManagementDeletion(confirmation)
                    }
                }
                Button(L10n.string("common.cancel"), role: .cancel) {
                    viewModel.cancelOfflineCacheManagementConfirmation()
                }
            } message: { confirmation in
                Text(confirmation.message)
            }
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingOfflineCacheManagementConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    Task { @MainActor in
                        viewModel.cancelOfflineCacheManagementConfirmation()
                    }
                }
            }
        )
    }
}

extension View {
    func offlineCacheManagementAlert(viewModel: SystemSettingsViewModel) -> some View {
        modifier(OfflineCacheManagementAlertModifier(viewModel: viewModel))
    }
}
