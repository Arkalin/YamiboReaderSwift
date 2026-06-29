import SwiftUI
import YamiboReaderCore

public struct ForumNavigationHostView: View {
    @State private var model: ForumHomeViewModel
    @State private var path: [ForumDestination] = []
    @State private var actionErrorMessage: String?

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
                onCarouselTap: openCarouselItem,
                onSearchTap: openSearchFallback
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
                        onPinnedTap: openPinnedItem,
                        onThreadTap: openThread,
                        onSearchTap: {
                            openBoardSearchFallback(fid: fid)
                        },
                        onPostThreadTap: {
                            openPostThreadFallback(fid: fid)
                        }
                    )
                case let .web(url):
                    ForumBrowserView(
                        url: url,
                        appContext: appContext,
                        appModel: appModel,
                        listensToForumNavigationRequest: false
                    )
                }
            }
            .navigationTitle(L10n.string("forum.default_title"))
        }
        .task {
            await model.load()
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
            openThread(threadURL, title: nil)
        case let .web(url):
            path.append(.web(url))
        }
    }

    private func openBoard(_ board: ForumBoardSummary) {
        path.append(.board(fid: board.fid, title: board.name, page: nil))
    }

    private func openCarouselItem(_ item: ForumHomeCarouselItem) {
        if item.threadID != nil {
            openThread(item.targetURL, title: nil)
        } else {
            path.append(.web(item.targetURL))
        }
    }

    private func openThread(_ url: URL, title: String?) {
        Task {
            do {
                let resolver = await appContext.makeThreadOpenResolver()
                let target = try await resolver.resolve(threadURL: url, title: title, favoriteType: .unknown)
                switch target {
                case let .novel(context):
                    appModel.presentReader(context)
                case let .manga(context):
                    await appModel.openManga(context)
                case let .web(url):
                    path.append(.web(url))
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func openThread(_ thread: ForumThreadSummary) {
        openThread(thread.url, title: thread.title)
    }

    private func openPinnedItem(_ item: ForumPinnedItem) {
        if item.threadID != nil {
            openThread(item.url, title: item.title)
        } else {
            path.append(.web(item.url))
        }
    }

    private func openSearchFallback() {
        var components = URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/search.php"
        components.queryItems = [
            .init(name: "mod", value: "forum"),
            .init(name: "mobile", value: "2")
        ]
        if let url = components.url {
            path.append(.web(url))
        }
    }

    private func openBoardSearchFallback(fid: String) {
        var components = URLComponents(url: YamiboRoute.baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/search.php"
        components.queryItems = [
            .init(name: "mod", value: "curforum"),
            .init(name: "srhfid", value: fid),
            .init(name: "mobile", value: "2")
        ]
        if let url = components.url {
            path.append(.web(url))
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
    case web(URL)
}
