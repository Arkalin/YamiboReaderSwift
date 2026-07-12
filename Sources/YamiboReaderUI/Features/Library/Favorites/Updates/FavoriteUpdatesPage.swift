import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import YamiboReaderCore

/// Dedicated favorite-updates page behind the favorites toolbar bell:
/// check controls, the automatic interval, notifications, and the detected
/// update events.
struct FavoriteUpdatesPage: View {
    @ObservedObject var updateMonitor: FavoriteUpdateMonitor
    let routes: LocalFavoritesRoutes
    let isEventVisible: (FavoriteUpdateEvent) -> Bool
    let onOpen: (FavoriteUpdateEvent) async -> Void

    @State private var selectedInterval: FavoriteUpdateCheckInterval = .off
    @State private var selectedMangaInterval: SmartMangaUpdateCheckInterval = .threeDays
    @State private var notificationsEnabled = false
    @State private var notificationsBlockedBySystem = false
    @State private var showsNotificationDeniedAlert = false

    var body: some View {
        List {
            statusSection
            intervalSection
            mangaIntervalSection
            notificationSection
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
            selectedMangaInterval = await updateMonitor.configuredMangaInterval() ?? .threeDays
            notificationsEnabled = await updateMonitor.notificationsEnabled()
            notificationsBlockedBySystem = await updateMonitor.notificationsBlockedBySystem()
        }
        .alert(
            L10n.string("favorites.updates.notifications_denied_title"),
            isPresented: $showsNotificationDeniedAlert
        ) {
            #if canImport(UIKit)
            Button(L10n.string("favorites.updates.notifications_open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            #endif
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("favorites.updates.notifications_denied_message"))
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
                    // Manual/foreground check: a larger non-tag directory cap
                    // than the background task's is safe here since the user
                    // is actively waiting on this run, not a tight
                    // BGAppRefreshTask execution budget.
                    Task { _ = await updateMonitor.startCheck(nonTagMangaDirectoryCheckCap: 3) }
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

    private var mangaIntervalSection: some View {
        Section {
            Picker(L10n.string("favorites.updates.manga_interval"), selection: $selectedMangaInterval) {
                ForEach(SmartMangaUpdateCheckInterval.allCases) { interval in
                    Text(interval.title)
                        .tag(interval)
                }
            }
            .onChange(of: selectedMangaInterval) { _, newValue in
                Task { await updateMonitor.setConfiguredMangaInterval(newValue) }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("favorites.updates.manga_interval_footer_read_required"))
                Text(L10n.string("favorites.updates.manga_interval_footer_mode_off"))
            }
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle(L10n.string("favorites.updates.notifications"), isOn: notificationsBinding)
        } footer: {
            if notificationsBlockedBySystem {
                Text(L10n.string("favorites.updates.notifications_blocked"))
            } else {
                Text(L10n.string("favorites.updates.notifications_footer"))
            }
        }
    }

    /// A custom binding (not `onChange`) so reverting a denied enable back to
    /// off doesn't re-enter the setter and re-trigger the alert.
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { requested in
                notificationsEnabled = requested
                Task {
                    let effective = await updateMonitor.setNotificationsEnabled(requested)
                    notificationsEnabled = effective
                    notificationsBlockedBySystem = await updateMonitor.notificationsBlockedBySystem()
                    if requested, !effective {
                        showsNotificationDeniedAlert = true
                    }
                }
            }
        )
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
