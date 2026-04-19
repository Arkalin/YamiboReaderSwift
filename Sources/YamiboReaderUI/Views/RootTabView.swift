import SwiftUI
import YamiboReaderCore

public struct RootTabView: View {
    private let forumURL = URL(string: "https://bbs.yamibo.com/forum.php?mobile=2")!
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

            MigrationStatusView()
                .tag(AppTab.migration)
                .tabItem {
                    Label("迁移", systemImage: "hammer")
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

private struct MigrationStatusView: View {
    var body: some View {
        NavigationStack {
            List {
                Label("论坛浏览容器已迁到 SwiftUI + WebKit", systemImage: "checkmark.circle.fill")
                Label("收藏页同步、基础解析与数据模型已迁移", systemImage: "checkmark.circle.fill")
                Label("原生小说阅读器与漫画阅读器待继续迁移", systemImage: "clock")
            }
            .navigationTitle("Swift 迁移状态")
        }
    }
}
