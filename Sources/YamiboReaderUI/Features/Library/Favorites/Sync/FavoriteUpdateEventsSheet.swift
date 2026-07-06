import SwiftUI
import YamiboReaderCore

/// List of detected favorite updates with read and dismiss actions.
struct FavoriteUpdateEventsSheet: View {
    let events: [FavoriteUpdateEvent]
    let onMarkRead: (String) async -> Void
    let onDismiss: (String) async -> Void
    let onDismissAll: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView(L10n.string("favorites.updates.no_events"), systemImage: "bell")
            } else {
                ForEach(events) { event in
                    FavoriteUpdateEventRow(
                        event: event,
                        onMarkRead: {
                            await onMarkRead(event.id)
                        },
                        onDismiss: {
                            await onDismiss(event.id)
                        }
                    )
                }
            }
        }
        .navigationTitle(L10n.string("favorites.updates.events"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.string("common.close")) {
                    dismiss()
                }
            }
            if !events.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        Task { await onDismissAll() }
                    } label: {
                        Label(L10n.string("favorites.updates.dismiss_all"), systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }
}

private struct FavoriteUpdateEventRow: View {
    let event: FavoriteUpdateEvent
    let onMarkRead: () async -> Void
    let onDismiss: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: event.readAt == nil ? "bell.badge" : "bell")
                    .foregroundStyle(event.readAt == nil ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                    Text(event.summary.displayText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let forumName = event.forumName {
                        Text(forumName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                Text(event.detectedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if event.readAt == nil {
                    Button {
                        Task { await onMarkRead() }
                    } label: {
                        Label(L10n.string("favorites.updates.mark_read"), systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    Task { await onDismiss() }
                } label: {
                    Label(L10n.string("favorites.updates.dismiss"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}
