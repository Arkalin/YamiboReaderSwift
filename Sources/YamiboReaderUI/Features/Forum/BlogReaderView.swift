import SwiftUI
import YamiboReaderCore

struct BlogReaderView: View {
    @State private var model: BlogReaderViewModel

    let onUserTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    init(
        model: BlogReaderViewModel,
        onUserTap: @escaping (String, String?) -> Void,
        onWebTap: @escaping (URL) -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onUserTap = onUserTap
        self.onWebTap = onWebTap
    }

    var body: some View {
        BlogReaderBodyView(
            page: model.page,
            currentPage: model.currentPage,
            pageNavigation: model.pageNavigation,
            isLoading: model.isLoading,
            isSubmittingComment: model.isSubmittingComment,
            canEditComment: model.canEditComment,
            canSubmitComment: model.canSubmitComment,
            commentText: model.commentText,
            commentPlaceholder: model.commentPlaceholder,
            errorMessage: model.errorMessage,
            refresh: refresh,
            retry: retry,
            goToPage: goToPage,
            updateCommentText: updateCommentText,
            submitComment: submitComment,
            onUserTap: onUserTap,
            onWebTap: onWebTap
        )
        .navigationTitle(model.navigationTitle)
        .yamiboInlineNavigationTitleDisplayMode()
        .task {
            await model.load()
        }
        .alert(
            L10n.string("blog_reader.comment_result"),
            isPresented: Binding(
                get: { model.commentResultMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.clearCommentResult()
                    }
                }
            )
        ) {
            Button(L10n.string("common.ok")) {
                model.clearCommentResult()
            }
        } message: {
            Text(model.commentResultMessage ?? "")
        }
        .alert(
            L10n.string("blog_reader.comment_failed_title"),
            isPresented: Binding(
                get: { model.page != nil && model.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        model.errorMessage = nil
                    }
                }
            )
        ) {
            Button(L10n.string("common.ok")) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "")
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

    private func updateCommentText(_ text: String) {
        model.commentText = text
    }

    private func submitComment() {
        Task {
            await model.submitComment()
        }
    }
}

private struct BlogReaderBodyView: View {
    let page: BlogReaderPage?
    let currentPage: Int
    let pageNavigation: ForumPageNavigation?
    let isLoading: Bool
    let isSubmittingComment: Bool
    let canEditComment: Bool
    let canSubmitComment: Bool
    let commentText: String
    let commentPlaceholder: String
    let errorMessage: String?
    let refresh: () async -> Void
    let retry: () -> Void
    let goToPage: (Int) -> Void
    let updateCommentText: (String) -> Void
    let submitComment: () -> Void
    let onUserTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let page {
                    BlogReaderRootCard(page: page, onUserTap: onUserTap, onWebTap: onWebTap)
                    BlogReaderCommentSection(
                        comments: page.comments,
                        currentPage: currentPage,
                        pageNavigation: pageNavigation,
                        isSubmittingComment: isSubmittingComment,
                        canEditComment: canEditComment,
                        canSubmitComment: canSubmitComment,
                        commentText: commentText,
                        commentPlaceholder: commentPlaceholder,
                        goToPage: goToPage,
                        updateCommentText: updateCommentText,
                        submitComment: submitComment,
                        onUserTap: onUserTap,
                        onWebTap: onWebTap
                    )
                } else if isLoading {
                    BlogReaderLoadingView()
                } else if let errorMessage {
                    BlogReaderErrorView(message: errorMessage, retry: retry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .refreshable {
            await refresh()
        }
        .overlay(alignment: .top) {
            if isLoading && page != nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
    }
}

private struct BlogReaderRootCard: View {
    let page: BlogReaderPage
    let onUserTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(page.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ForumColors.textDark)
                .fixedSize(horizontal: false, vertical: true)

            BlogReaderAuthorRow(user: page.author, postedAtText: page.postedAtText, onUserTap: onUserTap)

            BlogReaderStatRow(viewCount: page.viewCount, replyCount: page.replyCount)

            Text(page.contentText)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(ForumColors.textDark)
                .textSelection(.enabled)

            BlogReaderActionRow(page: page, onWebTap: onWebTap)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }
}

private struct BlogReaderAuthorRow: View {
    let user: BlogReaderUser
    let postedAtText: String?
    let onUserTap: (String, String?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            YamiboRemoteImage(request: user.avatarURL.map { YamiboImageRequest(url: $0) }) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(ForumColors.secondaryText)
            } failure: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(ForumColors.secondaryText)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                if let uid = user.uid {
                    Button(user.name) {
                        onUserTap(uid, user.name)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForumColors.brownPrimary)
                } else {
                    Text(user.name)
                        .font(.subheadline.weight(.semibold))
                }
                if let postedAtText {
                    Text(postedAtText)
                        .font(.caption)
                        .foregroundStyle(ForumColors.brownLight)
                }
            }
            Spacer()
        }
    }
}

private struct BlogReaderStatRow: View {
    let viewCount: Int?
    let replyCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            if let viewCount {
                Label(String(viewCount), systemImage: "eye")
            }
            if let replyCount {
                Label(String(replyCount), systemImage: "bubble.right")
            }
        }
        .font(.caption)
        .foregroundStyle(ForumColors.secondaryText)
    }
}

private struct BlogReaderActionRow: View {
    let page: BlogReaderPage
    let onWebTap: (URL) -> Void

    var body: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                actionButtons
            }
            VStack(alignment: .leading, spacing: 8) {
                actionButtons
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(ForumColors.brownEmphasis)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let collectURL = page.collectURL {
            Button {
                onWebTap(collectURL)
            } label: {
                Label(L10n.string("blog_reader.collect"), systemImage: "star")
            }
        }
        if let shareURL = page.shareURL {
            Button {
                onWebTap(shareURL)
            } label: {
                Label(L10n.string("blog_reader.share"), systemImage: "square.and.arrow.up")
            }
        }
        if let inviteURL = page.inviteURL {
            Button {
                onWebTap(inviteURL)
            } label: {
                Label(L10n.string("blog_reader.invite"), systemImage: "person.badge.plus")
            }
        }
    }
}

private struct BlogReaderCommentSection: View {
    let comments: [BlogReaderComment]
    let currentPage: Int
    let pageNavigation: ForumPageNavigation?
    let isSubmittingComment: Bool
    let canEditComment: Bool
    let canSubmitComment: Bool
    let commentText: String
    let commentPlaceholder: String
    let goToPage: (Int) -> Void
    let updateCommentText: (String) -> Void
    let submitComment: () -> Void
    let onUserTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("blog_reader.comments"))
                .font(.headline)
                .foregroundStyle(ForumColors.brownPrimary)
            if comments.isEmpty {
                ContentUnavailableView(L10n.string("blog_reader.empty_comments"), systemImage: "bubble.left")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(comments) { comment in
                    BlogReaderCommentRow(comment: comment, onUserTap: onUserTap, onWebTap: onWebTap)
                }
            }
            BlogReaderPageNavigationView(navigation: pageNavigation, currentPage: currentPage, goToPage: goToPage)
            BlogReaderCommentEditor(
                text: commentText,
                placeholder: commentPlaceholder,
                canEdit: canEditComment,
                canSubmit: canSubmitComment,
                isSubmitting: isSubmittingComment,
                updateText: updateCommentText,
                submit: submitComment
            )
        }
    }
}

private struct BlogReaderCommentEditor: View {
    let text: String
    let placeholder: String
    let canEdit: Bool
    let canSubmit: Bool
    let isSubmitting: Bool
    let updateText: (String) -> Void
    let submit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("blog_reader.write_comment"))
                .font(.headline)
                .foregroundStyle(ForumColors.brownPrimary)

            TextField(
                placeholder,
                text: Binding(
                    get: { text },
                    set: { newValue in
                        updateText(newValue)
                    }
                ),
                axis: .vertical
            )
            .lineLimit(3 ... 6)
            .textFieldStyle(.roundedBorder)
            .disabled(!canEdit)

            Button {
                submit()
            } label: {
                Label(
                    isSubmitting ? L10n.string("blog_reader.comment_submitting") : L10n.string("blog_reader.comment_submit"),
                    systemImage: "paperplane"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ForumColors.brownDeep)
            .disabled(!canSubmit)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }
}

private struct BlogReaderCommentRow: View {
    let comment: BlogReaderComment
    let onUserTap: (String, String?) -> Void
    let onWebTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                YamiboRemoteImage(request: comment.author.avatarURL.map { YamiboImageRequest(url: $0) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(ForumColors.secondaryText)
                } failure: {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(ForumColors.secondaryText)
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    if let uid = comment.author.uid {
                        Button(comment.author.name) {
                            onUserTap(uid, comment.author.name)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ForumColors.brownPrimary)
                    } else {
                        Text(comment.author.name)
                    }
                    if let postedAtText = comment.postedAtText {
                        Text(postedAtText)
                            .font(.caption)
                            .foregroundStyle(ForumColors.brownLight)
                    }
                }
                Spacer()
                if let replyURL = comment.replyURL {
                    Button(L10n.string("blog_reader.reply")) {
                        onWebTap(replyURL)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                }
            }

            Text(comment.contentText)
                .font(.subheadline)
                .foregroundStyle(ForumColors.textDark)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground()
    }
}

private struct BlogReaderPageNavigationView: View {
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
        }
    }

    private func pageText(_ navigation: ForumPageNavigation) -> String {
        if let totalPages = navigation.totalPages {
            return L10n.string("forum.board.page_count", currentPage, totalPages)
        }
        return L10n.string("forum.board.current_page", currentPage)
    }
}

private struct BlogReaderLoadingView: View {
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

private struct BlogReaderErrorView: View {
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
