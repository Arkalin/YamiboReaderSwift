import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif
import YamiboReaderCore
import YamiboReaderUI

@main
struct YamiboReaderIOSApp: App {
    @State private var appModel: YamiboAppModel

    init() {
        let initialTab = YamiboReaderIOSApp.resolveInitialTab()
        _appModel = State(initialValue: YamiboAppModel(appContext: YamiboAppContext(), initialTab: initialTab))
        #if canImport(AppIntents)
        YamiboAppShortcutsProvider.updateAppShortcutParameters()
        #endif
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
        case "mine", "my":
            .mine
        case "migration":
            .mine
        default:
            .forum
        }
        #else
        .forum
        #endif
    }
}

#if canImport(AppIntents)
struct YamiboSignInIntent: AppIntent {
    static let title: LocalizedStringResource = "百合会签到"
    static let description = IntentDescription("在后台检查并完成百合会每日签到")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await YamiboAppContext().makeAutoSignInService().signInIfNeeded(force: false)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}

struct YamiboAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: YamiboSignInIntent(),
                phrases: [
                    "使用 \(.applicationName) 进行百合会签到",
                    "在 \(.applicationName) 里进行百合会签到",
                    "让 \(.applicationName) 完成百合会签到"
                ],
                shortTitle: "百合会签到",
                systemImageName: "checkmark.circle"
            )
        ]
    }
}
#endif
