import SwiftUI
import YamiboReaderCore
import UIKit

struct ForumThreadReaderView: View {
    @State private var model: ForumThreadReaderViewModel

    let onUserTap: (String, String?) -> Void
    let onURLTap: (URL) -> Void

    init(
        model: ForumThreadReaderViewModel,
        onUserTap: @escaping (String, String?) -> Void,
        onURLTap: @escaping (URL) -> Void
    ) {
        _model = State(wrappedValue: model)
        self.onUserTap = onUserTap
        self.onURLTap = onURLTap
    }

    var body: some View {
        ForumThreadReaderBodyView(
            page: model.page,
            pageNavigation: model.pageNavigation,
            currentPage: model.currentPage,
            targetPostID: model.targetPostID,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            isFavorited: model.isFavorited,
            inlineImageLoadingContext: model.inlineImageLoadingContext,
            refresh: refresh,
            retry: model.retry,
            goToPage: goToPage,
            toggleFavorite: toggleFavorite,
            loadRatingResults: model.loadRatingResults,
            loadRateOptions: model.loadRateOptions,
            loadPollVoters: model.loadPollVoters,
            votePoll: model.votePoll,
            ratePost: model.ratePost,
            commentPost: model.commentPost,
            onUserTap: onUserTap,
            onURLTap: onURLTap
        )
        .navigationTitle(model.navigationTitle)
        .yamiboInlineNavigationTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await model.refresh()
                    }
                } label: {
                    Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .alert(
            L10n.string("forum.thread.favorite_failed"),
            isPresented: favoriteErrorBinding,
            actions: {
                Button(L10n.string("common.ok")) {
                    model.clearFavoriteError()
                }
            },
            message: {
                Text(model.favoriteErrorMessage ?? "")
            }
        )
        .task {
            await model.load()
        }
        .forumTransientMessage(model.transientMessage, bottomPadding: model.page == nil ? 24 : 82) {
            model.clearTransientMessage()
        }
    }

    private func refresh() async {
        await model.refresh()
    }

    private func goToPage(_ page: Int) {
        Task {
            await model.goToPage(page)
        }
    }

    private func toggleFavorite() {
        Task {
            await model.toggleFavorite()
        }
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding(
            get: {
                model.favoriteErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    model.clearFavoriteError()
                }
            }
        )
    }
}

private struct ForumThreadReaderBodyView: View {
    @State private var imageBrowserRequest: ForumThreadImageBrowserRequest?
    @State private var ratingResultsRequest: ForumThreadRatingResultsRequest?
    @State private var pollVotersRequest: ForumThreadPollVotersRequest?

    let page: ForumThreadPage?
    let pageNavigation: ForumPageNavigation?
    let currentPage: Int
    let targetPostID: String?
    let isLoading: Bool
    let errorMessage: String?
    let isFavorited: Bool
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let refresh: () async -> Void
    let retry: () -> Void
    let goToPage: (Int) -> Void
    let toggleFavorite: () -> Void
    let loadRatingResults: (String, String) async throws -> ForumThreadRatingResultsPage
    let loadRateOptions: (String, String) async throws -> ForumThreadRateOptionsPage
    let loadPollVoters: (String, String?, Int) async throws -> ForumThreadPollVotersPage
    let votePoll: (String, String, [String], String) async throws -> String
    let ratePost: (String, String, Int, String, String, Bool) async throws -> String
    let commentPost: (String, String, String, String, Int) async throws -> String
    let onUserTap: (String, String?) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        contentWithSheets
            .fullScreenCover(item: $imageBrowserRequest) { request in
                if let inlineImageLoadingContext {
                    ImageBrowserView(
                        items: request.items,
                        initialItemID: request.initialItemID,
                        mode: .multiple,
                        imageDataLoader: inlineImageLoadingContext.loader,
                        onDismiss: {
                            imageBrowserRequest = nil
                        }
                    )
                }
            }
    }

    private var contentWithSheets: some View {
        content
            .sheet(item: $ratingResultsRequest) { request in
                ForumThreadRatingResultsSheet(
                    request: request,
                    load: loadRatingResults,
                    onUserTap: onUserTap
                )
            }
            .sheet(item: $pollVotersRequest) { request in
                ForumThreadPollVotersSheet(
                    request: request,
                    load: loadPollVoters,
                    onUserTap: onUserTap
                )
            }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let page {
                        ForEach(page.posts) { post in
                            let isFirstPost = currentPage == 1 && post.postID == page.posts.first?.postID
                            ForumThreadPostCard(
                                post: post,
                                isTarget: post.postID == targetPostID,
                                threadTitle: isFirstPost ? page.title : nil,
                                totalViews: isFirstPost ? page.totalViews : nil,
                                totalReplies: isFirstPost ? page.totalReplies : nil,
                                refererURL: YamiboRoute.threadByID(
                                    tid: page.thread.tid,
                                    page: currentPage,
                                    authorID: nil,
                                    reverse: false
                                ).url,
                                threadID: page.thread.tid,
                                currentPage: currentPage,
                                forumID: page.forumID,
                                formHash: page.formHash,
                                inlineImageLoadingContext: inlineImageLoadingContext,
                                onUserTap: onUserTap,
                                onImageTap: openImageBrowser,
                                onShowRatingResults: showRatingResults,
                                onShowPollVoters: showPollVoters,
                                onVotePoll: votePoll,
                                onLoadRateOptions: loadRateOptions,
                                onRatePost: ratePost,
                                onCommentPost: commentPost,
                                onURLTap: onURLTap
                            )
                            .id(post.postID)
                        }

                        ForumThreadReaderPageNavigationView(
                            navigation: pageNavigation,
                            currentPage: currentPage,
                            goToPage: goToPage
                        )
                    } else if isLoading {
                        ForumThreadReaderLoadingView()
                    } else if let errorMessage {
                        ForumThreadReaderErrorView(message: errorMessage, retry: retry)
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
            .task(id: scrollTaskIdentity(page: page, targetPostID: targetPostID)) {
                guard let targetPostID,
                      page?.posts.contains(where: { $0.postID == targetPostID }) == true else {
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.snappy) {
                    proxy.scrollTo(targetPostID, anchor: .center)
                }
            }
        }
        .forumPageBackground()
        .tint(ForumColors.brownDeep)
        .safeAreaInset(edge: .bottom) {
            if let page {
                ForumThreadReaderActionBar(
                    thread: page.thread,
                    isFavorited: isFavorited,
                    onReply: {
                        onURLTap(YamiboRoute.threadReply(tid: page.thread.tid, page: currentPage).url)
                    },
                    onFavorite: toggleFavorite
                )
            }
        }
    }

    private func scrollTaskIdentity(page: ForumThreadPage?, targetPostID: String?) -> String {
        [
            targetPostID ?? "",
            page?.posts.map(\.postID).joined(separator: ",") ?? ""
        ].joined(separator: "|")
    }

    private func openImageBrowser(_ imageID: String, _ url: URL, _ title: String?, _ refererURL: URL) {
        guard inlineImageLoadingContext != nil, let page else {
            onURLTap(url)
            return
        }
        let gallery = ForumThreadImageBrowserGallery(
            page: page,
            refererURL: refererURL,
            selectedBlockID: imageID,
            defaultTitle: L10n.string("forum.thread.image")
        )
        let fallbackItem = ImageBrowserItem(
            id: imageID,
            request: YamiboImageRequest(url: url, refererURL: refererURL),
            title: imageBrowserTitle(from: title),
        )
        imageBrowserRequest = ForumThreadImageBrowserRequest(
            items: gallery.items.isEmpty ? [fallbackItem] : gallery.items,
            initialItemID: gallery.initialItemID ?? fallbackItem.id
        )
    }

    private func imageBrowserTitle(from title: String?) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.string("forum.thread.image") : trimmed
    }

    private func showRatingResults(threadID: String, postID: String) {
        ratingResultsRequest = ForumThreadRatingResultsRequest(threadID: threadID, postID: postID)
    }

    private func showPollVoters(threadID: String, optionID: String?) {
        pollVotersRequest = ForumThreadPollVotersRequest(threadID: threadID, optionID: optionID)
    }
}

private struct ForumThreadReaderActionBar: View {
    let thread: ThreadIdentity
    let isFavorited: Bool
    let onReply: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onReply) {
                Label(L10n.string("forum.thread.send_reply"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ForumColors.brownDeep)

            Button(action: onFavorite) {
                Label(
                    isFavorited ? L10n.string("forum.thread.favorited") : L10n.string("forum.thread.favorite"),
                    systemImage: isFavorited ? "star.fill" : "star"
                )
                .labelStyle(.iconOnly)
                .foregroundStyle(isFavorited ? ForumColors.orangeAccent : ForumColors.brownEmphasis)
                .frame(width: 42, height: 34)
            }
            .buttonStyle(.bordered)
            .tint(ForumColors.brownEmphasis)
            .accessibilityLabel(
                isFavorited ? L10n.string("forum.thread.favorited") : L10n.string("forum.thread.favorite")
            )

            ShareLink(item: Self.threadURL(for: thread)) {
                Label(L10n.string("forum.thread.share"), systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(ForumColors.brownEmphasis)
                    .frame(width: 42, height: 34)
            }
            .buttonStyle(.bordered)
            .tint(ForumColors.brownEmphasis)
            .accessibilityLabel(L10n.string("forum.thread.share"))
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private static func threadURL(for thread: ThreadIdentity) -> URL {
        YamiboRoute.threadByID(tid: thread.tid, page: 1, authorID: nil, reverse: false).url
    }
}

private struct ForumThreadImageBrowserRequest: Identifiable, Equatable {
    var items: [ImageBrowserItem]
    var initialItemID: String

    var id: String {
        [
            initialItemID,
            items.map(\.id).joined(separator: "\u{1E}")
        ].joined(separator: "\u{1F}")
    }
}

private struct ForumThreadRatingResultsRequest: Identifiable, Equatable {
    var threadID: String
    var postID: String

    var id: String {
        "\(threadID)\u{1F}\(postID)"
    }
}

private struct ForumThreadPollVotersRequest: Identifiable, Equatable {
    var threadID: String
    var optionID: String?

    var id: String {
        "\(threadID)\u{1F}\(optionID ?? "")"
    }
}

private struct ForumThreadRatingResultsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: ForumThreadRatingResultsPage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let request: ForumThreadRatingResultsRequest
    let load: (String, String) async throws -> ForumThreadRatingResultsPage
    let onUserTap: (String, String?) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && page == nil {
                    ForumThreadReaderLoadingView()
                } else if let errorMessage, page == nil {
                    ForumThreadReaderErrorView(message: errorMessage) {
                        Task {
                            await loadPage()
                        }
                    }
                } else if let page {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.string("forum.thread.rating_participants_format", page.ratings.count))
                                .font(.caption)
                                .foregroundStyle(ForumColors.secondaryText)
                            Spacer(minLength: 0)
                            if let totalScore = page.totalScore {
                                Text(L10n.string("forum.thread.ratings_total_format", totalScore))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ForumColors.orangeAccent)
                            }
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(page.ratings) { rating in
                                    ForumThreadRatingResultRow(rating: rating, onUserTap: openUser)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.string("forum.thread.ratings_all"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if isLoading && page != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
        .task(id: request.id) {
            await loadPage()
        }
    }

    private func loadPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            page = try await load(request.threadID, request.postID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openUser(uid: String, name: String?) {
        dismiss()
        onUserTap(uid, name)
    }
}

private struct ForumThreadRatingResultRow: View {
    let rating: ForumThreadRating
    let onUserTap: (String, String?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let uid = rating.user.uid {
                Button(rating.user.name) {
                    onUserTap(uid, rating.user.name)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ForumColors.brownPrimary)
                .frame(maxWidth: 120, alignment: .leading)
            } else {
                Text(rating.user.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.secondaryText)
                    .frame(maxWidth: 120, alignment: .leading)
            }

            Text(rating.scoreText)
                .font(.caption.weight(.bold))
                .foregroundStyle(ForumColors.orangeAccent)
                .frame(width: 48, alignment: .leading)

            Text(rating.reason ?? "")
                .font(.caption)
                .foregroundStyle(ForumColors.textDark)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
    }
}

private struct ForumThreadPollVotersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOptionID: String?
    @State private var pageNumber = 1
    @State private var votersPage: ForumThreadPollVotersPage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    let request: ForumThreadPollVotersRequest
    let load: (String, String?, Int) async throws -> ForumThreadPollVotersPage
    let onUserTap: (String, String?) -> Void

    init(
        request: ForumThreadPollVotersRequest,
        load: @escaping (String, String?, Int) async throws -> ForumThreadPollVotersPage,
        onUserTap: @escaping (String, String?) -> Void
    ) {
        self.request = request
        self.load = load
        self.onUserTap = onUserTap
        _selectedOptionID = State(initialValue: request.optionID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && votersPage == nil {
                    ForumThreadReaderLoadingView()
                } else if let errorMessage, votersPage == nil {
                    ForumThreadReaderErrorView(message: errorMessage) {
                        Task {
                            await loadPage()
                        }
                    }
                } else if let votersPage {
                    VStack(alignment: .leading, spacing: 14) {
                        optionMenu(votersPage)

                        if votersPage.voters.isEmpty {
                            Text(L10n.string("forum.thread.poll_voters_empty"))
                                .font(.body)
                                .foregroundStyle(ForumColors.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            ScrollView {
                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(votersPage.voters, id: \.self) { voter in
                                        ForumThreadPollVoterButton(user: voter, onUserTap: openUser)
                                    }
                                }
                            }
                        }

                        ForumThreadReaderPageNavigationView(
                            navigation: votersPage.pageNavigation,
                            currentPage: votersPage.pageNavigation?.currentPage ?? pageNumber,
                            goToPage: { page in
                                pageNumber = page
                            }
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.string("forum.thread.poll_voters"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.close")) {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if isLoading && votersPage != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                }
            }
        }
        .task(id: loadIdentity) {
            await loadPage()
        }
    }

    @ViewBuilder
    private func optionMenu(_ page: ForumThreadPollVotersPage) -> some View {
        if !page.pollOptions.isEmpty {
            Menu {
                ForEach(page.pollOptions) { option in
                    Button(option.name) {
                        selectedOptionID = option.id
                        pageNumber = 1
                    }
                }
            } label: {
                HStack {
                    Text(selectedOptionName(in: page))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForumColors.textDark)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForumColors.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var loadIdentity: String {
        "\(selectedOptionID ?? "")\u{1F}\(pageNumber)"
    }

    private func selectedOptionName(in page: ForumThreadPollVotersPage) -> String {
        let id = selectedOptionID ?? page.selectedOptionID
        return page.pollOptions.first(where: { $0.id == id })?.name
            ?? page.pollOptions.first?.name
            ?? L10n.string("forum.thread.poll_voters")
    }

    private func loadPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            votersPage = try await load(request.threadID, selectedOptionID, pageNumber)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openUser(uid: String, name: String?) {
        dismiss()
        onUserTap(uid, name)
    }
}

private struct ForumThreadPollVoterButton: View {
    let user: BlogReaderUser
    let onUserTap: (String, String?) -> Void

    var body: some View {
        if let uid = user.uid {
            Button {
                onUserTap(uid, user.name)
            } label: {
                Text(user.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ForumColors.brownPrimary)
            .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
        } else {
            Text(user.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(ForumColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 11)
                .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ForumThreadPostCard: View {
    @State private var isShowingRateSheet = false
    @State private var isShowingCommentSheet = false

    let post: ForumThreadPost
    let isTarget: Bool
    let threadTitle: String?
    let totalViews: Int?
    let totalReplies: Int?
    let refererURL: URL
    let threadID: String
    let currentPage: Int
    let forumID: String?
    let formHash: String?
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onUserTap: (String, String?) -> Void
    let onImageTap: (String, URL, String?, URL) -> Void
    let onShowRatingResults: (String, String) -> Void
    let onShowPollVoters: (String, String?) -> Void
    let onVotePoll: (String, String, [String], String) async throws -> String
    let onLoadRateOptions: (String, String) async throws -> ForumThreadRateOptionsPage
    let onRatePost: (String, String, Int, String, String, Bool) async throws -> String
    let onCommentPost: (String, String, String, String, Int) async throws -> String
    let onURLTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let threadTitle {
                ForumThreadPostTitleHeader(
                    title: threadTitle,
                    totalViews: totalViews,
                    totalReplies: totalReplies
                )
            }

            ForumThreadPostHeader(
                post: post,
                onUserTap: onUserTap,
                onURLTap: onURLTap
            )

            ForumThreadContentBlocksView(
                blocks: post.contentBlocks,
                fallbackText: post.contentText,
                refererURL: refererURL,
                inlineImageLoadingContext: inlineImageLoadingContext,
                onImageTap: onImageTap,
                onURLTap: onURLTap
            )

            if let lastEditedText = post.lastEditedText {
                ForumThreadPostEditedTextView(text: lastEditedText)
            }

            if let poll = post.poll {
                ForumThreadPollView(
                    poll: poll,
                    onVote: pollVoteAction,
                    onShowVoters: poll.status == .voted ? {
                        onShowPollVoters(threadID, nil)
                    } : nil
                )
            }

            if let ratingBlock = post.ratingBlock {
                ForumThreadRatingBlockView(block: ratingBlock) {
                    onShowRatingResults(threadID, post.postID)
                }
            }

            if !post.comments.isEmpty {
                ForumThreadCommentsView(comments: post.comments, onUserTap: onUserTap)
            }

            if !post.attachments.isEmpty {
                ForumThreadFooterAttachmentsView(attachments: post.attachments, onURLTap: onURLTap)
            }

            ForumThreadPostActionRow(
                replyURL: YamiboRoute.threadPostReply(tid: threadID, pid: post.postID, page: currentPage).url,
                onRate: {
                    isShowingRateSheet = true
                },
                onComment: {
                    isShowingCommentSheet = true
                },
                onURLTap: onURLTap
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forumCardBackground(fill: isTarget ? ForumColors.accentFill : ForumColors.creamSurface)
        .sheet(isPresented: $isShowingRateSheet) {
            ForumThreadRateSheet(
                threadID: threadID,
                postID: post.postID,
                formHash: normalizedFormHash,
                loadOptions: onLoadRateOptions,
                submit: onRatePost
            )
        }
        .sheet(isPresented: $isShowingCommentSheet) {
            ForumThreadCommentSheet(
                threadID: threadID,
                postID: post.postID,
                formHash: normalizedFormHash,
                page: currentPage,
                submit: onCommentPost
            )
        }
    }

    private var pollVoteAction: (([String]) async throws -> String)? {
        return { optionIDs in
            guard let forumID = forumID?.trimmingCharacters(in: .whitespacesAndNewlines), !forumID.isEmpty,
                  let normalizedFormHash else {
                throw YamiboError.underlying(L10n.string("forum.thread.login_info_failed"))
            }
            return try await onVotePoll(forumID, threadID, optionIDs, normalizedFormHash)
        }
    }

    private var normalizedFormHash: String? {
        let value = formHash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

private struct ForumThreadPostActionRow: View {
    let replyURL: URL
    let onRate: () -> Void
    let onComment: () -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider()
                .overlay(ForumColors.brownLight.opacity(0.25))

            HStack {
                Spacer(minLength: 0)
                Button(action: onRate) {
                    Label(L10n.string("forum.thread.rate"), systemImage: "heart")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForumColors.brownPrimary)

                Button(action: onComment) {
                    Label(L10n.string("forum.thread.comment"), systemImage: "text.bubble")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForumColors.brownPrimary)

                Button {
                    onURLTap(replyURL)
                } label: {
                    Label(L10n.string("forum.thread.reply"), systemImage: "arrowshape.turn.up.left")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForumColors.brownPrimary)
            }
        }
    }
}

private struct ForumThreadRateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var options: ForumThreadRateOptionsPage?
    @State private var scoreText = ""
    @State private var reason = ""
    @State private var noticeAuthor = false
    @State private var isLoadingOptions = false
    @State private var isSubmitting = false
    @State private var hintMessage: String?
    @State private var errorMessage: String?

    let threadID: String
    let postID: String
    let formHash: String?
    let loadOptions: (String, String) async throws -> ForumThreadRateOptionsPage
    let submit: (String, String, Int, String, String, Bool) async throws -> String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("forum.thread.rate_score"), text: $scoreText)

                    if let options, !options.availableScores.isEmpty {
                        Menu(L10n.string("forum.thread.rate_score_options")) {
                            ForEach(options.availableScores, id: \.self) { score in
                                Button(String(score)) {
                                    scoreText = String(score)
                                }
                            }
                        }
                    }

                    TextField(L10n.string("forum.thread.rate_reason"), text: $reason, axis: .vertical)
                        .lineLimit(3 ... 5)

                    if let options, !options.defaultReasons.isEmpty {
                        Menu(L10n.string("forum.thread.rate_reason_options")) {
                            ForEach(options.defaultReasons, id: \.self) { value in
                                Button(value) {
                                    reason = value
                                }
                            }
                        }
                    }

                    Toggle(L10n.string("forum.thread.rate_notice_author"), isOn: $noticeAuthor)
                }

                if let hintMessage {
                    Section {
                        Text(hintMessage)
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.string("forum.thread.ratings"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? L10n.string("forum.thread.submitting") : L10n.string("forum.thread.submit")) {
                        submitRate()
                    }
                    .disabled(isSubmitting || scoreText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isLoadingOptions || isSubmitting {
                    ProgressView()
                }
            }
        }
        .task(id: "\(threadID)-\(postID)") {
            await loadRateOptions()
        }
    }

    private func loadRateOptions() async {
        isLoadingOptions = true
        hintMessage = L10n.string("forum.thread.rate_loading_options")
        defer { isLoadingOptions = false }

        do {
            options = try await loadOptions(threadID, postID)
            hintMessage = nil
        } catch {
            hintMessage = L10n.string("forum.thread.rate_options_failed")
        }
    }

    private func submitRate() {
        guard let score = Int(scoreText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = L10n.string("forum.thread.rate_score_invalid")
            return
        }
        guard let formHash else {
            errorMessage = L10n.string("forum.thread.login_info_failed")
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                _ = try await submit(threadID, postID, score, reason, formHash, noticeAuthor)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct ForumThreadCommentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let threadID: String
    let postID: String
    let formHash: String?
    let page: Int
    let submit: (String, String, String, String, Int) async throws -> String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(L10n.string("forum.thread.comment_placeholder"))
                                .foregroundStyle(ForumColors.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(L10n.string("forum.thread.comment"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? L10n.string("forum.thread.submitting") : L10n.string("forum.thread.publish")) {
                        submitComment()
                    }
                    .disabled(isSubmitting || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView()
                }
            }
        }
    }

    private func submitComment() {
        guard let formHash else {
            errorMessage = L10n.string("forum.thread.login_info_failed")
            return
        }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                _ = try await submit(threadID, postID, message, formHash, page)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct ForumThreadPollView: View {
    @State private var selectedOptionIDs: Set<String>
    @State private var isSubmitting = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    let poll: ForumThreadPoll
    let onVote: (([String]) async throws -> String)?
    let onShowVoters: (() -> Void)?

    init(
        poll: ForumThreadPoll,
        onVote: (([String]) async throws -> String)? = nil,
        onShowVoters: (() -> Void)? = nil
    ) {
        self.poll = poll
        self.onVote = onVote
        self.onShowVoters = onShowVoters
        _selectedOptionIDs = State(
            initialValue: Set(poll.options.filter(\.isSelected).map(\.id))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(poll.title, systemImage: "chart.bar.doc.horizontal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForumColors.brownPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let endTimeText = poll.endTimeText {
                Text(endTimeText)
                    .font(.caption)
                    .foregroundStyle(ForumColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(poll.options) { option in
                    ForumThreadPollOptionView(
                        option: option,
                        pollStatus: poll.status,
                        pollType: poll.type,
                        isSelectedForSubmission: selectedOptionIDs.contains(option.id),
                        showProgress: poll.options.contains { $0.percentage != nil },
                        toggleSelection: {
                            toggle(option.id)
                        }
                    )
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(ForumColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if poll.status == .notVoted, let onVote {
                Button {
                    submit(using: onVote)
                } label: {
                    Label(
                        isSubmitting ? L10n.string("forum.thread.poll_submitting") : L10n.string("forum.thread.poll_submit"),
                        systemImage: "paperplane"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(ForumColors.brownPrimary)
                .disabled(selectedOptionIDs.isEmpty || isSubmitting)
            }

            if let onShowVoters {
                Button(action: onShowVoters) {
                    Label(L10n.string("forum.thread.poll_voters"), systemImage: "person.2")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForumColors.brownPrimary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func toggle(_ optionID: String) {
        errorMessage = nil
        resultMessage = nil
        if poll.type == .multipleChoice {
            if selectedOptionIDs.contains(optionID) {
                selectedOptionIDs.remove(optionID)
            } else {
                selectedOptionIDs.insert(optionID)
            }
        } else {
            selectedOptionIDs = [optionID]
        }
    }

    private func submit(using onVote: @escaping ([String]) async throws -> String) {
        let optionIDs = poll.options
            .map(\.id)
            .filter { selectedOptionIDs.contains($0) }
        guard !optionIDs.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        resultMessage = nil
        Task {
            do {
                resultMessage = try await onVote(optionIDs)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

private struct ForumThreadPollOptionView: View {
    let option: ForumThreadPollOption
    let pollStatus: ForumThreadPollStatus
    let pollType: ForumThreadPollType
    let isSelectedForSubmission: Bool
    let showProgress: Bool
    let toggleSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                if pollStatus == .notVoted {
                    toggleSelection()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: selectionIconName)
                        .font(.caption)
                        .foregroundStyle(isVisuallySelected ? ForumColors.brownPrimary : ForumColors.secondaryText)
                    Text(option.title)
                        .font(.callout)
                        .foregroundStyle(ForumColors.textDark)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let voteCount = option.voteCount {
                        Text(L10n.string("forum.thread.poll_votes_format", voteCount))
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(pollStatus != .notVoted)

            if showProgress {
                ProgressView(value: min(max((option.percentage ?? 0) / 100, 0), 1))
                    .tint(ForumColors.brownPrimary)
                if let percentage = option.percentage {
                    Text(percentage.formatted(.number.precision(.fractionLength(0 ... 2))) + "%")
                        .font(.caption2)
                        .foregroundStyle(ForumColors.secondaryText)
                }
            }
        }
    }

    private var isVisuallySelected: Bool {
        pollStatus == .notVoted ? isSelectedForSubmission : option.isSelected
    }

    private var selectionIconName: String {
        switch (pollType, isVisuallySelected) {
        case (.multipleChoice, true):
            "checkmark.square.fill"
        case (.multipleChoice, false):
            "square"
        case (_, true):
            "largecircle.fill.circle"
        case (_, false):
            "circle"
        }
    }
}

private struct ForumThreadRatingBlockView: View {
    let block: ForumThreadRatingBlock
    let onShowAllRatings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ratingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForumColors.brownPrimary)
                Spacer(minLength: 0)
                if let totalScore = block.totalScore {
                    Text(L10n.string("forum.thread.ratings_total_format", totalScore))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForumColors.orangeAccent)
                }
            }

            ForEach(block.ratings) { rating in
                HStack(alignment: .top, spacing: 8) {
                    Text(rating.user.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForumColors.secondaryText)
                        .frame(maxWidth: 92, alignment: .leading)
                    Text(rating.scoreText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ForumColors.orangeAccent)
                        .frame(width: 44, alignment: .leading)
                    Text(rating.reason ?? "")
                        .font(.caption)
                        .foregroundStyle(ForumColors.textDark)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if block.allRatingsURL != nil {
                Button {
                    onShowAllRatings()
                } label: {
                    Label(L10n.string("forum.thread.ratings_all"), systemImage: "list.bullet")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ForumColors.brownPrimary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var ratingTitle: String {
        if let participantCount = block.participantCount {
            return L10n.string("forum.thread.ratings_title_format", participantCount)
        }
        return L10n.string("forum.thread.ratings")
    }
}

private struct ForumThreadCommentsView: View {
    let comments: [ForumThreadPostComment]
    let onUserTap: (String, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("forum.thread.comments"), systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForumColors.brownPrimary)

            ForEach(comments) { comment in
                ForumThreadCommentRow(comment: comment, onUserTap: onUserTap)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ForumThreadCommentRow: View {
    let comment: ForumThreadPostComment
    let onUserTap: (String, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let uid = comment.author.uid {
                    Button(comment.author.name) {
                        onUserTap(uid, comment.author.name)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.brownPrimary)
                } else {
                    Text(comment.author.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ForumColors.brownPrimary)
                }

                Spacer(minLength: 0)

                if let postedAtText = comment.postedAtText {
                    Text(postedAtText)
                        .font(.caption2)
                        .foregroundStyle(ForumColors.secondaryText)
                }
            }

            Text(comment.message)
                .font(.callout)
                .foregroundStyle(ForumColors.textDark)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ForumThreadFooterAttachmentsView: View {
    let attachments: [ForumThreadAttachmentBlock]
    let onURLTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("forum.thread.attachments"), systemImage: "paperclip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForumColors.brownPrimary)

            ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
                ForumThreadAttachmentBlockView(block: attachment, onURLTap: onURLTap)
            }
        }
    }
}

private struct ForumThreadPostEditedTextView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(ForumColors.secondaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

private struct ForumThreadPostTitleHeader: View {
    let title: String
    let totalViews: Int?
    let totalReplies: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ForumColors.textDark)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if totalViews != nil || totalReplies != nil {
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    if let totalViews {
                        ForumThreadStatBadge(systemImage: "eye", value: totalViews)
                    }
                    if let totalReplies {
                        ForumThreadStatBadge(systemImage: "text.bubble", value: totalReplies)
                    }
                }
            }
        }
    }
}

private struct ForumThreadStatBadge: View {
    let systemImage: String
    let value: Int

    var body: some View {
        Label {
            Text(value.formatted())
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(ForumColors.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ForumColors.creamBackground, in: Capsule())
    }
}

private struct ForumThreadContentBlocksView: View {
    let blocks: [ForumThreadContentBlock]
    let fallbackText: String
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                ForumThreadTextBlockView(
                    block: ForumThreadTextBlock(text: fallbackText),
                    onURLTap: onURLTap
                )
            } else {
                ForEach(blocks) { block in
                    ForumThreadContentBlockView(
                        block: block,
                        refererURL: refererURL,
                        inlineImageLoadingContext: inlineImageLoadingContext,
                        onImageTap: onImageTap,
                        onURLTap: onURLTap
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ForumThreadContentBlockView: View {
    let block: ForumThreadContentBlock
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        switch block.kind {
        case let .text(textBlock):
            ForumThreadTextBlockView(block: textBlock, onURLTap: onURLTap)
        case let .image(imageBlock):
            ForumThreadImageBlockView(
                blockID: block.id,
                block: imageBlock,
                refererURL: refererURL,
                inlineImageLoadingContext: inlineImageLoadingContext,
                onImageTap: onImageTap,
                onURLTap: onURLTap
            )
        case let .attachment(attachment):
            ForumThreadAttachmentBlockView(block: attachment, onURLTap: onURLTap)
        case let .quote(blocks):
            ForumThreadNestedBlockContainer(accented: true) {
                ForumThreadContentBlocksView(
                    blocks: blocks,
                    fallbackText: "",
                    refererURL: refererURL,
                    inlineImageLoadingContext: inlineImageLoadingContext,
                    onImageTap: onImageTap,
                    onURLTap: onURLTap
                )
            }
        case let .code(text):
            ForumThreadCodeBlockView(text: text)
        case .horizontalRule:
            Divider()
                .overlay(ForumColors.brownLight.opacity(0.35))
        case let .collapse(title, blocks):
            ForumThreadDisclosureBlockView(
                title: title ?? L10n.string("forum.thread.collapse_title"),
                blocks: blocks,
                refererURL: refererURL,
                inlineImageLoadingContext: inlineImageLoadingContext,
                onImageTap: onImageTap,
                onURLTap: onURLTap
            )
        case let .locked(cost, blocks):
            ForumThreadLockedBlockView(
                cost: cost,
                blocks: blocks,
                refererURL: refererURL,
                inlineImageLoadingContext: inlineImageLoadingContext,
                onImageTap: onImageTap,
                onURLTap: onURLTap
            )
        case let .table(rows):
            ForumThreadTableBlockView(
                rows: rows,
                refererURL: refererURL,
                inlineImageLoadingContext: inlineImageLoadingContext,
                onImageTap: onImageTap,
                onURLTap: onURLTap
            )
        }
    }
}

private struct ForumThreadTextBlockView: View {
    let block: ForumThreadTextBlock
    let onURLTap: (URL) -> Void

    @ViewBuilder
    var body: some View {
        if block.rubies.isEmpty {
            plainText
        } else {
            ForumThreadRubyTextBlockView(
                segments: rubySegments,
                alignment: block.alignment,
                onURLTap: onURLTap
            )
        }
    }

    private var plainText: some View {
        Text(attributedText)
            .font(.body)
            .lineSpacing(4)
            .foregroundStyle(ForumColors.textDark)
            .multilineTextAlignment(block.alignment.swiftUITextAlignment)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: block.alignment.swiftUIFrameAlignment)
            .environment(\.openURL, OpenURLAction { url in
                onURLTap(url)
                return .handled
            })
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(block.text)
        let characters = Array(block.text)
        for run in block.styleRuns {
            guard run.start >= 0, run.start < characters.count else { continue }
            let end = min(characters.count, run.start + run.length)
            guard end > run.start else { continue }
            let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: run.start)
            let endIndex = attributed.index(attributed.startIndex, offsetByCharacters: end)
            attributed[startIndex ..< endIndex].font = forumThreadFont(for: run.style)
            if let foregroundColor = Color(forumThreadHex: run.style.foregroundHex) {
                attributed[startIndex ..< endIndex].foregroundColor = foregroundColor
            }
            if let backgroundColor = Color(forumThreadHex: run.style.backgroundHex) {
                attributed[startIndex ..< endIndex].backgroundColor = backgroundColor
            }
            if run.style.isUnderline {
                attributed[startIndex ..< endIndex].underlineStyle = .single
            }
            if run.style.isStrikethrough {
                attributed[startIndex ..< endIndex].strikethroughStyle = .single
            }
        }
        for link in block.links {
            guard link.start >= 0, link.start < characters.count else { continue }
            let end = min(characters.count, link.start + link.length)
            guard end > link.start else { continue }
            let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: link.start)
            let endIndex = attributed.index(attributed.startIndex, offsetByCharacters: end)
            attributed[startIndex ..< endIndex].link = link.url
            attributed[startIndex ..< endIndex].foregroundColor = ForumColors.brownPrimary
            attributed[startIndex ..< endIndex].underlineStyle = .single
        }
        return attributed
    }

    private var rubySegments: [ForumThreadRubySegment] {
        let textCount = Array(block.text).count
        let sortedRubies = block.rubies
            .filter { ruby in
                ruby.start >= 0
                    && ruby.length > 0
                    && ruby.start + ruby.length <= textCount
            }
            .sorted { first, second in
                first.start < second.start
            }
        var cursor = 0
        var segments: [ForumThreadRubySegment] = []

        for ruby in sortedRubies {
            guard ruby.start >= cursor else { continue }
            if cursor < ruby.start,
               let attributed = attributedTextSlice(start: cursor, length: ruby.start - cursor) {
                segments.append(ForumThreadRubySegment(attributedText: attributed, rubyText: nil))
            }
            if let attributed = attributedTextSlice(start: ruby.start, length: ruby.length) {
                segments.append(ForumThreadRubySegment(attributedText: attributed, rubyText: ruby.rubyText))
            }
            cursor = ruby.start + ruby.length
        }

        if cursor < textCount,
           let attributed = attributedTextSlice(start: cursor, length: textCount - cursor) {
            segments.append(ForumThreadRubySegment(attributedText: attributed, rubyText: nil))
        }

        return segments
    }

    private func attributedTextSlice(start: Int, length: Int) -> AttributedString? {
        guard length > 0 else { return nil }
        let attributed = attributedText
        let startIndex = attributed.index(attributed.startIndex, offsetByCharacters: start)
        let endIndex = attributed.index(startIndex, offsetByCharacters: length)
        return AttributedString(attributed[startIndex ..< endIndex])
    }

    private func forumThreadFont(for style: ForumThreadTextStyle) -> Font {
        let baseSize = 17 * (style.relativeFontSize ?? 1)
        var font = Font.system(size: baseSize)
        if style.isBold {
            font = font.bold()
        }
        if style.isItalic {
            font = font.italic()
        }
        return font
    }
}

private struct ForumThreadRubySegment: Identifiable {
    var id = UUID()
    var attributedText: AttributedString
    var rubyText: String?
}

private struct ForumThreadRubyTextBlockView: View {
    let segments: [ForumThreadRubySegment]
    let alignment: ForumThreadTextAlignment
    let onURLTap: (URL) -> Void

    var body: some View {
        ForumThreadRubyFlowLayout(alignment: alignment) {
            ForEach(segments) { segment in
                ForumThreadRubySegmentView(segment: segment)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment.swiftUIFrameAlignment)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            onURLTap(url)
            return .handled
        })
    }
}

private struct ForumThreadRubySegmentView: View {
    let segment: ForumThreadRubySegment

    var body: some View {
        if let rubyText = segment.rubyText {
            VStack(spacing: 0) {
                Text(rubyText)
                    .font(.caption2)
                    .foregroundStyle(ForumColors.secondaryText)
                    .lineLimit(1)
                Text(segment.attributedText)
                    .font(.body)
                    .foregroundStyle(ForumColors.textDark)
                    .lineLimit(1)
            }
        } else {
            Text(segment.attributedText)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(ForumColors.textDark)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

private struct ForumThreadRubyFlowLayout: Layout {
    var alignment: ForumThreadTextAlignment

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? subviews.reduce(CGFloat.zero) { partial, subview in
            partial + subview.sizeThatFits(.unspecified).width
        }
        let lines = measuredLines(maxWidth: max(maxWidth, 1), subviews: subviews)
        return CGSize(
            width: maxWidth,
            height: lines.reduce(CGFloat.zero) { partial, line in
                partial + line.height
            }
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let lines = measuredLines(maxWidth: max(bounds.width, 1), subviews: subviews)
        var y = bounds.minY
        var index = 0
        for line in lines {
            var x = bounds.minX + horizontalOffset(for: line.width, in: bounds.width)
            for size in line.sizes {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height)),
                    proposal: ProposedViewSize(size)
                )
                x += size.width
                index += 1
            }
            y += line.height
        }
    }

    private func measuredLines(maxWidth: CGFloat, subviews: Subviews) -> [ForumThreadRubyFlowLine] {
        var lines: [ForumThreadRubyFlowLine] = []
        var currentSizes: [CGSize] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        func flush() {
            guard !currentSizes.isEmpty else { return }
            lines.append(
                ForumThreadRubyFlowLine(
                    sizes: currentSizes,
                    width: currentWidth,
                    height: currentHeight
                )
            )
            currentSizes = []
            currentWidth = 0
            currentHeight = 0
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth > 0, currentWidth + size.width > maxWidth {
                flush()
            }
            currentSizes.append(size)
            currentWidth += size.width
            currentHeight = max(currentHeight, size.height)
        }
        flush()
        return lines
    }

    private func horizontalOffset(for lineWidth: CGFloat, in availableWidth: CGFloat) -> CGFloat {
        switch alignment {
        case .center:
            return max((availableWidth - lineWidth) / 2, 0)
        case .right:
            return max(availableWidth - lineWidth, 0)
        case .start, .left:
            return 0
        }
    }
}

private struct ForumThreadRubyFlowLine {
    var sizes: [CGSize]
    var width: CGFloat
    var height: CGFloat
}

private extension ForumThreadTextAlignment {
    var swiftUITextAlignment: TextAlignment {
        switch self {
        case .center:
            return .center
        case .right:
            return .trailing
        case .start, .left:
            return .leading
        }
    }

    var swiftUIFrameAlignment: Alignment {
        switch self {
        case .center:
            return .center
        case .right:
            return .trailing
        case .start, .left:
            return .leading
        }
    }
}

private extension Color {
    init?(forumThreadHex hex: String?) {
        guard let hex else { return nil }
        let normalized = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard normalized.count == 6,
              let value = UInt64(normalized, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

private struct ForumThreadImageBlockView: View {
    let blockID: String
    let block: ForumThreadImageBlock
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        if block.isEmoticon {
            image
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel(block.altText ?? L10n.string("forum.thread.image"))
        } else {
            Button {
                if let linkURL = block.linkURL {
                    onURLTap(linkURL)
                } else {
                    onImageTap(blockID, block.url, block.altText, refererURL)
                }
            } label: {
                image
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.altText ?? L10n.string("forum.thread.image"))
        }
    }

    @ViewBuilder
    private var image: some View {
        if let inlineImageLoadingContext {
            ForumThreadAuthenticatedImage(
                url: block.url,
                refererURL: refererURL,
                imageDataLoader: inlineImageLoadingContext.loader
            )
        } else {
            YamiboRemoteImage(
                request: YamiboImageRequest(url: block.url, refererURL: refererURL)
            ) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                ForumThreadImagePlaceholderView()
            } failure: {
                ForumThreadImageFailureView()
            }
        }
    }
}

private struct ForumThreadImagePlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(ForumColors.creamBackground)
            .frame(height: 180)
            .overlay {
                ProgressView()
            }
    }
}

private struct ForumThreadImageFailureView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(ForumColors.creamBackground)
            .frame(height: 120)
            .overlay {
                Label(L10n.string("forum.thread.image_load_failed"), systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(ForumColors.secondaryText)
            }
    }
}

private struct ForumThreadAuthenticatedImage: View {
    @StateObject private var loader: NovelReaderImageLoader

    init(
        url: URL,
        refererURL: URL,
        imageDataLoader: any YamiboImageDataLoading
    ) {
        _loader = StateObject(
            wrappedValue: NovelReaderImageLoader(
                request: YamiboImageRequest(url: url, refererURL: refererURL),
                imageDataLoader: imageDataLoader
            )
        )
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.didFail {
                ForumThreadImageFailureView()
            } else {
                ForumThreadImagePlaceholderView()
            }
        }
        .task {
            await loader.loadIfNeeded()
        }
    }
}

private struct ForumThreadAttachmentBlockView: View {
    let block: ForumThreadAttachmentBlock
    let onURLTap: (URL) -> Void

    var body: some View {
        Button {
            onURLTap(block.url)
        } label: {
            HStack(spacing: 12) {
                ForumThreadAttachmentIconView(iconURL: block.iconURL)

                VStack(alignment: .leading, spacing: 3) {
                    Text(block.fileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForumColors.textDark)
                        .lineLimit(2)
                    if let uploadInfo = block.uploadInfo {
                        Text(uploadInfo)
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                    if let statInfo = block.statInfo {
                        Text(statInfo)
                            .font(.caption)
                            .foregroundStyle(ForumColors.secondaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ForumColors.brownLight.opacity(0.25), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ForumThreadAttachmentIconView: View {
    let iconURL: URL?

    var body: some View {
        YamiboRemoteImage(request: iconURL.map { YamiboImageRequest(url: $0) }) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "paperclip")
                .foregroundStyle(ForumColors.brownPrimary)
        } failure: {
            Image(systemName: "paperclip")
                .foregroundStyle(ForumColors.brownPrimary)
        }
        .frame(width: 34, height: 34)
        .padding(6)
        .background(ForumColors.creamSurface, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ForumThreadNestedBlockContainer<Content: View>: View {
    let accented: Bool
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if accented {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ForumColors.brownPrimary)
                    .frame(width: 4)
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ForumThreadDisclosureBlockView: View {
    let title: String
    let blocks: [ForumThreadContentBlock]
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForumThreadContentBlocksView(
                blocks: blocks,
                fallbackText: "",
                refererURL: refererURL,
                inlineImageLoadingContext: inlineImageLoadingContext,
                onImageTap: onImageTap,
                onURLTap: onURLTap
            )
                .padding(.top, 8)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ForumColors.textDark)
        }
        .padding(12)
        .background(ForumColors.creamBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ForumThreadLockedBlockView: View {
    let cost: Int?
    let blocks: [ForumThreadContentBlock]
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        ForumThreadNestedBlockContainer(accented: false) {
            VStack(alignment: .leading, spacing: 10) {
                Label(lockedText, systemImage: "lock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForumColors.orangeAccent)
                ForumThreadContentBlocksView(
                    blocks: blocks,
                    fallbackText: "",
                    refererURL: refererURL,
                    inlineImageLoadingContext: inlineImageLoadingContext,
                    onImageTap: onImageTap,
                    onURLTap: onURLTap
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ForumColors.orangeAccent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private var lockedText: String {
        if let cost {
            return L10n.string("forum.thread.locked_cost", cost)
        }
        return L10n.string("forum.thread.locked")
    }
}

private struct ForumThreadCodeBlockView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.92))
            .textSelection(.enabled)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ForumThreadTableBlockView: View {
    let rows: [[ForumThreadTableCell]]
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(rows[rowIndex].indices, id: \.self) { cellIndex in
                        ForumThreadTableCellView(
                            cell: rows[rowIndex][cellIndex],
                            refererURL: refererURL,
                            inlineImageLoadingContext: inlineImageLoadingContext,
                            onImageTap: onImageTap,
                            onURLTap: onURLTap
                        )
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(ForumColors.brownLight.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct ForumThreadTableCellView: View {
    let cell: ForumThreadTableCell
    let refererURL: URL
    let inlineImageLoadingContext: NovelInlineImageLoadingContext?
    let onImageTap: (String, URL, String?, URL) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        ForumThreadContentBlocksView(
            blocks: cell.blocks,
            fallbackText: "",
            refererURL: refererURL,
            inlineImageLoadingContext: inlineImageLoadingContext,
            onImageTap: onImageTap,
            onURLTap: onURLTap
        )
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cell.isHeader ? ForumColors.accentFill.opacity(0.5) : ForumColors.creamBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(ForumColors.brownLight.opacity(0.2))
                    .frame(width: 1)
            }
    }
}

private struct ForumThreadPostHeader: View {
    let post: ForumThreadPost
    let onUserTap: (String, String?) -> Void
    let onURLTap: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            YamiboRemoteImage(request: post.author.avatarURL.map { YamiboImageRequest(url: $0) }) { image in
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

            VStack(alignment: .leading, spacing: 3) {
                if let uid = post.author.uid {
                    Button(post.author.name) {
                        onUserTap(uid, post.author.name)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ForumColors.brownPrimary)
                } else {
                    Text(post.author.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ForumColors.textDark)
                }

                HStack(spacing: 8) {
                    if let floorText = post.floorText {
                        Text(floorText)
                    }
                    if let postedAtText = post.postedAtText {
                        Text(postedAtText)
                    }
                }
                .font(.caption)
                .foregroundStyle(ForumColors.brownLight)
            }

            Spacer(minLength: 0)

            if !post.manageActions.isEmpty {
                ForumThreadManageActionsView(actions: post.manageActions, onURLTap: onURLTap)
            }

            if post.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.secondaryText)
                    .accessibilityLabel(L10n.string("forum.thread.pinned"))
            }
        }
    }
}

private struct ForumThreadManageActionsView: View {
    let actions: [ForumThreadManageAction]
    let onURLTap: (URL) -> Void

    var body: some View {
        if let singleAction = actions.single {
            Button {
                onURLTap(singleAction.url)
            } label: {
                Text(singleAction.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.orangeAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("forum.thread.manage_action"))
        } else {
            Menu {
                ForEach(actions) { action in
                    Button(action.title) {
                        onURLTap(action.url)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ForumColors.orangeAccent)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(L10n.string("forum.thread.manage_action"))
        }
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}

private struct ForumThreadReaderPageNavigationView: View {
    let navigation: ForumPageNavigation?
    let currentPage: Int
    let goToPage: (Int) -> Void

    var body: some View {
        if let navigation, (navigation.totalPages ?? navigation.currentPage) > 1 {
            HStack(spacing: 12) {
                Button {
                    goToPage(currentPage - 1)
                } label: {
                    Label(L10n.string("forum.board.previous_page"), systemImage: "chevron.left")
                }
                .disabled(currentPage <= 1)

                Spacer()

                Text(pageText(navigation))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ForumColors.secondaryText)

                Spacer()

                Button {
                    goToPage(currentPage + 1)
                } label: {
                    Label(L10n.string("forum.board.next_page"), systemImage: "chevron.right")
                }
                .disabled(navigation.totalPages.map { currentPage >= $0 } ?? false)
            }
            .font(.subheadline)
            .buttonStyle(.bordered)
            .tint(ForumColors.brownEmphasis)
        }
    }

    private func pageText(_ navigation: ForumPageNavigation) -> String {
        if let totalPages = navigation.totalPages {
            return L10n.string("forum.board.page_count", navigation.currentPage, totalPages)
        }
        return L10n.string("forum.board.current_page", navigation.currentPage)
    }
}

struct ForumThreadReaderLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.string("common.loading"))
                .font(.subheadline)
                .foregroundStyle(ForumColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

struct ForumThreadReaderErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ForumColors.orangeAccent)
            Text(message)
                .font(.body)
                .foregroundStyle(ForumColors.textDark)
                .multilineTextAlignment(.center)
            Button {
                retry()
            } label: {
                Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .forumCardBackground()
    }
}
