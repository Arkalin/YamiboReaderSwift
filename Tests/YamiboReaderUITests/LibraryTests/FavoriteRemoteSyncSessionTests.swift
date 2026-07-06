import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@MainActor
final class FavoriteRemoteSyncSessionTests: XCTestCase {
    func testSnapshotLoadsInterruptsRunningTaskAndPersistsHiddenCard() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-snapshot")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let runningSnapshot = FavoriteRemoteSyncSnapshot(
            runID: "sync-run",
            status: .running,
            targetCategoryID: FavoriteCategory.defaultID,
            targetCategoryName: "默认",
            phase: .importing,
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            scannedCount: 2,
            importedCount: 1
        )
        try await settingsStore.save(AppSettings(favorites: FavoriteLibrarySettings(remoteSyncSnapshot: runningSnapshot)))

        let session = try makeSyncSession(settingsStore: settingsStore)
        await session.load()

        XCTAssertEqual(session.snapshot?.runID, "sync-run")
        XCTAssertEqual(session.snapshot?.status, .interrupted)
        XCTAssertEqual(session.snapshot?.warnings, [.taskLost])
        let interruptedSettings = await settingsStore.load()
        XCTAssertEqual(interruptedSettings.favorites.remoteSyncSnapshot?.status, .interrupted)

        await session.hideCard()
        let hiddenSettings = await settingsStore.load()
        XCTAssertTrue(hiddenSettings.favorites.remoteSyncSnapshot?.isHiddenFromFavoritePage == true)
    }

    func testStartCompletesAndResumeUsesPersistedTargetCategory() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-complete")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let recorder = FavoriteRemoteSyncTestRecorder()
        let session = try makeSyncSession(
            settingsStore: settingsStore,
            executor: { _, categoryID in
                await recorder.record(categoryID)
                return YamiboFavoriteSyncReport(
                    importedTargetIDs: ["imported-a", "imported-b"],
                    failedRemoteFavoriteIDs: ["remote-failed"],
                    markedMissingTargetIDs: ["missing-a"],
                    uploadTargetIDs: ["upload-a"]
                )
            }
        )
        await session.load()

        let firstRunID = await session.start(targetCategoryID: FavoriteCategory.defaultID)
        try await waitForStatus(.completed, in: session)
        XCTAssertEqual(session.snapshot?.runID, firstRunID)
        XCTAssertEqual(session.snapshot?.importedCount, 2)
        XCTAssertEqual(session.snapshot?.failedCount, 1)
        XCTAssertEqual(session.snapshot?.markedMissingCount, 1)
        XCTAssertEqual(session.snapshot?.uploadTargetCount, 1)
        // `.backgroundUnavailable` is environment-dependent: the test host's
        // `beginBackgroundTask` may return `.invalid`, in which case the
        // session appends it. Ignore it and assert the sync-outcome warnings.
        XCTAssertEqual(
            session.snapshot?.warnings.filter { $0 != .backgroundUnavailable },
            [.failedItems(count: 1), .uploadPending(count: 1)]
        )

        let secondRunID = await session.resume()
        try await waitForStatus(.completed, in: session)
        XCTAssertNotEqual(secondRunID, firstRunID)
        let recordedCategoryIDs = await recorder.recordedCategoryIDs()
        XCTAssertEqual(recordedCategoryIDs, [FavoriteCategory.defaultID, FavoriteCategory.defaultID])
        let savedStatus = await settingsStore.load().favorites.remoteSyncSnapshot?.status
        XCTAssertEqual(savedStatus, .completed)
    }

    func testInterruptCancelsRunningTaskAndPersistsInterruptedStatus() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-interrupt")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let session = try makeSyncSession(
            settingsStore: settingsStore,
            executor: { _, _ in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return YamiboFavoriteSyncReport(importedTargetIDs: ["late"])
            }
        )
        await session.load()

        _ = await session.start(targetCategoryID: FavoriteCategory.defaultID)
        XCTAssertEqual(session.snapshot?.status, .running)
        await session.interrupt()
        try await waitForStatus(.interrupted, in: session)

        let saved = await settingsStore.load()
        XCTAssertEqual(saved.favorites.remoteSyncSnapshot?.status, .interrupted)
        XCTAssertEqual(saved.favorites.remoteSyncSnapshot?.warnings.isEmpty, false)
    }

    private func waitForStatus(
        _ status: FavoriteRemoteSyncTaskStatus,
        in session: FavoriteRemoteSyncSession
    ) async throws {
        for _ in 0..<100 {
            if session.snapshot?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for remote sync status \(status)")
    }
}

private actor FavoriteRemoteSyncTestRecorder {
    private var categoryIDs: [String] = []

    func record(_ categoryID: String) {
        categoryIDs.append(categoryID)
    }

    func recordedCategoryIDs() -> [String] {
        categoryIDs
    }
}

/// Builds a `FavoriteRemoteSyncSession` backed by isolated per-test stores.
@MainActor
private func makeSyncSession(
    libraryStore: FavoriteLibraryStore? = nil,
    settingsStore: SettingsStore? = nil,
    executor: ((String, String) async throws -> YamiboFavoriteSyncReport)? = nil
) throws -> FavoriteRemoteSyncSession {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "favorite-sync-session-deps")
    let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
    let sessionStore = SessionStore(defaults: defaults, key: "session")
    let urlSession = YamiboNetworkConfiguration.makeSession()
    let forumCacheStore = ForumCacheStore(
        baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    @Sendable func makeClient() async -> YamiboClient {
        let sessionState = await sessionStore.load()
        return YamiboClient(
            session: urlSession,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
    }
    return FavoriteRemoteSyncSession(
        libraryStore: libraryStore ?? FavoriteLibraryStore(defaults: defaults, key: "local-favorites"),
        settingsStore: settingsStore ?? SettingsStore(defaults: defaults, key: "settings"),
        contentCoverStore: ContentCoverStore(defaults: defaults, key: "content-covers"),
        makeFavoriteRepository: { FavoriteRepository(client: await makeClient()) },
        makeForumThreadReaderRepository: { ForumThreadReaderRepository(client: await makeClient(), cacheStore: forumCacheStore) },
        makeThreadRouteResolver: { YamiboThreadRouteResolver(client: await makeClient()) },
        executor: executor
    )
}
