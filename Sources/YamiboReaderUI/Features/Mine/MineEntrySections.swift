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
    let isLoggedIn: Bool
    let isCheckingIn: Bool
    let hasCheckedInToday: Bool
    let isInteractionDisabled: Bool
    let checkIn: () -> Void

    var body: some View {
        Section {
            MineEntryButtonRow(
                title: title,
                systemImage: "checkmark.seal.fill",
                tint: .green,
                showsProgress: isCheckingIn,
                showsDisclosureIndicator: !hasCheckedInToday,
                action: checkIn
            )
            .disabled(isInteractionDisabled || hasCheckedInToday)
            .accessibilityHint(
                accessibilityHint
            )
        }
    }

    private var title: String {
        if isCheckingIn {
            L10n.string("mine.checking_in")
        } else if hasCheckedInToday {
            L10n.string("yamibo_check_in.already_checked_in_today")
        } else {
            L10n.string("mine.check_in")
        }
    }

    private var accessibilityHint: String {
        if hasCheckedInToday {
            L10n.string("mine.check_in_checked_hint")
        } else if isLoggedIn {
            L10n.string("mine.check_in_hint")
        } else {
            L10n.string("mine.check_in_login_hint")
        }
    }
}

struct MineLibraryEntriesSection: View {
    let offlineCacheQueueCount: Int
    let showMessages: () -> Void
    let showOfflineCacheQueue: () -> Void
    let showMyLikes: () -> Void
    let showHistory: () -> Void

    var body: some View {
        Section {
            MineEntryButtonRow(
                title: L10n.string("message_center.private_messages"),
                systemImage: "envelope.fill",
                tint: .orange,
                action: showMessages
            )
            MineEntryButtonRow(
                title: L10n.string("forum.history"),
                systemImage: "clock.arrow.circlepath",
                tint: .blue,
                action: showHistory
            )
            MineEntryButtonRow(
                title: L10n.string("mine.my_likes"),
                systemImage: "heart.fill",
                tint: .pink,
                action: showMyLikes
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

private struct MineEntryButtonRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeText: String? = nil
    var showsProgress = false
    var showsDisclosureIndicator = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MineEntryRowContent(
                title: title,
                systemImage: systemImage,
                tint: tint,
                badgeText: badgeText,
                showsProgress: showsProgress,
                showsDisclosureIndicator: showsDisclosureIndicator
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MineEntryRowContent: View {
    let title: String
    let systemImage: String
    let tint: Color
    var badgeText: String? = nil
    var showsProgress = false
    var showsDisclosureIndicator = true

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

            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
