import SwiftUI
import YamiboReaderCore

enum ForumDestination: Hashable {
    case board(fid: String, title: String?, page: Int?)
    case search(fid: String?)
    case userSpace(uid: String?, name: String?, section: UserSpaceSection, subPage: UserSpaceSubPage)
    case messageCenter(tab: MessageCenterTab)
    case privateMessage(uid: String, name: String?)
    case blog(blogID: String, uid: String?, title: String?)
    case novelDetail(NovelDetailLaunchContext)
    case mangaDetail(MangaDetailLaunchContext)
    case threadReader(ThreadNovelLaunchContext)
    /// A thread URL that still needs `YamiboThreadRouteResolver` before it can
    /// render: the pushed screen resolves in place (spinner first), so the
    /// findpost page lookup stays visible instead of happening before any
    /// navigation. Only `.readerOverlay` stacks produce this.
    case threadLink(url: URL, title: String?, containingFid: String?, authorID: String?, isDiscussionView: Bool)
    case web(URL)
}

/// How a `ForumDestinationNavigator` treats thread links.
enum ForumNavigationMode {
    /// The forum tab: thread taps go through content classification
    /// (novel/manga detail pages, direct manga reader, native thread reader).
    case forumTab
    /// A forum stack layered on top of an active reader (原帖/评论跳转 and the
    /// reader's chapter-comments sheet). Everything stays inside this stack:
    /// every thread link opens as a native thread reader page and full
    /// novel/manga readers are never launched, because a second reader cannot
    /// be presented while one is already covering the app.
    case readerOverlay
}

/// Path owner + route helpers shared by the forum tab and reader-overlay
/// forum stacks. Owns everything `ForumDestinationScreen` needs to wire its
/// destination views, so hosts only decide the root content and the mode.
@MainActor
@Observable
final class ForumDestinationNavigator {
    var path: [ForumDestination] = []
    var actionErrorMessage: String?

    @ObservationIgnored let dependencies: ForumDependencies
    @ObservationIgnored let appModel: YamiboAppModel
    @ObservationIgnored let mode: ForumNavigationMode
    /// The reader session's own thread IDs (the work plus, for smart manga,
    /// its chapter threads). Any thread opened inside the overlay that
    /// resolves to one of these is still the work's discussion companion, so
    /// it must keep `isDiscussionView: true` — otherwise its plain-thread
    /// history row would absorb the work's main-form row (browsing-history
    /// decision #14 / review finding P1-B: rows upsert by tid across kinds).
    @ObservationIgnored let discussionWorkTIDs: Set<String>

    init(
        dependencies: ForumDependencies,
        appModel: YamiboAppModel,
        mode: ForumNavigationMode,
        discussionWorkTIDs: Set<String> = []
    ) {
        self.dependencies = dependencies
        self.appModel = appModel
        self.mode = mode
        self.discussionWorkTIDs = discussionWorkTIDs
    }

    func threadLinkLaunchContext(
        for payload: YamiboThreadRoutePayload,
        isDiscussionView: Bool
    ) -> ThreadNovelLaunchContext {
        ThreadNovelLaunchContext(
            thread: payload.thread,
            title: payload.title,
            initialPage: payload.initialPage,
            targetPostID: payload.targetPostID,
            authorID: payload.authorID,
            isDiscussionView: isDiscussionView || discussionWorkTIDs.contains(payload.thread.tid)
        )
    }

    func push(_ destination: ForumDestination) {
        path.append(destination)
    }

    func route(_ url: URL, source: ForumNavigationSource, title: String? = nil) {
        switch ForumRouteResolver.resolve(url: url, source: source) {
        case .home:
            switch mode {
            case .forumTab:
                path = []
            case .readerOverlay:
                // There is no forum home inside an overlay stack, and popping
                // to its root would land on the original post instead — show
                // the web home so the link still leads somewhere sensible.
                push(.web(url))
            }
        case let .board(fid, title, page):
            push(.board(fid: fid, title: title, page: page))
        case let .thread(threadURL):
            openThread(
                threadURL,
                title: title,
                containingFid: nil,
                intent: source == .readerOrigin || source == .readerDiscussion ? .nativeThreadReader : .contentRoute,
                isDiscussionView: source == .readerDiscussion
            )
        case let .userSpace(uid, name):
            push(.userSpace(uid: uid, name: name, section: .space, subPage: .profile))
        case let .messageCenter(tab):
            push(.messageCenter(tab: tab))
        case let .privateMessage(uid, name):
            push(.privateMessage(uid: uid, name: name))
        case let .blog(blogID, uid, title):
            push(.blog(blogID: blogID, uid: uid, title: title))
        case let .web(url):
            push(.web(url))
        }
    }

    func openBoard(_ board: ForumBoardSummary) {
        push(.board(fid: board.fid, title: board.name, page: nil))
    }

    func openCarouselItem(_ item: ForumHomeCarouselItem) {
        if item.isThreadTarget {
            openThread(item.targetURL, title: nil, containingFid: nil)
        }
    }

    func openThread(
        _ url: URL,
        title: String?,
        containingFid: String?,
        intent: YamiboThreadRouteIntent = .contentRoute,
        isDiscussionView: Bool = false
    ) {
        if mode == .readerOverlay {
            pushThreadLink(url: url, title: title, containingFid: containingFid, isDiscussionView: isDiscussionView)
            return
        }
        Task {
            do {
                let resolver = await dependencies.makeThreadRouteResolver()
                let target = try await resolver.resolve(
                    YamiboThreadRouteRequest(
                        threadURL: url,
                        title: title,
                        intent: intent,
                        tapContext: YamiboThreadTapContext(containingFid: containingFid)
                    )
                )
                openYamiboThreadRouteTarget(target, isDiscussionView: isDiscussionView)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    func openThread(_ thread: ForumThreadSummary, containingFid: String?) {
        if mode == .readerOverlay {
            pushThreadLink(
                url: thread.url,
                title: thread.title,
                containingFid: containingFid ?? thread.fid,
                authorID: thread.authorID
            )
            return
        }
        Task {
            do {
                let resolver = await dependencies.makeThreadRouteResolver()
                let target = try await resolver.resolve(
                    YamiboThreadRouteRequest(
                        threadURL: thread.url,
                        threadID: thread.tid,
                        title: thread.title,
                        authorID: thread.authorID,
                        threadFid: thread.fid,
                        tapContext: YamiboThreadTapContext(containingFid: containingFid)
                    )
                )
                openYamiboThreadRouteTarget(target)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    func pushThreadLink(
        url: URL,
        title: String?,
        containingFid: String? = nil,
        authorID: String? = nil,
        isDiscussionView: Bool = false
    ) {
        push(.threadLink(
            url: url,
            title: title,
            containingFid: containingFid,
            authorID: authorID,
            isDiscussionView: isDiscussionView
        ))
    }

    func openUserSpace(uid: String, name: String?) {
        push(.userSpace(uid: uid, name: name, section: .space, subPage: .profile))
    }

    func openUserSpaceSection(uid: String?, name: String?, section: UserSpaceSection, subPage: UserSpaceSubPage) {
        push(.userSpace(uid: uid, name: name, section: section, subPage: subPage))
    }

    func openBlog(_ blog: UserSpaceBlogSummary) {
        push(.blog(blogID: blog.blogID, uid: blog.authorID, title: blog.title))
    }

    func openPrivateMessage(uid: String, name: String?) {
        push(.privateMessage(uid: uid, name: name))
    }

    func openMessageCenter(tab: MessageCenterTab) {
        push(.messageCenter(tab: tab))
    }

    func openPinnedItem(_ item: ForumPinnedItem, containingFid: String?) {
        if item.threadID != nil {
            openThread(item.url, title: item.title, containingFid: containingFid)
        } else {
            push(.web(item.url))
        }
    }

    func openPostThreadFallback(fid: String) {
        var components = URLComponents(url: YamiboDomain.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/forum.php"
        components.queryItems = [
            .init(name: "mod", value: "post"),
            .init(name: "action", value: "newthread"),
            .init(name: "fid", value: fid),
            .init(name: "mobile", value: "2")
        ]
        if let url = components.url {
            push(.web(url))
        }
    }

    private func openYamiboThreadRouteTarget(_ target: YamiboThreadRouteTarget, isDiscussionView: Bool = false) {
        switch target {
        case let .novel(payload):
            let context = NovelDetailLaunchContext(
                thread: payload.thread,
                title: payload.title,
                authorID: payload.authorID
            )
            push(.novelDetail(context))
        case let .manga(payload):
            let cleanBookName = MangaTitleCleaner.cleanBookName(payload.title)
            let context = MangaDetailLaunchContext(
                thread: payload.thread,
                title: cleanBookName,
                focusedChapterTID: payload.thread.tid,
                directoryNameHint: cleanBookName
            )
            push(.mangaDetail(context))
        case let .mangaDirect(payload):
            // Board's Smart Comic Mode is off (decision #2/#12): open the
            // manga reader directly for this one thread instead of pushing
            // `ForumMangaDetailView`, using the same full-screen presentation
            // path as favorites/likes/the chapter picker
            // (`appModel.presentMangaReader`) rather than a NavigationStack
            // destination. No directory concept applies here — this thread
            // is treated exactly like a normal thread (total principle,
            // decision #2), just rendered with the manga reader — so the
            // title is used as-is (no `cleanBookName` cleanup) and page 0 is
            // the only sensible start (no resume, matching
            // `ForumMangaDetailViewModel.launchContext(for chapter:)`'s
            // existing convention of never passing `initialPage`).
            let context = MangaLaunchContext(
                originalThreadID: payload.thread.tid,
                chapterTID: payload.thread.tid,
                displayTitle: payload.title,
                source: .forum,
                isSmartModeEnabled: false,
                forumID: payload.thread.fid
            )
            appModel.presentMangaReader(context)
        case let .thread(payload):
            let context = ThreadNovelLaunchContext(
                thread: payload.thread,
                title: payload.title,
                initialPage: payload.initialPage,
                targetPostID: payload.targetPostID,
                authorID: payload.authorID,
                isDiscussionView: isDiscussionView
            )
            push(.threadReader(context))
        case let .webFallback(url):
            push(.web(url))
        }
    }
}

/// The `NavigationStack` + `navigationDestination` wiring shared by the forum
/// tab and every reader-overlay forum stack, so all of them resolve the same
/// destinations identically.
struct ForumDestinationStackView<Root: View>: View {
    private let navigator: ForumDestinationNavigator
    private let root: Root

    init(navigator: ForumDestinationNavigator, @ViewBuilder root: () -> Root) {
        self.navigator = navigator
        self.root = root()
    }

    var body: some View {
        @Bindable var navigator = navigator
        return NavigationStack(path: $navigator.path) {
            root
                .navigationDestination(for: ForumDestination.self) { destination in
                    ForumDestinationScreen(destination: destination, navigator: navigator)
                }
        }
        .alert(L10n.string("forum.open_native_failed"), isPresented: actionErrorBinding, actions: {
            Button(L10n.string("common.ok")) {
                navigator.actionErrorMessage = nil
            }
        }, message: {
            Text(navigator.actionErrorMessage ?? "")
        })
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { navigator.actionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    navigator.actionErrorMessage = nil
                }
            }
        )
    }
}

struct ForumDestinationScreen: View {
    let destination: ForumDestination
    let navigator: ForumDestinationNavigator

    private var dependencies: ForumDependencies { navigator.dependencies }

    var body: some View {
        switch destination {
        case let .board(fid, title, page):
            ForumBoardView(
                model: ForumBoardViewModel(
                    fid: fid,
                    title: title,
                    initialPage: page ?? 1,
                    dependencies: dependencies
                ),
                onSubBoardTap: { navigator.openBoard($0) },
                onPinnedTap: { navigator.openPinnedItem($0, containingFid: fid) },
                onThreadTap: { navigator.openThread($0, containingFid: fid) },
                onAuthorTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onSearchTap: {
                    navigator.push(.search(fid: fid))
                },
                onPostThreadTap: {
                    navigator.openPostThreadFallback(fid: fid)
                }
            )
            .forumNavigationBarStyle()
        case let .search(fid):
            ForumSearchView(
                model: ForumSearchViewModel(forumID: fid, dependencies: dependencies),
                onThreadTap: { navigator.openThread($0, containingFid: fid) },
                onAuthorTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onURLSubmit: {
                    navigator.route($0, source: .external)
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
                    dependencies: dependencies
                ),
                onThreadTap: { navigator.openThread($0, title: $1, containingFid: nil) },
                onUserTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onSectionTap: { navigator.openUserSpaceSection(uid: $0, name: $1, section: $2, subPage: $3) },
                onBlogTap: { navigator.openBlog($0) },
                onPrivateMessageTap: { navigator.openPrivateMessage(uid: $0, name: $1) },
                onMessageCenterTap: { navigator.openMessageCenter(tab: $0) },
                onWebTap: {
                    navigator.push(.web($0))
                }
            )
            .forumNavigationBarStyle()
        case let .messageCenter(tab):
            MessageCenterView(
                model: MessageCenterViewModel(initialTab: tab, dependencies: dependencies),
                onPrivateMessageTap: { navigator.openPrivateMessage(uid: $0, name: $1) },
                onUserTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onWebTap: {
                    navigator.push(.web($0))
                }
            )
            .forumNavigationBarStyle()
        case let .privateMessage(uid, name):
            PrivateMessageView(
                model: PrivateMessageViewModel(
                    uid: uid,
                    titleHint: name,
                    dependencies: dependencies
                )
            )
            .forumNavigationBarStyle()
        case let .blog(blogID, uid, title):
            BlogReaderView(
                model: BlogReaderViewModel(blogID: blogID, uid: uid, titleHint: title, dependencies: dependencies),
                onUserTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onWebTap: {
                    navigator.push(.web($0))
                }
            )
            .forumNavigationBarStyle()
        case let .novelDetail(context):
            ForumNovelDetailView(
                model: ForumNovelDetailViewModel(context: context, dependencies: dependencies),
                onChapterTap: { launchContext in
                    navigator.appModel.presentNovelReader(launchContext)
                },
                onUserTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onViewThread: {
                    navigator.push(.threadReader(ThreadNovelLaunchContext(thread: context.thread, title: context.title, authorID: context.authorID, isDiscussionView: true)))
                }
            )
            .forumNavigationBarStyle()
        case let .mangaDetail(context):
            ForumMangaDetailView(
                model: ForumMangaDetailViewModel(context: context, dependencies: dependencies),
                onChapterTap: { launchContext in
                    navigator.appModel.presentMangaReader(launchContext)
                },
                onViewThread: {
                    navigator.push(.threadReader(ThreadNovelLaunchContext(thread: context.thread, title: context.title, isDiscussionView: true)))
                }
            )
            .forumNavigationBarStyle()
        case let .threadReader(context):
            ForumThreadReaderView(
                model: ForumThreadReaderViewModel(context: context, dependencies: dependencies),
                onUserTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onURLTap: { navigator.route($0, source: .external) }
            )
            .forumNavigationBarStyle()
        case let .threadLink(url, title, containingFid, authorID, isDiscussionView):
            ForumThreadLinkScreen(
                url: url,
                title: title,
                containingFid: containingFid,
                authorID: authorID,
                isDiscussionView: isDiscussionView,
                navigator: navigator
            )
            .forumNavigationBarStyle()
        case let .web(url):
            ForumBrowserView(
                url: url,
                sessionStore: dependencies.sessionStore,
                appModel: navigator.appModel,
                listensToForumNavigationRequest: false
            )
            .forumNavigationBarStyle()
        }
    }
}

/// Resolves a thread URL in place (native thread reader intent) and then
/// renders the thread reader, keeping the resolution visible where the user
/// tapped instead of blocking the navigation on a network round-trip. Used as
/// the reader overlay's root and for `.threadLink` pushes.
struct ForumThreadLinkScreen: View {
    let url: URL
    let title: String?
    let containingFid: String?
    let authorID: String?
    let isDiscussionView: Bool
    let navigator: ForumDestinationNavigator

    @State private var resolution: Resolution = .resolving

    private enum Resolution {
        case resolving
        case thread(ThreadNovelLaunchContext)
        case web(URL)
        case failed(String)
    }

    var body: some View {
        content
            .task {
                await resolveIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch resolution {
        case .resolving:
            VStack(spacing: 12) {
                ProgressView()
                Text(L10n.string("forum.thread_link.loading"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .forumPageBackground()
            .navigationTitle(title ?? L10n.string("forum.default_title"))
            .yamiboInlineNavigationTitleDisplayMode()
        case let .thread(context):
            ForumThreadReaderView(
                model: ForumThreadReaderViewModel(context: context, dependencies: navigator.dependencies),
                onUserTap: { navigator.openUserSpace(uid: $0, name: $1) },
                onURLTap: { navigator.route($0, source: .external) }
            )
        case let .web(webURL):
            ForumBrowserView(
                url: webURL,
                sessionStore: navigator.dependencies.sessionStore,
                appModel: navigator.appModel,
                listensToForumNavigationRequest: false
            )
        case let .failed(message):
            VStack(spacing: 12) {
                ContentUnavailableView(
                    message,
                    systemImage: "exclamationmark.triangle"
                )
                Button(L10n.string("common.retry")) {
                    resolution = .resolving
                    Task {
                        await resolveIfNeeded()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .forumPageBackground()
        }
    }

    private func resolveIfNeeded() async {
        guard case .resolving = resolution else { return }
        let resolver = await navigator.dependencies.makeThreadRouteResolver()
        do {
            let target = try await resolver.resolve(
                YamiboThreadRouteRequest(
                    threadURL: url,
                    title: title,
                    authorID: authorID,
                    intent: .nativeThreadReader,
                    tapContext: YamiboThreadTapContext(containingFid: containingFid)
                )
            )
            switch target {
            case let .thread(payload), let .novel(payload), let .manga(payload), let .mangaDirect(payload):
                guard !payload.thread.tid.isEmpty else {
                    resolution = .web(url)
                    return
                }
                resolution = .thread(
                    navigator.threadLinkLaunchContext(for: payload, isDiscussionView: isDiscussionView)
                )
            case let .webFallback(fallbackURL):
                resolution = .web(fallbackURL)
            }
        } catch {
            resolution = .failed(error.localizedDescription)
        }
    }
}
