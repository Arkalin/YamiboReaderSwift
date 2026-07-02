import SwiftUI
import YamiboReaderCore

struct FavoritesNavigationHostView: View {
    @State private var navigationPath: [FavoriteCollection] = []
    @State private var isSelecting = false

    let appContext: YamiboAppContext
    let appModel: YamiboAppModel

    var body: some View {
        NavigationStack(path: $navigationPath) {
            LocalFavoritesRootView(appContext: appContext, appModel: appModel)
        }
        #if os(iOS)
        .toolbar(isSelecting ? .hidden : .visible, for: .tabBar)
        #endif
        .onChange(of: navigationPath) { _, _ in
            isSelecting = false
        }
    }

    private var rootSelectionBinding: Binding<Bool> {
        Binding(
            get: {
                navigationPath.isEmpty && isSelecting
            },
            set: { newValue in
                guard navigationPath.isEmpty else { return }
                isSelecting = newValue
            }
        )
    }

    private func collectionSelectionBinding(for collection: FavoriteCollection) -> Binding<Bool> {
        Binding(
            get: {
                navigationPath.last?.id == collection.id && isSelecting
            },
            set: { newValue in
                guard navigationPath.last?.id == collection.id else { return }
                isSelecting = newValue
            }
        )
    }
}
