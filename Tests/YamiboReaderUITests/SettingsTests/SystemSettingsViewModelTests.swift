import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class SystemSettingsViewModelTests: XCTestCase {
    func testLoadReadsApplePencilPageTurnSettings() async throws {
        let fixture = try makeFixture()
        let savedSettings = ApplePencilPageTurnSettings(
            isEnabled: true,
            behavior: .doubleTapNextSqueezePrevious
        )
        try await fixture.settingsStore.save(AppSettings(applePencilPageTurn: savedSettings))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.applePencilPageTurn, savedSettings)
    }

    func testLoadReadsFavoriteBackgroundSettings() async throws {
        let fixture = try makeFixture()
        let savedSettings = FavoriteBackgroundSettings(
            isEnabled: true,
            imageID: "background",
            scale: 1.7,
            offsetX: 0.2,
            offsetY: -0.3,
            blurRadius: 11
        )
        try await fixture.settingsStore.save(AppSettings(favoriteBackground: savedSettings))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.favoriteBackground, savedSettings)
    }

    func testFavoriteLibraryDisplaySettingsLoadAndPersist() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings(
            favoriteLayoutMode: .staggered,
            favoriteSortOrder: .displayTitle,
            favoriteSortDescending: true,
            favoriteShowsCategoryCounts: false
        ))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.favoriteLayoutMode, .staggered)
        XCTAssertEqual(viewModel.favoriteSortOrder, .displayTitle)
        XCTAssertTrue(viewModel.favoriteSortDescending)
        XCTAssertFalse(viewModel.favoriteShowsCategoryCounts)

        viewModel.updateFavoriteLayoutMode(.fixedGrid)
        viewModel.updateFavoriteSortOrder(.lastReadAt)
        viewModel.updateFavoriteSortDescending(false)
        viewModel.updateFavoriteShowsCategoryCounts(true)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.favoriteLayoutMode == .fixedGrid
                && loaded.favoriteSortOrder == .lastReadAt
                && !loaded.favoriteSortDescending
                && loaded.favoriteShowsCategoryCounts
        }
        XCTAssertEqual(viewModel.favoriteLayoutMode, .fixedGrid)
        XCTAssertEqual(viewModel.favoriteSortOrder, .lastReadAt)
        XCTAssertFalse(viewModel.favoriteSortDescending)
        XCTAssertTrue(viewModel.favoriteShowsCategoryCounts)
    }

    func testApplyFavoriteBackgroundPersistsImageAndSettings() async throws {
        let fixture = try makeFixture()
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let imageData = Data(repeating: 6, count: 128)
        let draftSettings = FavoriteBackgroundSettings(
            isEnabled: true,
            scale: 2,
            offsetX: 0.5,
            offsetY: -0.25,
            blurRadius: 14
        )

        let didApply = await viewModel.applyFavoriteBackground(
            imageData: imageData,
            draftSettings: draftSettings
        )

        XCTAssertTrue(didApply)
        let loaded = await fixture.settingsStore.load()
        let imageID = try XCTUnwrap(loaded.favoriteBackground.imageID)
        XCTAssertTrue(loaded.favoriteBackground.isEnabled)
        XCTAssertEqual(loaded.favoriteBackground.scale, 2)
        XCTAssertEqual(loaded.favoriteBackground.offsetX, 0.5)
        XCTAssertEqual(loaded.favoriteBackground.offsetY, -0.25)
        XCTAssertEqual(loaded.favoriteBackground.blurRadius, 14)
        let savedImageData = await fixture.favoriteBackgroundImageStore.loadData(imageID: imageID)
        XCTAssertEqual(savedImageData, imageData)
        XCTAssertEqual(viewModel.favoriteBackground, loaded.favoriteBackground)
    }

    func testRestoreDefaultFavoriteBackgroundClearsImageAndSettings() async throws {
        let fixture = try makeFixture()
        let imageID = "background"
        try await fixture.favoriteBackgroundImageStore.save(Data(repeating: 7, count: 96), imageID: imageID)
        try await fixture.settingsStore.save(AppSettings(
            favoriteBackground: FavoriteBackgroundSettings(isEnabled: true, imageID: imageID)
        ))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let didRestore = await viewModel.restoreDefaultFavoriteBackground()

        XCTAssertTrue(didRestore)
        XCTAssertEqual(viewModel.favoriteBackground, FavoriteBackgroundSettings())
        let loadedSettings = await fixture.settingsStore.load()
        XCTAssertEqual(loadedSettings.favoriteBackground, FavoriteBackgroundSettings())
        let savedImageData = await fixture.favoriteBackgroundImageStore.loadData(imageID: imageID)
        XCTAssertNil(savedImageData)
    }

    func testUpdateApplePencilEnabledPersistsSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings())

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        viewModel.updateApplePencilPageTurnEnabled(true)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.applePencilPageTurn.isEnabled
        }
        XCTAssertTrue(viewModel.applePencilPageTurn.isEnabled)
    }

    func testUpdateApplePencilBehaviorPersistsSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings())

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        viewModel.updateApplePencilPageTurnBehavior(.doubleTapNextSqueezePrevious)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.applePencilPageTurn.behavior == .doubleTapNextSqueezePrevious
        }
        XCTAssertEqual(viewModel.applePencilPageTurn.behavior, .doubleTapNextSqueezePrevious)
    }

    func testResetApplicationRestoresDefaultApplePencilSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings(
            applePencilPageTurn: ApplePencilPageTurnSettings(
                isEnabled: true,
                behavior: .doubleTapNextSqueezePrevious
            )
        ))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let didReset = await viewModel.resetApplication()

        XCTAssertTrue(didReset)
        XCTAssertEqual(viewModel.applePencilPageTurn, ApplePencilPageTurnSettings())
        let loaded = await fixture.settingsStore.load()
        XCTAssertEqual(loaded.applePencilPageTurn, ApplePencilPageTurnSettings())
        XCTAssertEqual(viewModel.favoriteBackground, FavoriteBackgroundSettings())
    }

    func testLoadReadsNovelAndMangaStorageUsage() async throws {
        let fixture = try makeFixture()
        try await seedNovelCache(fixture)
        try await seedMangaIndexCache(fixture)
        try await seedMangaImageCache(fixture)
        try await seedMangaOfflineCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertGreaterThan(viewModel.novelCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaImageCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaOfflineCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheLabel, cacheLabel(for: viewModel.mangaIndexCacheBytes))
        XCTAssertEqual(viewModel.mangaImageCacheLabel, cacheLabel(for: viewModel.mangaImageCacheBytes))
        XCTAssertEqual(viewModel.mangaOfflineCacheLabel, cacheLabel(for: viewModel.mangaOfflineCacheBytes))
    }

    func testClearMangaIndexCacheClearsDirectoriesAndChapterDocumentsOnly() async throws {
        let fixture = try makeFixture()
        try await seedMangaIndexCache(fixture)
        try await seedMangaImageCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let imageBytesBeforeClear = await fixture.mangaImageDataCacheStore.totalDiskUsageBytes()

        let didClear = await viewModel.clearMangaIndexCache()
        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let chapterDocumentBytesAfterClear = await fixture.mangaChapterDocumentStore.totalDiskUsageBytes()
        let imageBytesAfterClear = await fixture.mangaImageDataCacheStore.totalDiskUsageBytes()

        XCTAssertTrue(didClear)
        XCTAssertEqual(directoryBytesAfterClear, 0)
        XCTAssertEqual(chapterDocumentBytesAfterClear, 0)
        XCTAssertEqual(imageBytesAfterClear, imageBytesBeforeClear)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaImageCacheBytes, imageBytesBeforeClear)
    }

    func testClearMangaImageCacheClearsImageDataOnly() async throws {
        let fixture = try makeFixture()
        try await seedMangaIndexCache(fixture)
        try await seedMangaImageCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let directoryBytesBeforeClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let chapterDocumentBytesBeforeClear = await fixture.mangaChapterDocumentStore.totalDiskUsageBytes()
        let indexBytesBeforeClear = directoryBytesBeforeClear + chapterDocumentBytesBeforeClear

        let didClear = await viewModel.clearMangaImageCache()
        let imageBytesAfterClear = await fixture.mangaImageDataCacheStore.totalDiskUsageBytes()
        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let chapterDocumentBytesAfterClear = await fixture.mangaChapterDocumentStore.totalDiskUsageBytes()

        XCTAssertTrue(didClear)
        XCTAssertEqual(imageBytesAfterClear, 0)
        XCTAssertEqual(directoryBytesAfterClear, directoryBytesBeforeClear)
        XCTAssertEqual(chapterDocumentBytesAfterClear, chapterDocumentBytesBeforeClear)
        XCTAssertEqual(viewModel.mangaImageCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, indexBytesBeforeClear)
    }

    func testMangaOfflineCacheCleanupFiltersOwnersWithMembershipOrWorkAndShowsUsage() async throws {
        let fixture = try makeFixture()
        let membershipImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-a.jpg"))
        let workImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-b.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data(repeating: 1, count: 4), for: membershipImage)
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data(repeating: 2, count: 7), for: workImage)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [membershipImage])
        )
        _ = try await fixture.mangaOfflineCacheStore.enqueueOfflineCacheWork(
            try makeMangaOfflineWorkRequest(ownerName: "作品B", tid: "320", targetImageURLs: [workImage])
        )
        try await fixture.mangaOfflineCacheStore.updateOfflineCacheWorkProgress(
            ownerName: "作品B",
            tid: "320",
            targetImageURLs: [workImage],
            completedImageURLs: [workImage],
            currentBytesPerSecond: nil
        )

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        XCTAssertEqual(viewModel.mangaOfflineCacheCleanupRows.map(\.ownerName), ["作品A", "作品B"])
        XCTAssertEqual(viewModel.mangaOfflineCacheCleanupRows.map(\.title), ["作品A", "作品B"])
        XCTAssertEqual(viewModel.mangaOfflineCacheCleanupRows.map(\.byteCount), [4, 7])
        XCTAssertFalse(viewModel.mangaOfflineCacheCleanupIsEmpty)
    }

    func testMangaOfflineCacheCleanupEmptyStateWhenNoMembershipOrWorkExists() async throws {
        let fixture = try makeFixture()
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)

        await viewModel.refreshMangaOfflineCacheCleanup()

        XCTAssertTrue(viewModel.mangaOfflineCacheCleanupRows.isEmpty)
        XCTAssertTrue(viewModel.mangaOfflineCacheCleanupIsEmpty)
    }

    func testMangaOfflineCacheCleanupSingleAndSwipeDeletePrepareConfirmation() async throws {
        let fixture = try makeFixture()
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-single.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [imageURL])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        viewModel.requestMangaOfflineCacheCleanup(ownerName: "作品A")
        XCTAssertEqual(viewModel.pendingMangaOfflineCacheCleanupConfirmation?.ownerNames, ["作品A"])

        viewModel.cancelMangaOfflineCacheCleanupConfirmation()
        viewModel.requestMangaOfflineCacheSwipeCleanup(ownerName: "作品A")
        XCTAssertEqual(viewModel.pendingMangaOfflineCacheCleanupConfirmation?.ownerNames, ["作品A"])
    }

    func testMangaOfflineCacheCleanupBatchDeleteUsesOneConfirmationForSelectedOwners() async throws {
        let fixture = try makeFixture()
        let firstImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-batch-1.jpg"))
        let secondImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-batch-2.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([1]), for: firstImage)
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([2]), for: secondImage)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [firstImage])
        )
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品B", tid: "320", imageURLs: [secondImage])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        viewModel.setMangaOfflineCacheCleanupSelectionMode(true)
        viewModel.toggleMangaOfflineCacheCleanupSelection(ownerName: "作品A")
        viewModel.toggleMangaOfflineCacheCleanupSelection(ownerName: "作品B")
        viewModel.requestSelectedMangaOfflineCacheCleanup()

        XCTAssertEqual(viewModel.pendingMangaOfflineCacheCleanupConfirmation?.ownerNames, ["作品A", "作品B"])
    }

    func testMangaOfflineCacheCleanupSelectionActionStateEnablesDeleteWhenOwnerIsSelected() async throws {
        let fixture = try makeFixture()
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-selection-state.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [imageURL])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        viewModel.setMangaOfflineCacheCleanupSelectionMode(true)
        XCTAssertEqual(
            viewModel.mangaOfflineCacheCleanupSelectionActionState,
            MangaOfflineCacheCleanupSelectionActionState(selectedOwnerCount: 0, canDelete: false)
        )

        viewModel.toggleMangaOfflineCacheCleanupSelection(ownerName: "作品A")
        XCTAssertEqual(
            viewModel.mangaOfflineCacheCleanupSelectionActionState,
            MangaOfflineCacheCleanupSelectionActionState(selectedOwnerCount: 1, canDelete: true)
        )

        viewModel.toggleMangaOfflineCacheCleanupSelection(ownerName: "作品A")
        XCTAssertEqual(
            viewModel.mangaOfflineCacheCleanupSelectionActionState,
            MangaOfflineCacheCleanupSelectionActionState(selectedOwnerCount: 0, canDelete: false)
        )
    }

    func testMangaOfflineCacheCleanupConfirmDeletesMembershipsWorksAndUnsharedOfflineBytes() async throws {
        let fixture = try makeFixture()
        let removedImage = try XCTUnwrap(URL(string: "https://img.example.com/remove.jpg"))
        let sharedImage = try XCTUnwrap(URL(string: "https://img.example.com/shared.jpg"))
        let workImage = try XCTUnwrap(URL(string: "https://img.example.com/work.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([1]), for: removedImage)
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([2]), for: sharedImage)
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([3]), for: workImage)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [removedImage, sharedImage])
        )
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品B", tid: "320", imageURLs: [sharedImage])
        )
        _ = try await fixture.mangaOfflineCacheStore.enqueueOfflineCacheWork(
            try makeMangaOfflineWorkRequest(ownerName: "作品A", tid: "311", targetImageURLs: [workImage])
        )
        try await fixture.mangaOfflineCacheStore.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "311",
            targetImageURLs: [workImage],
            completedImageURLs: [workImage],
            currentBytesPerSecond: nil
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        viewModel.requestMangaOfflineCacheCleanup(ownerName: "作品A")
        let didDelete = await viewModel.confirmPendingMangaOfflineCacheCleanup()

        let removedMembership = await fixture.mangaOfflineCacheStore.membership(ownerName: "作品A", tid: "310")
        let removedWork = await fixture.mangaOfflineCacheStore.offlineCacheWork(ownerName: "作品A", tid: "311")
        let removedImageData = await fixture.mangaOfflineCacheStore.offlineImageData(for: removedImage)
        let workImageData = await fixture.mangaOfflineCacheStore.offlineImageData(for: workImage)
        let sharedImageData = await fixture.mangaOfflineCacheStore.offlineImageData(for: sharedImage)

        XCTAssertTrue(didDelete)
        XCTAssertNil(removedMembership)
        XCTAssertNil(removedWork)
        XCTAssertNil(removedImageData)
        XCTAssertNil(workImageData)
        XCTAssertEqual(sharedImageData, Data([2]))
        XCTAssertEqual(viewModel.mangaOfflineCacheCleanupRows.map(\.ownerName), ["作品B"])
        XCTAssertFalse(viewModel.isMangaOfflineCacheCleanupSelectionMode)
        XCTAssertTrue(viewModel.selectedMangaOfflineCacheOwnerNames.isEmpty)
    }

    func testMangaOfflineCacheCleanupConfirmUsesCapturedConfirmationAfterPendingDismissal() async throws {
        let fixture = try makeFixture()
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/dismiss-race.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [imageURL])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        viewModel.requestMangaOfflineCacheCleanup(ownerName: "作品A")
        let confirmation = try XCTUnwrap(viewModel.pendingMangaOfflineCacheCleanupConfirmation)
        viewModel.cancelMangaOfflineCacheCleanupConfirmation()
        let didDelete = await viewModel.confirmMangaOfflineCacheCleanup(confirmation)

        let removedMembership = await fixture.mangaOfflineCacheStore.membership(ownerName: "作品A", tid: "310")
        XCTAssertTrue(didDelete)
        XCTAssertNil(removedMembership)
        XCTAssertTrue(viewModel.mangaOfflineCacheCleanupRows.isEmpty)
    }

    func testMangaOfflineCacheCleanupPreservesTransparentMangaCaches() async throws {
        let fixture = try makeFixture()
        try await seedMangaIndexCache(fixture)
        try await seedMangaImageCache(fixture)
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/901-1.jpg"))
        try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.mangaOfflineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "901", imageURLs: [imageURL])
        )
        let directoryBytesBeforeClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let chapterDocumentBytesBeforeClear = await fixture.mangaChapterDocumentStore.totalDiskUsageBytes()
        let imageBytesBeforeClear = await fixture.mangaImageDataCacheStore.totalDiskUsageBytes()
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshMangaOfflineCacheCleanup()

        viewModel.requestMangaOfflineCacheCleanup(ownerName: "作品A")
        let didDelete = await viewModel.confirmPendingMangaOfflineCacheCleanup()

        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let chapterDocumentBytesAfterClear = await fixture.mangaChapterDocumentStore.totalDiskUsageBytes()
        let imageBytesAfterClear = await fixture.mangaImageDataCacheStore.totalDiskUsageBytes()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(directoryBytesAfterClear, directoryBytesBeforeClear)
        XCTAssertEqual(chapterDocumentBytesAfterClear, chapterDocumentBytesBeforeClear)
        XCTAssertEqual(imageBytesAfterClear, imageBytesBeforeClear)
    }

    func testResetApplicationClearsStorageUsageCounters() async throws {
        let fixture = try makeFixture()
        try await seedNovelCache(fixture)
        try await seedMangaIndexCache(fixture)
        try await seedMangaImageCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        XCTAssertGreaterThan(viewModel.novelCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaImageCacheBytes, 0)

        let didReset = await viewModel.resetApplication()

        XCTAssertTrue(didReset)
        XCTAssertEqual(viewModel.novelCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaImageCacheBytes, 0)
    }
}

private struct SystemSettingsFixture {
    let appContext: YamiboAppContext
    let settingsStore: SettingsStore
    let readerCacheStore: ReaderCacheStore
    let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
    let mangaDirectoryStore: GRDBMangaDirectoryStore
    let mangaChapterDocumentStore: GRDBMangaChapterDocumentStore
    let mangaImageDataCacheStore: FileMangaImageDataCacheStore
    let mangaOfflineCacheStore: any MangaOfflineCacheStoring
}

private func makeFixture() throws -> SystemSettingsFixture {
    let suiteName = "system-settings-view-model-\(UUID().uuidString)"
    try makeDefaults(suiteName: suiteName).removePersistentDomain(forName: suiteName)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("system-settings-view-model-\(UUID().uuidString)", isDirectory: true)
    let settingsStore = SettingsStore(defaults: try makeDefaults(suiteName: suiteName), key: "settings")
    let readerCacheStore = ReaderCacheStore(baseDirectory: root.appendingPathComponent("reader-cache", isDirectory: true))
    let favoriteBackgroundImageStore = FavoriteBackgroundImageStore(
        baseDirectory: root.appendingPathComponent("favorite-background", isDirectory: true)
    )
    let database = try YamiboDatabase.openPool(rootDirectory: root.appendingPathComponent("grdb", isDirectory: true))
    let mangaDirectoryStore = GRDBMangaDirectoryStore(databasePool: database)
    let mangaChapterDocumentStore = GRDBMangaChapterDocumentStore(databasePool: database)
    let mangaImageDataCacheStore = FileMangaImageDataCacheStore(
        baseDirectory: root.appendingPathComponent("manga-image-data", isDirectory: true)
    )
    let mangaOfflineCacheStore = GRDBMangaOfflineCacheStore(
        databasePool: database,
        baseDirectory: root.appendingPathComponent("manga-offline-cache", isDirectory: true)
    )
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(defaults: try makeDefaults(suiteName: suiteName), key: "session"),
        checkInStore: YamiboCheckInStore(defaults: try makeDefaults(suiteName: suiteName), keyPrefix: "check-in"),
        settingsStore: settingsStore,
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore(defaults: try makeDefaults(suiteName: suiteName), key: "webdav"),
        readerResumeRouteStore: ReaderResumeRouteStore(defaults: try makeDefaults(suiteName: suiteName), key: "reader-resume-route"),
        readerCacheStore: readerCacheStore,
        favoriteBackgroundImageStore: favoriteBackgroundImageStore,
        mangaDirectoryStore: mangaDirectoryStore,
        mangaChapterDocumentStore: mangaChapterDocumentStore,
        mangaImageDataCacheStore: mangaImageDataCacheStore,
        mangaOfflineCacheStore: mangaOfflineCacheStore
    )

    return SystemSettingsFixture(
        appContext: appContext,
        settingsStore: settingsStore,
        readerCacheStore: readerCacheStore,
        favoriteBackgroundImageStore: favoriteBackgroundImageStore,
        mangaDirectoryStore: mangaDirectoryStore,
        mangaChapterDocumentStore: mangaChapterDocumentStore,
        mangaImageDataCacheStore: mangaImageDataCacheStore,
        mangaOfflineCacheStore: mangaOfflineCacheStore
    )
}

private func makeDefaults(suiteName: String) throws -> UserDefaults {
    try XCTUnwrap(UserDefaults(suiteName: suiteName))
}

private func seedNovelCache(_ fixture: SystemSettingsFixture) async throws {
    let threadURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=900&mobile=2"))
    try await fixture.readerCacheStore.save(
        ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            segments: [.text("测试小说缓存", chapterTitle: nil)]
        )
    )
}

private func seedMangaIndexCache(_ fixture: SystemSettingsFixture) async throws {
    let chapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=901&mobile=2"))
    try await fixture.mangaDirectoryStore.saveDirectory(
        MangaDirectory(
            cleanBookName: "测试漫画",
            strategy: .tag,
            sourceKey: "tag:1",
            chapters: [
                MangaChapter(
                    tid: "901",
                    rawTitle: "第1话",
                    chapterNumber: 1,
                    url: chapterURL
                )
            ],
            lastUpdatedAt: Date(timeIntervalSince1970: 1)
        )
    )
    try await fixture.mangaChapterDocumentStore.save(
        MangaChapterDocument(
            tid: "901",
            ownerPostID: "post-901",
            chapterTitle: "第1话",
            chapterURL: chapterURL,
            imageURLs: [
                try XCTUnwrap(URL(string: "https://img.example.com/901-1.jpg")),
                try XCTUnwrap(URL(string: "https://img.example.com/901-2.jpg"))
            ]
        ),
        for: chapterURL
    )
}

private func seedMangaImageCache(_ fixture: SystemSettingsFixture) async throws {
    try await fixture.mangaImageDataCacheStore.save(
        Data(repeating: 8, count: 4096),
        for: try XCTUnwrap(URL(string: "https://img.example.com/901-1.jpg"))
    )
}

private func seedMangaOfflineCache(_ fixture: SystemSettingsFixture) async throws {
    let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-seed.jpg"))
    try await fixture.mangaOfflineCacheStore.saveOfflineImageData(Data(repeating: 9, count: 2048), for: imageURL)
    try await fixture.mangaOfflineCacheStore.saveMembership(
        try makeMangaOfflineMembership(ownerName: "favorite-seed", tid: "902", imageURLs: [imageURL])
    )
}

private func makeMangaOfflineMembership(
    ownerName: String,
    tid: String,
    imageURLs: [URL]
) throws -> MangaOfflineCacheMembership {
    MangaOfflineCacheMembership(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")),
        imageURLs: imageURLs
    )
}

private func makeMangaOfflineWorkRequest(
    ownerName: String,
    tid: String,
    targetImageURLs: [URL]
) throws -> MangaOfflineCacheWorkRequest {
    MangaOfflineCacheWorkRequest(
        ownerName: ownerName,
        tid: tid,
        chapterTitle: "第\(tid)话",
        chapterURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")),
        targetImageURLs: targetImageURLs
    )
}

private func cacheLabel(for bytes: Int) -> String {
    let megabytes = Double(max(0, bytes)) / 1_048_576
    return String(format: "%.2f MB", megabytes)
}

@MainActor
private func waitFor(
    timeout: TimeInterval = 2,
    pollInterval: UInt64 = 20_000_000,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }
    XCTFail("Timed out waiting for condition")
}
