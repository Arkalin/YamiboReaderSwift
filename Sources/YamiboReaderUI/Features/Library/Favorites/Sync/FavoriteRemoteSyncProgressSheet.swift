import SwiftUI
import YamiboReaderCore

/// Detailed progress sheet for a remote favorite sync run. Also used from
/// system settings, which is why the actions are optional closures.
struct FavoriteRemoteSyncProgressSheet: View {
    let snapshot: FavoriteRemoteSyncSnapshot?
    var onResume: (() async -> String?)? = nil
    var onInterrupt: (() async -> Void)? = nil
    var onHide: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let snapshot {
                Section {
                    FavoriteRemoteSyncSummary(snapshot: snapshot)
                }

                Section(L10n.string("favorites.sync.progress.metrics")) {
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.target"), value: snapshot.targetCategoryName)
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.scanned"), value: "\(snapshot.scannedCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.imported"), value: "\(snapshot.importedCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.failed"), value: "\(snapshot.failedCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.marked_missing"), value: "\(snapshot.markedMissingCount)")
                    FavoriteRemoteSyncMetricRow(title: L10n.string("favorites.sync.progress.upload_pending"), value: "\(snapshot.uploadTargetCount)")
                }

                FavoriteRemoteSyncMessageSection(
                    title: L10n.string("favorites.sync.progress.logs"),
                    messages: snapshot.logMessages,
                    fallback: L10n.string("favorites.sync.progress.no_logs")
                )
                FavoriteRemoteSyncMessageSection(
                    title: L10n.string("favorites.sync.progress.warnings"),
                    messages: snapshot.warningMessages,
                    fallback: L10n.string("favorites.sync.progress.no_warnings")
                )
                FavoriteRemoteSyncMessageSection(
                    title: L10n.string("favorites.sync.progress.errors"),
                    messages: snapshot.errorMessages,
                    fallback: L10n.string("favorites.sync.progress.no_errors")
                )
            } else {
                ContentUnavailableView(L10n.string("favorites.sync.progress.empty"), systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .navigationTitle(L10n.string("favorites.sync.progress.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("common.close")) {
                    dismiss()
                }
            }
            if let snapshot, hasActions {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if snapshot.status == .running, let onInterrupt {
                            Button(role: .destructive) {
                                Task { await onInterrupt() }
                            } label: {
                                Label(L10n.string("favorites.sync.interrupt"), systemImage: "stop.circle")
                            }
                        } else if let onResume {
                            Button {
                                Task { _ = await onResume() }
                            } label: {
                                Label(L10n.string("favorites.sync.resume"), systemImage: "play.circle")
                            }
                        }
                        if let onHide {
                            Button {
                                Task {
                                    await onHide()
                                    dismiss()
                                }
                            } label: {
                                Label(L10n.string("favorites.sync.hide_card"), systemImage: "eye.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var hasActions: Bool {
        onResume != nil || onInterrupt != nil || onHide != nil
    }
}

private struct FavoriteRemoteSyncSummary: View {
    let snapshot: FavoriteRemoteSyncSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusTitle)
                    .font(.headline)
                Spacer()
                Text(snapshot.updatedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(snapshot.phase)
                .foregroundStyle(.secondary)
            if let total = snapshot.totalRemoteCount {
                ProgressView(value: Double(snapshot.scannedCount), total: Double(max(total, 1)))
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        switch snapshot.status {
        case .running:
            L10n.string("favorites.sync.status.running")
        case .completed:
            L10n.string("favorites.sync.status.completed")
        case .failed:
            L10n.string("favorites.sync.status.failed")
        case .interrupted:
            L10n.string("favorites.sync.status.interrupted")
        }
    }
}

private struct FavoriteRemoteSyncMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FavoriteRemoteSyncMessageSection: View {
    let title: String
    let messages: [String]
    let fallback: String

    var body: some View {
        Section(title) {
            if messages.isEmpty {
                Text(fallback)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    Text(message)
                }
            }
        }
    }
}
