import SwiftUI
import YamiboReaderCore

struct MessageCenterView: View {
    @State private var model: MessageCenterViewModel

    let onPrivateMessageTap: (String, String?) -> Void
    let onUserTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    init(
        model: MessageCenterViewModel,
        onPrivateMessageTap: @escaping (String, String?) -> Void,
        onUserTap: @escaping (String, String?) -> Void,
        onWebTap: @escaping (URL) -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onPrivateMessageTap = onPrivateMessageTap
        self.onUserTap = onUserTap
        self.onWebTap = onWebTap
    }

    var body: some View {
        MessageCenterBodyView(
            selectedTab: model.selectedTab,
            content: model.content,
            pageNavigation: model.pageNavigation,
            currentPage: model.currentPage,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            selectTab: selectTab,
            refresh: refresh,
            retry: retry,
            goToPage: goToPage,
            onPrivateMessageTap: onPrivateMessageTap,
            onUserTap: onUserTap
        )
        .navigationTitle(model.navigationTitle)
        .toolbar {
            if model.selectedTab == .privateMessages {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onWebTap(YamiboRoute.userSpaceSendPrivateMessage.url)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(L10n.string("message_center.compose_private_message"))
                }
            }
        }
        .task {
            await model.load()
        }
    }

    private func selectTab(_ tab: MessageCenterTab) {
        Task {
            await model.selectTab(tab)
        }
    }

    private func refresh() async {
        await model.refresh()
    }

    private func retry() {
        Task {
            await model.refresh()
        }
    }

    private func goToPage(_ page: Int) {
        Task {
            await model.goToPage(page)
        }
    }
}

private struct MessageCenterBodyView: View {
    let selectedTab: MessageCenterTab
    let content: MessageCenterViewModel.Content?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let isLoading: Bool
    let errorMessage: String?
    let selectTab: (MessageCenterTab) -> Void
    let refresh: () async -> Void
    let retry: () -> Void
    let goToPage: (Int) -> Void
    let onPrivateMessageTap: (String, String?) -> Void
    let onUserTap: (String, String?) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                MessageCenterTabPickerView(selectedTab: selectedTab, selectTab: selectTab)

                if let errorMessage, content == nil {
                    MessageCenterErrorView(message: errorMessage, retry: retry)
                } else if isLoading && content == nil {
                    MessageCenterLoadingView()
                } else {
                    MessageCenterContentView(
                        selectedTab: selectedTab,
                        content: content,
                        pageNavigation: pageNavigation,
                        currentPage: currentPage,
                        goToPage: goToPage,
                        onPrivateMessageTap: onPrivateMessageTap,
                        onUserTap: onUserTap
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .refreshable {
            await refresh()
        }
        .overlay(alignment: .top) {
            if isLoading && content != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
    }
}

private struct MessageCenterTabPickerView: View {
    let selectedTab: MessageCenterTab
    let selectTab: (MessageCenterTab) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MessageCenterTab.allCases, id: \.self) { tab in
                Button {
                    selectTab(tab)
                } label: {
                    Text(MessageCenterViewModel.title(for: tab))
                        .font(.footnote.weight(tab == selectedTab ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .foregroundStyle(tab == selectedTab ? ForumColors.textDark : ForumColors.secondaryText)
                        .background(Capsule().fill(tab == selectedTab ? ForumColors.accentFill : ForumColors.mutedFill))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MessageCenterContentView: View {
    let selectedTab: MessageCenterTab
    let content: MessageCenterViewModel.Content?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let goToPage: (Int) -> Void
    let onPrivateMessageTap: (String, String?) -> Void
    let onUserTap: (String, String?) -> Void

    var body: some View {
        switch selectedTab {
        case .privateMessages:
            if case let .privateMessages(page) = content {
                if page.messages.isEmpty {
                    MessageCenterEmptyView(message: L10n.string("message_center.empty_private_messages"))
                } else {
                    ForEach(page.messages) { message in
                        MessageCenterPrivateMessageRowView(
                            message: message,
                            onUserTap: onUserTap
                        ) {
                            onPrivateMessageTap(message.uid, message.name)
                        }
                    }
                    MessageCenterPageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
                }
            }
        case .notices:
            if case let .notices(page) = content {
                if page.notices.isEmpty {
                    MessageCenterEmptyView(message: L10n.string("message_center.empty_notices"))
                } else {
                    ForEach(page.notices) { notice in
                        MessageCenterNoticeRowView(notice: notice, onUserTap: onUserTap)
                    }
                    MessageCenterPageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
                }
            }
        }
    }
}

private struct MessageCenterPrivateMessageRowView: View {
    let message: UserSpacePrivateMessageSummary
    let onUserTap: (String, String?) -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onUserTap(message.uid, message.name)
            } label: {
                MessageCenterAvatarView(url: message.avatarURL, systemImage: "person.crop.circle")
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(message.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ForumColors.textDark)
                            .lineLimit(1)
                        if let unreadCount = message.unreadCount {
                            Text(String(unreadCount))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(ForumColors.redAccent, in: Capsule())
                        }
                    }
                    Text(message.message)
                        .font(.caption)
                        .foregroundStyle(ForumColors.secondaryText)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if let timeText = message.timeText {
                Text(timeText)
                    .font(.caption2)
                    .foregroundStyle(ForumColors.brownLight)
                    .lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }
}

private struct MessageCenterNoticeRowView: View {
    let notice: UserSpaceNoticeSummary
    let onUserTap: (String, String?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let userID = notice.userID {
                Button {
                    onUserTap(userID, nil)
                } label: {
                    MessageCenterAvatarView(url: notice.avatarURL, systemImage: "bell")
                }
                .buttonStyle(.plain)
            } else {
                MessageCenterAvatarView(url: notice.avatarURL, systemImage: "bell")
            }

            VStack(alignment: .leading, spacing: 7) {
                if let timeText = notice.timeText {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(ForumColors.brownLight)
                }
                Text(notice.contentText)
                    .font(.subheadline)
                    .foregroundStyle(ForumColors.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                if let quote = notice.quote {
                    Text(quote)
                        .font(.caption)
                        .foregroundStyle(ForumColors.secondaryText)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ForumColors.mutedFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }
}

private struct MessageCenterAvatarView: View {
    let url: URL?
    let systemImage: String

    var body: some View {
        YamiboRemoteImage(source: url.map { YamiboImageSource(url: $0) }) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(ForumColors.secondaryText)
        } failure: {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }
}

private struct MessageCenterPageNavigationView: View {
    let navigation: ForumPageNavigation?
    let currentPage: Int
    let goToPage: (Int) -> Void

    var body: some View {
        if let navigation {
            HStack(spacing: 12) {
                Button {
                    goToPage(currentPage - 1)
                } label: {
                    Label(L10n.string("forum.board.previous_page"), systemImage: "chevron.left")
                }
                .disabled(currentPage <= 1)

                Spacer()

                Text(pageText(navigation))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ForumColors.secondaryText)

                Spacer()

                Button {
                    goToPage(currentPage + 1)
                } label: {
                    Label(L10n.string("forum.board.next_page"), systemImage: "chevron.right")
                }
                .disabled(navigation.totalPages.map { currentPage >= $0 } ?? false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(ForumColors.brownEmphasis)
            .padding(.top, 4)
        }
    }

    private func pageText(_ navigation: ForumPageNavigation) -> String {
        if let totalPages = navigation.totalPages {
            return L10n.string("forum.board.page_count", currentPage, totalPages)
        }
        return L10n.string("forum.board.current_page", currentPage)
    }
}

private struct MessageCenterLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("common.loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct MessageCenterErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(L10n.string("common.load_failed"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.string("common.retry"), action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct MessageCenterEmptyView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(message, systemImage: "tray")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
    }
}
