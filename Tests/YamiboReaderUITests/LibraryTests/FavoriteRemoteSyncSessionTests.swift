import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@MainActor
final class FavoriteRemoteSyncSessionTests: XCTestCase {
    func testSnapshotLoadsInterruptsRunningTaskAndPersistsHiddenCard() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-snapshot")
        let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
        let runStore = FavoriteSyncRunStore(defaults: defaults, key: "sync-runs")
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
        try await runStore.save(runningSnapshot)

        let session = try makeSyncSession(runStore: runStore)
        await session.load()

        XCTAssertEqual(session.snapshot?.runID, "sync-run")
        XCTAssertEqual(session.snapshot?.status, .interrupted)
        XCTAssertEqual(session.snapshot?.warnings, [.taskLost])
        let interrupted = await runStore.latestSnapshot()
        XCTAssertEqual(interrupted?.status, .interrupted)

        await session.hideCard()
        let hidden = await runStore.latestSnapshot()
        XCTAssertTrue(hidden?.isHiddenFromFavoritePage == true)
    }

    func testStartCompletesAndResumeUsesPersistedTargetCategory() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-complete")
        let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
        let runStore = FavoriteSyncRunStore(defaults: defaults, key: "sync-runs")
        let recorder = FavoriteRemoteSyncTestRecorder()
        let session = try makeSyncSession(
            runStore: runStore,
            runnerOverride: { snapshot, _, persist in
                await recorder.record(snapshot.targetCategoryID)
                var final = snapshot
                final.status = .completed
                final.phase = .completed
                final.importedCount = 2
                final.skippedCount = 1
                final.uploadTargetCount = 1
                final.uploadedCount = 1
                final.failedCount = 1
                final.finishedAt = .now
                await persist(final)
                return final
            }
        )
        await session.load()

        let firstRunID = await session.start(targetCategoryID: FavoriteCategory.defaultID)
        try await waitForStatus(.completed, in: session)
        XCTAssertEqual(session.snapshot?.runID, firstRunID)
        XCTAssertEqual(session.snapshot?.importedCount, 2)
        XCTAssertEqual(session.snapshot?.skippedCount, 1)
        XCTAssertEqual(session.snapshot?.uploadedCount, 1)
        XCTAssertEqual(session.snapshot?.failedCount, 1)

        let secondRunID = await session.resume()
        try await waitForStatus(.completed, in: session)
        XCTAssertNotEqual(secondRunID, firstRunID)
        let recordedCategoryIDs = await recorder.recordedCategoryIDs()
        XCTAssertEqual(recordedCategoryIDs, [FavoriteCategory.defaultID, FavoriteCategory.defaultID])
        let savedStatus = await runStore.latestSnapshot()?.status
        XCTAssertEqual(savedStatus, .completed)
    }

    func testInterruptCancelsRunningTaskAndPersistsInterruptedStatus() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-interrupt")
        let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
        let runStore = FavoriteSyncRunStore(defaults: defaults, key: "sync-runs")
        let session = try makeSyncSession(
            runStore: runStore,
            runnerOverride: { snapshot, interruptionReason, persist in
                // Emulates the engine's cancellation handling: a cooperative
                // cancellation ends the run as interrupted with the session's
                // provided reason.
                var final = snapshot
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    final.status = .completed
                    final.phase = .completed
                } catch {
                    final.status = .interrupted
                    final.phase = .interrupted
                    final.warnings.append(interruptionReason() ?? .interrupted)
                }
                final.finishedAt = .now
                await persist(final)
                return final
            }
        )
        await session.load()

        _ = await session.start(targetCategoryID: FavoriteCategory.defaultID)
        XCTAssertEqual(session.snapshot?.status, .running)
        await session.interrupt()
        try await waitForStatus(.interrupted, in: session)

        XCTAssertEqual(session.snapshot?.warnings.contains(.interruptedByUser), true)
        XCTAssertNil(session.errorMessage)
        let saved = await runStore.latestSnapshot()
        XCTAssertEqual(saved?.runID, session.snapshot?.runID)
        XCTAssertEqual(saved?.status, .interrupted)
        XCTAssertEqual(saved?.warnings.isEmpty, false)
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
    runStore: FavoriteSyncRunStore? = nil,
    runnerOverride: FavoriteRemoteSyncSession.EngineRunner? = nil
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
        runStore: runStore ?? FavoriteSyncRunStore(defaults: defaults, key: "sync-runs"),
        contentCoverStore: ContentCoverStore(defaults: defaults, key: "content-covers"),
        makeFavoriteRepository: { FavoriteRepository(client: await makeClient()) },
        makeForumThreadReaderRepository: { ForumThreadReaderRepository(client: await makeClient(), cacheStore: forumCacheStore) },
        makeThreadRouteResolver: { YamiboThreadRouteResolver(client: await makeClient()) },
        runnerOverride: runnerOverride
    )
}
