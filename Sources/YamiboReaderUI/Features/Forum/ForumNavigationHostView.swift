import SwiftUI
import YamiboReaderCore

public struct ForumNavigationHostView: View {
    @State private var model: ForumHomeViewModel
    @State private var path: [ForumDestination] = []
    @State private var actionErrorMessage: String?
    @State private var imageLoadingContext: YamiboImageLoadingContext?

    private let appContext: YamiboAppContext
    private let appModel: YamiboAppModel

    public init(appContext: YamiboAppContext, appModel: YamiboAppModel) {
        self.appContext = appContext
        self.appModel = appModel
        _model = State(wrappedValue: ForumHomeViewModel(appContext: appContext))
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ForumHomeView(
                model: model,
                onBoardTap: openBoard,
                onCarouselTap: openCarouselItem
            )
            .navigationDestination(for: ForumDestination.self) { destination in
                switch destination {
                case let .board(fid, title, page):
                    ForumBoardView(
                        model: ForumBoardViewModel(
                            fid: fid,
                            title: title,
                            initialPage: page ?? 1,
                            appContext: appContext
                        ),
                        onSubBoardTap: openBoard,
                        onPinnedTap: { openPinnedItem($0, containingFid: fid) },
                        onThreadTap: { openThread($0, containingFid: fid) },
                        onAuthorTap: openUserSpace,
                        onSearchTap: {
                            path.append(.search(fid: fid))
                        },
                        onPostThreadTap: {
                            openPostThreadFallback(fid: fid)
                        }
                    )
                    .forumNavigationBarStyle()
                case let .search(fid):
                    ForumSearchView(
                        model: ForumSearchViewModel(forumID: fid, appContext: appContext),
                        onThreadTap: { openThread($0, containingFid: fid) },
                        onAuthorTap: openUserSpace,
                        onURLSubmit: {
                            route($0, source: .external)
                        }
                    )
                    .forumNavigationBarStyle()
                case let .userSpace(uid, name, section, subPage):
                    UserSpaceView(
                        model: UserSpaceViewModel(
                            uid: uid,
                            titleHint: name,
                            initialSection: section,
                            initialSubPage: subPage,
                            appContext: appContext
                        ),
                        onThreadTap: { openThread($0, title: $1, containingFid: nil) },
                        onUserTap: openUserSpace,
                        onSectionTap: openUserSpaceSection,
                        onBlogTap: openBlog,
                        onPrivateMessageTap: openPrivateMessage,
                        onMessageCenterTap: openMessageCenter,
                        onWebTap: {
                            path.append(.web($0))
                        }
                    )
                    .forumNavigationBarStyle()
                case let .messageCenter(tab):
                    MessageCenterView(
                        model: MessageCenterViewModel(initialTab: tab, appContext: appContext),
                        onPrivateMessageTap: openPrivateMessage,
                        onUserTap: openUserSpace,
                        onWebTap: {
                            path.append(.web($0))
                        }
                    )
                    .forumNavigationBarStyle()
                case let .privateMessage(uid, name):
                    PrivateMessageView(
                        model: PrivateMessageViewModel(
                            uid: uid,
                            titleHint: name,
                            appContext: appContext
                        )
                    )
                    .forumNavigationBarStyle()
                case let .blog(blogID, uid, title):
                    BlogReaderView(
                        model: BlogReaderViewModel(blogID: blogID, uid: uid, titleHint: title, appContext: appContext),
                        onUserTap: openUserSpace,
                        onWebTap: {
                            path.append(.web($0))
                        }
                    )
                    .forumNavigationBarStyle()
                case let .novelDetail(context):
                    ForumNovelDetailView(
                        model: ForumNovelDetailViewModel(context: context, appContext: appContext),
                        onChapterTap: { launchContext in
                            appModel.presentReader(launchContext)
                        },
                        onUserTap: openUserSpace,
                        onViewThread: {
                            path.append(.threadReader(ThreadReaderLaunchContext(thread: context.thread, title: context.title, authorID: context.authorID)))
                        }
                    )
                    .forumNavigationBarStyle()
                case let .mangaDetail(context):
                    ForumMangaDetailView(
                        model: ForumMangaDetailViewModel(context: context, appContext: appContext),
                        onChapterTap: { launchContext in
                            Task {
                                await appModel.openManga(launchContext)
                            }
                        },
                        onViewThread: {
                            path.append(.threadReader(ThreadReaderLaunchContext(thread: context.thread, title: context.title)))
                        }
                    )
                    .forumNavigationBarStyle()
                case let .threadReader(context):
                    ForumThreadReaderView(
                        model: ForumThreadReaderViewModel(context: context, appContext: appContext),
                        onUserTap: openUserSpace,
                        onURLTap: { route($0, source: .external) }
                    )
                        .forumNavigationBarStyle()
                case let .web(url):
                    ForumBrowserView(
                        url: url,
                        appContext: appContext,
                        appModel: appModel,
                        listensToForumNavigationRequest: false
                    )
                    .forumNavigationBarStyle()
                }
            }
            .navigationTitle(L10n.string("forum.default_title"))
            .yamiboInlineNavigationTitleDisplayMode()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        path.append(.search(fid: nil))
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(L10n.string("forum.home.search_placeholder"))
                }
            }
            .forumNavigationBarStyle()
        }
        .environment(\.yamiboImageLoadingContext, imageLoadingContext)
        .task {
            await model.load()
            await refreshImageLoadingContext()
        }
        .task {
            for await notification in NotificationCenter.default.notifications(named: SessionStore.didChangeNotification) {
                guard let changeID = notification.userInfo?[SessionStore.changeIDUserInfoKey] as? String,
                      changeID == appContext.sessionStore.changeID else {
                    continue
                }
                await refreshImageLoadingContext()
            }
        }
        .onChange(of: appModel.forumNavigationRequest?.id) { _, _ in
            guard let request = appModel.forumNavigationRequest else { return }
            route(request.url, source: request.source)
        }
        .alert(L10n.string("forum.open_native_failed"), isPresented: .constant(actionErrorMessage != nil), actions: {
            Button(L10n.string("common.ok")) {
                actionErrorMessage = nil
            }
        }, message: {
            Text(actionErrorMessage ?? "")
        })
    }

    private func route(_ url: URL, source: ForumNavigationSource) {
        switch ForumRouteResolver.resolve(url: url, source: source) {
        case .home:
            path = []
        case let .board(fid, title, page):
            path.append(.board(fid: fid, title: title, page: page))
        case let .thread(threadURL):
            openThread(threadURL, title: nil, containingFid: nil)
        case let .userSpace(uid, name):
            path.append(.userSpace(uid: uid, name: name, section: .space, subPage: .profile))
        case let .messageCenter(tab):
            path.append(.messageCenter(tab: tab))
        case let .privateMessage(uid, name):
            path.append(.privateMessage(uid: uid, name: name))
        case let .blog(blogID, uid, title):
            path.append(.blog(blogID: blogID, uid: uid, title: title))
        case let .web(url):
            path.append(.web(url))
        }
    }

    private func refreshImageLoadingContext() async {
        imageLoadingContext = await appContext.makeImagePipelineContext()
    }

    private func openBoard(_ board: ForumBoardSummary) {
        path.append(.board(fid: board.fid, title: board.name, page: nil))
    }

    private func openCarouselItem(_ item: ForumHomeCarouselItem) {
        if item.isThreadTarget {
            openThread(item.targetURL, title: nil, containingFid: nil)
        }
    }

    private func openThread(_ url: URL, title: String?, containingFid: String?) {
        Task {
            do {
                let resolver = await appContext.makeForumThreadRouteResolver()
                let target = try await resolver.resolve(
                    ThreadRouteRequest(
                        threadURL: url,
                        title: title,
                        tapContext: ForumThreadTapContext(containingFid: containingFid)
                    )
                )
                openThreadRouteTarget(target)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func openThread(_ thread: ForumThreadSummary, containingFid: String?) {
        Task {
            do {
                let resolver = await appContext.makeForumThreadRouteResolver()
                let target = try await resolver.resolve(
                    ThreadRouteRequest(
                        threadURL: thread.url,
                        threadID: thread.tid,
                        title: thread.title,
                        authorID: thread.authorID,
                        threadFid: thread.fid,
                        tapContext: ForumThreadTapContext(containingFid: containingFid)
                    )
                )
                openThreadRouteTarget(target)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func openThreadRouteTarget(_ target: ThreadRouteTarget) {
        switch target {
        case let .novelDetail(context):
            path.append(.novelDetail(context))
        case let .mangaDetail(context):
            path.append(.mangaDetail(context))
        case let .threadReader(context):
            path.append(.threadReader(context))
        case let .webFallback(url):
            path.append(.web(url))
        }
    }

    private func openUserSpace(uid: String, name: String?) {
        path.append(.userSpace(uid: uid, name: name, section: .space, subPage: .profile))
    }

    private func openUserSpaceSection(uid: String?, name: String?, section: UserSpaceSection, subPage: UserSpaceSubPage) {
        path.append(.userSpace(uid: uid, name: name, section: section, subPage: subPage))
    }

    private func openBlog(_ blog: UserSpaceBlogSummary) {
        path.append(.blog(blogID: blog.blogID, uid: blog.authorID, title: blog.title))
    }

    private func openPrivateMessage(uid: String, name: String?) {
        path.append(.privateMessage(uid: uid, name: name))
    }

    private func openMessageCenter(tab: MessageCenterTab) {
        path.append(.messageCenter(tab: tab))
    }

    private func openPinnedItem(_ item: ForumPinnedItem, containingFid: String?) {
        if item.threadID != nil {
            openThread(item.url, title: item.title, containingFid: containingFid)
        } else {
            path.append(.web(item.url))
        }
    }

    private func openPostThreadFallback(fid: String) {
        var components = URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/forum.php"
        components.queryItems = [
            .init(name: "mod", value: "post"),
            .init(name: "action", value: "newthread"),
            .init(name: "fid", value: fid),
            .init(name: "mobile", value: "2")
        ]
        if let url = components.url {
            path.append(.web(url))
        }
    }

}

private enum ForumDestination: Hashable {
    case board(fid: String, title: String?, page: Int?)
    case search(fid: String?)
    case userSpace(uid: String?, name: String?, section: UserSpaceSection, subPage: UserSpaceSubPage)
    case messageCenter(tab: MessageCenterTab)
    case privateMessage(uid: String, name: String?)
    case blog(blogID: String, uid: String?, title: String?)
    case novelDetail(NovelDetailLaunchContext)
    case mangaDetail(MangaDetailLaunchContext)
    case threadReader(ThreadReaderLaunchContext)
    case web(URL)
}
