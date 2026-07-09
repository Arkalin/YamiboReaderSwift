import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@MainActor
final class FavoriteLibraryOrganizerTests: XCTestCase {
    func testSourceGroupFilterCountsRespectSearchAndTags() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-source-filter")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let boardA = FavoriteSourceGroup.forumBoard(id: "10", label: "版区A")
        let boardALegacy = FavoriteSourceGroup.forumBoard(id: "10", label: "旧版区A")
        let boardB = FavoriteSourceGroup.forumBoard(id: "20", label: "版区B")
        let boardAFilter = LocalFavoriteSourceFilter.forumBoard(id: "10", label: "版区A")
        let boardBFilter = LocalFavoriteSourceFilter.forumBoard(id: "20", label: "版区B")
        let firstTarget = FavoriteItemTarget(kind: .normalThread, threadID: "940")
        let secondTarget = FavoriteItemTarget(kind: .normalThread, threadID: "941")
        let thirdTarget = FavoriteItemTarget(kind: .normalThread, threadID: "942")
        let fourthTarget = FavoriteItemTarget(kind: .normalThread, threadID: "943")
        var document = try await localFavoriteLibraryStore.load()
        let tag = document.createTag(name: "筛选", color: .blue)
        document.addItem(try FavoriteItem(
            target: firstTarget,
            title: "同名主题一",
            sourceGroup: boardA,
            locations: [.category(document.defaultCategory.id)],
            tagIDs: [tag.id]
        ))
        document.addItem(try FavoriteItem(
            target: secondTarget,
            title: "同名主题二",
            sourceGroup: boardB,
            locations: [.category(document.defaultCategory.id)],
            tagIDs: [tag.id]
        ))
        document.addItem(try FavoriteItem(
            target: thirdTarget,
            title: "其他主题",
            sourceGroup: boardA,
            locations: [.category(document.defaultCategory.id)]
        ))
        document.addItem(try FavoriteItem(
            target: fourthTarget,
            title: "同名主题三",
            sourceGroup: boardALegacy,
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[boardAFilter], 3)
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[boardBFilter], 1)

        organizer.filter.searchText = "同名"
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[boardAFilter], 2)
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[boardBFilter], 1)

        organizer.filter.selectedSourceFilters = [boardAFilter]
        XCTAssertEqual(Set(organizer.derived.cards.map(\.item.target)), [firstTarget, fourthTarget])

        organizer.filter.selectedSourceFilters = [boardBFilter]
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [secondTarget])

        organizer.filter.selectedSourceFilters = [boardAFilter, boardBFilter]
        XCTAssertEqual(Set(organizer.derived.cards.map(\.item.target)), [firstTarget, secondTarget, fourthTarget])

        organizer.filter.selectedSourceFilters = [boardBFilter]
        organizer.filter.selectedTagIDs = [tag.id]
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[boardAFilter], 1)
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[boardBFilter], 1)
    }

    /// Smart-comic-mode decision #9: the "智能漫画" filter chip's visibility
    /// is gated purely on `SmartComicModeSettings` — at least one of the 3
    /// manageable boards being on — never on whether a `.mangaThread`
    /// favorite happens to exist. This deliberately checks both directions:
    /// available with zero manga favorites (mode on by default), and NOT
    /// available even with an existing manga favorite once every manageable
    /// board is switched off.
    func testMangaSourceFilterAvailabilityIsGatedOnSmartComicModeSettingsNotFavoriteExistence() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-manga-filter-availability")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            settingsStore: settingsStore
        )
        await organizer.load()
        // `load()` assigning `selectedCategoryID`/`selectedCollectionID`
        // fires `persistNavigationState()`, which spawns its own
        // unstructured load-modify-save `Task` against this same
        // `settingsStore`. Letting that settle before this test does its
        // own concurrent load-modify-save below avoids a lost-update race
        // where that Task's save (started from a `settings` snapshot it
        // read before this test's own save below) would clobber this
        // test's change with stale data — mirrors the settle delay other
        // tests in this file already use around `persistNavigationState`.
        try await Task.sleep(nanoseconds: 100_000_000)

        // Default settings: fid 30 on, zero favorites of any kind yet — the
        // chip must still be offered.
        XCTAssertTrue(organizer.derived.isMangaSourceFilterAvailable)
        XCTAssertNil(organizer.derived.sourceFilterEntryCounts[.manga])

        // Turn every manageable board off, then favorite a manga thread on
        // one of them: the favorite exists, but the chip must stay hidden.
        var settings = await settingsStore.load()
        settings.smartComicMode.enabledForumIDs = []
        try await settingsStore.save(settings)

        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: .mangaThread(threadID: "950"),
            title: "关闭板块漫画",
            forumID: "46",
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        XCTAssertFalse(organizer.derived.isMangaSourceFilterAvailable)
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[.manga], 1)

        // Turning that same board back on makes the chip available again.
        settings = await settingsStore.load()
        settings.smartComicMode.enabledForumIDs = ["46"]
        try await settingsStore.save(settings)
        await organizer.reload()

        XCTAssertTrue(organizer.derived.isMangaSourceFilterAvailable)
        XCTAssertEqual(organizer.derived.sourceFilterEntryCounts[.manga], 1)
    }

    /// Fix for the stale-state gap this file's Phase H review flagged:
    /// `FavoriteLibraryOrganizer` did not subscribe to
    /// `SettingsStore.didChangeNotification`, so toggling Smart Comic Mode
    /// while the Favorites tab was already loaded left the merged-card
    /// grouping stale until an unrelated favorite/progress/cover change
    /// happened to trigger a reload. This proves the live subscription
    /// re-derives grouping from a bare `settingsStore.save(...)` alone, with
    /// no explicit `organizer.reload()` call in between.
    func testSettingsStoreChangeLiveRefreshesMangaDirectoryGroupingWithoutManualReload() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-settings-live-refresh")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let mangaDirectoryStore = try makeMangaDirectoryStore(suiteName: suiteName)
        let directory = MangaDirectory(
            cleanBookName: "实时刷新测试漫画",
            strategy: .links,
            sourceKey: "chapter:980",
            chapters: [
                MangaChapter(tid: "980", rawTitle: "第一话", chapterNumber: 1),
                MangaChapter(tid: "981", rawTitle: "第二话", chapterNumber: 2),
            ]
        )
        try await mangaDirectoryStore.saveDirectory(directory)

        let firstTarget = FavoriteItemTarget(kind: .mangaThread, threadID: "980")
        let secondTarget = FavoriteItemTarget(kind: .mangaThread, threadID: "981")
        var document = try await localFavoriteLibraryStore.load()
        let firstItem = try FavoriteItem(
            target: firstTarget,
            title: "第一话",
            forumID: "46",
            forumName: "关闭板块",
            locations: [.category(document.defaultCategory.id)]
        )
        let secondItem = try FavoriteItem(
            target: secondTarget,
            title: "第二话",
            forumID: "46",
            forumName: "关闭板块",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(firstItem)
        document.addItem(secondItem)
        try await localFavoriteLibraryStore.save(document)

        // Board 30 is on by default (unrelated to this test's fid "46"
        // favorites), so it alone would already make the "智能漫画" chip
        // available — disable it up front so this test's chip assertions
        // isolate the fid "46" toggle being exercised below. Seeded before
        // the organizer exists, so there is no load-modify-save race with
        // its own `persistNavigationState()` background Task.
        try await settingsStore.save(AppSettings(smartComicMode: SmartComicModeSettings(enabledForumIDs: [])))

        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            settingsStore: settingsStore,
            mangaDirectoryStore: mangaDirectoryStore
        )
        await organizer.load()
        // See the sibling availability test's identical comment: let
        // `load()`'s own `persistNavigationState()` background Task settle
        // before this test does its own concurrent settings save below.
        try await Task.sleep(nanoseconds: 100_000_000)

        // fid "46" is off by default: no merge yet, two standalone cards.
        XCTAssertEqual(organizer.derived.cards.count, 2)
        XCTAssertFalse(organizer.derived.cards.contains { $0.isMergedGroup })
        XCTAssertFalse(organizer.derived.isMangaSourceFilterAvailable)

        // Flip the board on directly through the settings store — exactly
        // what the new Settings UI's toggle does — with no call to
        // `organizer.reload()` in between.
        var settings = await settingsStore.load()
        settings.smartComicMode.enabledForumIDs.insert("46")
        try await settingsStore.save(settings)

        try await waitForOrganizerCondition {
            organizer.derived.cards.count == 1
        }
        let mergedCard = try XCTUnwrap(organizer.derived.cards.first { $0.id == firstItem.id })
        XCTAssertTrue(mergedCard.isMergedGroup)
        XCTAssertEqual(mergedCard.mergedMembers?.map(\.target), [firstTarget, secondTarget])
        XCTAssertTrue(organizer.derived.isMangaSourceFilterAvailable)
    }

    func testLocalFirstTagsFilterDisplayAndBatchAssignment() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-tags")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let firstTarget = FavoriteItemTarget(kind: .normalThread, threadID: "930")
        let secondTarget = FavoriteItemTarget(kind: .normalThread, threadID: "931")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: firstTarget,
            title: "第一条",
            locations: [.category(document.defaultCategory.id)]
        ))
        document.addItem(try FavoriteItem(
            target: secondTarget,
            title: "第二条",
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        let createdTag = await organizer.createTag(name: "待读", color: .green)
        let tag = try XCTUnwrap(createdTag)
        await organizer.updateTags(for: firstTarget.id, tagIDs: [tag.id])

        XCTAssertEqual(organizer.derived.cards.first { $0.id == firstTarget.id }?.tags.map(\.name), ["待读"])

        organizer.filter.selectedTagIDs = [tag.id]
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget])

        organizer.filter.selectedTagIDs = []
        organizer.filter.searchText = "待读"
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget])

        await organizer.updateTag(id: tag.id, name: "已读", color: .purple)
        XCTAssertTrue(organizer.tags.contains { $0.id == tag.id && $0.name == "已读" && $0.color == .purple })

        organizer.filter.searchText = ""
        organizer.selection.toggleFavoriteSelection(id: secondTarget.id)
        await organizer.updateTagsForSelection([tag.id])
        XCTAssertFalse(organizer.selection.isSelectionMode)
        XCTAssertEqual(organizer.derived.cards.first { $0.id == secondTarget.id }?.tags.map(\.name), ["已读"])

        await organizer.deleteTag(id: tag.id)
        XCTAssertTrue(organizer.tags.isEmpty)
        let storedItems = try await localFavoriteLibraryStore.load().items
        XCTAssertTrue(storedItems.allSatisfy(\.tagIDs.isEmpty))
    }

    func testBatchSelectionCreatesMovesDissolvesAndDeletesEntries() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-batch-selection")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let createdCategory = await organizer.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdExistingCollection = await organizer.createCollection(name: "旧合集", color: .gray)
        let existingCollection = try XCTUnwrap(createdExistingCollection)
        organizer.closeCollection()

        let firstTarget = FavoriteItemTarget(kind: .normalThread, threadID: "920")
        let secondTarget = FavoriteItemTarget(kind: .normalThread, threadID: "921")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: firstTarget,
            title: "第一条",
            locations: [.category(category.id)]
        ))
        document.addItem(try FavoriteItem(
            target: secondTarget,
            title: "第二条",
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        organizer.selection.toggleFavoriteSelection(id: firstTarget.id)
        let createdMergedCollection = await organizer.createCollectionFromSelection(name: "合成合集", color: .green)
        let mergedCollection = try XCTUnwrap(createdMergedCollection)
        XCTAssertFalse(organizer.selection.isSelectionMode)
        let mergedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(mergedItem?.locations.contains(.collection(categoryID: category.id, collectionID: mergedCollection.id)) == true)

        organizer.closeCollection()
        let createdSecondCategory = await organizer.createCategory(name: "分类B")
        let secondCategory = try XCTUnwrap(createdSecondCategory)
        organizer.selectedCategoryID = category.id
        organizer.selection.toggleFavoriteSelection(id: secondTarget.id)
        organizer.toggleCollectionSelection(id: existingCollection.id)
        await organizer.moveSelectionToCategory(id: secondCategory.id)

        XCTAssertFalse(organizer.selection.isSelectionMode)
        XCTAssertEqual(organizer.selectedCategoryID, secondCategory.id)
        XCTAssertTrue(organizer.collections.contains { $0.id == existingCollection.id && $0.categoryID == secondCategory.id })
        let movedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == secondTarget }
        XCTAssertTrue(movedItem?.locations.contains(.category(secondCategory.id)) == true)
        XCTAssertFalse(movedItem?.locations.contains(.category(category.id)) == true)

        organizer.toggleCollectionSelection(id: existingCollection.id)
        await organizer.dissolveSelectedCollections()
        XCTAssertFalse(organizer.collections.contains { $0.id == existingCollection.id })

        organizer.selection.toggleFavoriteSelection(id: secondTarget.id)
        await organizer.deleteSelection()
        let deletedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == secondTarget }
        XCTAssertNil(deletedItem)
    }

    func testSelectionCanAddAndRemoveIndividualFavoriteLocations() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-multi-location")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let createdSourceCategory = await organizer.createCategory(name: "分类A")
        let sourceCategory = try XCTUnwrap(createdSourceCategory)
        let createdDestinationCategory = await organizer.createCategory(name: "分类B")
        let destinationCategory = try XCTUnwrap(createdDestinationCategory)
        organizer.selectedCategoryID = destinationCategory.id
        let createdCollection = await organizer.createCollection(name: "合集B", color: .blue)
        let collection = try XCTUnwrap(createdCollection)
        organizer.selectedCategoryID = sourceCategory.id
        organizer.closeCollection()

        let target = FavoriteItemTarget(kind: .normalThread, threadID: "940")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "多路径收藏",
            locations: [.category(sourceCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.addSelectionToCategory(id: destinationCategory.id)

        var loadedDocument = try await localFavoriteLibraryStore.load()
        var storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertTrue(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))

        organizer.selectedCategoryID = sourceCategory.id
        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.removeSelectionFromCurrentLocation()

        loadedDocument = try await localFavoriteLibraryStore.load()
        storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertFalse(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))

        organizer.selectedCategoryID = destinationCategory.id
        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.addSelectionToCollection(id: collection.id)

        loadedDocument = try await localFavoriteLibraryStore.load()
        storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.collection(categoryID: destinationCategory.id, collectionID: collection.id)))
    }

    func testDeleteSelectionCurrentLocationKeepsOtherLocationsAndSkipsRemoteDelete() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-location")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let recorder = FavoriteDeleteTestRecorder()
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            remoteFavoriteDeleteHandler: { items in
                try await recorder.record(items)
            }
        )
        await organizer.load()

        let createdSourceCategory = await organizer.createCategory(name: "分类A")
        let sourceCategory = try XCTUnwrap(createdSourceCategory)
        let createdDestinationCategory = await organizer.createCategory(name: "分类B")
        let destinationCategory = try XCTUnwrap(createdDestinationCategory)
        let target = FavoriteItemTarget(kind: .normalThread, threadID: "952")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "多位置远端收藏",
            remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-952"),
            locations: [.category(sourceCategory.id), .category(destinationCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        organizer.selectedCategoryID = sourceCategory.id
        await organizer.reload()

        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.deleteSelection(scope: .currentLocation)

        let loadedDocument = try await localFavoriteLibraryStore.load()
        let storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        let recordedTargetIDs = await recorder.recordedTargetIDs()
        XCTAssertFalse(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))
        XCTAssertEqual(recordedTargetIDs, [])
    }

    func testDeleteSelectionCurrentLocationDoesNotDissolveSelectedCollections() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-mixed-location")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let createdCategory = await organizer.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdCollection = await organizer.createCollection(name: "合集A", color: .blue)
        let collection = try XCTUnwrap(createdCollection)
        organizer.closeCollection()
        let target = FavoriteItemTarget(kind: .normalThread, threadID: "956")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "多位置收藏",
            locations: [
                .category(category.id),
                .collection(categoryID: category.id, collectionID: collection.id)
            ]
        ))
        try await localFavoriteLibraryStore.save(document)
        organizer.selectedCategoryID = category.id
        await organizer.reload()

        organizer.selection.toggleFavoriteSelection(id: target.id)
        organizer.toggleCollectionSelection(id: collection.id)
        await organizer.deleteSelection(scope: .currentLocation)

        let loadedDocument = try await localFavoriteLibraryStore.load()
        XCTAssertTrue(loadedDocument.collections.contains { $0.id == collection.id })
        let storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertFalse(storedItem.locations.contains(.category(category.id)))
        XCTAssertTrue(storedItem.locations.contains(.collection(categoryID: category.id, collectionID: collection.id)))
    }

    func testDeleteSelectionRemoteFailureRollsBackLocalDelete() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-rollback")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let recorder = FavoriteDeleteTestRecorder(error: YamiboError.favoriteDeleteFailed)
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            remoteFavoriteDeleteHandler: { items in
                try await recorder.record(items)
            }
        )
        await organizer.load()

        let target = FavoriteItemTarget(kind: .normalThread, threadID: "953")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "远端删除失败收藏",
            remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-953"),
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.deleteSelection(scope: .everywhere)

        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == target }
        let recordedTargetIDs = await recorder.recordedTargetIDs()
        XCTAssertNotNil(storedItem)
        XCTAssertEqual(recordedTargetIDs, [target.id])
        XCTAssertNotNil(organizer.errorMessage)
    }

    func testEverywhereDeleteFallsBackToRemoteFavoriteLookupWhenMappingIDIsMissing() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-fallback")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        LocalFavoriteDeleteTestURLProtocol.reset()
        defer { LocalFavoriteDeleteTestURLProtocol.reset() }
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            session: makeLocalFavoriteDeleteTestSession()
        )
        await organizer.load()

        let target = FavoriteItemTarget(kind: .normalThread, threadID: "955")
        var document = try await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: target,
            title: "需要回查远端 ID 的收藏",
            remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: ""),
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        await organizer.deleteItem(item, scope: .everywhere)

        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertNil(storedItem)
        XCTAssertNil(organizer.errorMessage)
        XCTAssertEqual(LocalFavoriteDeleteTestURLProtocol.deletedFavoriteIDs, ["997"])
    }

    func testLocalOnlyEverywhereDeleteDoesNotRequireRemoteLookup() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-local-only")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let target = FavoriteItemTarget(kind: .normalThread, threadID: "954")
        var document = try await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: target,
            title: "纯本地收藏",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        await organizer.deleteItem(item, scope: .everywhere)

        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertNil(storedItem)
        XCTAssertNil(organizer.errorMessage)
    }

    /// Smart-comic-mode decision #6: a merged card's unfavorite removes every
    /// member, not just the one it was invoked with, and leaves unrelated
    /// favorites untouched.
    func testDeleteMergedGroupRemovesEveryMemberAndAttemptsRemoteDeleteForEach() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-merged-group")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let recorder = FavoriteDeleteTestRecorder()
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            remoteFavoriteDeleteHandler: { items in
                try await recorder.record(items)
            }
        )
        await organizer.load()

        let firstTarget = FavoriteItemTarget(kind: .mangaThread, threadID: "960")
        let secondTarget = FavoriteItemTarget(kind: .mangaThread, threadID: "961")
        let unrelatedTarget = FavoriteItemTarget(kind: .normalThread, threadID: "962")
        var document = try await localFavoriteLibraryStore.load()
        let firstItem = try FavoriteItem(target: firstTarget, title: "第一话", locations: [.category(document.defaultCategory.id)])
        let secondItem = try FavoriteItem(target: secondTarget, title: "第二话", locations: [.category(document.defaultCategory.id)])
        document.addItem(firstItem)
        document.addItem(secondItem)
        document.addItem(try FavoriteItem(target: unrelatedTarget, title: "无关收藏", locations: [.category(document.defaultCategory.id)]))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        await organizer.deleteMergedGroup([firstItem, secondItem])

        let remainingTargets = Set(try await localFavoriteLibraryStore.load().items.map(\.target))
        let recordedTargetIDs = await recorder.recordedTargetIDs()
        XCTAssertEqual(remainingTargets, [unrelatedTarget])
        XCTAssertNil(organizer.errorMessage)
        XCTAssertEqual(Set(recordedTargetIDs), [firstTarget.id, secondTarget.id])
    }

    /// Phase E gap (smart-comic-mode design doc, Phase E's "两个不构成缺陷、
    /// 但记录供参考的观察" note ①): every other test in this file builds its
    /// organizer via `makeOrganizer` with `mangaDirectoryStore: nil`, so
    /// `resolveMangaDirectories`/`scheduleMangaCoverBackfill` always
    /// short-circuit on the nil dependency and are only ever exercised by
    /// `LocalFavoriteLibraryProjectionTests`' pure-function tests, never
    /// through the organizer's real `load()`/`reload()` wiring. This test
    /// injects a genuine GRDB-backed `MangaDirectoryStore` (mirroring
    /// `LocalFavoriteOpenTargetResolverTests`' own helper) with real chapter
    /// data, favorites two `.mangaThread` chapters on a Smart-Comic-Mode-on
    /// board (fid "30", on by `SmartComicModeSettings`'s own default) sharing
    /// that directory, and proves the full path from `load()`/`reload()`
    /// through to a merged `FavoriteCardProjection` actually resolves end to
    /// end — not just that the pure grouping function works when handed a
    /// pre-built `mangaDirectoriesByTID` dictionary directly.
    func testLoadWiresRealMangaDirectoryStoreIntoMergedFavoriteCardProjection() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-manga-directory-wiring")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let mangaDirectoryStore = try makeMangaDirectoryStore(suiteName: suiteName)
        let directory = MangaDirectory(
            cleanBookName: "组织者集成测试漫画",
            strategy: .links,
            sourceKey: "chapter:970",
            chapters: [
                MangaChapter(tid: "970", rawTitle: "第一话", chapterNumber: 1),
                MangaChapter(tid: "971", rawTitle: "第二话", chapterNumber: 2),
            ]
        )
        try await mangaDirectoryStore.saveDirectory(directory)

        let firstTarget = FavoriteItemTarget(kind: .mangaThread, threadID: "970")
        let secondTarget = FavoriteItemTarget(kind: .mangaThread, threadID: "971")
        var document = try await localFavoriteLibraryStore.load()
        let firstItem = try FavoriteItem(
            target: firstTarget,
            title: "第一话",
            forumID: "30",
            forumName: "中文百合漫画区",
            locations: [.category(document.defaultCategory.id)]
        )
        let secondItem = try FavoriteItem(
            target: secondTarget,
            title: "第二话",
            forumID: "30",
            forumName: "中文百合漫画区",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(firstItem)
        document.addItem(secondItem)
        try await localFavoriteLibraryStore.save(document)

        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            mangaDirectoryStore: mangaDirectoryStore
        )
        await organizer.load()

        XCTAssertEqual(organizer.derived.cards.count, 1)
        let mergedCard = try XCTUnwrap(organizer.derived.cards.first { $0.id == firstItem.id })
        XCTAssertTrue(mergedCard.isMergedGroup)
        XCTAssertEqual(mergedCard.mangaDirectory?.cleanBookName, "组织者集成测试漫画")
        XCTAssertEqual(mergedCard.mergedMembers?.map(\.target), [firstTarget, secondTarget])

        // `reload()` re-resolves directories independently of `load()` — a
        // background reload (e.g. from a favorite-store change notification)
        // must keep showing the merged card, not silently drop back to two
        // standalone favorites.
        await organizer.reload()
        XCTAssertEqual(organizer.derived.cards.count, 1)
        let reloadedCard = try XCTUnwrap(organizer.derived.cards.first { $0.id == firstItem.id })
        XCTAssertTrue(reloadedCard.isMergedGroup)
        XCTAssertEqual(reloadedCard.mergedMembers?.map(\.target), [firstTarget, secondTarget])
    }

    func testCollectionManagementFiltersMovesAndDissolvesFavorites() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-collections")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let createdCategory = await organizer.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdFirstCollection = await organizer.createCollection(name: "合集A", color: .blue)
        let firstCollection = try XCTUnwrap(createdFirstCollection)
        let createdSecondCollection = await organizer.createCollection(name: "合集B", color: .gray)
        let secondCollection = try XCTUnwrap(createdSecondCollection)

        let firstTarget = FavoriteItemTarget(kind: .normalThread, threadID: "910")
        let secondTarget = FavoriteItemTarget(kind: .normalThread, threadID: "911")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: firstTarget,
            title: "合集内主题",
            locations: [
                .category(category.id),
                .collection(categoryID: category.id, collectionID: firstCollection.id)
            ]
        ))
        document.addItem(try FavoriteItem(
            target: secondTarget,
            title: "分类根主题",
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        XCTAssertEqual(organizer.derived.collectionEntryCounts[firstCollection.id], 1)
        organizer.openCollection(id: firstCollection.id)
        XCTAssertEqual(organizer.selectedCollection?.id, firstCollection.id)
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget])

        await organizer.updateCollection(id: firstCollection.id, name: "合集A+", color: .purple)
        XCTAssertTrue(organizer.collections.contains { $0.id == firstCollection.id && $0.name == "合集A+" && $0.color == .purple })

        await organizer.moveCollection(id: secondCollection.id, direction: .up)
        let sameCategoryCollections = organizer.collections
            .filter { $0.categoryID == category.id }
            .sorted { $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder }
        XCTAssertEqual(sameCategoryCollections.first?.id, secondCollection.id)

        let createdSecondCategory = await organizer.createCategory(name: "分类B")
        let secondCategory = try XCTUnwrap(createdSecondCategory)
        await organizer.moveCollection(id: firstCollection.id, toCategoryID: secondCategory.id)
        organizer.openCollection(id: firstCollection.id)
        XCTAssertEqual(organizer.selectedCategoryID, secondCategory.id)
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget])
        let movedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(movedItem?.locations.contains(.collection(categoryID: secondCategory.id, collectionID: firstCollection.id)) == true)

        await organizer.dissolveCollection(id: firstCollection.id)
        XCTAssertNil(organizer.selectedCollection)
        XCTAssertFalse(organizer.collections.contains { $0.id == firstCollection.id })
        let dissolvedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(dissolvedItem?.locations.contains(.category(secondCategory.id)) == true)
        XCTAssertFalse(dissolvedItem?.locations.contains { $0.collectionID == firstCollection.id } == true)
    }

    /// `rootDerived` must keep reflecting the whole category (cards *and*
    /// collections) even while a collection is open, so the root favorites
    /// screen — which `NavigationStack` keeps mounted underneath the pushed
    /// collection detail page — never renders the same narrowed content as
    /// the detail page during an interactive edge-swipe-back gesture.
    func testRootDerivedStaysUnscopedWhileCollectionIsOpen() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-root-derived")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        let createdCategory = await organizer.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdCollection = await organizer.createCollection(name: "合集A", color: .blue)
        let collection = try XCTUnwrap(createdCollection)

        let collectionTarget = FavoriteItemTarget(kind: .normalThread, threadID: "920")
        let rootTarget = FavoriteItemTarget(kind: .normalThread, threadID: "921")
        var document = try await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: collectionTarget,
            title: "合集内主题",
            locations: [
                .category(category.id),
                .collection(categoryID: category.id, collectionID: collection.id)
            ]
        ))
        document.addItem(try FavoriteItem(
            target: rootTarget,
            title: "分类根主题",
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        // `createCollection` above already opened the new collection; return
        // to the root scope so the "before opening" assertions below reflect
        // how a user would actually land on this screen.
        organizer.closeCollection()

        // Before opening the collection, `rootDerived` mirrors `derived`.
        XCTAssertEqual(organizer.rootDerived.cards.map(\.item.target), organizer.derived.cards.map(\.item.target))
        XCTAssertTrue(organizer.rootDerived.mixedEntries.contains { if case let .collection(c) = $0 { c.id == collection.id } else { false } })

        organizer.openCollection(id: collection.id)

        // `derived` (the pushed detail page's scope) narrows to the
        // collection's own member and drops sibling collections.
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [collectionTarget])
        XCTAssertFalse(organizer.derived.mixedEntries.contains { if case .collection = $0 { true } else { false } })

        // `rootDerived` (the root page's scope) must still show everything,
        // unaffected by the collection being open.
        XCTAssertEqual(Set(organizer.rootDerived.cards.map(\.item.target)), [collectionTarget, rootTarget])
        XCTAssertTrue(organizer.rootDerived.mixedEntries.contains { if case let .collection(c) = $0 { c.id == collection.id } else { false } })
    }

    func testCategoryManagementUpdatesLibraryCountsAndSelectedCategorySetting() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-categories")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            settingsStore: settingsStore
        )
        await organizer.load()

        let createdCategory = await organizer.createCategory(name: "待读")
        let category = try XCTUnwrap(createdCategory)
        XCTAssertEqual(organizer.selectedCategoryID, category.id)

        var document = try await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: FavoriteItemTarget(kind: .normalThread, threadID: "904"),
            title: "主题",
            locations: [.category(category.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()
        XCTAssertEqual(organizer.derived.categoryEntryCounts[category.id], 1)

        await organizer.renameCategory(id: category.id, name: "已读")
        XCTAssertTrue(organizer.categories.contains { $0.id == category.id && $0.name == "已读" })

        let createdSecondCategory = await organizer.createCategory(name: "同步")
        let second = try XCTUnwrap(createdSecondCategory)
        await organizer.moveCategory(id: second.id, direction: .up)
        let nonDefault = organizer.categories.filter { !$0.isDefault }.sorted { $0.manualOrder < $1.manualOrder }
        XCTAssertEqual(nonDefault.first?.id, second.id)

        await organizer.deleteCategory(id: second.id)
        XCTAssertFalse(organizer.categories.contains { $0.id == second.id })

        try await Task.sleep(nanoseconds: 50_000_000)
        let settings = await settingsStore.load()
        XCTAssertEqual(settings.favorites.selectedCategoryID, organizer.selectedCategoryID)
    }

    func testOpenCollectionStateLoadsAndPersistsThroughSettingsStore() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-collection")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        var document = FavoriteLibraryDocument()
        let category = document.createCategory(name: "分类")
        let collection = document.createCollection(categoryID: category.id, name: "合集", color: .blue)
        try await localFavoriteLibraryStore.save(document)
        try await settingsStore.save(AppSettings(favorites: FavoriteLibrarySettings(
            selectedCategoryID: FavoriteCategory.defaultID,
            selectedCollectionID: collection.id
        )))

        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            settingsStore: settingsStore
        )
        await organizer.load()

        XCTAssertEqual(organizer.selectedCategoryID, category.id)
        XCTAssertEqual(organizer.selectedCollection?.id, collection.id)

        organizer.closeCollection()
        try await Task.sleep(nanoseconds: 50_000_000)
        var saved = await settingsStore.load()
        XCTAssertEqual(saved.favorites.selectedCategoryID, category.id)
        XCTAssertNil(saved.favorites.selectedCollectionID)

        organizer.openCollection(id: collection.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        saved = await settingsStore.load()
        XCTAssertEqual(saved.favorites.selectedCategoryID, category.id)
        XCTAssertEqual(saved.favorites.selectedCollectionID, collection.id)
    }

    func testLayoutModeLoadsAndPersistsThroughSettingsStore() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-layout")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            settingsStore: settingsStore
        )
        try await settingsStore.save(AppSettings(favorites: FavoriteLibrarySettings(
            layoutMode: .staggered,
            sortOrder: .displayTitle,
            sortDescending: true,
            showsCategoryCounts: false
        )))

        await organizer.load()
        XCTAssertEqual(organizer.display.layoutMode, .staggered)
        XCTAssertEqual(organizer.filter.sortOrder, .displayTitle)
        XCTAssertTrue(organizer.filter.sortDescending)
        XCTAssertFalse(organizer.display.showsCategoryCounts)

        organizer.updateLayoutMode(.fixedGrid)
        organizer.updateSortOrder(.lastReadAt)
        organizer.updateSortDescending(false)
        organizer.updateShowsCategoryCounts(true)
        try await Task.sleep(nanoseconds: 50_000_000)

        let saved = await settingsStore.load()
        XCTAssertEqual(saved.favorites.layoutMode, .fixedGrid)
        XCTAssertEqual(saved.favorites.sortOrder, .lastReadAt)
        XCTAssertFalse(saved.favorites.sortDescending)
        XCTAssertTrue(saved.favorites.showsCategoryCounts)
    }

    func testAddFavoritePersistsForumMetadataForNormalThread() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-add-cover")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )

        _ = try await FavoriteQuickActions.addFavorite(
            threadID: "902",
            title: "普通主题",
            type: .other,
            authorID: nil,
            forumID: "60",
            forumName: "图文区",
            contentUpdatedAt: Date(timeIntervalSince1970: 600),
            formHash: nil,
            syncToRemote: false,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            remoteRepository: nil
        )

        let target = FavoriteItemTarget(kind: .normalThread, threadID: "902")
        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertEqual(storedItem?.forumID, "60")
        XCTAssertEqual(storedItem?.forumName, "图文区")
        XCTAssertEqual(storedItem?.sourceGroup, .forumBoard(id: "60", label: "图文区"))
        XCTAssertEqual(storedItem?.contentUpdatedAt, Date(timeIntervalSince1970: 600))
    }

    func testAddNovelFavoritePersistsForumMetadataInLocalFirstLibrary() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-add-novel-forum")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        _ = try await FavoriteQuickActions.addFavorite(
            threadID: "903",
            title: "小说主题",
            type: .novel,
            authorID: "42",
            forumID: "49",
            forumName: "百合小说区",
            contentUpdatedAt: Date(timeIntervalSince1970: 700),
            formHash: nil,
            syncToRemote: false,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            remoteRepository: nil
        )

        let target = FavoriteItemTarget(kind: .novelThread, threadID: "903")
        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertEqual(storedItem?.target.kind, .novelThread)
        XCTAssertEqual(storedItem?.forumID, "49")
        XCTAssertEqual(storedItem?.forumName, "百合小说区")
        XCTAssertEqual(storedItem?.sourceGroup, .forumBoard(id: "49", label: "百合小说区"))
        XCTAssertEqual(storedItem?.contentUpdatedAt, Date(timeIntervalSince1970: 700))
    }

    func testLoadProjectsContentCoverStoreURLWhenFavoriteHasNoCoverURL() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-content-cover")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let contentCoverStore = ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
        let target = FavoriteItemTarget(kind: .normalThread, threadID: "903")
        let coverURL = try XCTUnwrap(URL(string: "https://img.example.com/store-cover.jpg"))
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: target,
            title: "普通主题",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        try await contentCoverStore.setAutomaticCover(
            coverURL,
            for: ContentCoverKey(targetType: .thread, targetID: "903")
        )

        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            contentCoverStore: contentCoverStore
        )
        await organizer.load()

        XCTAssertEqual(organizer.derived.cards.first?.coverURL, coverURL)
    }

    func testLoadProjectsNovelThreadCoverFromSharedThreadKey() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-content-cover-novel-priority")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let contentCoverStore = ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
        let target = FavoriteItemTarget(kind: .novelThread, threadID: "905")
        let resolvedCoverURL = try XCTUnwrap(URL(string: "https://img.example.com/resolved-novel-cover.jpg"))
        var document = FavoriteLibraryDocument()
        document.addItem(try FavoriteItem(
            target: target,
            title: "小说主题",
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        // Novel and normal threads share the `.thread` cover key.
        try await contentCoverStore.setAutomaticCover(
            resolvedCoverURL,
            for: ContentCoverKey(targetType: .thread, targetID: "905")
        )

        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            contentCoverStore: contentCoverStore
        )
        await organizer.load()

        XCTAssertEqual(organizer.derived.cards.first?.coverURL, resolvedCoverURL)
    }

    func testToggleTextCoverSuppressesAndRestoresResolvedCoverURL() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-toggle-text-cover")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let contentCoverStore = ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
        let target = FavoriteItemTarget(kind: .normalThread, threadID: "906")
        let coverURL = try XCTUnwrap(URL(string: "https://img.example.com/toggle-cover.jpg"))
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: target,
            title: "长按封面主题",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        try await contentCoverStore.setAutomaticCover(coverURL, for: ContentCoverKey(targetType: .thread, targetID: "906"))

        let organizer = try makeOrganizer(
            libraryStore: localFavoriteLibraryStore,
            contentCoverStore: contentCoverStore
        )
        await organizer.load()
        XCTAssertEqual(organizer.derived.cards.first?.coverURL, coverURL)
        XCTAssertEqual(organizer.derived.cards.first?.textCoverForced, false)

        let firstToggleSucceeded = await organizer.toggleTextCover(for: item)
        XCTAssertTrue(firstToggleSucceeded)
        XCTAssertNil(organizer.derived.cards.first?.coverURL)
        XCTAssertEqual(organizer.derived.cards.first?.textCoverForced, true)

        let secondToggleSucceeded = await organizer.toggleTextCover(for: item)
        XCTAssertTrue(secondToggleSucceeded)
        XCTAssertEqual(organizer.derived.cards.first?.coverURL, coverURL)
        XCTAssertEqual(organizer.derived.cards.first?.textCoverForced, false)
    }

    func testSearchModeSubmitsCountsAndExitClearsSelection() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-search-mode")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        var document = FavoriteLibraryDocument()
        let secondCategory = document.createCategory(name: "分类B")
        let matchingCollection = document.createCollection(categoryID: document.defaultCategory.id, name: "命中合集")
        _ = document.createCollection(categoryID: document.defaultCategory.id, name: "其他合集")
        let firstTarget = FavoriteItemTarget(kind: .normalThread, threadID: "950")
        let secondTarget = FavoriteItemTarget(kind: .normalThread, threadID: "951")
        let thirdTarget = FavoriteItemTarget(kind: .normalThread, threadID: "952")
        document.addItem(try FavoriteItem(
            target: firstTarget,
            title: "命中默认分类",
            locations: [.category(document.defaultCategory.id)]
        ))
        document.addItem(try FavoriteItem(
            target: secondTarget,
            title: "其他默认分类",
            locations: [
                .category(document.defaultCategory.id),
                .collection(categoryID: document.defaultCategory.id, collectionID: matchingCollection.id)
            ]
        ))
        document.addItem(try FavoriteItem(
            target: thirdTarget,
            title: "命中第二分类",
            locations: [.category(secondCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)

        let organizer = try makeOrganizer(libraryStore: localFavoriteLibraryStore)
        await organizer.load()

        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget, secondTarget])

        // Search is a live filter driven directly by the searchable text.
        organizer.filter.searchText = "命中"
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget])
        XCTAssertEqual(organizer.derived.categoryEntryCounts[document.defaultCategory.id], 2)
        XCTAssertEqual(organizer.derived.categoryEntryCounts[secondCategory.id], 1)

        organizer.filter.searchText = ""
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget, secondTarget])
    }
}

private actor FavoriteDeleteTestRecorder {
    private var targetIDs: [String] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func record(_ items: [FavoriteItem]) throws {
        targetIDs.append(contentsOf: items.map(\.id))
        if let error {
            throw error
        }
    }

    func recordedTargetIDs() -> [String] {
        targetIDs
    }
}

private final class LocalFavoriteDeleteTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var deletedFavoriteIDs: [String] = []

    static func reset() {
        deletedFavoriteIDs = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bbs.yamibo.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let absoluteString = request.url?.absoluteString ?? ""
        let body: String
        let statusCode = 200

        if absoluteString.contains("do=favorite") {
            body = """
            <html><body>
              <ul class="sclist">
                <li>
                  <a href="forum.php?mod=viewthread&tid=955&mobile=2">需要回查远端 ID 的收藏</a>
                  <a class="mdel" href="home.php?mod=spacecp&ac=favorite&op=delete&favid=997">删除</a>
                </li>
              </ul>
            </body></html>
            """
        } else if absoluteString.contains("mod=faq") {
            body = #"<html><body><input name="formhash" value="abc12345" /></body></html>"#
        } else if absoluteString.contains("ac=favorite"),
                  absoluteString.contains("op=delete") {
            let requestBody = Self.requestBodyString(from: request)
            if requestBody.contains("favorite%5B%5D=997") || requestBody.contains("favorite[]=997") {
                Self.deletedFavoriteIDs.append("997")
                body = "<html><body>操作成功</body></html>"
            } else {
                body = "<html><body>操作失败</body></html>"
            }
        } else {
            body = "<html><body>not found</body></html>"
        }

        let data = Data(body.utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://bbs.yamibo.com/")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBodyString(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private func makeLocalFavoriteDeleteTestSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LocalFavoriteDeleteTestURLProtocol.self]
    return URLSession(configuration: configuration)
}

/// Builds a `FavoriteLibraryOrganizer` backed by isolated per-test stores,
/// mirroring the composition root's repository wiring for the given session.
@MainActor
private func makeOrganizer(
    libraryStore: FavoriteLibraryStore? = nil,
    readingProgressStore: ReadingProgressStore? = nil,
    settingsStore: SettingsStore? = nil,
    contentCoverStore: ContentCoverStore? = nil,
    mangaDirectoryStore: MangaDirectoryStore? = nil,
    makeForumThreadReaderRepository: (@Sendable () async -> ForumThreadReaderRepository)? = nil,
    session: URLSession? = nil,
    remoteFavoriteDeleteHandler: (([FavoriteItem]) async throws -> Void)? = nil
) throws -> FavoriteLibraryOrganizer {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "favorite-organizer-deps")
    let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
    let sessionStore = SessionStore(defaults: defaults, key: "session")
    let resolvedSession = session ?? YamiboNetworkConfiguration.makeSession()
    return FavoriteLibraryOrganizer(
        libraryStore: libraryStore ?? FavoriteLibraryStore(defaults: defaults, key: "local-favorites"),
        readingProgressStore: readingProgressStore ?? ReadingProgressStore(defaults: defaults, key: "reading-progress"),
        settingsStore: settingsStore ?? SettingsStore(defaults: defaults, key: "settings"),
        contentCoverStore: contentCoverStore ?? ContentCoverStore(defaults: defaults, key: "content-covers"),
        mangaDirectoryStore: mangaDirectoryStore,
        makeForumThreadReaderRepository: makeForumThreadReaderRepository,
        makeFavoriteRepository: {
            let sessionState = await sessionStore.load()
            return FavoriteRepository(client: YamiboClient(
                session: resolvedSession,
                cookie: sessionState.cookie,
                userAgent: sessionState.userAgent
            ))
        },
        remoteFavoriteDeleteHandler: remoteFavoriteDeleteHandler
    )
}

/// Real GRDB-backed `MangaDirectoryStore` for a test, mirroring
/// `LocalFavoriteOpenTargetResolverTests`' own helper — the Phase E gap this
/// file's integration test closes is specifically that `makeOrganizer` never
/// injected a real store, so a fake/in-memory double would not prove
/// anything a mock couldn't already; this needs the genuine GRDB-backed type.
private func makeMangaDirectoryStore(suiteName: String) throws -> MangaDirectoryStore {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("favorite-library-organizer-tests", isDirectory: true)
        .appendingPathComponent(suiteName, isDirectory: true)
    let database = try YamiboDatabase.openPool(rootDirectory: root)
    return MangaDirectoryStore(databasePool: database)
}

/// Polls a `@MainActor` condition until it's true or the timeout elapses —
/// for asserting on state that only updates asynchronously in response to a
/// `NotificationCenter` subscription (e.g. `FavoriteLibraryOrganizer`'s
/// `SettingsStore.didChangeNotification` listener), where a fixed
/// `Task.sleep` would be a flaky guess at how long that takes.
@MainActor
private func waitForOrganizerCondition(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let start = ContinuousClock.now
    while condition() == false {
        if start.duration(to: .now) > .nanoseconds(Int64(timeoutNanoseconds)) {
            throw YamiboError.underlying("Timed out waiting for condition")
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}
