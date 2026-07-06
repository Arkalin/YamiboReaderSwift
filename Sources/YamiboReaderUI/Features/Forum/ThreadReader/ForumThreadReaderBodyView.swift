import SwiftUI
import YamiboReaderCore

struct ForumThreadReaderBodyView: View {
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
                ImageBrowserView(
                    items: request.items,
                    initialItemID: request.initialItemID,
                    mode: .multiple,
                    onDismiss: {
                        imageBrowserRequest = nil
                    }
                )
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
        guard let page else {
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
            source: YamiboImageSource(url: url, refererPageURL: refererURL),
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
