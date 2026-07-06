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
        let firstTarget = FavoriteContentTarget(kind: .normalThread, threadID: "940")
        let secondTarget = FavoriteContentTarget(kind: .normalThread, threadID: "941")
        let thirdTarget = FavoriteContentTarget(kind: .normalThread, threadID: "942")
        let fourthTarget = FavoriteContentTarget(kind: .normalThread, threadID: "943")
        var document = await localFavoriteLibraryStore.load()
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

        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardA], 3)
        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardALegacy], 3)
        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardB], 1)

        organizer.filter.searchText = "同名"
        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardA], 2)
        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardB], 1)

        organizer.filter.sourceGroupFilter = .group(boardA)
        XCTAssertEqual(Set(organizer.derived.cards.map(\.item.target)), [firstTarget, fourthTarget])

        organizer.filter.sourceGroupFilter = .group(boardB)
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [secondTarget])

        organizer.filter.selectedTagIDs = [tag.id]
        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardA], 1)
        XCTAssertEqual(organizer.derived.sourceGroupEntryCounts[boardB], 1)
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

        let firstTarget = FavoriteContentTarget(kind: .normalThread, threadID: "930")
        let secondTarget = FavoriteContentTarget(kind: .normalThread, threadID: "931")
        var document = await localFavoriteLibraryStore.load()
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
        let storedItems = await localFavoriteLibraryStore.load().items
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

        let firstTarget = FavoriteContentTarget(kind: .normalThread, threadID: "920")
        let secondTarget = FavoriteContentTarget(kind: .normalThread, threadID: "921")
        var document = await localFavoriteLibraryStore.load()
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
        let mergedItem = await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
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
        let movedItem = await localFavoriteLibraryStore.load().items.first { $0.target == secondTarget }
        XCTAssertTrue(movedItem?.locations.contains(.category(secondCategory.id)) == true)
        XCTAssertFalse(movedItem?.locations.contains(.category(category.id)) == true)

        organizer.toggleCollectionSelection(id: existingCollection.id)
        await organizer.dissolveSelectedCollections()
        XCTAssertFalse(organizer.collections.contains { $0.id == existingCollection.id })

        organizer.selection.toggleFavoriteSelection(id: secondTarget.id)
        await organizer.deleteSelection()
        let deletedItem = await localFavoriteLibraryStore.load().items.first { $0.target == secondTarget }
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

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "940")
        var document = await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "多路径收藏",
            locations: [.category(sourceCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.addSelectionToCategory(id: destinationCategory.id)

        var loadedDocument = await localFavoriteLibraryStore.load()
        var storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertTrue(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))

        organizer.selectedCategoryID = sourceCategory.id
        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.removeSelectionFromCurrentLocation()

        loadedDocument = await localFavoriteLibraryStore.load()
        storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertFalse(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))

        organizer.selectedCategoryID = destinationCategory.id
        organizer.selection.toggleFavoriteSelection(id: target.id)
        await organizer.addSelectionToCollection(id: collection.id)

        loadedDocument = await localFavoriteLibraryStore.load()
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
        let target = FavoriteContentTarget(kind: .normalThread, threadID: "952")
        var document = await localFavoriteLibraryStore.load()
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

        let loadedDocument = await localFavoriteLibraryStore.load()
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
        let target = FavoriteContentTarget(kind: .normalThread, threadID: "956")
        var document = await localFavoriteLibraryStore.load()
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

        let loadedDocument = await localFavoriteLibraryStore.load()
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

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "953")
        var document = await localFavoriteLibraryStore.load()
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

        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
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

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "955")
        var document = await localFavoriteLibraryStore.load()
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

        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
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

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "954")
        var document = await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: target,
            title: "纯本地收藏",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        await organizer.reload()

        await organizer.deleteItem(item, scope: .everywhere)

        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertNil(storedItem)
        XCTAssertNil(organizer.errorMessage)
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

        let firstTarget = FavoriteContentTarget(kind: .normalThread, threadID: "910")
        let secondTarget = FavoriteContentTarget(kind: .normalThread, threadID: "911")
        var document = await localFavoriteLibraryStore.load()
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
        let movedItem = await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(movedItem?.locations.contains(.collection(categoryID: secondCategory.id, collectionID: firstCollection.id)) == true)

        await organizer.dissolveCollection(id: firstCollection.id)
        XCTAssertNil(organizer.selectedCollection)
        XCTAssertFalse(organizer.collections.contains { $0.id == firstCollection.id })
        let dissolvedItem = await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(dissolvedItem?.locations.contains(.category(secondCategory.id)) == true)
        XCTAssertFalse(dissolvedItem?.locations.contains { $0.collectionID == firstCollection.id } == true)
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

        var document = await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: FavoriteContentTarget(kind: .normalThread, threadID: "904"),
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

        _ = try await ForumThreadFavoriteSync.addFavorite(
            threadID: "902",
            title: "普通主题",
            type: .other,
            authorID: nil,
            forumID: "60",
            forumName: "图文区",
            contentUpdatedAt: Date(timeIntervalSince1970: 600),
            formHash: nil,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            remoteRepository: nil
        )

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "902")
        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
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
        _ = try await ForumThreadFavoriteSync.addFavorite(
            threadID: "903",
            title: "小说主题",
            type: .novel,
            authorID: "42",
            forumID: "49",
            forumName: "百合小说区",
            contentUpdatedAt: Date(timeIntervalSince1970: 700),
            formHash: nil,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            remoteRepository: nil
        )

        let target = FavoriteContentTarget(kind: .novelThread, threadID: "903")
        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
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
        let target = FavoriteContentTarget(kind: .normalThread, threadID: "903")
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
        let target = FavoriteContentTarget(kind: .novelThread, threadID: "905")
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
        let firstTarget = FavoriteContentTarget(kind: .normalThread, threadID: "950")
        let secondTarget = FavoriteContentTarget(kind: .normalThread, threadID: "951")
        let thirdTarget = FavoriteContentTarget(kind: .normalThread, threadID: "952")
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
        organizer.selection.toggleFavoriteSelection(id: firstTarget.id)
        XCTAssertTrue(organizer.selection.isSelectionMode)
        organizer.enterSearchMode()
        XCTAssertTrue(organizer.selection.isSearchMode)
        XCTAssertFalse(organizer.selection.isSelectionMode)
        organizer.selection.searchDraftText = " 命中 "
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget, secondTarget])

        organizer.submitSearch()
        XCTAssertEqual(organizer.filter.searchText, "命中")
        XCTAssertEqual(organizer.derived.cards.map(\.item.target), [firstTarget])
        XCTAssertEqual(organizer.derived.categoryEntryCounts[document.defaultCategory.id], 2)
        XCTAssertEqual(organizer.derived.categoryEntryCounts[secondCategory.id], 1)

        organizer.selection.toggleFavoriteSelection(id: firstTarget.id)
        XCTAssertFalse(organizer.selection.isSearchMode)
        XCTAssertTrue(organizer.selection.isSelectionMode)
        organizer.exitSearchMode()
        XCTAssertFalse(organizer.selection.isSearchMode)
        XCTAssertEqual(organizer.selection.searchDraftText, "")
        XCTAssertEqual(organizer.filter.searchText, "")
        XCTAssertFalse(organizer.selection.isSelectionMode)
        XCTAssertEqual(organizer.selection.selectedEntryCount, 0)
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
