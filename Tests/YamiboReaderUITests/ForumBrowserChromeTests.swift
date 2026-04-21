import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
@testable import YamiboReaderCore
@testable import YamiboReaderUI

#if os(iOS)
@MainActor
final class ForumBrowserChromeTests: XCTestCase {
    private var retainedWindows: [UIWindow] = []

    override func tearDown() {
        retainedWindows.removeAll()
        super.tearDown()
    }

    func testChromeShowsLocationLabelAndToolbarButtonsWhenEnabled() {
        let controller = hostChrome(showsLocationLabel: true)

        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-location-label", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-back-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-forward-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-reload-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-share-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-open-native-button", in: controller.view))
    }

    func testChromeHidesOnlyLocationLabelWhenDisabled() {
        let controller = hostChrome(showsLocationLabel: false)

        XCTAssertFalse(hasAccessibilityIdentifier("forum-browser-location-label", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-back-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-forward-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-reload-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-share-button", in: controller.view))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-open-native-button", in: controller.view))
    }

    func testForumBrowserViewRefreshesLocationLabelAfterSettingsChange() async throws {
        let defaultsName = "forum-browser-settings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)

        let settingsStore = SettingsStore(defaults: defaults, key: "settings")
        try await settingsStore.save(AppSettings(webBrowser: WebBrowserSettings(showsNavigationBar: false)))

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(defaults: defaults, key: "session"),
            settingsStore: settingsStore,
            favoriteStore: FavoriteStore(defaults: defaults, key: "favorites")
        )
        let controller = hostView(
            ForumBrowserView(
                url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                appContext: appContext,
                appModel: YamiboAppModel(appContext: appContext)
            )
        )

        XCTAssertTrue(waitForIdentifier("forum-browser-back-button", in: controller.view, exists: true))
        XCTAssertTrue(waitForIdentifier("forum-browser-location-label", in: controller.view, exists: false))

        try await settingsStore.save(AppSettings(webBrowser: WebBrowserSettings(showsNavigationBar: true)))

        XCTAssertTrue(waitForIdentifier("forum-browser-location-label", in: controller.view, exists: true))
        XCTAssertTrue(hasAccessibilityIdentifier("forum-browser-back-button", in: controller.view))
    }

    private func hostChrome(showsLocationLabel: Bool) -> UIHostingController<ForumBrowserChrome> {
        let model = ForumBrowserModel(
            initialURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!
        )
        model.recordVisit(
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
            title: "论坛 - 百合会"
        )
        return hostView(
            ForumBrowserChrome(
                model: model,
                showingHistory: .constant(false),
                openNative: {},
                showsLocationLabel: showsLocationLabel
            )
        )
    }

    private func hostView<Content: View>(_ view: Content) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        retainedWindows.append(window)
        return controller
    }

    private func waitForIdentifier(_ identifier: String, in view: UIView, exists: Bool) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if hasAccessibilityIdentifier(identifier, in: view) == exists {
                return true
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    private func hasAccessibilityIdentifier(_ identifier: String, in view: UIView) -> Bool {
        if view.accessibilityIdentifier == identifier {
            return true
        }

        for subview in view.subviews {
            if hasAccessibilityIdentifier(identifier, in: subview) {
                return true
            }
        }

        return false
    }
}
#endif
