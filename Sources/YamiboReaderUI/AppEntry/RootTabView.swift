import SwiftUI
import YamiboReaderCore
import UIKit

public struct RootTabView: View {
    private let appModel: YamiboAppModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var clipboardForumLinkPasteboardReader = ClipboardForumLinkPasteboardReader()

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
            await observeFavoriteLibraryChanges()
        }
        .task {
            await observeSettingsStoreChanges()
        }
        .task {
            await observeReadingProgressChanges()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appModel.synchronizeWebDAVIfNeeded()
                presentClipboardForumLinkPromptIfNeeded()
            case .background:
                appModel.flushWebDAVSyncBeforeBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .modifier(ClipboardForumLinkPromptAlert(appModel: appModel, isActive: !appModel.hasActiveReaderPresentation))
    }

    private var content: some View {
        TabView(selection: selectedTabBinding) {
            ForumNavigationHostView(appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.forum)
                .tabItem {
                    Label(L10n.string("tab.forum"), systemImage: "text.bubble")
                }

            FavoritesNavigationHostView(appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.favorites)
                .tabItem {
                    Label(L10n.string("tab.favorites"), systemImage: "heart.text.square")
                }

            MineHomeView(appContext: appModel.appContext, appModel: appModel)
                .tag(AppTab.mine)
                .tabItem {
                    Label(L10n.string("tab.mine"), systemImage: "person.crop.circle")
                }
        }
        .modifier(ReaderPresentationModifier(appModel: appModel))
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { appModel.selectedTab },
            set: { appModel.selectTab($0) }
        )
    }

    private func observeFavoriteLibraryChanges() async {
        for await notification in NotificationCenter.default.notifications(named: FavoriteLibraryStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[FavoriteLibraryStore.changeIDUserInfoKey] as? String,
                  changeID == appModel.appContext.localFavoriteLibraryStore.changeID else {
                continue
            }
            appModel.scheduleWebDAVUploadForLocalChange()
        }
    }

    private func observeSettingsStoreChanges() async {
        for await notification in NotificationCenter.default.notifications(named: SettingsStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[SettingsStore.changeIDUserInfoKey] as? String,
                  changeID == appModel.appContext.settingsStore.changeID else {
                continue
            }
            appModel.scheduleWebDAVUploadForLocalChange(touchesAppSettings: true)
        }
    }

    private func observeReadingProgressChanges() async {
        await Self.observeReadingProgressChanges(appContext: appModel.appContext) {
            appModel.scheduleWebDAVUploadForReadingProgressChange()
        }
    }

    static func observeReadingProgressChanges(
        appContext: YamiboAppContext,
        onChange: @escaping @MainActor () -> Void
    ) async {
        for await notification in NotificationCenter.default.notifications(named: ReadingProgressStore.didChangeNotification) {
            guard !Task.isCancelled else { return }
            guard let changeID = notification.userInfo?[ReadingProgressStore.changeIDUserInfoKey] as? String,
                  changeID == appContext.readingProgressStore.changeID else {
                continue
            }
            await MainActor.run(body: onChange)
        }
    }

    private func presentClipboardForumLinkPromptIfNeeded() {
        Task { @MainActor in
            guard let url = await clipboardForumLinkPasteboardReader.promptURL(from: UIPasteboard.general) else { return }
            appModel.presentClipboardForumLinkPrompt(url: url)
        }
    }
}

private struct ClipboardForumLinkPromptAlert: ViewModifier {
    let appModel: YamiboAppModel
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .alert(item: promptBinding) { prompt in
                Alert(
                    title: Text(L10n.string("clipboard_forum_link.title")),
                    message: Text(prompt.url.absoluteString),
                    primaryButton: .default(Text(L10n.string("clipboard_forum_link.open"))) {
                        appModel.confirmClipboardForumLinkPrompt(prompt)
                    },
                    secondaryButton: .cancel(Text(L10n.string("common.cancel"))) {
                        appModel.dismissClipboardForumLinkPrompt()
                    }
                )
            }
    }

    private var promptBinding: Binding<ClipboardForumLinkPrompt?> {
        Binding(
            get: { isActive ? appModel.clipboardForumLinkPrompt : nil },
            set: { prompt in
                if prompt == nil, isActive {
                    appModel.dismissClipboardForumLinkPrompt()
                }
            }
        )
    }
}

private struct ReaderPresentationModifier: ViewModifier {
    let appModel: YamiboAppModel

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: binding(for: \.activeReaderContext)) { context in
                ReaderContainerView(context: context, appModel: appModel)
                    .ignoresSafeArea()
                    .modifier(ClipboardForumLinkPromptAlert(appModel: appModel, isActive: true))
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
                    .modifier(ClipboardForumLinkPromptAlert(appModel: appModel, isActive: true))
            }
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
