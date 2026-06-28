import SwiftUI
import YamiboReaderCore

struct MineSettingsSection: View {
    let showSettings: () -> Void

    var body: some View {
        Section {
            MineEntryButtonRow(
                title: L10n.string("settings.title"),
                systemImage: "gearshape.fill",
                tint: .gray,
                action: showSettings
            )
        }
    }
}

struct MineCheckInSection: View {
    var body: some View {
        Section {
            MineEntryDisplayRow(
                title: L10n.string("mine.check_in"),
                systemImage: "checkmark.seal.fill",
                tint: .green
            )
        }
    }
}

struct MineLibraryEntriesSection: View {
    let offlineCacheQueueCount: Int
    let showOfflineCacheQueue: () -> Void

    var body: some View {
        Section {
            MineEntryDisplayRow(
                title: L10n.string("forum.history"),
                systemImage: "clock.arrow.circlepath",
                tint: .blue
            )
            MineEntryDisplayRow(
                title: L10n.string("mine.my_likes"),
                systemImage: "heart.fill",
                tint: .pink
            )
            MineEntryButtonRow(
                title: L10n.string("mine.download_queue"),
                systemImage: "arrow.down.circle.fill",
                tint: .indigo,
                badgeText: String(offlineCacheQueueCount),
                action: showOfflineCacheQueue
            )
        }
    }
}

private struct MineEntryDisplayRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        MineEntryRowContent(title: title, systemImage: systemImage, tint: tint)
    }
}

private struct MineEntryButtonRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MineEntryRowContent(title: title, systemImage: systemImage, tint: tint, badgeText: badgeText)
        }
        .buttonStyle(.plain)
    }
}

private struct MineEntryRowContent: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeText: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if let badgeText {
                Text(badgeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
