import SwiftUI
import YamiboReaderCore

public struct RootTabView: View {
    private let forumURL = URL(string: "https://bbs.yamibo.com/forum.php?mobile=2")!
    private let mineURL = URL(string: "https://bbs.yamibo.com/home.php?mod=space&do=profile&mycenter=1&mobile=2")!
    private let appModel: YamiboAppModel

    public init(appModel: YamiboAppModel, initialTab: AppTab = .forum) {
        self.appModel = appModel
    }

    public var body: some View {
        Group {
            if appModel.isBootstrapping && appModel.bootstrapState == nil {
                ProgressView("初始化中…")
            } else {
                content
            }
        }
        .task {
            await appModel.bootstrapIfNeeded()
        }
    }

    private var content: some View {
        let favoriteStore = appModel.appContext.favoriteStore

        return TabView(selection: binding(for: \.selectedTab)) {
            ForumBrowserView(url: forumURL, appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.forum)
                .tabItem {
                    Label("论坛", systemImage: "globe.asia.australia")
                }

            FavoritesView(favoriteStore: favoriteStore, appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.favorites)
                .tabItem {
                    Label("收藏", systemImage: "heart.text.square")
                }

            ForumBrowserView(url: mineURL, appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.mine)
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
        .modifier(ReaderPresentationModifier(appModel: appModel))
    }

    private func binding<Value>(for keyPath: ReferenceWritableKeyPath<YamiboAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { appModel[keyPath: keyPath] },
            set: { appModel[keyPath: keyPath] = $0 }
        )
    }
}

private struct ReaderPresentationModifier: ViewModifier {
    let appModel: YamiboAppModel

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .fullScreenCover(item: binding(for: \.activeReaderContext)) { context in
                ReaderContainerView(context: context, appModel: appModel)
                    .ignoresSafeArea()
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { appModel.activeMangaRoute != nil },
                    set: { isPresented in
                        if !isPresented {
                            appModel.dismissManga()
                        }
                    }
                )
            ) {
                MangaPresentationHostView(appModel: appModel)
                    .ignoresSafeArea()
            }
        #else
        content
            .sheet(item: binding(for: \.activeReaderContext)) { context in
                ReaderContainerView(context: context, appModel: appModel)
            }
            .sheet(
                isPresented: Binding(
                    get: { appModel.activeMangaRoute != nil },
                    set: { isPresented in
                        if !isPresented {
                            appModel.dismissManga()
                        }
                    }
                )
            ) {
                MangaPresentationHostView(appModel: appModel)
            }
        #endif
    }

    private func binding<Value>(for keyPath: ReferenceWritableKeyPath<YamiboAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { appModel[keyPath: keyPath] },
            set: { appModel[keyPath: keyPath] = $0 }
        )
    }
}

private struct MangaPresentationHostView: View {
    let appModel: YamiboAppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch appModel.activeMangaRoute {
            case let .native(context)?:
                MangaReaderView(context: context, appModel: appModel)
            case let .web(context)?:
                MangaWebFallbackView(context: context, appModel: appModel)
            case nil:
                Color.clear
            }
        }
    }
}
