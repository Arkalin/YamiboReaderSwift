import SwiftUI
import YamiboReaderCore

struct FavoritesNavigationHostView: View {
    let appContext: YamiboAppContext
    let appModel: YamiboAppModel
    @State private var imageLoadingContext: YamiboImageLoadingContext?

    var body: some View {
        NavigationStack {
            LocalFavoritesRootView(appContext: appContext, appModel: appModel)
        }
        .environment(\.yamiboImageLoadingContext, imageLoadingContext)
        .task {
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
    }

    private func refreshImageLoadingContext() async {
        imageLoadingContext = await appContext.makeImagePipelineContext()
    }
}
