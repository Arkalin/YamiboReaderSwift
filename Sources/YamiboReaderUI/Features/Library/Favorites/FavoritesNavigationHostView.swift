import SwiftUI
import YamiboReaderCore

struct FavoritesNavigationHostView: View {
    let dependencies: LibraryDependencies
    let appModel: YamiboAppModel

    var body: some View {
        NavigationStack {
            LocalFavoritesRootView(dependencies: dependencies, appModel: appModel)
        }
    }
}
