import SwiftUI
import YamiboReaderCore

/// Compact update-check status card pinned above the favorites list.
struct FavoriteUpdateStatusCard: View {
    let snapshot: FavoriteUpdateRunSnapshot
    let eventCount: Int
    let onOpenEvents: () -> Void
    let onOpenFilters: () -> Void
    let onStart: () -> Void
    let onInterrupt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusImageName)
                    .foregroundStyle(statusColor)
                    .font(.title3.weight(.semibold))
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(detailText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: onOpenFilters) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("favorites.updates.filters"))
            }

            ProgressView(value: progressValue)
                .opacity(snapshot.status == .running ? 1 : 0.65)

            HStack(spacing: 8) {
                Button(action: onOpenEvents) {
                    Label(L10n.string("favorites.updates.events_count", eventCount), systemImage: "bell")
                }
                .buttonStyle(.bordered)

                if snapshot.status == .running {
                    Button(role: .destructive, action: onInterrupt) {
                        Label(L10n.string("favorites.updates.interrupt"), systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: onStart) {
                        Label(L10n.string("favorites.updates.check"), systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressValue: Double {
        guard snapshot.totalCount > 0 else {
            return snapshot.status == .running ? 0.1 : 1
        }
        return min(1, Double(snapshot.completedCount + snapshot.skippedCount + snapshot.failedCount) / Double(snapshot.totalCount))
    }

    private var detailText: String {
        if let progress = snapshot.progress {
            return progress.displayText
        }
        return phaseTitle
    }

    private var phaseTitle: String {
        switch snapshot.phase {
        case .preparing:
            L10n.string("favorites.updates.preparing")
        case .checking:
            L10n.string("favorites.updates.checking")
        case .interrupted:
            L10n.string("favorites.updates.interrupted")
        case .failed:
            L10n.string("favorites.updates.failed")
        case .completed:
            L10n.string("favorites.updates.completed")
        case .canceled:
            L10n.string("favorites.updates.canceled")
        }
    }

    private var statusTitle: String {
        switch snapshot.status {
        case .running:
            L10n.string("favorites.updates.status.running")
        case .completed:
            L10n.string("favorites.updates.status.completed")
        case .failed:
            L10n.string("favorites.updates.status.failed")
        case .interrupted:
            L10n.string("favorites.updates.status.interrupted")
        case .canceled:
            L10n.string("favorites.updates.status.canceled")
        }
    }

    private var statusImageName: String {
        switch snapshot.status {
        case .running:
            "arrow.clockwise.circle"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .interrupted:
            "pause.circle"
        case .canceled:
            "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case .running:
            .accentColor
        case .completed:
            .green
        case .failed:
            .red
        case .interrupted, .canceled:
            .orange
        }
    }
}
