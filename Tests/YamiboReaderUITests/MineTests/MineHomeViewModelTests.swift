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

    func testManualCheckInUsesSharedServiceWithoutForceAndShowsSkippedTodayMessage() async throws {
        let fixture = try await makeMineHomeFixture()
        let checkInService = RecordingCheckInService(result: .skippedToday)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            checkInService: checkInService
        )

        await viewModel.checkIn()

        let forces = await checkInService.snapshotForces()
        XCTAssertEqual(forces, [false])
        XCTAssertEqual(
            viewModel.checkInResultMessage,
            YamiboCheckInResult.alreadyCheckedInToday.message
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isCheckingIn)
        XCTAssertTrue(viewModel.hasCheckedInToday)
    }

    func testManualCheckInAlreadyCheckedInShowsTodayMessage() async throws {
        let fixture = try await makeMineHomeFixture()
        let checkInService = RecordingCheckInService(result: .alreadyCheckedInToday)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            checkInService: checkInService
        )

        await viewModel.checkIn()

        let forces = await checkInService.snapshotForces()
        XCTAssertEqual(forces, [false])
        XCTAssertEqual(
            viewModel.checkInResultMessage,
            YamiboCheckInResult.alreadyCheckedInToday.message
        )
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasCheckedInToday)
    }

    func testManualCheckInSuccessRefreshesProfileWithoutOverwritingResult() async throws {
        let fixture = try await makeMineHomeFixture(accountUID: "535977")
        let checkInService = RecordingCheckInService(result: .success)
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }

        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            checkInService: checkInService
        )
        viewModel.session = await fixture.appContext.sessionStore.load()

        await viewModel.checkIn()

        let forces = await checkInService.snapshotForces()
        XCTAssertEqual(forces, [false])
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(viewModel.profile?.uid, "535977")
        XCTAssertEqual(viewModel.checkInResultMessage, YamiboCheckInResult.success.message)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasCheckedInToday)
    }

    func testManualCheckInFailurePresentsError() async throws {
        let fixture = try await makeMineHomeFixture()
        let checkInService = RecordingCheckInService(result: .verificationFailed)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            checkInService: checkInService
        )

        await viewModel.checkIn()

        let forces = await checkInService.snapshotForces()
        XCTAssertEqual(forces, [false])
        XCTAssertNil(viewModel.checkInResultMessage)
        XCTAssertEqual(viewModel.errorMessage, YamiboCheckInResult.verificationFailed.message)
        XCTAssertFalse(viewModel.isCheckingIn)
        XCTAssertFalse(viewModel.hasCheckedInToday)
    }

    func testLoadShowsCheckedInTodayWhenLocalRecordExists() async throws {
        let fixture = try await makeMineHomeFixture(cachedProfile: makeProfile(uid: "535977"))
        let session = await fixture.appContext.sessionStore.load()
        await fixture.checkInStore.markCheckedIn(session: session)
        let viewModel = MineHomeViewModel(appContext: fixture.appContext)

        await viewModel.load()

        XCTAssertTrue(viewModel.hasCheckedInToday)
    }

    func testManualCheckInDoesNotCallServiceWhenTodayAlreadyRecorded() async throws {
        let fixture = try await makeMineHomeFixture(cachedProfile: makeProfile(uid: "535977"))
        let session = await fixture.appContext.sessionStore.load()
        await fixture.checkInStore.markCheckedIn(session: session)
        let checkInService = RecordingCheckInService(result: .success)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            checkInService: checkInService
        )
        await viewModel.load()

        await viewModel.checkIn()

        let forces = await checkInService.snapshotForces()
        XCTAssertTrue(forces.isEmpty)
        XCTAssertEqual(
            viewModel.checkInResultMessage,
            YamiboCheckInResult.alreadyCheckedInToday.message
        )
        XCTAssertTrue(viewModel.hasCheckedInToday)
    }

    func testOfflineCacheQueueProjectsEntryCountGroupingOrderingProgressSpeedAndFailure() async throws {
        let fixture = try await makeMineHomeFixture()
        let activeImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        let pendingImage = try XCTUnwrap(URL(string: "https://img.example.com/100-2.jpg"))
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品B", tid: "300")
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(
                ownerName: "作品A",
                tid: "200"
            )
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(
                ownerName: "作品A",
                tid: "100",
                targetImageURLs: [activeImage, pendingImage]
            )
        )
        try await fixture.offlineCacheStore.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "100",
            targetImageURLs: [activeImage, pendingImage],
            completedImageURLs: [activeImage],
            currentBytesPerSecond: 2048
        )
        try await fixture.offlineCacheStore.markOfflineCacheWorkFailed(
            ownerName: "作品A",
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
        XCTAssertEqual(viewModel.offlineCacheQueueGroups.map(\.ownerName), ["作品B", "作品A"])
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].chapters.map(\.tid), ["100", "200"])
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].progressText, L10n.string("mine.offline_queue.image_progress_format", 1, 2))
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].percentageText, L10n.string("mine.offline_queue.percent_format", 50))
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].progressFraction, 0.5)
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].failureStatusText, "Timeout")

        let activeRow = viewModel.offlineCacheQueueGroups[1].chapters[0]
        XCTAssertEqual(activeRow.completedImageCount, 1)
        XCTAssertEqual(activeRow.targetImageCount, 2)
        XCTAssertEqual(activeRow.percentageText, L10n.string("mine.offline_queue.percent_format", 50))
        XCTAssertNotNil(activeRow.speedText)
        XCTAssertEqual(viewModel.offlineCacheQueueGroups[1].currentSpeedText, activeRow.speedText)

        let failedRow = viewModel.offlineCacheQueueGroups[1].chapters[1]
        XCTAssertEqual(failedRow.failureStatusText, "Timeout")
    }

    func testOfflineCacheQueueExcludesCompletedMembershipsFromEntryCount() async throws {
        let fixture = try await makeMineHomeFixture()
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/completed-100.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMineOfflineCacheMembership(
                ownerName: "作品A",
                tid: "100",
                imageURLs: [cachedImage]
            )
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "200")
        )

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheQueue()

        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 1)
        XCTAssertEqual(viewModel.offlineCacheQueueGroups.first?.chapters.map(\.tid), ["200"])
    }

    func testOfflineCacheQueueModelsKeepMixedReaderOwnersSeparate() throws {
        let mangaGroupID = OfflineCacheGroupID(readerKind: .manga, ownerKey: "同名作品")
        let novelGroupID = OfflineCacheGroupID(readerKind: .novel, ownerKey: "同名作品")
        let projection = OfflineCacheQueueProjection.project(works: [
            makeMineOfflineQueueWork(
                readerKind: .manga,
                ownerKey: "同名作品",
                entryKey: "100",
                title: "漫画章节",
                insertionIndex: 1
            ),
            makeMineOfflineQueueWork(
                readerKind: .novel,
                ownerKey: "同名作品",
                entryKey: "novel-1",
                title: "小说章节",
                insertionIndex: 2
            )
        ])
        let groups = projection.groups.map(MineOfflineCacheQueueOwnerGroup.init(group:))

        XCTAssertEqual(groups.map(\.id), [mangaGroupID, novelGroupID])
        XCTAssertEqual(groups.map(\.ownerName), ["同名作品", "同名作品"])
        XCTAssertEqual(groups.flatMap(\.chapters).map(\.readerKind), [.manga, .novel])
    }

    func testOfflineCacheQueueLoadsNovelWorkRowsFromStore() async throws {
        let fixture = try await makeMineHomeFixture()
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "漫画A", tid: "100")
        )
        _ = try await fixture.offlineCacheStore.enqueueNovelOfflineCacheWork(
            try makeMineNovelOfflineCacheWorkRequest(ownerTitle: "小说A", tid: "200", view: 1)
        )

        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheQueue()

        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 2)
        XCTAssertEqual(Set(viewModel.offlineCacheQueueGroups.map(\.readerKind)), [.manga, .novel])
        XCTAssertEqual(Set(viewModel.offlineCacheQueueGroups.map(\.ownerName)), ["漫画A", "小说A"])
        XCTAssertEqual(Set(viewModel.offlineCacheQueueGroups.flatMap(\.chapters).map(\.readerKind)), [.manga, .novel])
    }

    func testContinueOfflineCacheQueueRetriesFailedNovelWork() async throws {
        let fixture = try await makeMineHomeFixture()
        let enqueueResult = try await fixture.offlineCacheStore.enqueueNovelOfflineCacheWork(
            try makeMineNovelOfflineCacheWorkRequest(ownerTitle: "小说A", tid: "200", view: 1)
        )
        let workID = try XCTUnwrap(enqueueResult.enqueuedWork?.id)
        try await fixture.offlineCacheStore.markOfflineCacheWorkFailed(id: workID, message: "Timeout")
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )

        await viewModel.refreshOfflineCacheQueue()
        XCTAssertEqual(viewModel.offlineCacheQueueGroups.first?.chapters.first?.failureStatusText, "Timeout")

        await viewModel.continueOfflineCacheQueue()

        let refreshedWork = await fixture.offlineCacheStore.offlineCacheQueueWorks().first { $0.id == workID }
        XCTAssertEqual(refreshedWork?.state, .queued)
        XCTAssertNil(refreshedWork?.failureMessage)
        XCTAssertNil(viewModel.offlineCacheQueueGroups.first?.chapters.first?.failureStatusText)
    }

    func testOfflineCacheQueueAutomaticallyRefreshesWhenStoreProgressChanges() async throws {
        let fixture = try await makeMineHomeFixture()
        let firstImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        let secondImage = try XCTUnwrap(URL(string: "https://img.example.com/100-2.jpg"))
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(
                ownerName: "作品A",
                tid: "100",
                targetImageURLs: [firstImage, secondImage]
            )
        )
        let viewModel = MineHomeViewModel(appContext: fixture.appContext)

        await viewModel.load()
        XCTAssertEqual(viewModel.offlineCacheQueueGroups.first?.chapters.first?.completedImageCount, 0)

        try await fixture.offlineCacheStore.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "100",
            targetImageURLs: [firstImage, secondImage],
            completedImageURLs: [firstImage],
            currentBytesPerSecond: 4096
        )

        try await waitForMineHomeCondition {
            viewModel.offlineCacheQueueGroups.first?.chapters.first?.completedImageCount == 1
        }
        let row = try XCTUnwrap(viewModel.offlineCacheQueueGroups.first?.chapters.first)
        XCTAssertEqual(row.completedImageCount, 1)
        XCTAssertEqual(row.targetImageCount, 2)
        XCTAssertEqual(row.percentageText, L10n.string("mine.offline_queue.percent_format", 50))
        XCTAssertNotNil(row.speedText)
    }

    func testLoadOfflineCacheQueueAutomaticallyRefreshesWhenStoreChanges() async throws {
        let fixture = try await makeMineHomeFixture()
        let viewModel = MineHomeViewModel(appContext: fixture.appContext)

        await viewModel.loadOfflineCacheQueue()
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)

        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "100")
        )

        try await waitForMineHomeCondition {
            viewModel.offlineCacheQueueEntryCount == 1
                && viewModel.offlineCacheQueueGroups.first?.ownerName == "作品A"
        }
    }

    func testLoadOfflineCacheQueueDoesNotRefreshProfile() async throws {
        let fixture = try await makeMineHomeFixture(accountUID: "535977")
        nonisolated(unsafe) var requestCount = 0
        MineProfileRefreshTestURLProtocol.handler = { request in
            requestCount += 1
            return profileResponse(for: request, uid: "535977")
        }
        defer { MineProfileRefreshTestURLProtocol.handler = nil }
        let viewModel = MineHomeViewModel(appContext: fixture.appContext)

        await viewModel.loadOfflineCacheQueue()

        XCTAssertEqual(requestCount, 0)
        XCTAssertNil(viewModel.profile)
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
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "100")
        )
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )

        await viewModel.refreshOfflineCacheQueue()
        let workID = try XCTUnwrap(viewModel.offlineCacheQueueGroups.first?.chapters.first?.id)
        await viewModel.continueOfflineCacheQueue()
        await viewModel.pauseOfflineCacheQueue()
        await viewModel.cancelOfflineCacheChapter(workID)

        let events = await controller.snapshotEvents()
        let canceledWork = await fixture.offlineCacheStore.offlineCacheWork(ownerName: "作品A", tid: "100")
        XCTAssertEqual(events, ["continue", "pause", "cancel:作品A:100"])
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
        XCTAssertNil(canceledWork)
    }

    func testOfflineCacheOwnerGroupCancelPreservesCompletedCachedMembership() async throws {
        let fixture = try await makeMineHomeFixture()
        let cachedImage = try XCTUnwrap(URL(string: "https://img.example.com/100-1.jpg"))
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "200")
        )
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: cachedImage)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMineOfflineCacheMembership(
                ownerName: "作品A",
                tid: "100",
                imageURLs: [cachedImage]
            )
        )
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )

        await viewModel.cancelOfflineCacheOwnerGroup(id: mineMangaOfflineGroupID("作品A"))

        let canceledWork = await fixture.offlineCacheStore.offlineCacheWork(ownerName: "作品A", tid: "200")
        let completedMembership = await fixture.offlineCacheStore.membership(ownerName: "作品A", tid: "100")
        XCTAssertNil(canceledWork)
        XCTAssertNotNil(completedMembership)
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
    }

    func testOfflineCacheSelectionModeBatchCancelsSelectedWork() async throws {
        let fixture = try await makeMineHomeFixture()
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "100")
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "200")
        )
        let controller = RecordingOfflineCacheQueueController(store: fixture.offlineCacheStore)
        let viewModel = MineHomeViewModel(
            appContext: fixture.appContext,
            offlineCacheQueueController: controller
        )
        await viewModel.refreshOfflineCacheQueue()
        let selectedIDs = viewModel.offlineCacheQueueGroups
            .flatMap(\.chapters)
            .filter { $0.ownerName == "作品A" && ["100", "200"].contains($0.tid) }
            .map(\.id)

        viewModel.setOfflineCacheQueueSelectionMode(true)
        for id in selectedIDs {
            viewModel.toggleOfflineCacheWorkSelection(id)
        }
        await viewModel.cancelSelectedOfflineCacheWorks()

        let events = await controller.snapshotEvents()
        XCTAssertEqual(Set(events), ["cancel:作品A:100", "cancel:作品A:200"])
        XCTAssertFalse(viewModel.isOfflineCacheQueueSelectionMode)
        XCTAssertTrue(viewModel.selectedOfflineCacheWorkIDs.isEmpty)
        XCTAssertEqual(viewModel.offlineCacheQueueEntryCount, 0)
    }

    func testOfflineCacheSelectionModeTogglesWholeOwnerGroup() async throws {
        let fixture = try await makeMineHomeFixture()
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "100")
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品A", tid: "200")
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMineOfflineCacheWorkRequest(ownerName: "作品B", tid: "300")
        )
        let viewModel = MineHomeViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheQueue()
        let ownerAWorkIDs = Set(
            viewModel.offlineCacheQueueGroups
                .first { $0.ownerName == "作品A" }?
                .chapters
                .map(\.id) ?? []
        )

        viewModel.toggleOfflineCacheOwnerSelection(id: mineMangaOfflineGroupID("作品A"))

        XCTAssertTrue(viewModel.isOfflineCacheOwnerSelected(id: mineMangaOfflineGroupID("作品A")))
        XCTAssertFalse(viewModel.isOfflineCacheOwnerSelected(id: mineMangaOfflineGroupID("作品B")))
        XCTAssertEqual(viewModel.selectedOfflineCacheWorkIDs, ownerAWorkIDs)

        viewModel.toggleOfflineCacheOwnerSelection(id: mineMangaOfflineGroupID("作品A"))

        XCTAssertFalse(viewModel.isOfflineCacheOwnerSelected(id: mineMangaOfflineGroupID("作品A")))
        XCTAssertTrue(viewModel.selectedOfflineCacheWorkIDs.isEmpty)
    }
}

private struct MineHomeViewModelFixture {
    let appContext: YamiboAppContext
    let checkInStore: YamiboCheckInStore
    let offlineCacheStore: any OfflineCacheStoring
    let directoryStore: MangaDirectoryStore
}

private func makeMineHomeFixture(
    accountUID: String? = nil,
    cachedProfile: YamiboProfile? = nil
) async throws -> MineHomeViewModelFixture {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "mine-home-view-model")
    let sessionStore = try SessionStore(testSuiteName: defaultsSuiteName, key: "session")
    let profileStore = try YamiboProfileStore(testSuiteName: defaultsSuiteName, key: "profile")
    let checkInStore = YamiboCheckInStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: defaultsSuiteName),
        keyPrefix: "check-in"
    )
    let offlineCacheRoot = makeMineTemporaryDirectory()
    let database = try YamiboDatabase.openPool(rootDirectory: offlineCacheRoot)
    let offlineCacheStore = OfflineCacheStore(
        databasePool: database,
        baseDirectory: offlineCacheRoot.appendingPathComponent("offline-images", isDirectory: true)
    )
    let directoryStore = MangaDirectoryStore(databasePool: database)
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
        checkInStore: checkInStore,
        mangaDirectoryStore: directoryStore,
        offlineCacheStore: offlineCacheStore,
        session: makeProfileRefreshTestSession()
    )
    return MineHomeViewModelFixture(
        appContext: appContext,
        checkInStore: checkInStore,
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

private actor RecordingCheckInService: YamiboCheckInServicing {
    private let result: YamiboCheckInResult
    private var forces: [Bool] = []

    init(result: YamiboCheckInResult) {
        self.result = result
    }

    func checkInIfNeeded(force: Bool) async -> YamiboCheckInResult {
        forces.append(force)
        return result
    }

    func snapshotForces() -> [Bool] {
        forces
    }
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
    private let store: any OfflineCacheStoring
    private var recordedEvents: [String] = []

    func snapshotEvents() -> [String] {
        recordedEvents
    }

    init(store: any OfflineCacheStoring) {
        self.store = store
    }

    func continueQueue() async throws {
        recordedEvents.append("continue")
        try await store.retryFailedOfflineCacheWorks()
        try await store.setOfflineCacheQueueRunState(.running)
    }

    func pauseQueue() async throws {
        recordedEvents.append("pause")
        try await store.setOfflineCacheQueueRunState(.paused)
    }

    func cancelWork(id: OfflineCacheWorkID) async throws {
        if let work = await store.allOfflineCacheWorks().first(where: { $0.workID == id.rawValue }) {
            recordedEvents.append("cancel:\(work.ownerName):\(work.tid)")
        } else {
            recordedEvents.append("cancel:\(id.readerKind.rawValue):\(id.rawValue)")
        }
        try await store.cancelOfflineCacheWork(id: id)
    }

    func cancelGroup(id: OfflineCacheGroupID) async throws {
        recordedEvents.append("cancel-group:\(id.ownerKey)")
        try await store.cancelOfflineCacheGroup(id)
    }
}

private func mineMangaOfflineGroupID(_ ownerName: String) -> OfflineCacheGroupID {
    OfflineCacheGroupID(readerKind: .manga, ownerKey: ownerName)
}

private func makeMineOfflineQueueWork(
    readerKind: OfflineCacheReaderKind,
    ownerKey: String,
    entryKey: String,
    title: String,
    insertionIndex: Int
) -> OfflineCacheQueueWorkProjection {
    let groupID = OfflineCacheGroupID(readerKind: readerKind, ownerKey: ownerKey)
    let entryID = OfflineCacheEntryID(readerKind: readerKind, ownerKey: ownerKey, entryKey: entryKey)
    return OfflineCacheQueueWorkProjection(
        id: OfflineCacheWorkID(readerKind: readerKind, rawValue: "\(readerKind.rawValue)-\(entryKey)"),
        groupID: groupID,
        entryID: entryID,
        ownerTitle: ownerKey,
        title: title,
        progress: OfflineCacheProgress(completedUnitCount: 0, targetUnitCount: 1),
        state: .queued,
        failureMessage: nil,
        currentBytesPerSecond: 0,
        insertionIndex: insertionIndex
    )
}

private func makeMineNovelOfflineCacheWorkRequest(
    ownerTitle: String,
    tid: String,
    view: Int
) throws -> NovelOfflineCacheWorkRequest {
    NovelOfflineCacheWorkRequest(
        ownerTitle: ownerTitle,
        title: "第\(view)页",
        threadURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=\(view)")),
        view: view,
        targetImageURLs: []
    )
}

private func makeMineOfflineCacheWorkRequest(
    ownerName: String,
    tid: String,
    targetImageURLs: [URL] = []
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=1")),
        targetImageURLs: targetImageURLs
    )
}

private func makeMineOfflineCacheMembership(
    ownerName: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: ownerName,
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

private func waitForMineHomeCondition(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let start = ContinuousClock.now
    while await MainActor.run(body: condition) == false {
        if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
            throw YamiboError.underlying("Timed out waiting for condition")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
