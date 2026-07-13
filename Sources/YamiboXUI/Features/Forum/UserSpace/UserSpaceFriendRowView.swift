import SwiftUI
import YamiboReaderCore

struct UserSpaceFriendRowView: View {
    let friend: UserSpaceFriendSummary
    let onPrivateMessageTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                friendContent
            }
            .buttonStyle(.plain)

            if friend.privateMessageURL != nil || friend.deleteURL != nil {
                VStack(spacing: 6) {
                    if friend.privateMessageURL != nil {
                        Button {
                            onPrivateMessageTap(friend.uid, friend.name)
                        } label: {
                            Text(L10n.string("user_space.send_message"))
                        }
                        .tint(ForumColors.brownEmphasis)
                    }
                    if let deleteURL = friend.deleteURL {
                        Button(role: .destructive) {
                            onWebTap(deleteURL)
                        } label: {
                            Text(L10n.string("common.delete"))
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(13)
        .forumCardBackground()
    }

    private var friendContent: some View {
        HStack(spacing: 10) {
            YamiboRemoteImage(source: friend.avatarURL.map { YamiboImageSource(url: $0) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(ForumColors.secondaryText)
            } failure: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(ForumColors.secondaryText)
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForumColors.textDark)
                if let detail = friend.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ForumColors.secondaryText)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }
}
