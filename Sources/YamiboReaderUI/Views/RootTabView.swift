import SwiftUI
import YamiboReaderCore

public struct RootTabView: View {
    private let forumURL = URL(string: "https://bbs.yamibo.com/forum.php?mobile=2")!
    private let mineURL = URL(string: "https://bbs.yamibo.com/home.php?mod=space&do=profile&mycenter=1&mobile=2")!
    private let appModel: YamiboAppModel

    @Environment(\.scenePhase) private var scenePhase

    public init(appModel: YamiboAppModel, initialTab: AppTab = .forum) {
        self.appModel = appModel
    }

    public var body: some View {
        Group {
            if appModel.isBootstrapping && appModel.bootstrapState == nil {
                ProgressView(L10n.string("app.initializing"))
            } else {
                content
            }
        }
        .task {
            await appModel.bootstrapIfNeeded()
        }
        .task {
            await observeFavoriteStoreChanges()
        }
        .task {
            await observeSessionStoreChanges()
        }
        .task {
            await observeAutoSignInStoreChanges()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appModel.synchronizeWebDAVIfNeeded()
            case .background:
                appModel.flushWebDAVSyncBeforeBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    private var content: some View {
        let favoriteStore = appModel.appContext.favoriteStore

        return TabView(selection: binding(for: \.selectedTab)) {
            ForumBrowserView(
                url: forumURL,
                appContext: appModel.appContext,
                appModel: appModel,
                listensToForumNavigationRequest: true
            )
                .tag(AppTab.forum)
                .tabItem {
                    Label(L10n.string("tab.forum"), systemImage: "globe.asia.australia")
                }

            FavoritesView(favoriteStore: favoriteStore, appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.favorites)
                .tabItem {
                    Label(L10n.string("tab.favorites"), systemImage: "heart.text.square")
                }

            ForumBrowserView(
                url: mineURL,
                appContext: appModel.appContext,
                appModel: appModel,
                listensToForumNavigationRequest: false
            )
                .tag(AppTab.mine)
                .tabItem {
                    Label(L10n.string("tab.mine"), systemImage: "person.crop.circle")
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

    private func observeFavoriteStoreChanges() async {
        for await notification in NotificationCenter.default.notifications(named: FavoriteStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[FavoriteStore.changeIDUserInfoKey] as? String,
                  changeID == appModel.appContext.favoriteStore.changeID else {
                continue
            }
            appModel.scheduleWebDAVUploadForLocalChange()
        }
    }

    private func observeSessionStoreChanges() async {
        for await notification in NotificationCenter.default.notifications(named: SessionStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[SessionStore.changeIDUserInfoKey] as? String,
                  changeID == appModel.appContext.sessionStore.changeID else {
                continue
            }
            appModel.scheduleWebDAVUploadForLocalChange()
        }
    }

    private func observeAutoSignInStoreChanges() async {
        for await notification in NotificationCenter.default.notifications(named: AutoSignInStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[AutoSignInStore.changeIDUserInfoKey] as? String,
                  changeID == appModel.appContext.autoSignInStore.changeID else {
                continue
            }
            appModel.scheduleWebDAVUploadForLocalChange()
        }
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
                    .id("native-\(context.id)")
            case let .web(context)?:
                MangaWebFallbackView(context: context, appModel: appModel)
                    .id("web-\(context.id)")
            case nil:
                Color.clear
            }
        }
    }
}
