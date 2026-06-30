import SwiftUI
import YamiboReaderCore

struct UserSpaceView: View {
    @State private var model: UserSpaceViewModel

    let onThreadTap: (URL, String?) -> Void
    let onUserTap: (String, String?) -> Void
    let onSectionTap: (String?, String?, UserSpaceSection, UserSpaceSubPage) -> Void
    let onBlogTap: (UserSpaceBlogSummary) -> Void
    let onPrivateMessageTap: (String, String?) -> Void
    let onMessageCenterTap: (MessageCenterTab) -> Void
    let onWebTap: (URL) -> Void

    init(
        model: UserSpaceViewModel,
        onThreadTap: @escaping (URL, String?) -> Void,
        onUserTap: @escaping (String, String?) -> Void,
        onSectionTap: @escaping (String?, String?, UserSpaceSection, UserSpaceSubPage) -> Void,
        onBlogTap: @escaping (UserSpaceBlogSummary) -> Void,
        onPrivateMessageTap: @escaping (String, String?) -> Void,
        onMessageCenterTap: @escaping (MessageCenterTab) -> Void,
        onWebTap: @escaping (URL) -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onThreadTap = onThreadTap
        self.onUserTap = onUserTap
        self.onSectionTap = onSectionTap
        self.onBlogTap = onBlogTap
        self.onPrivateMessageTap = onPrivateMessageTap
        self.onMessageCenterTap = onMessageCenterTap
        self.onWebTap = onWebTap
    }

    var body: some View {
        UserSpaceBodyView(
            profile: model.profile,
            selectedSubPage: model.selectedSubPage,
            availableSubPages: model.availableSubPages,
            viewAllBlogFilter: model.viewAllBlogFilter,
            content: model.content,
            pageNavigation: model.pageNavigation,
            currentPage: model.currentPage,
            isLoadingProfile: model.isLoadingProfile,
            isLoadingContent: model.isLoadingContent,
            isSelf: model.isSelf,
            errorMessage: model.errorMessage,
            selectSubPage: selectSubPage,
            selectViewAllBlogFilter: selectViewAllBlogFilter,
            beginAddFriend: beginAddFriend,
            refresh: refresh,
            retry: retry,
            goToPage: goToPage,
            onThreadTap: onThreadTap,
            onUserTap: onUserTap,
            onSectionTap: { section, subPage in
                onSectionTap(model.uid, model.profile?.username ?? model.titleHint, section, subPage)
            },
            onBlogTap: onBlogTap,
            onPrivateMessageTap: onPrivateMessageTap,
            onMessageCenterTap: onMessageCenterTap,
            onWebTap: onWebTap
        )
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
        .navigationTitle(model.navigationTitle)
        .toolbar {
            if model.canOpenBlogEditor {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onWebTap(YamiboRoute.userSpaceBlogEditor.url)
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(L10n.string("user_space.write_blog"))
                }
            }
        }
        .task {
            await model.load()
        }
        .sheet(isPresented: Binding(
            get: { model.isAddFriendSheetPresented },
            set: { isPresented in
                if !isPresented {
                    model.dismissAddFriend()
                }
            }
        )) {
            UserSpaceAddFriendSheet(
                targetName: model.addFriendTargetName,
                form: model.addFriendForm,
                isLoading: model.isLoadingAddFriendForm,
                isSubmitting: model.isSubmittingAddFriend,
                errorMessage: model.addFriendErrorMessage,
                retry: retryAddFriendForm,
                submit: submitAddFriend,
                dismiss: { model.dismissAddFriend() }
            )
        }
        .alert(
            L10n.string("user_space.add_friend_result"),
            isPresented: Binding(
                get: { model.addFriendResultMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearAddFriendResult()
                    }
                }
            )
        ) {
            Button(L10n.string("common.ok")) {
                model.clearAddFriendResult()
            }
        } message: {
            Text(model.addFriendResultMessage ?? "")
        }
    }

    private func selectSubPage(_ subPage: UserSpaceSubPage) {
        Task {
            await model.selectSubPage(subPage)
        }
    }

    private func selectViewAllBlogFilter(_ filter: UserSpaceViewAllBlogFilter) {
        Task {
            await model.selectViewAllBlogFilter(filter)
        }
    }

    private func beginAddFriend() {
        Task {
            await model.beginAddFriend()
        }
    }

    private func retryAddFriendForm() {
        Task {
            await model.retryAddFriendForm()
        }
    }

    private func submitAddFriend(_ note: String, _ groupID: Int) {
        Task {
            await model.submitAddFriend(note: note, groupID: groupID)
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

private struct UserSpaceBodyView: View {
    let profile: UserSpaceProfile?
    let selectedSubPage: UserSpaceSubPage
    let availableSubPages: [UserSpaceSubPage]
    let viewAllBlogFilter: UserSpaceViewAllBlogFilter
    let content: UserSpaceViewModel.Content?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let isLoadingProfile: Bool
    let isLoadingContent: Bool
    let isSelf: Bool
    let errorMessage: String?
    let selectSubPage: (UserSpaceSubPage) -> Void
    let selectViewAllBlogFilter: (UserSpaceViewAllBlogFilter) -> Void
    let beginAddFriend: () -> Void
    let refresh: () async -> Void
    let retry: () -> Void
    let goToPage: (Int) -> Void
    let onThreadTap: (URL, String?) -> Void
    let onUserTap: (String, String?) -> Void
    let onSectionTap: (UserSpaceSection, UserSpaceSubPage) -> Void
    let onBlogTap: (UserSpaceBlogSummary) -> Void
    let onPrivateMessageTap: (String, String?) -> Void
    let onMessageCenterTap: (MessageCenterTab) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if selectedSubPage == .profile {
                    UserSpaceProfileContentView(
                        profile: profile,
                        isSelf: isSelf,
                        isLoading: isLoadingProfile,
                        errorMessage: errorMessage,
                        onSectionTap: onSectionTap,
                        beginAddFriend: beginAddFriend,
                        onMessageCenterTap: onMessageCenterTap,
                        retry: retry,
                        onWebTap: onWebTap
                    )
                } else {
                    UserSpaceSubPageContentView(
                        selectedSubPage: selectedSubPage,
                        availableSubPages: availableSubPages,
                        viewAllBlogFilter: viewAllBlogFilter,
                        content: content,
                        pageNavigation: pageNavigation,
                        currentPage: currentPage,
                        isLoadingContent: isLoadingContent,
                        errorMessage: errorMessage,
                        selectSubPage: selectSubPage,
                        selectViewAllBlogFilter: selectViewAllBlogFilter,
                        retry: retry,
                        goToPage: goToPage,
                        onThreadTap: onThreadTap,
                        onUserTap: onUserTap,
                        onBlogTap: onBlogTap,
                        onPrivateMessageTap: onPrivateMessageTap,
                        onWebTap: onWebTap
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
            if isLoadingContent && content != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
    }
}

private struct UserSpaceProfileContentView: View {
    let profile: UserSpaceProfile?
    let isSelf: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onSectionTap: (UserSpaceSection, UserSpaceSubPage) -> Void
    let beginAddFriend: () -> Void
    let onMessageCenterTap: (MessageCenterTab) -> Void
    let retry: () -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        if let profile {
            UserSpaceProfileHeaderView(
                profile: profile,
                isSelf: isSelf,
                onSectionTap: onSectionTap,
                beginAddFriend: beginAddFriend,
                onMessageCenterTap: onMessageCenterTap,
                onWebTap: onWebTap
            )
        } else if let errorMessage {
            UserSpaceErrorView(message: errorMessage, retry: retry)
        } else if isLoading {
            UserSpaceLoadingView()
        } else {
            UserSpaceLoadingView()
        }
    }
}

private struct UserSpaceSubPageContentView: View {
    let selectedSubPage: UserSpaceSubPage
    let availableSubPages: [UserSpaceSubPage]
    let viewAllBlogFilter: UserSpaceViewAllBlogFilter
    let content: UserSpaceViewModel.Content?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let isLoadingContent: Bool
    let errorMessage: String?
    let selectSubPage: (UserSpaceSubPage) -> Void
    let selectViewAllBlogFilter: (UserSpaceViewAllBlogFilter) -> Void
    let retry: () -> Void
    let goToPage: (Int) -> Void
    let onThreadTap: (URL, String?) -> Void
    let onUserTap: (String, String?) -> Void
    let onBlogTap: (UserSpaceBlogSummary) -> Void
    let onPrivateMessageTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        if availableSubPages.count > 1 {
            UserSpaceSubPagePickerView(
                subPages: availableSubPages,
                selectedSubPage: selectedSubPage,
                selectSubPage: selectSubPage
            )
        }

        if selectedSubPage == .viewAllBlogs {
            UserSpaceViewAllBlogFilterView(
                selectedFilter: viewAllBlogFilter,
                selectFilter: selectViewAllBlogFilter
            )
        }

        if let errorMessage, content == nil {
            UserSpaceErrorView(message: errorMessage, retry: retry)
        } else if isLoadingContent && content == nil {
            UserSpaceLoadingView()
        } else {
            UserSpaceContentView(
                selectedSubPage: selectedSubPage,
                content: content,
                pageNavigation: pageNavigation,
                currentPage: currentPage,
                goToPage: goToPage,
                onThreadTap: onThreadTap,
                onUserTap: onUserTap,
                onBlogTap: onBlogTap,
                onPrivateMessageTap: onPrivateMessageTap,
                onWebTap: onWebTap
            )
        }
    }
}

private struct UserSpaceProfileHeaderView: View {
    let profile: UserSpaceProfile
    let isSelf: Bool
    let onSectionTap: (UserSpaceSection, UserSpaceSubPage) -> Void
    let beginAddFriend: () -> Void
    let onMessageCenterTap: (MessageCenterTab) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                YamiboRemoteImage(url: profile.avatarBackgroundURL ?? profile.avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle().fill(ForumColors.brownDeep.opacity(0.24))
                } failure: {
                    Rectangle().fill(ForumColors.brownDeep.opacity(0.24))
                }
                .frame(height: 172)
                .clipped()

                Rectangle()
                    .fill(.black.opacity(0.38))

                VStack(spacing: 10) {
                    YamiboRemoteImage(url: profile.avatarURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.white.opacity(0.8))
                    } failure: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())

                    Text(profile.username)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 172)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            UserSpaceStatsView(profile: profile)
            UserSpaceActionGridView(
                isSelf: isSelf,
                onSectionTap: onSectionTap,
                beginAddFriend: beginAddFriend,
                onMessageCenterTap: onMessageCenterTap,
                onWebTap: onWebTap
            )

            if let signature = profile.signature {
                UserSpaceSignatureView(signature: signature)
            }

            UserSpaceInfoTableView(rows: profile.infoRows, onWebTap: onWebTap)
        }
    }
}

private struct UserSpaceActionGridView: View {
    let isSelf: Bool
    let onSectionTap: (UserSpaceSection, UserSpaceSubPage) -> Void
    let beginAddFriend: () -> Void
    let onMessageCenterTap: (MessageCenterTab) -> Void
    let onWebTap: (URL) -> Void

    private var actions: [UserSpaceProfileAction] {
        if isSelf {
            [
                UserSpaceProfileAction(section: .threads, subPage: .threads, icon: "text.bubble", titleKey: "user_space.my_threads"),
                UserSpaceProfileAction(section: .blogs, subPage: .friendBlogs, icon: "book.pages", titleKey: "user_space.my_blogs"),
                UserSpaceProfileAction(section: .friends, subPage: .friends, icon: "person.2", titleKey: "user_space.my_friends"),
                UserSpaceProfileAction(messageCenterTab: .privateMessages, icon: "bell.badge", titleKey: "user_space.message_alerts")
            ]
        } else {
            [
                UserSpaceProfileAction(section: .threads, subPage: .threads, icon: "text.bubble", titleKey: "user_space.other_threads"),
                UserSpaceProfileAction(section: .blogs, subPage: .myBlogs, icon: "book.pages", titleKey: "user_space.other_blogs"),
                UserSpaceProfileAction(section: .threads, subPage: .replies, icon: "arrowshape.turn.up.left", titleKey: "user_space.other_replies"),
                UserSpaceProfileAction(subPage: nil, icon: "person.badge.plus", titleKey: "user_space.add_friend")
            ]
        }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(actions) { action in
                Button {
                    if let section = action.section, let subPage = action.subPage {
                        onSectionTap(section, subPage)
                    } else if let messageCenterTab = action.messageCenterTab {
                        onMessageCenterTap(messageCenterTab)
                    } else if let webURL = action.webURL {
                        onWebTap(webURL)
                    } else {
                        beginAddFriend()
                    }
                } label: {
                    Label(L10n.string(action.titleKey), systemImage: action.icon)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .tint(ForumColors.brownEmphasis)
            }
        }
        .padding(13)
        .forumCardBackground()
        .padding(.top, 10)
    }

}

private struct UserSpaceProfileAction: Identifiable {
    let section: UserSpaceSection?
    let subPage: UserSpaceSubPage?
    let webURL: URL?
    let messageCenterTab: MessageCenterTab?
    let icon: String
    let titleKey: String

    init(
        section: UserSpaceSection? = nil,
        subPage: UserSpaceSubPage? = nil,
        webURL: URL? = nil,
        messageCenterTab: MessageCenterTab? = nil,
        icon: String,
        titleKey: String
    ) {
        self.section = section
        self.subPage = subPage
        self.webURL = webURL
        self.messageCenterTab = messageCenterTab
        self.icon = icon
        self.titleKey = titleKey
    }

    var id: String {
        [section?.rawValue, subPage?.rawValue, webURL?.absoluteString, messageCenterTab?.rawValue, titleKey]
            .compactMap { $0 }
            .joined(separator: "|")
    }
}

private struct UserSpaceStatsView: View {
    let profile: UserSpaceProfile

    var body: some View {
        HStack(spacing: 0) {
            UserSpaceStatView(label: L10n.string("user_space.total_points"), value: profile.totalPoints.map(String.init) ?? "-")
            UserSpaceStatView(label: L10n.string("user_space.points"), value: profile.points.map(String.init) ?? "-")
            UserSpaceStatView(label: L10n.string("user_space.partner"), value: profile.partner.map(String.init) ?? "-")
        }
        .padding(.vertical, 12)
        .forumCardBackground()
        .padding(.top, 10)
    }
}

private struct UserSpaceStatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(ForumColors.textDark)
            Text(label)
                .font(.caption)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UserSpaceSignatureView: View {
    let signature: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("user_space.signature"))
                .font(.headline)
                .foregroundStyle(ForumColors.brownPrimary)
            Text(signature)
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
        .padding(.top, 10)
    }
}

private struct UserSpaceInfoTableView: View {
    let rows: [UserSpaceInfoRow]
    let onWebTap: (URL) -> Void

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("user_space.profile"))
                    .font(.headline)
                    .foregroundStyle(ForumColors.brownPrimary)
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(ForumColors.secondaryText)
                        Spacer(minLength: 8)
                        if let url = row.url {
                            Button(row.value) {
                                onWebTap(url)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(ForumColors.brownPrimary)
                        } else {
                            Text(row.value)
                                .foregroundStyle(ForumColors.textDark)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .font(.subheadline)
                    Divider()
                }
            }
            .padding(13)
            .forumCardBackground()
            .padding(.top, 10)
        }
    }
}

private struct UserSpaceSubPagePickerView: View {
    let subPages: [UserSpaceSubPage]
    let selectedSubPage: UserSpaceSubPage
    let selectSubPage: (UserSpaceSubPage) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(subPages, id: \.self) { subPage in
                    Button {
                        selectSubPage(subPage)
                    } label: {
                        Text(title(for: subPage))
                            .font(.footnote.weight(subPage == selectedSubPage ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .foregroundStyle(subPage == selectedSubPage ? ForumColors.textDark : ForumColors.secondaryText)
                            .background(Capsule().fill(subPage == selectedSubPage ? ForumColors.accentFill : ForumColors.mutedFill))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func title(for subPage: UserSpaceSubPage) -> String {
        switch subPage {
        case .profile:
            L10n.string("user_space.profile")
        case .threads:
            L10n.string("user_space.my_threads")
        case .replies:
            L10n.string("user_space.my_replies")
        case .myBlogs:
            L10n.string("user_space.my_blogs")
        case .friendBlogs:
            L10n.string("user_space.friend_blogs")
        case .viewAllBlogs:
            L10n.string("user_space.view_all_blogs")
        case .friends:
            L10n.string("user_space.my_friends")
        case .online:
            L10n.string("user_space.online")
        case .visitors:
            L10n.string("user_space.visitors")
        case .traces:
            L10n.string("user_space.traces")
        }
    }
}

private struct UserSpaceViewAllBlogFilterView: View {
    let selectedFilter: UserSpaceViewAllBlogFilter
    let selectFilter: (UserSpaceViewAllBlogFilter) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(UserSpaceViewAllBlogFilter.allCases, id: \.self) { filter in
                Button {
                    selectFilter(filter)
                } label: {
                    Text(title(for: filter))
                        .font(.footnote.weight(filter == selectedFilter ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
                .buttonStyle(.bordered)
                .tint(filter == selectedFilter ? ForumColors.brownEmphasis : ForumColors.brownLight)
            }
        }
    }

    private func title(for filter: UserSpaceViewAllBlogFilter) -> String {
        switch filter {
        case .latest:
            L10n.string("user_space.blog_filter_latest")
        case .hot:
            L10n.string("user_space.blog_filter_hot")
        }
    }
}

private struct UserSpaceContentView: View {
    let selectedSubPage: UserSpaceSubPage
    let content: UserSpaceViewModel.Content?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let goToPage: (Int) -> Void
    let onThreadTap: (URL, String?) -> Void
    let onUserTap: (String, String?) -> Void
    let onBlogTap: (UserSpaceBlogSummary) -> Void
    let onPrivateMessageTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        switch selectedSubPage {
        case .profile:
            EmptyView()
        case .threads:
            if case let .threads(page) = content {
                if page.threads.isEmpty {
                    UserSpaceEmptyView(message: L10n.string("user_space.empty_threads"))
                } else {
                    ForEach(page.threads) { thread in
                        ForumThreadSummaryRowView(
                            thread: thread,
                            onThreadTap: { onThreadTap(thread.url, thread.title) },
                            onAuthorTap: onUserTap
                        )
                    }
                    UserSpacePageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
                }
            }
        case .replies:
            if case let .replies(page) = content {
                if page.replies.isEmpty {
                    UserSpaceEmptyView(message: L10n.string("user_space.empty_replies"))
                } else {
                    ForEach(page.replies) { reply in
                        UserSpaceReplyRowView(reply: reply) {
                            onThreadTap(reply.threadURL, reply.threadTitle)
                        }
                    }
                    UserSpacePageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
                }
            }
        case .myBlogs, .friendBlogs, .viewAllBlogs:
            if case let .blogs(page) = content {
                if page.blogs.isEmpty {
                    UserSpaceEmptyView(message: L10n.string("user_space.empty_blogs"))
                } else {
                    ForEach(page.blogs) { blog in
                        UserSpaceBlogRowView(blog: blog, onUserTap: onUserTap) {
                            onBlogTap(blog)
                        }
                    }
                    UserSpacePageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
                }
            }
        case .friends, .online, .visitors, .traces:
            if case let .friends(page) = content {
                if page.friends.isEmpty {
                    UserSpaceEmptyView(message: emptyFriendsMessage)
                } else {
                    ForEach(page.friends) { friend in
                        UserSpaceFriendRowView(
                            friend: friend,
                            onPrivateMessageTap: onPrivateMessageTap,
                            onWebTap: onWebTap
                        ) {
                            onUserTap(friend.uid, friend.name)
                        }
                    }
                    UserSpacePageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
                }
            }
        }
    }

    private var emptyFriendsMessage: String {
        switch selectedSubPage {
        case .online:
            L10n.string("user_space.empty_online")
        case .visitors:
            L10n.string("user_space.empty_visitors")
        case .traces:
            L10n.string("user_space.empty_traces")
        default:
            L10n.string("user_space.empty_friends")
        }
    }
}

private struct UserSpaceReplyRowView: View {
    let reply: UserSpaceReplyGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(reply.threadTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ForumColors.textDark)
                if let excerpt = reply.excerpt {
                    Text(excerpt)
                        .font(.subheadline)
                        .foregroundStyle(ForumColors.secondaryText)
                        .lineLimit(3)
                }
                if let lastActivityText = reply.lastActivityText {
                    Text(lastActivityText)
                        .font(.caption)
                        .foregroundStyle(ForumColors.brownLight)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .forumCardBackground()
        }
        .buttonStyle(.plain)
    }
}

private struct UserSpaceBlogRowView: View {
    let blog: UserSpaceBlogSummary
    let onUserTap: (String, String?) -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(blog.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ForumColors.textDark)
                    if let excerpt = blog.excerpt {
                        Text(excerpt)
                            .font(.subheadline)
                            .foregroundStyle(ForumColors.secondaryText)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack {
                if let authorID = blog.authorID, let authorName = blog.authorName {
                    Button(authorName) {
                        onUserTap(authorID, authorName)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ForumColors.brownPrimary)
                }
                Spacer()
                if let viewCount = blog.viewCount {
                    Label(String(viewCount), systemImage: "eye")
                }
                if let replyCount = blog.replyCount {
                    Label(String(replyCount), systemImage: "bubble.right")
                }
            }
            .font(.caption)
            .foregroundStyle(ForumColors.secondaryText)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UserSpaceFriendRowView: View {
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
            YamiboRemoteImage(url: friend.avatarURL) { image in
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

private struct UserSpaceAddFriendSheet: View {
    let targetName: String?
    let form: UserSpaceAddFriendForm?
    let isLoading: Bool
    let isSubmitting: Bool
    let errorMessage: String?
    let retry: () -> Void
    let submit: (String, Int) -> Void
    let dismiss: () -> Void

    @State private var note = ""
    @State private var selectedGroupID: Int?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    UserSpaceAddFriendLoadingView()
                } else if let errorMessage {
                    UserSpaceErrorView(message: errorMessage, retry: retry)
                } else if let form {
                    UserSpaceAddFriendFormView(
                        targetName: form.name ?? targetName,
                        avatarURL: form.avatarURL,
                        options: form.options,
                        note: Binding(
                            get: { note },
                            set: { note = String($0.prefix(10)) }
                        ),
                        selectedGroupID: Binding(
                            get: { selectedGroupID ?? form.options.first?.id ?? 1 },
                            set: { selectedGroupID = $0 }
                        ),
                        isSubmitting: isSubmitting,
                        submit: {
                            submit(note, selectedGroupID ?? form.options.first?.id ?? 1)
                        }
                    )
                } else {
                    UserSpaceEmptyView(message: L10n.string("user_space.add_friend_form_unavailable"))
                }
            }
            .navigationTitle(L10n.string("user_space.add_friend"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel"), action: dismiss)
                        .disabled(isSubmitting)
                }
            }
            .task(id: form?.formHash) {
                selectedGroupID = form?.options.first?.id
            }
        }
    }
}

private struct UserSpaceAddFriendFormView: View {
    let targetName: String?
    let avatarURL: URL?
    let options: [UserSpaceAddFriendOption]
    @Binding var note: String
    @Binding var selectedGroupID: Int
    let isSubmitting: Bool
    let submit: () -> Void

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    YamiboRemoteImage(url: avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle")
                            .font(.largeTitle)
                            .foregroundStyle(ForumColors.secondaryText)
                    } failure: {
                        Image(systemName: "person.crop.circle")
                            .font(.largeTitle)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(targetName ?? L10n.string("user_space.unknown_user"))
                            .font(.headline)
                        Text(L10n.string("user_space.add_friend_note_limit"))
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }

            Section(L10n.string("user_space.add_friend_note")) {
                TextField(L10n.string("user_space.add_friend_note_placeholder"), text: $note)
                    .disabled(isSubmitting)
            }

            Section(L10n.string("user_space.add_friend_group")) {
                Picker(L10n.string("user_space.add_friend_group"), selection: $selectedGroupID) {
                    ForEach(options) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .disabled(isSubmitting)
            }

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(L10n.string("user_space.add_friend_submit"))
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isSubmitting)
            }
        }
    }
}

private struct UserSpaceAddFriendLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("user_space.add_friend_loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct UserSpacePageNavigationView: View {
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

private struct UserSpaceLoadingHeaderView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(ForumColors.creamSurface)
            ProgressView()
        }
        .frame(height: 172)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UserSpaceLoadingView: View {
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

private struct UserSpaceErrorView: View {
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

private struct UserSpaceEmptyView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(message, systemImage: "tray")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
    }
}
