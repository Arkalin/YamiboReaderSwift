import SwiftUI
import YamiboReaderCore

/// Dedicated favorite-updates page behind the favorites toolbar bell:
/// check controls, the automatic interval, and the detected update events.
struct FavoriteUpdatesPage: View {
    @ObservedObject var updateMonitor: FavoriteUpdateMonitor
    let routes: LocalFavoritesRoutes
    let isEventVisible: (FavoriteUpdateEvent) -> Bool
    let onOpen: (FavoriteUpdateEvent) async -> Void

    @State private var selectedInterval: FavoriteUpdateCheckInterval = .off

    var body: some View {
        List {
            statusSection
            intervalSection
            eventsSection
        }
        .navigationTitle(L10n.string("favorites.updates.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    routes.sheet = .updateFilters
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel(L10n.string("favorites.updates.filters"))
            }
        }
        .task {
            selectedInterval = await updateMonitor.configuredInterval() ?? .off
        }
    }

    private var statusSection: some View {
        Section {
            if let snapshot = updateMonitor.snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.status.displayTitle)
                        .font(.subheadline.weight(.semibold))
                    if let progress = snapshot.progress {
                        Text(progress.displayText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let finishedAt = snapshot.finishedAt {
                        Text(L10n.string("favorites.updates.last_checked", LocalFavoriteRelativeDate.string(from: finishedAt)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(L10n.string("favorites.updates.run_counts", snapshot.completedCount, snapshot.totalCount, snapshot.detectedCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            if updateMonitor.snapshot?.status == .running {
                Button(role: .destructive) {
                    Task { await updateMonitor.interrupt() }
                } label: {
                    Label(L10n.string("favorites.updates.interrupt"), systemImage: "stop.circle")
                }
            } else {
                Button {
                    Task { _ = await updateMonitor.startCheck() }
                } label: {
                    Label(L10n.string("favorites.updates.check"), systemImage: "arrow.clockwise.circle")
                }
            }
        }
    }

    private var intervalSection: some View {
        Section {
            Picker(L10n.string("favorites.updates.interval"), selection: $selectedInterval) {
                ForEach(FavoriteUpdateCheckInterval.allCases) { interval in
                    Text(interval.title)
                        .tag(interval)
                }
            }
            .onChange(of: selectedInterval) { _, newValue in
                Task { await updateMonitor.setConfiguredInterval(newValue) }
            }
        } footer: {
            Text(L10n.string("favorites.updates.interval_footer"))
        }
    }

    private var visibleEvents: [FavoriteUpdateEvent] {
        updateMonitor.events.filter(isEventVisible)
    }

    @ViewBuilder
    private var eventsSection: some View {
        Section {
            let events = visibleEvents
            if events.isEmpty {
                Text(L10n.string("favorites.updates.no_events"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    FavoriteUpdateEventRow(
                        event: event,
                        onOpen: {
                            await onOpen(event)
                        },
                        onMarkRead: {
                            await updateMonitor.markEventRead(event.id)
                        },
                        onDismiss: {
                            await updateMonitor.dismissEvent(event.id)
                        }
                    )
                }
            }
        } header: {
            HStack {
                Text(L10n.string("favorites.updates.events"))
                Spacer()
                if !visibleEvents.isEmpty {
                    Button(L10n.string("favorites.updates.dismiss_all")) {
                        Task { await updateMonitor.dismissAllEvents() }
                    }
                    .font(.footnote)
                }
            }
        }
    }
}

extension FavoriteUpdateRunStatus {
    var displayTitle: String {
        switch self {
        case .running:
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
}
