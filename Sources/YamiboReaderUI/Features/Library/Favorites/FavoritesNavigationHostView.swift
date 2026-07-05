import SwiftUI
import YamiboReaderCore

struct FavoritesNavigationHostView: View {
    let appContext: YamiboAppContext
    let appModel: YamiboAppModel

    var body: some View {
        NavigationStack {
            LocalFavoritesRootView(appContext: appContext, appModel: appModel)
        }
    }
}
