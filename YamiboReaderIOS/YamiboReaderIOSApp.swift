import SwiftUI
import YamiboReaderCore
import YamiboReaderUI

@main
struct YamiboReaderIOSApp: App {
    @State private var appModel: YamiboAppModel

    init() {
        let initialTab = YamiboReaderIOSApp.resolveInitialTab()
        _appModel = State(initialValue: YamiboAppModel(appContext: YamiboAppContext(), initialTab: initialTab))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(appModel: appModel)
        }
    }

    private static func resolveInitialTab() -> AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["START_TAB"]?.lowercased() {
        case "favorites":
            .favorites
        case "migration":
            .migration
        default:
            .forum
        }
        #else
        .forum
        #endif
    }
}
