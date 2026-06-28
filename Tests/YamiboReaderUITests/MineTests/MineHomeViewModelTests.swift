import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MineHomeViewModelTests: XCTestCase {
    func testLoadRefreshesMatchingCachedProfileOncePerCredential() async throws {
        let fixture = try await makeMineHomeFixture(
            accountUID: "535977",
            cachedProfile: makeProfile(uid: "535977")
        )
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
    }

    func testLoadRefreshesMissingCachedProfileOnlyOncePerCredential() async throws {
        let fixture = try await makeMineHomeFixture()
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
    }

    func testManualRefreshStillRequestsProfileWhenCachedProfileExists() async throws {
        let fixture = try await makeMineHomeFixture(
            accountUID: "535977",
            cachedProfile: makeProfile(uid: "535977")
        )
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.load()
        await viewModel.refreshProfile()

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
    }

    func testLoadRefreshesWhenCachedProfileUIDConflictsWithSessionUID() async throws {
        let fixture = try await makeMineHomeFixture(
            accountUID: "535977",
            cachedProfile: makeProfile(uid: "111111")
        )
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
    }

    func testAutomaticRefreshFailureKeepsCachedProfileWithoutPresentingError() async throws {
        let fixture = try await makeMineHomeFixture(
            accountUID: "535977",
            cachedProfile: makeProfile(uid: "535977")
        )
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { _ in
            requestCount += 1
            throw MineProfileRefreshTestError.missingHandler
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
    }

    func testManualRefreshFailurePresentsErrorWhenCachedProfileExists() async throws {
        let fixture = try await makeMineHomeFixture(
            accountUID: "535977",
            cachedProfile: makeProfile(uid: "535977")
        )
        nonisolated(unsafe) var requestCount = 0
        nonisolated(unsafe) var shouldFail = false
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            if shouldFail {
                throw MineProfileRefreshTestError.missingHandler
            }
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.load()
        shouldFail = true
        await viewModel.refreshProfile()

        XCTAssertEqual(requestCount, 2)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
    }

    func testOfflineCacheQueueProjectsEntryCountGroupingOrderingProgressSpeedAndFailure() async throws {
        let fixture = try await makeMineHomeFixture()
        let activeImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        let pendingImage = try XCTUnwrap(URL(string: "https://img.example.com/100-2.jpg"))
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(favoriteID: "favorite-b", favoriteTitle: "作品B", tid: "300")
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(
                favoriteID: "favorite-a",
                favoriteTitle: "作品A",
                tid: "200"
            )
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(
                favoriteID: "favorite-a",
                favoriteTitle: "作品A",
                tid: "100",
                targetImageURLs: [activeImage, pendingImage]
            )
        )
        try await fixture.offlineCacheStore.updateOfflineCacheWorkProgress(
            favoriteID: "favorite-a",
            tid: "100",
            targetImageURLs: [activeImage, pendingImage],
            completedImageURLs: [activeImage],
            currentBytesPerSecond: 2048
        )
        try await fixture.offlineCacheStore.markOfflineCacheWorkFailed(
            favoriteID: "favorite-a",
            tid: "200",
            message: "Timeout"
        )
        try await fixture.directoryStore.saveDirectory(
            MangaDirectory(
                cleanBookName: "作品A",
                strategy: .tag,
                sourceKey: "tag:1",
                chapters: [
                    try makeMineDirectoryChapter(tid: "100", chapterNumber: 1),
                    try makeMineDirectoryChapter(tid: "200", chapterNumber: 2)
                ]
            )
        )

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheQueue()

        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 3)
        XCTAssertEqual(viewModel.offlineCacheQueueGroups.map(\.favoriteID), ["favorite-b", "favorite-a"])
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].chapters.map(\.id.tid), ["100", "200"])

        let activeRow = viewModel.offlineCacheQueueGroups[1].chapters[0]
        XCTAssertEqual(activeRow.completedImageCount, 1)
        XCTAssertEqual(activeRow.targetImageCount, 2)
        XCTAssertEqual(activeRow.percentageText, L10n.string("mine.offline_queue.percent_format", 50))
        XCTAssertNotNil(activeRow.speedText)
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].currentSpeedText, activeRow.speedText)

        let failedRow = viewModel.offlineCacheQueueGroups[1].chapters[1]
        XCTAssertEqual(failedRow.failureStatusText, "Timeout")
    }

    func testOfflineCacheQueueEmptyStateHidesControls() async throws {
        let fixture = try await makeMineHomeFixture()
        let viewModel = MineHomeViewModel(appContext: fixture.appContext)

        await viewModel.refreshOfflineCacheQueue()

        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
        XCTAssertTrue(viewModel.offlineCacheQueueIsEmpty)
        XCTAssertFalse(viewModel.showsOfflineCacheQueueControls)
    }

    func testOfflineCacheQueueCommandsUseQueueControllerAndRefreshProjection() async throws {
        let fixture = try await makeMineHomeFixture()
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "100")
        )
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )

        await viewModel.refreshOfflineCacheQueue()
        await viewModel.continueOfflineCacheQueue()
        await viewModel.pauseOfflineCacheQueue()
        await viewModel.cancelOfflineCacheChapter(MangaOfflineCacheMembershipID(favoriteID: "favorite-a", tid: "100"))

        let events = await controller.snapshotEvents()
        let canceledWork = await fixture.offlineCacheStore.offlineCacheWork(favoriteID: "favorite-a", tid: "100")
        XCTAssertEqual(events, ["continue", "pause", "cancel:favorite-a:100"])
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
        XCTAssertNil(canceledWork)
    }

    func testOfflineCacheFavoriteGroupCancelPreservesCompletedCachedMembership() async throws {
        let fixture = try await makeMineHomeFixture()
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "200")
        )
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMineOfflineCacheMembership(
                favoriteID: "favorite-a",
                tid: "100",
                imageURLs: [cachedImage]
            )
        )
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )

        await viewModel.cancelOfflineCacheFavoriteGroup(favoriteID: "favorite-a")

        let canceledWork = await fixture.offlineCacheStore.offlineCacheWork(favoriteID: "favorite-a", tid: "200")
        let completedMembership = await fixture.offlineCacheStore.membership(favoriteID: "favorite-a", tid: "100")
        XCTAssertNil(canceledWork)
        XCTAssertNotNil(completedMembership)
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
    }

    func testOfflineCacheSelectionModeBatchCancelsSelectedWork() async throws {
        let fixture = try await makeMineHomeFixture()
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "100")
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(favoriteID: "favorite-a", tid: "200")
        )
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )
        await viewModel.refreshOfflineCacheQueue()

        viewModel.setOfflineCacheQueueSelectionMode(true)
        viewModel.toggleOfflineCacheWorkSelection(MangaOfflineCacheMembershipID(favoriteID: "favorite-a", tid: "100"))
        viewModel.toggleOfflineCacheWorkSelection(MangaOfflineCacheMembershipID(favoriteID: "favorite-a", tid: "200"))
        await viewModel.cancelSelectedOfflineCacheWorks()

        let events = await controller.snapshotEvents()
        XCTAssertEqual(Set(events), ["cancel:favorite-a:100", "cancel:favorite-a:200"])
        XCTAssertFalse(viewModel.isOfflineCacheQueueSelectionMode)
        XCTAssertTrue(viewModel.selectedOfflineCacheWorkIDs.isEmpty)
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
    }
}

private struct MineHomeViewModelFixture {
    let appContext: YamiboAppContext
    let offlineCacheStore: FileMangaOfflineCacheStore
    let directoryStore: FileMangaDirectoryStore
}

private func makeMineHomeFixture(
    accountUID: String? = nil,
    cachedProfile: YamiboProfile? = nil
) async throws -> MineHomeViewModelFixture {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "mine-home-view-model")
    let sessionStore = try SessionStore(testSuiteName: defaultsSuiteName, key: "session")
    let profileStore = try YamiboProfileStore(testSuiteName: defaultsSuiteName, key: "profile")
    let offlineCacheStore = FileMangaOfflineCacheStore(baseDirectory: makeMineTemporaryDirectory())
    let directoryStore = FileMangaDirectoryStore(baseDirectory: makeMineTemporaryDirectory())
    try await sessionStore.save(
        SessionState(
            cookie: "EeqY_2132_auth=token",
            userAgent: "Test-UA",
            isLoggedIn: true,
            accountUID: accountUID
        )
    )
    if let cachedProfile {
        try await profileStore.save(cachedProfile)
    }

    let appContext = YamiboAppContext(
        sessionStore: sessionStore,
        profileStore: profileStore,
        mangaDirectoryStore: directoryStore,
        mangaOfflineCacheStore: offlineCacheStore,
        session: makeProfileRefreshTestSession()
    )
    return MineHomeViewModelFixture(
        appContext: appContext,
        offlineCacheStore: offlineCacheStore,
        directoryStore: directoryStore
    )
}

private final class MineProfileRefreshTestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Data, HTTPURLResponse)

    nonisolated(unsafe) static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: MineProfileRefreshTestError.missingHandler)
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum MineProfileRefreshTestError: Error {
    case missingHandler
}

private func makeProfileRefreshTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MineProfileRefreshTestURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func profileResponse(for request: URLRequest, uid: String) -> (Data, HTTPURLResponse) {
    XCTAssertEqual(request.url?.path, "/home.php")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Test-UA")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "EeqY_2132_auth=token")
    return httpResponse(url: request.url!, body: profileHTML(uid: uid))
}

private func httpResponse(
    url: URL,
    body: String,
    statusCode: Int = 200,
    headers: [String: String]? = nil
) -> (Data, HTTPURLResponse) {
    (
        Data(body.utf8),
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
    )
}

private func makeProfile(uid: String) -> YamiboProfile {
    YamiboProfile(
        uid: uid,
        username: "arkalin",
        userGroup: "百合花蕾",
        points: 29,
        partner: 377,
        totalPoints: 155
    )
}

private func profileHTML(uid: String) -> String {
    """
    <html>
      <body>
        <div class="avatar_bg" style="background-image:url(uc_server/data/avatar/000/53/59/77_avatar_big.jpg?x)">
          <div class="avatar_m"><img src="uc_server/data/avatar/000/53/59/77_avatar_big.jpg?y" /></div>
          <div class="name">arkalin</div>
        </div>
        <ul class="user_box">
          <li><span>155</span>总积分</li>
          <li><span>29 点</span>积分</li>
          <li><span>377</span>对象</li>
        </ul>
        <ul class="myinfo_list">
          <li>UID<span>\(uid)</span></li>
          <li>用户组<span><font>百合花蕾</font></span></li>
        </ul>
        <div class="btn_exit"><a href="member.php?mod=logging&amp;action=logout&amp;formhash=abc123">退出</a></div>
      </body>
    </html>
    """
}

private actor RecordingOfflineCacheQueueController: MangaOfflineCacheQueueControlling {
    private let store: FileMangaOfflineCacheStore
    private var recordedEvents: [String] = []

    func snapshotEvents() -> [String] {
        recordedEvents
    }

    init(store: FileMangaOfflineCacheStore) {
        self.store = store
    }

    func continueQueue() async throws {
        recordedEvents.append("continue")
        try await store.setOfflineCacheQueueRunState(.running)
    }

    func pauseQueue() async throws {
        recordedEvents.append("pause")
        try await store.setOfflineCacheQueueRunState(.paused)
    }

    func cancelChapter(favoriteID: String, tid: String) async throws {
        recordedEvents.append("cancel:\(favoriteID):\(tid)")
        try await store.cancelOfflineCacheWork(favoriteID: favoriteID, tid: tid)
    }

    func cancelFavoriteGroup(favoriteID: String) async throws {
        recordedEvents.append("cancel-group:\(favoriteID)")
        try await store.cancelOfflineCacheWorks(forFavoriteID: favoriteID)
    }
}

private func makeMineOfflineCacheWorkRequest(
    favoriteID: String,
    favoriteTitle: String = "作品",
    tid: String,
    targetImageURLs: [URL] = []
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        favoriteID: favoriteID,
        favoriteTitle: favoriteTitle,
        favoriteURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html")),
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1")),
        targetImageURLs: targetImageURLs
    )
}

private func makeMineOfflineCacheMembership(
    favoriteID: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        favoriteID: favoriteID,
        favoriteTitle: "作品",
        favoriteURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html")),
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1")),
        imageURLs: imageURLs
    )
}

private func makeMineDirectoryChapter(tid: String, chapterNumber: Double) throws -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: "第\(tid)话",
        chapterNumber: chapterNumber,
        url: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)"))
    )
}

private func makeMineTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}
