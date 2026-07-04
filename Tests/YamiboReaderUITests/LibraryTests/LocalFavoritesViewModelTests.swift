import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class LocalFavoritesViewModelTests: XCTestCase {
    func testSourceGroupFilterCountsRespectSearchAndTags() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-source-filter")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

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
        await viewModel.reload()

        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardA], 3)
        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardALegacy], 3)
        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardB], 1)

        viewModel.searchText = "同名"
        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardA], 2)
        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardB], 1)

        viewModel.sourceGroupFilter = .group(boardA)
        XCTAssertEqual(Set(viewModel.cards.map(\.item.target)), [firstTarget, fourthTarget])

        viewModel.sourceGroupFilter = .group(boardB)
        XCTAssertEqual(viewModel.cards.map(\.item.target), [secondTarget])

        viewModel.selectedTagIDs = [tag.id]
        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardA], 1)
        XCTAssertEqual(viewModel.sourceGroupEntryCounts[boardB], 1)
    }

    func testLocalFirstTagsFilterDisplayAndBatchAssignment() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-tags")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

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
        await viewModel.reload()

        let createdTag = await viewModel.createTag(name: "待读", color: .green)
        let tag = try XCTUnwrap(createdTag)
        await viewModel.updateTags(for: firstTarget.id, tagIDs: [tag.id])

        XCTAssertEqual(viewModel.cards.first { $0.id == firstTarget.id }?.tags.map(\.name), ["待读"])

        viewModel.selectedTagIDs = [tag.id]
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget])

        viewModel.selectedTagIDs = []
        viewModel.searchText = "待读"
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget])

        await viewModel.updateTag(id: tag.id, name: "已读", color: .purple)
        XCTAssertTrue(viewModel.tags.contains { $0.id == tag.id && $0.name == "已读" && $0.color == .purple })

        viewModel.searchText = ""
        viewModel.toggleFavoriteSelection(id: secondTarget.id)
        await viewModel.updateTagsForSelection([tag.id])
        XCTAssertFalse(viewModel.isSelectionMode)
        XCTAssertEqual(viewModel.cards.first { $0.id == secondTarget.id }?.tags.map(\.name), ["已读"])

        await viewModel.deleteTag(id: tag.id)
        XCTAssertTrue(viewModel.tags.isEmpty)
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
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        let createdCategory = await viewModel.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdExistingCollection = await viewModel.createCollection(name: "旧合集", color: .gray)
        let existingCollection = try XCTUnwrap(createdExistingCollection)
        viewModel.closeCollection()

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
        await viewModel.reload()

        viewModel.toggleFavoriteSelection(id: firstTarget.id)
        let createdMergedCollection = await viewModel.createCollectionFromSelection(name: "合成合集", color: .green)
        let mergedCollection = try XCTUnwrap(createdMergedCollection)
        XCTAssertFalse(viewModel.isSelectionMode)
        let mergedItem = await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(mergedItem?.locations.contains(.collection(categoryID: category.id, collectionID: mergedCollection.id)) == true)

        viewModel.closeCollection()
        let createdSecondCategory = await viewModel.createCategory(name: "分类B")
        let secondCategory = try XCTUnwrap(createdSecondCategory)
        viewModel.selectedCategoryID = category.id
        viewModel.toggleFavoriteSelection(id: secondTarget.id)
        viewModel.toggleCollectionSelection(id: existingCollection.id)
        await viewModel.moveSelectionToCategory(id: secondCategory.id)

        XCTAssertFalse(viewModel.isSelectionMode)
        XCTAssertEqual(viewModel.selectedCategoryID, secondCategory.id)
        XCTAssertTrue(viewModel.collections.contains { $0.id == existingCollection.id && $0.categoryID == secondCategory.id })
        let movedItem = await localFavoriteLibraryStore.load().items.first { $0.target == secondTarget }
        XCTAssertTrue(movedItem?.locations.contains(.category(secondCategory.id)) == true)
        XCTAssertFalse(movedItem?.locations.contains(.category(category.id)) == true)

        viewModel.toggleCollectionSelection(id: existingCollection.id)
        await viewModel.dissolveSelectedCollections()
        XCTAssertFalse(viewModel.collections.contains { $0.id == existingCollection.id })

        viewModel.toggleFavoriteSelection(id: secondTarget.id)
        await viewModel.deleteSelection()
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
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        let createdSourceCategory = await viewModel.createCategory(name: "分类A")
        let sourceCategory = try XCTUnwrap(createdSourceCategory)
        let createdDestinationCategory = await viewModel.createCategory(name: "分类B")
        let destinationCategory = try XCTUnwrap(createdDestinationCategory)
        viewModel.selectedCategoryID = destinationCategory.id
        let createdCollection = await viewModel.createCollection(name: "合集B", color: .blue)
        let collection = try XCTUnwrap(createdCollection)
        viewModel.selectedCategoryID = sourceCategory.id
        viewModel.closeCollection()

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "940")
        var document = await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "多路径收藏",
            locations: [.category(sourceCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await viewModel.reload()

        viewModel.toggleFavoriteSelection(id: target.id)
        await viewModel.addSelectionToCategory(id: destinationCategory.id)

        var loadedDocument = await localFavoriteLibraryStore.load()
        var storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertTrue(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))

        viewModel.selectedCategoryID = sourceCategory.id
        viewModel.toggleFavoriteSelection(id: target.id)
        await viewModel.removeSelectionFromCurrentLocation()

        loadedDocument = await localFavoriteLibraryStore.load()
        storedItem = try XCTUnwrap(loadedDocument.items.first { $0.target == target })
        XCTAssertFalse(storedItem.locations.contains(.category(sourceCategory.id)))
        XCTAssertTrue(storedItem.locations.contains(.category(destinationCategory.id)))

        viewModel.selectedCategoryID = destinationCategory.id
        viewModel.toggleFavoriteSelection(id: target.id)
        await viewModel.addSelectionToCollection(id: collection.id)

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
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(
            appContext: appContext,
            remoteFavoriteDeleteHandler: { items in
                try await recorder.record(items)
            }
        )
        await viewModel.load()

        let createdSourceCategory = await viewModel.createCategory(name: "分类A")
        let sourceCategory = try XCTUnwrap(createdSourceCategory)
        let createdDestinationCategory = await viewModel.createCategory(name: "分类B")
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
        viewModel.selectedCategoryID = sourceCategory.id
        await viewModel.reload()

        viewModel.toggleFavoriteSelection(id: target.id)
        await viewModel.deleteSelection(scope: .currentLocation)

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
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        let createdCategory = await viewModel.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdCollection = await viewModel.createCollection(name: "合集A", color: .blue)
        let collection = try XCTUnwrap(createdCollection)
        viewModel.closeCollection()
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
        viewModel.selectedCategoryID = category.id
        await viewModel.reload()

        viewModel.toggleFavoriteSelection(id: target.id)
        viewModel.toggleCollectionSelection(id: collection.id)
        await viewModel.deleteSelection(scope: .currentLocation)

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
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(
            appContext: appContext,
            remoteFavoriteDeleteHandler: { items in
                try await recorder.record(items)
            }
        )
        await viewModel.load()

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "953")
        var document = await localFavoriteLibraryStore.load()
        document.addItem(try FavoriteItem(
            target: target,
            title: "远端删除失败收藏",
            remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-953"),
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        await viewModel.reload()

        viewModel.toggleFavoriteSelection(id: target.id)
        await viewModel.deleteSelection(scope: .everywhere)

        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
        let recordedTargetIDs = await recorder.recordedTargetIDs()
        XCTAssertNotNil(storedItem)
        XCTAssertEqual(recordedTargetIDs, [target.id])
        XCTAssertNotNil(viewModel.errorMessage)
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
        let appContext = YamiboAppContext(
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            session: makeLocalFavoriteDeleteTestSession()
        )
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

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
        await viewModel.reload()

        await viewModel.deleteItem(item, scope: .everywhere)

        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertNil(storedItem)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(LocalFavoriteDeleteTestURLProtocol.deletedFavoriteIDs, ["997"])
    }

    func testLocalOnlyEverywhereDeleteDoesNotRequireRemoteLookup() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-delete-local-only")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "954")
        var document = await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: target,
            title: "纯本地收藏",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        await viewModel.reload()

        await viewModel.deleteItem(item, scope: .everywhere)

        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertNil(storedItem)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCollectionManagementFiltersMovesAndDissolvesFavorites() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-collections")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        let createdCategory = await viewModel.createCategory(name: "分类A")
        let category = try XCTUnwrap(createdCategory)
        let createdFirstCollection = await viewModel.createCollection(name: "合集A", color: .blue)
        let firstCollection = try XCTUnwrap(createdFirstCollection)
        let createdSecondCollection = await viewModel.createCollection(name: "合集B", color: .gray)
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
        await viewModel.reload()

        XCTAssertEqual(viewModel.collectionEntryCounts[firstCollection.id], 1)
        viewModel.openCollection(id: firstCollection.id)
        XCTAssertEqual(viewModel.selectedCollection?.id, firstCollection.id)
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget])

        await viewModel.updateCollection(id: firstCollection.id, name: "合集A+", color: .purple)
        XCTAssertTrue(viewModel.collections.contains { $0.id == firstCollection.id && $0.name == "合集A+" && $0.color == .purple })

        await viewModel.moveCollection(id: secondCollection.id, direction: .up)
        let sameCategoryCollections = viewModel.collections
            .filter { $0.categoryID == category.id }
            .sorted { $0.manualOrder == $1.manualOrder ? $0.id < $1.id : $0.manualOrder < $1.manualOrder }
        XCTAssertEqual(sameCategoryCollections.first?.id, secondCollection.id)

        let createdSecondCategory = await viewModel.createCategory(name: "分类B")
        let secondCategory = try XCTUnwrap(createdSecondCategory)
        await viewModel.moveCollection(id: firstCollection.id, toCategoryID: secondCategory.id)
        viewModel.openCollection(id: firstCollection.id)
        XCTAssertEqual(viewModel.selectedCategoryID, secondCategory.id)
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget])
        let movedItem = await localFavoriteLibraryStore.load().items.first { $0.target == firstTarget }
        XCTAssertTrue(movedItem?.locations.contains(.collection(categoryID: secondCategory.id, collectionID: firstCollection.id)) == true)

        await viewModel.dissolveCollection(id: firstCollection.id)
        XCTAssertNil(viewModel.selectedCollection)
        XCTAssertFalse(viewModel.collections.contains { $0.id == firstCollection.id })
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
        let appContext = YamiboAppContext(
            settingsStore: settingsStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )
        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        let createdCategory = await viewModel.createCategory(name: "待读")
        let category = try XCTUnwrap(createdCategory)
        XCTAssertEqual(viewModel.selectedCategoryID, category.id)

        var document = await localFavoriteLibraryStore.load()
        let item = try FavoriteItem(
            target: FavoriteContentTarget(kind: .normalThread, threadID: "904"),
            title: "主题",
            locations: [.category(category.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)
        await viewModel.reload()
        XCTAssertEqual(viewModel.categoryEntryCounts[category.id], 1)

        await viewModel.renameCategory(id: category.id, name: "已读")
        XCTAssertTrue(viewModel.categories.contains { $0.id == category.id && $0.name == "已读" })

        let createdSecondCategory = await viewModel.createCategory(name: "同步")
        let second = try XCTUnwrap(createdSecondCategory)
        await viewModel.moveCategory(id: second.id, direction: .up)
        let nonDefault = viewModel.categories.filter { !$0.isDefault }.sorted { $0.manualOrder < $1.manualOrder }
        XCTAssertEqual(nonDefault.first?.id, second.id)

        await viewModel.deleteCategory(id: second.id)
        XCTAssertFalse(viewModel.categories.contains { $0.id == second.id })

        try await Task.sleep(nanoseconds: 50_000_000)
        let settings = await settingsStore.load()
        XCTAssertEqual(settings.favoriteSelectedCategoryID, viewModel.selectedCategoryID)
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
        try await settingsStore.save(AppSettings(
            favoriteSelectedCategoryID: FavoriteCategory.defaultID,
            favoriteSelectedCollectionID: collection.id
        ))
        let appContext = YamiboAppContext(
            settingsStore: settingsStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.selectedCategoryID, category.id)
        XCTAssertEqual(viewModel.selectedCollection?.id, collection.id)

        viewModel.closeCollection()
        try await Task.sleep(nanoseconds: 50_000_000)
        var saved = await settingsStore.load()
        XCTAssertEqual(saved.favoriteSelectedCategoryID, category.id)
        XCTAssertNil(saved.favoriteSelectedCollectionID)

        viewModel.openCollection(id: collection.id)
        try await Task.sleep(nanoseconds: 50_000_000)
        saved = await settingsStore.load()
        XCTAssertEqual(saved.favoriteSelectedCategoryID, category.id)
        XCTAssertEqual(saved.favoriteSelectedCollectionID, collection.id)
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
        let appContext = YamiboAppContext(
            settingsStore: settingsStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )
        try await settingsStore.save(AppSettings(
            favoriteLayoutMode: .staggered,
            favoriteSortOrder: .displayTitle,
            favoriteSortDescending: true,
            favoriteShowsCategoryCounts: false
        ))

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()
        XCTAssertEqual(viewModel.layoutMode, .staggered)
        XCTAssertEqual(viewModel.sortOrder, .displayTitle)
        XCTAssertTrue(viewModel.sortDescending)
        XCTAssertFalse(viewModel.showsCategoryCounts)

        viewModel.updateLayoutMode(.fixedGrid)
        viewModel.updateSortOrder(.lastReadAt)
        viewModel.updateSortDescending(false)
        viewModel.updateShowsCategoryCounts(true)
        try await Task.sleep(nanoseconds: 50_000_000)

        let saved = await settingsStore.load()
        XCTAssertEqual(saved.favoriteLayoutMode, .fixedGrid)
        XCTAssertEqual(saved.favoriteSortOrder, .lastReadAt)
        XCTAssertFalse(saved.favoriteSortDescending)
        XCTAssertTrue(saved.favoriteShowsCategoryCounts)
    }

    func testRemoteSyncSnapshotLoadsInterruptsRunningTaskAndPersistsHiddenCard() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-snapshot")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let runningSnapshot = FavoriteRemoteSyncSnapshot(
            runID: "sync-run",
            status: .running,
            targetCategoryID: FavoriteCategory.defaultID,
            targetCategoryName: "默认",
            phase: "导入",
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100),
            scannedCount: 2,
            importedCount: 1
        )
        try await settingsStore.save(AppSettings(favoriteRemoteSyncSnapshot: runningSnapshot))
        let appContext = YamiboAppContext(
            settingsStore: settingsStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.remoteSyncSnapshot?.runID, "sync-run")
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.status, .interrupted)
        XCTAssertTrue(viewModel.remoteSyncSnapshot?.warningMessages.isEmpty == false)
        let interruptedSettings = await settingsStore.load()
        XCTAssertEqual(interruptedSettings.favoriteRemoteSyncSnapshot?.status, .interrupted)

        await viewModel.hideRemoteFavoriteSyncCard()
        let hiddenSettings = await settingsStore.load()
        XCTAssertTrue(hiddenSettings.favoriteRemoteSyncSnapshot?.isHiddenFromFavoritePage == true)
    }

    func testRemoteSyncStartCompletesAndResumeUsesPersistedTargetCategory() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-complete")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let recorder = FavoriteRemoteSyncTestRecorder()
        let appContext = YamiboAppContext(
            settingsStore: settingsStore,
            localFavoriteLibraryStore: localFavoriteLibraryStore
        )
        let viewModel = LocalFavoritesViewModel(
            appContext: appContext,
            remoteFavoriteSyncExecutor: { _, categoryID in
                await recorder.record(categoryID)
                return YamiboFavoriteSyncReport(
                    importedTargetIDs: ["imported-a", "imported-b"],
                    failedRemoteFavoriteIDs: ["remote-failed"],
                    markedMissingTargetIDs: ["missing-a"],
                    uploadTargetIDs: ["upload-a"]
                )
            }
        )
        await viewModel.load()

        let firstRunID = await viewModel.startRemoteFavoriteSync(targetCategoryID: FavoriteCategory.defaultID)
        try await waitForRemoteSyncStatus(.completed, in: viewModel)
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.runID, firstRunID)
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.importedCount, 2)
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.failedCount, 1)
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.markedMissingCount, 1)
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.uploadTargetCount, 1)
        XCTAssertTrue(viewModel.remoteSyncSnapshot?.warningMessages.isEmpty == false)

        let secondRunID = await viewModel.resumeRemoteFavoriteSync()
        try await waitForRemoteSyncStatus(.completed, in: viewModel)
        XCTAssertNotEqual(secondRunID, firstRunID)
        let recordedCategoryIDs = await recorder.recordedCategoryIDs()
        XCTAssertEqual(recordedCategoryIDs, [FavoriteCategory.defaultID, FavoriteCategory.defaultID])
        let savedStatus = await settingsStore.load().favoriteRemoteSyncSnapshot?.status
        XCTAssertEqual(savedStatus, .completed)
    }

    func testRemoteSyncInterruptCancelsRunningTaskAndPersistsInterruptedStatus() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-sync-interrupt")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let settingsStore = SettingsStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "settings"
        )
        let appContext = YamiboAppContext(settingsStore: settingsStore)
        let viewModel = LocalFavoritesViewModel(
            appContext: appContext,
            remoteFavoriteSyncExecutor: { _, _ in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return YamiboFavoriteSyncReport(importedTargetIDs: ["late"])
            }
        )
        await viewModel.load()

        _ = await viewModel.startRemoteFavoriteSync(targetCategoryID: FavoriteCategory.defaultID)
        XCTAssertEqual(viewModel.remoteSyncSnapshot?.status, .running)
        await viewModel.interruptRemoteFavoriteSync()
        try await waitForRemoteSyncStatus(.interrupted, in: viewModel)

        let saved = await settingsStore.load()
        XCTAssertEqual(saved.favoriteRemoteSyncSnapshot?.status, .interrupted)
        XCTAssertTrue(saved.favoriteRemoteSyncSnapshot?.warningMessages.isEmpty == false)
    }

    func testFavoriteUpdateCheckBuildsBaselineDetectsEventsAndHonorsFidFilter() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-updates")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let favoriteUpdateStore = FavoriteUpdateStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "favorite-updates"
        )
        let appContext = YamiboAppContext(
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            favoriteUpdateStore: favoriteUpdateStore
        )
        let target = FavoriteContentTarget(kind: .normalThread, threadID: "960")
        var document = FavoriteLibraryDocument()
        let category = document.createCategory(name: "更新检测")
        document.addItem(try FavoriteItem(
            target: target,
            title: "更新主题",
            sourceGroup: .forumBoard(id: "50", label: "测试板块"),
            locations: [.category(category.id)]
        ))
        try await localFavoriteLibraryStore.save(document)

        var pagesByThreadID = [
            "960": [
                try makeFavoriteUpdateThreadPage(
                    threadID: "960",
                    postID: "p1",
                    title: "更新主题",
                    replyCount: 1,
                    pageCount: 1
                ),
                try makeFavoriteUpdateThreadPage(
                    threadID: "960",
                    postID: "p2",
                    title: "更新主题",
                    replyCount: 3,
                    pageCount: 2
                ),
                try makeFavoriteUpdateThreadPage(
                    threadID: "960",
                    postID: "p3",
                    title: "更新主题",
                    replyCount: 4,
                    pageCount: 2
                )
            ]
        ]
        var fetchedThreadIDs: [String] = []
        let viewModel = LocalFavoritesViewModel(
            appContext: appContext,
            favoriteUpdatePageFetcher: { item in
                let threadID = try XCTUnwrap(item.target.threadID)
                fetchedThreadIDs.append(threadID)
                var pages = pagesByThreadID[threadID] ?? []
                let page = try XCTUnwrap(pages.first)
                if pages.count > 1 {
                    pages.removeFirst()
                    pagesByThreadID[threadID] = pages
                }
                return page
            }
        )
        await viewModel.load()

        _ = await viewModel.startFavoriteUpdateCheck()
        try await waitForFavoriteUpdateStatus(.completed, in: viewModel)
        XCTAssertEqual(viewModel.favoriteUpdateEvents.count, 0)
        XCTAssertEqual(viewModel.favoriteUpdateFidFilters.map(\.fid), ["50"])
        XCTAssertEqual(viewModel.favoriteUpdateCategoryFilters.map(\.categoryID), [category.id])

        _ = await viewModel.startFavoriteUpdateCheck()
        try await waitForFavoriteUpdateStatus(.completed, in: viewModel)
        XCTAssertEqual(viewModel.favoriteUpdateEvents.count, 1)
        XCTAssertEqual(viewModel.favoriteUpdateEvents.first?.title, "更新主题")
        XCTAssertEqual(viewModel.favoriteUpdateEvents.first?.fid, "50")
        XCTAssertTrue(viewModel.favoriteUpdateEvents.first?.summary.contains("2") == true)

        await viewModel.setFavoriteUpdateFidFilter("50", enabled: false)
        let fetchCountBeforeDisabledRun = fetchedThreadIDs.count
        _ = await viewModel.startFavoriteUpdateCheck()
        try await waitForFavoriteUpdateStatus(.completed, in: viewModel)
        XCTAssertEqual(fetchedThreadIDs.count, fetchCountBeforeDisabledRun)
        XCTAssertEqual(viewModel.favoriteUpdateSnapshot?.totalCount, 0)
    }

    func testAddFavoritePersistsCoverURLInLocalFirstLibrary() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-add-cover")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let coverURL = try XCTUnwrap(URL(string: "https://img.example.com/cover.jpg"))

        _ = try await ForumThreadFavoriteSync.addFavorite(
            threadID: "902",
            title: "普通主题",
            type: .other,
            authorID: nil,
            forumID: "60",
            forumName: "图文区",
            coverURL: coverURL,
            contentUpdatedAt: Date(timeIntervalSince1970: 600),
            formHash: nil,
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            remoteRepository: nil
        )

        let target = FavoriteContentTarget(kind: .normalThread, threadID: "902")
        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.target == target }
        XCTAssertEqual(storedItem?.coverURL, coverURL)
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
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let contentCoverStore = ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
        let appContext = YamiboAppContext(
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            contentCoverStore: contentCoverStore
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
            for: ContentCoverKey(targetType: .threadNormal, targetID: "903")
        )

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.cards.first?.coverURL, coverURL)
    }

    func testLoadPrefersContentCoverStoreURLOverPersistedNormalThreadCoverURL() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-content-cover-normal-priority")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let contentCoverStore = ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
        let appContext = YamiboAppContext(
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            contentCoverStore: contentCoverStore
        )
        let target = FavoriteContentTarget(kind: .normalThread, threadID: "904")
        let persistedCoverURL = try XCTUnwrap(URL(string: "https://img.example.com/old-normal-cover.jpg"))
        let resolvedCoverURL = try XCTUnwrap(URL(string: "https://img.example.com/resolved-normal-cover.jpg"))
        var document = FavoriteLibraryDocument()
        document.addItem(try FavoriteItem(
            target: target,
            title: "普通主题",
            coverURL: persistedCoverURL,
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        try await contentCoverStore.setAutomaticCover(
            resolvedCoverURL,
            for: ContentCoverKey(targetType: .threadNormal, targetID: "904")
        )

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.cards.first?.coverURL, resolvedCoverURL)
        let persistedDocument = await localFavoriteLibraryStore.load()
        XCTAssertEqual(persistedDocument.items.first?.coverURL, persistedCoverURL)
    }

    func testLoadPrefersContentCoverStoreURLOverPersistedNovelThreadCoverURL() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-content-cover-novel-priority")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let contentCoverStore = ContentCoverStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "content-covers"
        )
        let appContext = YamiboAppContext(
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            contentCoverStore: contentCoverStore
        )
        let target = FavoriteContentTarget(kind: .novelThread, threadID: "905")
        let persistedCoverURL = try XCTUnwrap(URL(string: "https://img.example.com/old-novel-cover.jpg"))
        let resolvedCoverURL = try XCTUnwrap(URL(string: "https://img.example.com/resolved-novel-cover.jpg"))
        var document = FavoriteLibraryDocument()
        document.addItem(try FavoriteItem(
            target: target,
            title: "小说主题",
            coverURL: persistedCoverURL,
            locations: [.category(document.defaultCategory.id)]
        ))
        try await localFavoriteLibraryStore.save(document)
        try await contentCoverStore.setAutomaticCover(
            resolvedCoverURL,
            for: ContentCoverKey(targetType: .threadNovel, targetID: "905")
        )

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.cards.first?.coverURL, resolvedCoverURL)
        let persistedDocument = await localFavoriteLibraryStore.load()
        XCTAssertEqual(persistedDocument.items.first?.coverURL, persistedCoverURL)
    }

    func testNormalThreadOpenTargetUsesNativeReaderWithoutMutatingFavoriteUpdatedAt() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-view-model")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let appContext = YamiboAppContext(
            localFavoriteLibraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore
        )
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_000)
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: FavoriteContentTarget(kind: .normalThread, threadID: "901"),
            title: "普通主题",
            locations: [.category(document.defaultCategory.id)],
            updatedAt: originalUpdatedAt
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()
        let opened = await viewModel.openTarget(for: item)

        guard case let .nativeThread(openedURL, title)? = opened else {
            return XCTFail("Expected a native thread open target")
        }
        XCTAssertEqual(openedURL, YamiboRoute.threadByID(tid: "901", page: 1, authorID: nil, reverse: false).url)
        XCTAssertEqual(title, "普通主题")
        let storedItem = await localFavoriteLibraryStore.load().items.first { $0.id == item.id }
        XCTAssertEqual(storedItem?.updatedAt, originalUpdatedAt)
    }

    func testSearchModeSubmitsCountsAndExitClearsSelection() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-search-mode")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let appContext = YamiboAppContext(localFavoriteLibraryStore: localFavoriteLibraryStore)
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

        let viewModel = LocalFavoritesViewModel(appContext: appContext)
        await viewModel.load()

        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget, secondTarget])
        viewModel.toggleFavoriteSelection(id: firstTarget.id)
        XCTAssertTrue(viewModel.isSelectionMode)
        viewModel.enterSearchMode()
        XCTAssertTrue(viewModel.isSearchMode)
        XCTAssertFalse(viewModel.isSelectionMode)
        viewModel.searchDraftText = " 命中 "
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget, secondTarget])

        viewModel.submitSearch()
        XCTAssertEqual(viewModel.searchText, "命中")
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget])
        XCTAssertEqual(viewModel.categoryEntryCounts[document.defaultCategory.id], 2)
        XCTAssertEqual(viewModel.categoryEntryCounts[secondCategory.id], 1)

        viewModel.toggleFavoriteSelection(id: firstTarget.id)
        XCTAssertFalse(viewModel.isSearchMode)
        XCTAssertTrue(viewModel.isSelectionMode)
        viewModel.exitSearchMode()
        XCTAssertFalse(viewModel.isSearchMode)
        XCTAssertEqual(viewModel.searchDraftText, "")
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertFalse(viewModel.isSelectionMode)
        XCTAssertEqual(viewModel.selectedEntryCount, 0)
        XCTAssertEqual(viewModel.cards.map(\.item.target), [firstTarget, secondTarget])
    }

    private func waitForRemoteSyncStatus(
        _ status: FavoriteRemoteSyncTaskStatus,
        in viewModel: LocalFavoritesViewModel
    ) async throws {
        for _ in 0..<100 {
            if viewModel.remoteSyncSnapshot?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for remote sync status \(status)")
    }

    private func waitForFavoriteUpdateStatus(
        _ status: FavoriteUpdateRunStatus,
        in viewModel: LocalFavoritesViewModel
    ) async throws {
        for _ in 0..<100 {
            if viewModel.favoriteUpdateSnapshot?.status == status {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for favorite update status \(status)")
    }

    private func makeFavoriteUpdateThreadPage(
        threadID: String,
        postID: String,
        title: String,
        replyCount: Int,
        pageCount: Int
    ) throws -> ForumThreadPage {
        let url = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(threadID)"))
        return ForumThreadPage(
            thread: ThreadIdentity(tid: threadID, canonicalURL: url, fid: "50"),
            title: title,
            posts: [
                ForumThreadPost(
                    postID: postID,
                    author: BlogReaderUser(uid: "u1", name: "作者"),
                    contentHTML: "<p>正文</p>",
                    contentText: "正文"
                )
            ],
            pageNavigation: ForumPageNavigation(currentPage: 1, totalPages: pageCount),
            totalReplies: replyCount,
            forumID: "50",
            forumName: "测试板块"
        )
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
