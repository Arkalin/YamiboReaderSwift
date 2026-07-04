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

    func testLoadReadsNovelOfflineCacheSettings() async throws {
        let fixture = try makeFixture()
        let savedSettings = NovelOfflineCacheSettings(
            retainsInlineImages: true,
            isAutoRefreshEnabled: false
        )
        try await fixture.settingsStore.save(AppSettings(novelOfflineCache: savedSettings))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.novelOfflineCache, savedSettings)
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

    func testUpdateNovelOfflineCacheSettingsPersistsSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings())

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        XCTAssertFalse(viewModel.novelOfflineCache.retainsInlineImages)
        XCTAssertTrue(viewModel.novelOfflineCache.isAutoRefreshEnabled)

        viewModel.updateNovelOfflineCacheRetainsInlineImages(true)
        try await waitFor {
            await fixture.settingsStore.load().novelOfflineCache.retainsInlineImages
        }
        viewModel.updateNovelOfflineCacheAutoRefreshEnabled(false)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.novelOfflineCache == NovelOfflineCacheSettings(
                retainsInlineImages: true,
                isAutoRefreshEnabled: false
            )
        }
        XCTAssertEqual(viewModel.novelOfflineCache, NovelOfflineCacheSettings(
            retainsInlineImages: true,
            isAutoRefreshEnabled: false
        ))
    }

    func testResetApplicationRestoresDefaultApplePencilSettings() async throws {
        let fixture = try makeFixture()
        try await fixture.settingsStore.save(AppSettings(
            novelOfflineCache: NovelOfflineCacheSettings(
                retainsInlineImages: true,
                isAutoRefreshEnabled: false
            ),
            applePencilPageTurn: ApplePencilPageTurnSettings(
                isEnabled: true,
                behavior: .doubleTapNextSqueezePrevious
            )
        ))

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let didReset = await viewModel.resetApplication()

        XCTAssertTrue(didReset)
        XCTAssertEqual(viewModel.novelOfflineCache, NovelOfflineCacheSettings())
        XCTAssertEqual(viewModel.applePencilPageTurn, ApplePencilPageTurnSettings())
        let loaded = await fixture.settingsStore.load()
        XCTAssertEqual(loaded.novelOfflineCache, NovelOfflineCacheSettings())
        XCTAssertEqual(loaded.applePencilPageTurn, ApplePencilPageTurnSettings())
        XCTAssertEqual(viewModel.favoriteBackground, FavoriteBackgroundSettings())
    }

    func testLoadReadsNovelAndMangaStorageUsage() async throws {
        let fixture = try makeFixture()
        try await seedNovelCache(fixture)
        try await seedMangaIndexCache(fixture)
        try await seedMangaOfflineCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        XCTAssertGreaterThan(viewModel.novelCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.offlineCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheLabel, cacheLabel(for: viewModel.mangaIndexCacheBytes))
        XCTAssertEqual(viewModel.offlineCacheLabel, cacheLabel(for: viewModel.offlineCacheBytes))
    }

    func testClearNovelCacheClearsReaderProjectionCacheOnly() async throws {
        let fixture = try makeFixture()
        try await seedNovelCache(fixture)
        try await seedMangaIndexCache(fixture)
        try await seedMangaOfflineCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let novelBytesBeforeClear = await fixture.readerCacheStore.totalDiskUsageBytes()
        let directoryBytesBeforeClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesBeforeClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()
        let indexBytesBeforeClear = directoryBytesBeforeClear + projectionBytesBeforeClear
        let offlineBytesBeforeClear = await fixture.offlineCacheStore.totalDiskUsageBytes()

        let didClear = await viewModel.clearNovelCache()
        let novelBytesAfterClear = await fixture.readerCacheStore.totalDiskUsageBytes()
        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesAfterClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()
        let offlineBytesAfterClear = await fixture.offlineCacheStore.totalDiskUsageBytes()
        let offlineMembershipAfterClear = await fixture.offlineCacheStore.membership(
            ownerName: "favorite-seed",
            tid: "902"
        )

        XCTAssertTrue(didClear)
        XCTAssertGreaterThan(novelBytesBeforeClear, 0)
        XCTAssertGreaterThan(indexBytesBeforeClear, 0)
        XCTAssertGreaterThan(offlineBytesBeforeClear, 0)
        XCTAssertEqual(novelBytesAfterClear, 0)
        XCTAssertEqual(directoryBytesAfterClear, directoryBytesBeforeClear)
        XCTAssertEqual(projectionBytesAfterClear, projectionBytesBeforeClear)
        XCTAssertEqual(offlineBytesAfterClear, offlineBytesBeforeClear)
        XCTAssertNotNil(offlineMembershipAfterClear)
        XCTAssertEqual(viewModel.novelCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, indexBytesBeforeClear)
        XCTAssertEqual(viewModel.offlineCacheBytes, offlineBytesBeforeClear)
    }

    func testClearMangaIndexCacheClearsDirectoriesAndReaderProjectionsOnly() async throws {
        let fixture = try makeFixture()
        try await seedMangaIndexCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()

        let didClear = await viewModel.clearMangaIndexCache()
        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesAfterClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()

        XCTAssertTrue(didClear)
        XCTAssertEqual(directoryBytesAfterClear, 0)
        XCTAssertEqual(projectionBytesAfterClear, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, 0)
    }

    func testClearImageCachePreservesReaderAndUserOwnedCaches() async throws {
        let fixture = try makeFixture()
        try await seedNovelCache(fixture)
        try await seedMangaIndexCache(fixture)
        let offlineImageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-settings.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data(repeating: 4, count: 1024), for: offlineImageURL)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "903", imageURLs: [offlineImageURL])
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMangaOfflineWorkRequest(
                ownerName: "作品B",
                tid: "904",
                targetImageURLs: [try XCTUnwrap(URL(string: "https://img.example.com/offline-work.jpg"))]
            )
        )
        let favoriteBackgroundID = "settings-background"
        try await fixture.favoriteBackgroundImageStore.save(
            Data(repeating: 5, count: 128),
            imageID: favoriteBackgroundID
        )
        try await fixture.settingsStore.save(AppSettings(
            favoriteBackground: FavoriteBackgroundSettings(isEnabled: true, imageID: favoriteBackgroundID),
            homePage: .favorites
        ))
        var favoriteLibrary = FavoriteLibraryDocument()
        favoriteLibrary.addItem(try FavoriteItem(
            target: FavoriteContentTarget(kind: .normalThread, threadID: "905"),
            title: "收藏条目",
            locations: [.category(favoriteLibrary.defaultCategory.id)]
        ))
        try await fixture.appContext.localFavoriteLibraryStore.save(favoriteLibrary)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        let novelBytesBeforeClear = await fixture.readerCacheStore.totalDiskUsageBytes()
        let directoryBytesBeforeClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesBeforeClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()
        let indexBytesBeforeClear = directoryBytesBeforeClear + projectionBytesBeforeClear
        let offlineBytesBeforeClear = await fixture.offlineCacheStore.totalDiskUsageBytes()

        let didClear = await viewModel.clearImageCache()
        let novelBytesAfterClear = await fixture.readerCacheStore.totalDiskUsageBytes()
        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesAfterClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()
        let offlineBytesAfterClear = await fixture.offlineCacheStore.totalDiskUsageBytes()
        let offlineMembershipAfterClear = await fixture.offlineCacheStore.membership(ownerName: "作品A", tid: "903")
        let offlineWorkAfterClear = await fixture.offlineCacheStore.offlineCacheWork(ownerName: "作品B", tid: "904")
        let favoriteBackgroundDataAfterClear = await fixture.favoriteBackgroundImageStore.loadData(imageID: favoriteBackgroundID)
        let settingsAfterClear = await fixture.settingsStore.load()
        let favoriteLibraryAfterClear = await fixture.appContext.localFavoriteLibraryStore.load()

        XCTAssertTrue(didClear)
        XCTAssertEqual(fixture.ordinaryImageCache.removeAllCallCount, 1)
        XCTAssertEqual(novelBytesAfterClear, novelBytesBeforeClear)
        XCTAssertEqual(directoryBytesAfterClear, directoryBytesBeforeClear)
        XCTAssertEqual(projectionBytesAfterClear, projectionBytesBeforeClear)
        XCTAssertEqual(offlineBytesAfterClear, offlineBytesBeforeClear)
        XCTAssertNotNil(offlineMembershipAfterClear)
        XCTAssertNotNil(offlineWorkAfterClear)
        XCTAssertEqual(favoriteBackgroundDataAfterClear, Data(repeating: 5, count: 128))
        XCTAssertEqual(settingsAfterClear.homePage, .favorites)
        XCTAssertEqual(settingsAfterClear.favoriteBackground.imageID, favoriteBackgroundID)
        XCTAssertEqual(favoriteLibraryAfterClear, favoriteLibrary)
        XCTAssertEqual(viewModel.novelCacheBytes, novelBytesBeforeClear)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, indexBytesBeforeClear)
        XCTAssertEqual(viewModel.offlineCacheBytes, offlineBytesBeforeClear)
    }

    func testOfflineCacheManagementFiltersOwnersWithMembershipOrWorkAndShowsUsage() async throws {
        let fixture = try makeFixture()
        let membershipImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-a.jpg"))
        let workImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-b.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data(repeating: 1, count: 4), for: membershipImage)
        try await fixture.offlineCacheStore.saveOfflineImageData(Data(repeating: 2, count: 7), for: workImage)
        let membership = try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [membershipImage])
        try await fixture.offlineCacheStore.saveMembership(membership)
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMangaOfflineWorkRequest(ownerName: "作品B", tid: "320", targetImageURLs: [workImage])
        )
        try await fixture.offlineCacheStore.updateOfflineCacheWorkProgress(
            ownerName: "作品B",
            tid: "320",
            targetImageURLs: [workImage],
            completedImageURLs: [workImage],
            currentBytesPerSecond: nil
        )
        try await fixture.offlineCacheStore.saveNovelOfflineCacheEntry(
            try makeNovelOfflineCacheEntry(ownerTitle: "小说A", tid: "410", view: 1)
        )

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        let groupsByID = Dictionary(
            uniqueKeysWithValues: viewModel.offlineCacheManagementRows.map { ($0.id, $0) }
        )
        let novelGroupID = try novelOfflineEntryID(ownerTitle: "小说A", tid: "410", view: 1).groupID
        let cachedMangaGroup = groupsByID[OfflineCacheGroupID(readerKind: .manga, ownerKey: "作品A")]
        let pendingMangaGroup = groupsByID[OfflineCacheGroupID(readerKind: .manga, ownerKey: "作品B")]
        let novelGroup = groupsByID[novelGroupID]
        let expectedMangaBytes = try JSONEncoder().encode(membership.sourcePage).count + 4
        XCTAssertEqual(cachedMangaGroup?.title, "作品A")
        XCTAssertEqual(cachedMangaGroup?.byteCount, expectedMangaBytes)
        XCTAssertEqual(pendingMangaGroup?.title, "作品B")
        XCTAssertEqual(pendingMangaGroup?.byteCount, 7)
        XCTAssertEqual(novelGroup?.title, "小说A")
        XCTAssertEqual(novelGroup?.entries.count, 1)
        XCTAssertGreaterThan(novelGroup?.byteCount ?? 0, 0)
        XCTAssertFalse(viewModel.offlineCacheManagementIsEmpty)
    }

    func testOfflineCacheManagementEmptyStateWhenNoMembershipOrWorkExists() async throws {
        let fixture = try makeFixture()
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)

        await viewModel.refreshOfflineCacheManagement()

        XCTAssertTrue(viewModel.offlineCacheManagementRows.isEmpty)
        XCTAssertTrue(viewModel.offlineCacheManagementIsEmpty)
    }

    func testOfflineCacheManagementSingleAndSwipeDeletePrepareConfirmation() async throws {
        let fixture = try makeFixture()
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-single.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [imageURL])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.requestOfflineCacheGroupDeletion(id: mangaOfflineGroupID("作品A"))
        XCTAssertEqual(viewModel.pendingOfflineCacheManagementConfirmation?.groupIDs.map(\.ownerKey), ["作品A"])

        viewModel.cancelOfflineCacheManagementConfirmation()
        viewModel.requestOfflineCacheSwipeGroupDeletion(id: mangaOfflineGroupID("作品A"))
        XCTAssertEqual(viewModel.pendingOfflineCacheManagementConfirmation?.groupIDs.map(\.ownerKey), ["作品A"])
    }

    func testOfflineCacheManagementBatchDeleteUsesOneConfirmationForSelectedOwners() async throws {
        let fixture = try makeFixture()
        let firstImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-batch-1.jpg"))
        let secondImage = try XCTUnwrap(URL(string: "https://img.example.com/offline-batch-2.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: firstImage)
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([2]), for: secondImage)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [firstImage])
        )
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品B", tid: "320", imageURLs: [secondImage])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.setOfflineCacheManagementSelectionMode(true)
        viewModel.toggleOfflineCacheManagementSelection(id: mangaOfflineGroupID("作品A"))
        viewModel.toggleOfflineCacheManagementSelection(id: mangaOfflineGroupID("作品B"))
        viewModel.requestSelectedOfflineCacheGroupDeletion()

        XCTAssertEqual(viewModel.pendingOfflineCacheManagementConfirmation?.groupIDs.map(\.ownerKey), ["作品A", "作品B"])
    }

    func testOfflineCacheManagementSelectionActionStateEnablesDeleteWhenOwnerIsSelected() async throws {
        let fixture = try makeFixture()
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-selection-state.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [imageURL])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.setOfflineCacheManagementSelectionMode(true)
        XCTAssertEqual(
            viewModel.offlineCacheManagementSelectionActionState,
            OfflineCacheManagementSelectionActionState(selectedGroupCount: 0, canDelete: false)
        )

        viewModel.toggleOfflineCacheManagementSelection(id: mangaOfflineGroupID("作品A"))
        XCTAssertEqual(
            viewModel.offlineCacheManagementSelectionActionState,
            OfflineCacheManagementSelectionActionState(selectedGroupCount: 1, canDelete: true)
        )

        viewModel.toggleOfflineCacheManagementSelection(id: mangaOfflineGroupID("作品A"))
        XCTAssertEqual(
            viewModel.offlineCacheManagementSelectionActionState,
            OfflineCacheManagementSelectionActionState(selectedGroupCount: 0, canDelete: false)
        )
    }

    func testOfflineCacheManagementConfirmDeletesMembershipsWorksAndUnsharedOfflineBytes() async throws {
        let fixture = try makeFixture()
        let removedImage = try XCTUnwrap(URL(string: "https://img.example.com/remove.jpg"))
        let sharedImage = try XCTUnwrap(URL(string: "https://img.example.com/shared.jpg"))
        let workImage = try XCTUnwrap(URL(string: "https://img.example.com/work.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: removedImage)
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([2]), for: sharedImage)
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([3]), for: workImage)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [removedImage, sharedImage])
        )
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品B", tid: "320", imageURLs: [sharedImage])
        )
        _ = try await fixture.offlineCacheStore.enqueueOfflineCacheWork(
            try makeMangaOfflineWorkRequest(ownerName: "作品A", tid: "311", targetImageURLs: [workImage])
        )
        try await fixture.offlineCacheStore.updateOfflineCacheWorkProgress(
            ownerName: "作品A",
            tid: "311",
            targetImageURLs: [workImage],
            completedImageURLs: [workImage],
            currentBytesPerSecond: nil
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.requestOfflineCacheGroupDeletion(id: mangaOfflineGroupID("作品A"))
        let didDelete = await viewModel.confirmPendingOfflineCacheManagementDeletion()

        let removedMembership = await fixture.offlineCacheStore.membership(ownerName: "作品A", tid: "310")
        let removedWork = await fixture.offlineCacheStore.offlineCacheWork(ownerName: "作品A", tid: "311")
        let removedImageData = await fixture.offlineCacheStore.offlineImageData(for: removedImage)
        let workImageData = await fixture.offlineCacheStore.offlineImageData(for: workImage)
        let sharedImageData = await fixture.offlineCacheStore.offlineImageData(for: sharedImage)

        XCTAssertTrue(didDelete)
        XCTAssertNil(removedMembership)
        XCTAssertNil(removedWork)
        XCTAssertNil(removedImageData)
        XCTAssertNil(workImageData)
        XCTAssertEqual(sharedImageData, Data([2]))
        XCTAssertEqual(viewModel.offlineCacheManagementRows.map(\.id.ownerKey), ["作品B"])
        XCTAssertFalse(viewModel.isOfflineCacheManagementSelectionMode)
        XCTAssertTrue(viewModel.selectedOfflineCacheGroupIDs.isEmpty)
    }

    func testOfflineCacheManagementEntryDeletionDeletesOnlySelectedEntry() async throws {
        let fixture = try makeFixture()
        let firstImage = try XCTUnwrap(URL(string: "https://img.example.com/entry-310.jpg"))
        let secondImage = try XCTUnwrap(URL(string: "https://img.example.com/entry-311.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: firstImage)
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([2]), for: secondImage)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [firstImage])
        )
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "311", imageURLs: [secondImage])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.requestOfflineCacheEntryDeletion(id: mangaOfflineEntryID(ownerName: "作品A", tid: "310"))
        let didDelete = await viewModel.confirmPendingOfflineCacheManagementDeletion()

        let removedMembership = await fixture.offlineCacheStore.membership(ownerName: "作品A", tid: "310")
        let retainedMembership = await fixture.offlineCacheStore.membership(ownerName: "作品A", tid: "311")
        let removedImageData = await fixture.offlineCacheStore.offlineImageData(for: firstImage)
        let retainedImageData = await fixture.offlineCacheStore.offlineImageData(for: secondImage)

        XCTAssertTrue(didDelete)
        XCTAssertNil(removedMembership)
        XCTAssertNotNil(retainedMembership)
        XCTAssertNil(removedImageData)
        XCTAssertEqual(retainedImageData, Data([2]))
        XCTAssertEqual(viewModel.offlineCacheManagementRows.map(\.id.ownerKey), ["作品A"])
        XCTAssertEqual(viewModel.offlineCacheManagementRows.first?.entries.map(\.id.entryKey), ["311"])
    }

    func testOfflineCacheManagementDeletesNovelGroupAndIndividualView() async throws {
        let fixture = try makeFixture()
        try await fixture.offlineCacheStore.saveNovelOfflineCacheEntry(
            try makeNovelOfflineCacheEntry(ownerTitle: "小说A", tid: "410", view: 1)
        )
        try await fixture.offlineCacheStore.saveNovelOfflineCacheEntry(
            try makeNovelOfflineCacheEntry(ownerTitle: "小说A", tid: "410", view: 2)
        )
        try await fixture.offlineCacheStore.saveNovelOfflineCacheEntry(
            try makeNovelOfflineCacheEntry(ownerTitle: "小说B", tid: "420", view: 1)
        )
        let firstEntryID = try novelOfflineEntryID(tid: "410", view: 1)
        let secondEntryID = try novelOfflineEntryID(tid: "410", view: 2)
        let firstGroupID = firstEntryID.groupID
        let otherGroupID = try novelOfflineEntryID(ownerTitle: "小说B", tid: "420", view: 1).groupID
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.requestOfflineCacheEntryDeletion(id: firstEntryID)
        let didDeleteEntry = await viewModel.confirmPendingOfflineCacheManagementDeletion()

        XCTAssertTrue(didDeleteEntry)
        let removedEntry = await fixture.offlineCacheStore.novelOfflineCacheEntry(id: firstEntryID)
        let retainedEntry = await fixture.offlineCacheStore.novelOfflineCacheEntry(id: secondEntryID)
        XCTAssertNil(removedEntry)
        XCTAssertNotNil(retainedEntry)
        XCTAssertEqual(viewModel.offlineCacheManagementRows.first { $0.id == firstGroupID }?.title, "小说A")
        XCTAssertEqual(viewModel.offlineCacheManagementRows.first { $0.id == firstGroupID }?.entries.count, 1)

        viewModel.requestOfflineCacheGroupDeletion(id: firstGroupID)
        let didDeleteGroup = await viewModel.confirmPendingOfflineCacheManagementDeletion()

        XCTAssertTrue(didDeleteGroup)
        let removedGroupEntry = await fixture.offlineCacheStore.novelOfflineCacheEntry(id: secondEntryID)
        XCTAssertNil(removedGroupEntry)
        XCTAssertEqual(viewModel.offlineCacheManagementRows.map(\.id.ownerKey), [otherGroupID.ownerKey])
        XCTAssertEqual(viewModel.offlineCacheManagementRows.map(\.title), ["小说B"])
    }

    func testOfflineCacheManagementConfirmUsesCapturedConfirmationAfterPendingDismissal() async throws {
        let fixture = try makeFixture()
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/dismiss-race.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "310", imageURLs: [imageURL])
        )
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.requestOfflineCacheGroupDeletion(id: mangaOfflineGroupID("作品A"))
        let confirmation = try XCTUnwrap(viewModel.pendingOfflineCacheManagementConfirmation)
        viewModel.cancelOfflineCacheManagementConfirmation()
        let didDelete = await viewModel.confirmOfflineCacheManagementDeletion(confirmation)

        let removedMembership = await fixture.offlineCacheStore.membership(ownerName: "作品A", tid: "310")
        XCTAssertTrue(didDelete)
        XCTAssertNil(removedMembership)
        XCTAssertTrue(viewModel.offlineCacheManagementRows.isEmpty)
    }

    func testOfflineCacheManagementPreservesMangaIndexCaches() async throws {
        let fixture = try makeFixture()
        try await seedMangaIndexCache(fixture)
        let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/901-1.jpg"))
        try await fixture.offlineCacheStore.saveOfflineImageData(Data([1]), for: imageURL)
        try await fixture.offlineCacheStore.saveMembership(
            try makeMangaOfflineMembership(ownerName: "作品A", tid: "901", imageURLs: [imageURL])
        )
        let directoryBytesBeforeClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesBeforeClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()
        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.refreshOfflineCacheManagement()

        viewModel.requestOfflineCacheGroupDeletion(id: mangaOfflineGroupID("作品A"))
        let didDelete = await viewModel.confirmPendingOfflineCacheManagementDeletion()

        let directoryBytesAfterClear = await fixture.mangaDirectoryStore.totalDiskUsageBytes()
        let projectionBytesAfterClear = await fixture.mangaReaderProjectionStore.totalDiskUsageBytes()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(directoryBytesAfterClear, directoryBytesBeforeClear)
        XCTAssertEqual(projectionBytesAfterClear, projectionBytesBeforeClear)
    }

    func testResetApplicationClearsStorageUsageCounters() async throws {
        let fixture = try makeFixture()
        try await seedNovelCache(fixture)
        try await seedMangaIndexCache(fixture)
        try await seedMangaOfflineCache(fixture)

        let viewModel = SystemSettingsViewModel(appContext: fixture.appContext)
        await viewModel.load()
        XCTAssertGreaterThan(viewModel.novelCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertGreaterThan(viewModel.offlineCacheBytes, 0)

        let didReset = await viewModel.resetApplication()
        let offlineBytesAfterReset = await fixture.offlineCacheStore.totalDiskUsageBytes()
        let offlineMembershipAfterReset = await fixture.offlineCacheStore.membership(
            ownerName: "favorite-seed",
            tid: "902"
        )

        XCTAssertTrue(didReset)
        XCTAssertEqual(fixture.ordinaryImageCache.removeAllCallCount, 1)
        XCTAssertEqual(viewModel.novelCacheBytes, 0)
        XCTAssertEqual(viewModel.mangaIndexCacheBytes, 0)
        XCTAssertEqual(viewModel.offlineCacheBytes, 0)
        XCTAssertEqual(offlineBytesAfterReset, 0)
        XCTAssertNil(offlineMembershipAfterReset)
    }
}

private struct SystemSettingsFixture {
    let appContext: YamiboAppContext
    let settingsStore: SettingsStore
    let readerCacheStore: ReaderCacheStore
    let favoriteBackgroundImageStore: FavoriteBackgroundImageStore
    let mangaDirectoryStore: MangaDirectoryStore
    let mangaReaderProjectionStore: MangaReaderProjectionStore
    let offlineCacheStore: any OfflineCacheStoring
    let ordinaryImageCache: RecordingOrdinaryImageCache
}

private func makeFixture() throws -> SystemSettingsFixture {
    let suiteName = "system-settings-view-model-\(UUID().uuidString)"
    try makeDefaults(suiteName: suiteName).removePersistentDomain(forName: suiteName)

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("system-settings-view-model-\(UUID().uuidString)", isDirectory: true)
    let settingsStore = SettingsStore(defaults: try makeDefaults(suiteName: suiteName), key: "settings")
    let database = try YamiboDatabase.openPool(rootDirectory: root.appendingPathComponent("grdb", isDirectory: true))
    let readerCacheStore = ReaderCacheStore(
        databasePool: database,
        baseDirectory: root.appendingPathComponent("reader-cache", isDirectory: true)
    )
    let favoriteBackgroundImageStore = FavoriteBackgroundImageStore(
        baseDirectory: root.appendingPathComponent("favorite-background", isDirectory: true)
    )
    let mangaDirectoryStore = MangaDirectoryStore(databasePool: database)
    let mangaReaderProjectionStore = MangaReaderProjectionStore(databasePool: database)
    let offlineCacheStore = OfflineCacheStore(
        databasePool: database,
        baseDirectory: root.appendingPathComponent("manga-offline-cache", isDirectory: true)
    )
    let ordinaryImageCache = RecordingOrdinaryImageCache()
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(defaults: try makeDefaults(suiteName: suiteName), key: "session"),
        checkInStore: YamiboCheckInStore(defaults: try makeDefaults(suiteName: suiteName), keyPrefix: "check-in"),
        settingsStore: settingsStore,
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore(defaults: try makeDefaults(suiteName: suiteName), key: "webdav"),
        readerResumeRouteStore: ReaderResumeRouteStore(defaults: try makeDefaults(suiteName: suiteName), key: "reader-resume-route"),
        readerCacheStore: readerCacheStore,
        favoriteBackgroundImageStore: favoriteBackgroundImageStore,
        mangaDirectoryStore: mangaDirectoryStore,
        mangaReaderProjectionStore: mangaReaderProjectionStore,
        offlineCacheStore: offlineCacheStore,
        ordinaryImageCache: ordinaryImageCache
    )

    return SystemSettingsFixture(
        appContext: appContext,
        settingsStore: settingsStore,
        readerCacheStore: readerCacheStore,
        favoriteBackgroundImageStore: favoriteBackgroundImageStore,
        mangaDirectoryStore: mangaDirectoryStore,
        mangaReaderProjectionStore: mangaReaderProjectionStore,
        offlineCacheStore: offlineCacheStore,
        ordinaryImageCache: ordinaryImageCache
    )
}

private func mangaOfflineGroupID(_ ownerName: String) -> OfflineCacheGroupID {
    OfflineCacheGroupID(readerKind: .manga, ownerKey: ownerName)
}

private func mangaOfflineEntryID(ownerName: String, tid: String) -> OfflineCacheEntryID {
    OfflineCacheEntryID(readerKind: .manga, ownerKey: ownerName, entryKey: tid)
}

private func novelOfflineEntryID(
    ownerTitle: String = "小说A",
    tid: String,
    view: Int,
    authorID: String? = nil,
    contentSource: ReaderContentSource = .fallbackUnfilteredPage
) throws -> OfflineCacheEntryID {
    OfflineCacheEntryID(
        readerKind: .novel,
        ownerKey: NovelOfflineCacheEntry.groupKey(
            threadID: tid,
            authorID: authorID,
            contentSource: contentSource
        ),
        entryKey: NovelOfflineCacheEntry.entryKey(
            threadID: tid,
            view: view,
            authorID: authorID,
            contentSource: contentSource
        )
    )
}

private final class RecordingOrdinaryImageCache: YamiboOrdinaryImageCacheClearing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var removeAllCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func removeAllCachedData() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private func makeDefaults(suiteName: String) throws -> UserDefaults {
    try XCTUnwrap(UserDefaults(suiteName: suiteName))
}

private func makeNovelOfflineCacheEntry(
    ownerTitle: String,
    tid: String,
    view: Int,
    authorID: String? = nil
) throws -> NovelOfflineCacheEntry {
    return NovelOfflineCacheEntry(
        ownerTitle: ownerTitle,
        title: "第\(view)页",
        document: ReaderPageDocument(
            threadID: tid,
            view: view,
            maxView: max(2, view),
            resolvedAuthorID: authorID,
            contentSource: authorID == nil ? .fallbackUnfilteredPage : .authorFilteredPage,
            segments: [.text("小说\(tid)-\(view)", chapterTitle: nil)]
        ),
        updatedAt: Date(timeIntervalSince1970: Double(1_000 + view))
    )
}

private func seedNovelCache(_ fixture: SystemSettingsFixture) async throws {
    try await fixture.readerCacheStore.save(
        ReaderPageDocument(
            threadID: "900",
            view: 1,
            maxView: 1,
            segments: [.text("测试小说缓存", chapterTitle: nil)]
        )
    )
}

private func seedMangaIndexCache(_ fixture: SystemSettingsFixture) async throws {
    try await fixture.mangaDirectoryStore.saveDirectory(
        MangaDirectory(
            cleanBookName: "测试漫画",
            strategy: .tag,
            sourceKey: "tag:1",
            chapters: [
                MangaChapter(
                    tid: "901",
                    rawTitle: "第1话",
                    chapterNumber: 1
                )
            ],
            lastUpdatedAt: Date(timeIntervalSince1970: 1)
        )
    )
    let sourceIdentity = MangaReaderProjectionSourceIdentity(
        tid: "901",
        authorID: nil,
        contentSource: .authorFilteredPage,
        view: 1
    )
    try await fixture.mangaReaderProjectionStore.save(MangaReaderProjection(
        tid: "901",
        ownerPostID: "post-901",
        chapterTitle: "第1话",
        imageURLs: [
            try XCTUnwrap(URL(string: "https://img.example.com/901-1.jpg")),
            try XCTUnwrap(URL(string: "https://img.example.com/901-2.jpg"))
        ],
        sourceIdentity: sourceIdentity,
        sourceFingerprint: "settings-fixture"
    ))
}

private func seedMangaOfflineCache(_ fixture: SystemSettingsFixture) async throws {
    let imageURL = try XCTUnwrap(URL(string: "https://img.example.com/offline-seed.jpg"))
    try await fixture.offlineCacheStore.saveOfflineImageData(Data(repeating: 9, count: 2048), for: imageURL)
    try await fixture.offlineCacheStore.saveMembership(
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
        imageURLs: imageURLs,
        sourcePage: makeSystemSettingsOfflineSourcePage(tid: tid)
    )
}

private func makeSystemSettingsOfflineSourcePage(tid: String) -> ForumThreadPage {
    ForumThreadPage(
        thread: ThreadIdentity(tid: tid),
        title: "第\(tid)话",
        posts: [
            ForumThreadPost(
                postID: "p-\(tid)",
                author: BlogReaderUser(uid: "author-\(tid)", name: "作者"),
                contentHTML: "",
                contentText: ""
            )
        ]
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
