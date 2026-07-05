import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

final class YamiboAppModelWebDAVTests: XCTestCase {
    @MainActor
    func testReadingProgressChangeSchedulesWebDAVLocalUpdate() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "app-model-reading-progress-webdav")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let webDAVSettingsStore = WebDAVSyncSettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "webdav"
        )
        try await webDAVSettingsStore.save(WebDAVSyncSettings(isAutoSyncEnabled: true))
        let appContext = YamiboAppContext(webDAVSyncSettingsStore: webDAVSettingsStore)
        let appModel = YamiboAppModel(appContext: appContext)

        appModel.scheduleWebDAVUploadForReadingProgressChange()

        let localUpdatedAt = try await Self.waitForLocalUpdatedAt(in: webDAVSettingsStore)
        XCTAssertNotNil(localUpdatedAt)
        let appSettingsUpdatedAt = await webDAVSettingsStore.load().appSettingsUpdatedAt
        XCTAssertNil(appSettingsUpdatedAt)
    }

    @MainActor
    func testReadingProgressStoreNotificationSchedulesWebDAVLocalUpdate() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "app-model-reading-progress-notification")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let webDAVSettingsStore = WebDAVSyncSettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "webdav"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        try await webDAVSettingsStore.save(WebDAVSyncSettings(isAutoSyncEnabled: true))
        let appContext = YamiboAppContext(
            webDAVSyncSettingsStore: webDAVSettingsStore,
            readingProgressStore: readingProgressStore
        )
        let appModel = YamiboAppModel(appContext: appContext)
        let observerTask = Task {
            await RootTabView.observeReadingProgressChanges(appContext: appContext) {
                appModel.scheduleWebDAVUploadForReadingProgressChange()
            }
        }
        defer { observerTask.cancel() }
        try await Task.sleep(nanoseconds: 50_000_000)

        try await readingProgressStore.saveNovel(NovelReadingPosition(threadID: "2701", view: 2))

        let localUpdatedAt = try await Self.waitForLocalUpdatedAt(in: webDAVSettingsStore)
        XCTAssertNotNil(localUpdatedAt)
        let appSettingsUpdatedAt = await webDAVSettingsStore.load().appSettingsUpdatedAt
        XCTAssertNil(appSettingsUpdatedAt)
    }

    private static func waitForLocalUpdatedAt(
        in store: WebDAVSyncSettingsStore,
        timeout: TimeInterval = 1
    ) async throws -> Date? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let localUpdatedAt = await store.load().localUpdatedAt {
                return localUpdatedAt
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return await store.load().localUpdatedAt
    }
}
