import SwiftUI
#if canImport(AppIntents)
import AppIntents
#endif
import YamiboReaderCore
import YamiboReaderUI

@main
struct YamiboReaderApp: App {
    @State private var appModel: YamiboAppModel
    @State private var showsLaunchAnimation = true

    init() {
        let initialTab = YamiboReaderApp.resolveInitialTab()
        _appModel = State(initialValue: YamiboAppModel(appContext: YamiboAppContext(), initialTab: initialTab))
        #if canImport(AppIntents)
        YamiboAppShortcutsProvider.updateAppShortcutParameters()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView(appModel: appModel)

                if showsLaunchAnimation {
                    LaunchAnimationView {
                        showsLaunchAnimation = false
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }

    private static func resolveInitialTab() -> AppTab {
        let settings = SettingsStore.loadSync()
        return AppTabLaunchResolver.resolveInitialTab(homePage: settings.homePage)
    }
}

private struct LaunchAnimationView: View {
    let onCompletion: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false
    @State private var isFinishing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                HStack(spacing: 18) {
                    Image("LaunchIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize(for: proxy.size), height: iconSize(for: proxy.size))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Text(L10n.string("app.name"))
                        .font(.system(size: titleSize(for: proxy.size), weight: .heavy, design: .rounded))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: proxy.size.width * 0.78)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.82)
                .scaleEffect(isPresented ? 1 : 0.94)
                .offset(y: isPresented ? 0 : 18)
                .opacity(isFinishing ? 0 : (isPresented ? 1 : 0))
                .animation(.spring(response: 0.72, dampingFraction: 0.86), value: isPresented)
                .animation(.easeOut(duration: 0.35), value: isFinishing)
            }
        }
        .task {
            isPresented = true

            try? await Task.sleep(for: .seconds(1.35))
            isFinishing = true

            try? await Task.sleep(for: .seconds(0.35))
            onCompletion()
        }
    }

    private func iconSize(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.145, 46), 64)
    }

    private func titleSize(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.082, 26), 38)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var titleColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

#if canImport(AppIntents)
struct YamiboSignInIntent: AppIntent {
    static let title = LocalizedStringResource(
        "app.intent.sign_in.title",
        table: "Localizable"
    )
    static let description = IntentDescription(
        LocalizedStringResource(
            "app.intent.sign_in.description",
            table: "Localizable"
        )
    )
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
                shortTitle: LocalizedStringResource(
                    "app.intent.sign_in.title",
                    table: "Localizable"
                ),
                systemImageName: "checkmark.circle"
            )
        ]
    }
}
#endif
