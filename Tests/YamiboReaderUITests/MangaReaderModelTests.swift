import Foundation
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class MangaReaderModelTests: XCTestCase {
    func testForumMangaProgressDoesNotCreateFavorite() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                )
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.pages.count, 2)
            XCTAssertEqual(model.viewportRequest?.targetIndex, 0)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "700#0")
            model.updateCurrentPage(1)
        }
        await model.saveProgress()

        let favorite = await modelTestFavoriteStore?.favorite(for: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!)
        XCTAssertNil(favorite)
    }

    func testForumMangaProgressUpdatesExistingFavorite() async throws {
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                )
            ],
            initialFavorites: [
                Favorite(title: "测试漫画", url: originalURL, type: .manga)
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.pages.count, 2)
            model.updateCurrentPage(1)
        }
        await model.saveProgress()

        let favorite = await modelTestFavoriteStore?.favorite(for: originalURL)
        XCTAssertEqual(favorite?.type, .manga)
        XCTAssertEqual(favorite?.lastPage, 1)
        XCTAssertEqual(favorite?.lastChapter, "第1话")
    }

    func testPrefetchesNextChapterAndJumpsBetweenChapters() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 3
                )
            ]
        )

        await MainActor.run {
            model.updateCurrentPage(1)
        }
        try await waitFor {
            await MainActor.run {
                model.pages.count == 5
            }
        }

        await model.jumpToAdjacentChapter(1)
        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第2话")
            XCTAssertEqual(model.currentPageIndex, 2)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
            XCTAssertTrue(model.hasPreviousChapter)
            XCTAssertFalse(model.hasNextChapter)
        }
    }

    func testJumpingToLoadedChapterStillEmitsViewportRequest() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 2
                )
            ]
        )

        await MainActor.run {
            model.updateCurrentPage(1)
        }
        try await waitFor {
            await MainActor.run { model.pages.count == 4 }
        }

        let initialRevision = await MainActor.run { model.viewportRequest?.revision }
        guard let targetChapter = await MainActor.run(body: { model.currentDirectory?.chapters.last }) else {
            XCTFail("Expected a second chapter")
            return
        }

        await model.jumpToChapter(targetChapter)

        await MainActor.run {
            XCTAssertEqual(model.currentPageIndex, 2)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
            XCTAssertNotEqual(model.viewportRequest?.revision, initialRevision)
            XCTAssertNil(model.navigationRequest)
        }
    }

    func testJumpFailureFallsBackToWeb() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 1
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 0
                )
            ],
            chapterProbe: { context in
                .fallback(
                    reason: .noImages,
                    suggestedWebContext: MangaWebContext(
                        currentURL: context.chapterURL,
                        originalThreadURL: context.originalThreadURL,
                        source: context.source
                    )
                )
            }
        )

        await model.jumpToAdjacentChapter(1)
        await MainActor.run {
            guard case let .fallbackWeb(context)? = model.navigationRequest else {
                return XCTFail("Expected fallback web navigation")
            }
            XCTAssertEqual(
                context.currentURL.absoluteString,
                "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=701"
            )
            XCTAssertFalse(context.autoOpenNative)
            XCTAssertFalse(model.isTransitioningChapter)
        }
    }

    func testAdjacentJumpCanRecoverViaProbeWhenDirectLoadFails() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 1
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 0
                )
            ],
            chapterProbe: { context in
                .success(
                    MangaProbePayload(
                        images: [
                            URL(string: "https://img.example.com/701-probe-0.jpg")!,
                            URL(string: "https://img.example.com/701-probe-1.jpg")!
                        ],
                        title: "第2话",
                        html: "<html></html>",
                        sectionName: "中文百合漫画区"
                    )
                )
            }
        )

        await model.jumpToAdjacentChapter(1)

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第2话")
            XCTAssertEqual(model.currentPage?.chapterURL.absoluteString, "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=701")
            XCTAssertEqual(model.pages.count, 3)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
            XCTAssertNil(model.navigationRequest)
            XCTAssertFalse(model.isTransitioningChapter)
        }
    }

    func testFavoritesViewModelResolvesUnknownFavoriteToManga() async throws {
        let keyPrefix = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MangaReaderTestURLProtocol.handler = { request in
            let html = makeMangaHTML(tid: "800", title: "第1话", links: [], imageCount: 1)
            return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
        }
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "未知收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=800&mobile=2")!
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            session: session
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        let target = await viewModel.resolveOpenTarget(for: favorite)
        switch target {
        case .manga:
            let stored = await favoriteStore.favorite(for: favorite.url)
            XCTAssertEqual(stored?.type, .manga)
        default:
            XCTFail("Expected manga target")
        }
    }

    func testFavoritesViewModelCanSetDisplayNameByFavoriteID() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "原标题",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=820&mobile=2")!
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }

        await viewModel.setDisplayName("自定义名称", forFavoriteID: favorite.id, originalTitle: favorite.title)

        await MainActor.run {
            XCTAssertEqual(viewModel.favorites.first?.displayName, "自定义名称")
            XCTAssertEqual(viewModel.favorites.first?.resolvedDisplayTitle, "自定义名称")
        }
    }

    func testFavoritesViewModelCanClearDisplayNameByFavoriteID() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "原标题",
            displayName: "自定义名称",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=821&mobile=2")!
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }

        await viewModel.setDisplayName("   ", forFavoriteID: favorite.id, originalTitle: favorite.title)

        await MainActor.run {
            XCTAssertNil(viewModel.favorites.first?.displayName)
            XCTAssertEqual(viewModel.favorites.first?.resolvedDisplayTitle, "原标题")
        }
    }

    func testFavoritesViewModelCanToggleHiddenState() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "隐藏测试收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=822&mobile=2")!
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        await viewModel.setHidden(true, for: favorite)

        await MainActor.run {
            XCTAssertEqual(viewModel.favorites.first?.isHidden, true)
            XCTAssertNil(viewModel.errorMessage)
        }

        guard let hiddenFavorite = await MainActor.run(body: { viewModel.favorites.first }) else {
            return XCTFail("Expected hidden favorite to remain in view model state")
        }
        await viewModel.setHidden(false, for: hiddenFavorite)

        await MainActor.run {
            XCTAssertEqual(viewModel.favorites.first?.isHidden, false)
            XCTAssertNil(viewModel.errorMessage)
        }
    }

    func testFavoritesViewModelCanReorderFavorites() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let first = Favorite(
            title: "第一项",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=826&mobile=2")!
        )
        let second = Favorite(
            title: "第二项",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=827&mobile=2")!
        )
        let third = Favorite(
            title: "第三项",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=828&mobile=2")!
        )
        try await favoriteStore.saveFavorites([first, second, third])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        await viewModel.reorderFavorites(
            visibleIDs: [first.id, second.id, third.id],
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )

        await MainActor.run {
            XCTAssertEqual(viewModel.favorites.map(\.id), [second.id, third.id, first.id])
            XCTAssertNil(viewModel.errorMessage)
        }

        let persisted = await favoriteStore.loadFavorites()
        XCTAssertEqual(persisted.map(\.id), [second.id, third.id, first.id])
    }

    func testFavoritesViewModelReorderAvailabilityRequiresManualSortAndEmptySearch() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }

        await MainActor.run {
            XCTAssertTrue(viewModel.canReorderFavorites(sortOrder: .manual, searchText: ""))
            XCTAssertFalse(viewModel.canReorderFavorites(sortOrder: .title, searchText: ""))
            XCTAssertFalse(viewModel.canReorderFavorites(sortOrder: .progress, searchText: ""))
            XCTAssertFalse(viewModel.canReorderFavorites(sortOrder: .recentRead, searchText: ""))
            XCTAssertFalse(viewModel.canReorderFavorites(sortOrder: .manual, searchText: "百合"))
            XCTAssertFalse(viewModel.canReorderFavorites(sortOrder: .manual, searchText: "  test  "))

            XCTAssertTrue(viewModel.canReorderEntries(scope: .root, filter: .all, sortOrder: .manual, searchText: "", isSelecting: false))
            XCTAssertTrue(viewModel.canReorderEntries(scope: .root, filter: .novel, sortOrder: .manual, searchText: "", isSelecting: false))
            XCTAssertTrue(viewModel.canReorderEntries(scope: .root, filter: .manga, sortOrder: .manual, searchText: "", isSelecting: false))
            XCTAssertTrue(viewModel.canReorderEntries(scope: .root, filter: .other, sortOrder: .manual, searchText: "", isSelecting: false))
            XCTAssertFalse(viewModel.canReorderEntries(scope: .root, filter: .novel, sortOrder: .manual, searchText: "", isSelecting: true))
            XCTAssertFalse(viewModel.canReorderEntries(scope: .root, filter: .novel, sortOrder: .title, searchText: "", isSelecting: false))
            XCTAssertFalse(viewModel.canReorderEntries(scope: .root, filter: .novel, sortOrder: .progress, searchText: "", isSelecting: false))
            XCTAssertFalse(viewModel.canReorderEntries(scope: .root, filter: .novel, sortOrder: .recentRead, searchText: "", isSelecting: false))
            XCTAssertFalse(viewModel.canReorderEntries(scope: .root, filter: .novel, sortOrder: .manual, searchText: "百合", isSelecting: false))
        }
    }

    func testFilteredFavoritesRespectsShowsHiddenFlag() {
        let visible = Favorite(
            title: "可见收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=823&mobile=2")!
        )
        let hidden = Favorite(
            title: "隐藏收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=824&mobile=2")!,
            isHidden: true
        )

        let hiddenOff = makeFilteredFavorites(
            from: [visible, hidden],
            showsHidden: false,
            filter: .all,
            sortOrder: .manual,
            searchText: ""
        )
        XCTAssertEqual(hiddenOff.map(\.id), [visible.id])

        let hiddenOn = makeFilteredFavorites(
            from: [visible, hidden],
            showsHidden: true,
            filter: .all,
            sortOrder: .manual,
            searchText: ""
        )
        XCTAssertEqual(hiddenOn.map(\.id), [visible.id, hidden.id])
        XCTAssertEqual(hiddenOn.last?.isHidden, true)
    }

    func testRootEntriesShowCollectionsAlongsideFavoritesInManualOrder() {
        let rootFavorite = Favorite(
            title: "根页收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=860&mobile=2")!,
            manualOrder: 1
        )
        let collectionFavorite = Favorite(
            title: "合集内收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=861&mobile=2")!,
            parentCollectionID: "collection-1",
            manualOrder: 0
        )
        let collection = FavoriteCollection(id: "collection-1", name: "合集A", manualOrder: 0)

        let entries = makeFavoriteListEntries(
            scope: .root,
            favorites: [rootFavorite, collectionFavorite],
            collections: [collection],
            showsHidden: false,
            filter: .all,
            sortOrder: .manual,
            searchText: ""
        )

        XCTAssertEqual(entries.map(\.id), ["collection:collection-1", "favorite:\(rootFavorite.id)"])
    }

    func testSplitAlternatingColumnsDistributesRootEntriesLeftRightLeftRight() {
        let entries = [
            "collection:1",
            "favorite:1",
            "collection:2",
            "favorite:2",
            "favorite:3"
        ]

        let columns = splitAlternatingColumns(entries)

        XCTAssertEqual(columns.left, ["collection:1", "collection:2", "favorite:3"])
        XCTAssertEqual(columns.right, ["favorite:1", "favorite:2"])
    }

    func testSplitAlternatingColumnsDistributesCollectionFavoritesLeftRightLeftRight() {
        let favoriteIDs = ["favorite:1", "favorite:2", "favorite:3", "favorite:4"]

        let columns = splitAlternatingColumns(favoriteIDs)

        XCTAssertEqual(columns.left, ["favorite:1", "favorite:3"])
        XCTAssertEqual(columns.right, ["favorite:2", "favorite:4"])
    }

    func testReorderedItemsAfterDropMovesLeftColumnEntryAfterRightColumnEntry() {
        let entries = ["collection:1", "favorite:1", "collection:2", "favorite:2", "favorite:3"]

        let reordered = reorderedItemsAfterDrop(
            entries,
            draggedItem: "collection:2",
            targetItem: "favorite:2",
            position: .after
        )

        XCTAssertEqual(reordered, ["collection:1", "favorite:1", "favorite:2", "collection:2", "favorite:3"])
    }

    func testReorderedItemsAfterDropMovesRightColumnEntryBackIntoLeftColumnOrder() {
        let entries = ["collection:1", "favorite:1", "collection:2", "favorite:2", "favorite:3", "favorite:4"]

        let reordered = reorderedItemsAfterDrop(
            entries,
            draggedItem: "favorite:4",
            targetItem: "collection:2",
            position: .before
        )

        XCTAssertEqual(reordered, ["collection:1", "favorite:1", "favorite:4", "collection:2", "favorite:2", "favorite:3"])
    }

    func testReorderedItemsAfterDroppingAtRightColumnBottomAppendsToGlobalOrder() {
        let entries = ["collection:1", "favorite:1", "collection:2", "favorite:2", "favorite:3"]

        let reordered = reorderedItemsAfterDroppingAtColumnBottom(
            entries,
            draggedItem: "collection:1",
            column: .right
        )

        XCTAssertEqual(reordered, ["favorite:1", "collection:2", "favorite:2", "collection:1", "favorite:3"])
    }

    func testReorderedItemsAfterDroppingAtLeftColumnBottomSupportsCollectionScopeFavoritesOnly() {
        let entries = ["favorite:1", "favorite:2", "favorite:3", "favorite:4"]

        let reordered = reorderedItemsAfterDroppingAtColumnBottom(
            entries,
            draggedItem: "favorite:2",
            column: .left
        )

        XCTAssertEqual(reordered, ["favorite:1", "favorite:3", "favorite:2", "favorite:4"])
    }

    func testMoveStepsTransformMixedRootEntriesToAlternatingReorderedOrder() {
        let original = ["collection:1", "favorite:1", "collection:2", "favorite:2", "favorite:3"]
        let target = ["collection:2", "favorite:1", "collection:1", "favorite:2", "favorite:3"]

        let moves = makeVisibleOrderMovesToTransform(from: original, to: target)

        XCTAssertFalse(moves.isEmpty)
        XCTAssertEqual(applyingVisibleOrderMoves(original, moves: moves), target)
    }

    func testRootTypeFilterShowsCollectionsWithMatchingFavorites() {
        let novelFavorite = Favorite(
            title: "小说收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=862&mobile=2")!,
            type: .novel,
            manualOrder: 2
        )
        let collectionNovelFavorite = Favorite(
            title: "合集内小说",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=863&mobile=2")!,
            type: .novel,
            parentCollectionID: "collection-2"
        )
        let collectionMangaFavorite = Favorite(
            title: "合集内漫画",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=864&mobile=2")!,
            type: .manga,
            parentCollectionID: "collection-3"
        )
        let novelCollection = FavoriteCollection(id: "collection-2", name: "小说合集", manualOrder: 0)
        let mangaCollection = FavoriteCollection(id: "collection-3", name: "漫画合集", manualOrder: 1)

        let entries = makeFavoriteListEntries(
            scope: .root,
            favorites: [novelFavorite, collectionNovelFavorite, collectionMangaFavorite],
            collections: [novelCollection, mangaCollection],
            showsHidden: false,
            filter: .novel,
            sortOrder: .manual,
            searchText: ""
        )

        XCTAssertEqual(entries.map(\.id), ["collection:collection-2", "favorite:\(novelFavorite.id)"])
    }

    func testRootTypeFilterCollectionSummaryCountsMatchingFavoritesOnly() {
        let collection = FavoriteCollection(id: "collection-5", name: "混合合集", manualOrder: 0)
        let novelFavorite = Favorite(
            title: "合集内小说",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=866&mobile=2")!,
            type: .novel,
            parentCollectionID: collection.id
        )
        let mangaFavorite = Favorite(
            title: "合集内漫画",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=867&mobile=2")!,
            type: .manga,
            parentCollectionID: collection.id
        )

        let summary = makeFavoriteCollectionSummary(
            for: collection,
            favorites: [novelFavorite, mangaFavorite],
            scope: .root,
            showsHidden: false,
            filter: .novel,
            searchText: ""
        )

        XCTAssertEqual(summary, FavoriteCollectionSummary(itemCount: 1, hiddenCount: 0))
    }

    func testRootAllSearchMatchesCollectionFavoriteTitles() {
        let collectionFavorite = Favorite(
            title: "会被搜索命中的收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=865&mobile=2")!,
            parentCollectionID: "collection-4"
        )
        let collection = FavoriteCollection(id: "collection-4", name: "普通合集名", manualOrder: 0)

        let entries = makeFavoriteListEntries(
            scope: .root,
            favorites: [collectionFavorite],
            collections: [collection],
            showsHidden: false,
            filter: .all,
            sortOrder: .manual,
            searchText: "搜索命中"
        )

        XCTAssertEqual(entries.map(\.id), ["collection:collection-4"])
    }

    func testRootHiddenCollectionsRespectShowsHiddenFlag() {
        let visibleCollection = FavoriteCollection(id: "collection-6", name: "可见合集", manualOrder: 0)
        let hiddenCollection = FavoriteCollection(id: "collection-7", name: "隐藏合集", manualOrder: 1, isHidden: true)

        let hiddenOff = makeFavoriteListEntries(
            scope: .root,
            favorites: [],
            collections: [visibleCollection, hiddenCollection],
            showsHidden: false,
            filter: .all,
            sortOrder: .manual,
            searchText: ""
        )
        XCTAssertEqual(hiddenOff.map(\.id), ["collection:collection-6"])

        let hiddenOn = makeFavoriteListEntries(
            scope: .root,
            favorites: [],
            collections: [visibleCollection, hiddenCollection],
            showsHidden: true,
            filter: .all,
            sortOrder: .manual,
            searchText: ""
        )
        XCTAssertEqual(hiddenOn.map(\.id), ["collection:collection-6", "collection:collection-7"])
    }

    func testFilteredFavoritesSortsByRecentReadDescendingWithUnreadLast() {
        let oldReadAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newReadAt = Date(timeIntervalSince1970: 1_700_000_500)
        let unread = Favorite(
            title: "未读",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=870&mobile=2")!,
            manualOrder: 0
        )
        let older = Favorite(
            title: "较早阅读",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=871&mobile=2")!,
            manualOrder: 1,
            lastReadAt: oldReadAt
        )
        let newer = Favorite(
            title: "最近阅读",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=872&mobile=2")!,
            manualOrder: 2,
            lastReadAt: newReadAt
        )

        let sorted = makeFilteredFavorites(
            from: [unread, older, newer],
            showsHidden: false,
            filter: .all,
            sortOrder: .recentRead,
            searchText: ""
        )

        XCTAssertEqual(sorted.map(\.id), [newer.id, older.id, unread.id])
    }

    func testRootEntriesSortCollectionsByMostRecentChildRead() {
        let oldReadAt = Date(timeIntervalSince1970: 1_700_000_000)
        let newReadAt = Date(timeIntervalSince1970: 1_700_000_500)
        let rootFavorite = Favorite(
            title: "根页收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=873&mobile=2")!,
            manualOrder: 0,
            lastReadAt: oldReadAt
        )
        let collectionFavorite = Favorite(
            title: "合集最近阅读",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=874&mobile=2")!,
            parentCollectionID: "collection-8",
            manualOrder: 0,
            lastReadAt: newReadAt
        )
        let unreadCollectionFavorite = Favorite(
            title: "未阅读合集收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=875&mobile=2")!,
            parentCollectionID: "collection-9"
        )
        let recentCollection = FavoriteCollection(id: "collection-8", name: "最近合集", manualOrder: 1)
        let unreadCollection = FavoriteCollection(id: "collection-9", name: "未读合集", manualOrder: 2)

        let entries = makeFavoriteListEntries(
            scope: .root,
            favorites: [rootFavorite, collectionFavorite, unreadCollectionFavorite],
            collections: [recentCollection, unreadCollection],
            showsHidden: false,
            filter: .all,
            sortOrder: .recentRead,
            searchText: ""
        )

        XCTAssertEqual(entries.map(\.id), ["collection:collection-8", "favorite:\(rootFavorite.id)", "collection:collection-9"])
    }

    func testFavoriteSelectionActionStateMatchesRootAndCollectionRules() {
        let rootFavoritesOnly = makeFavoriteSelectionActionState(
            scope: .root,
            selectedFavoriteCount: 2,
            selectedCollectionCount: 0
        )
        XCTAssertEqual(rootFavoritesOnly, FavoriteSelectionActionState(canCreateCollection: true, canMove: true, canDelete: true))

        let rootMixed = makeFavoriteSelectionActionState(
            scope: .root,
            selectedFavoriteCount: 1,
            selectedCollectionCount: 1
        )
        XCTAssertEqual(rootMixed, FavoriteSelectionActionState(canCreateCollection: false, canMove: false, canDelete: true))

        let collectionScope = makeFavoriteSelectionActionState(
            scope: .collection(FavoriteCollection(id: "collection-3", name: "合集C", manualOrder: 0)),
            selectedFavoriteCount: 1,
            selectedCollectionCount: 0
        )
        XCTAssertEqual(collectionScope, FavoriteSelectionActionState(canCreateCollection: false, canMove: true, canDelete: true))
    }

    func testFavoriteAccentAppearanceUsesStoredTypeColors() {
        let appearance = FavoriteAppearanceSettings(
            collection: .purple,
            novel: .red,
            manga: .green,
            other: .purple
        )

        XCTAssertEqual(favoriteAccentAppearanceColor(for: .novel, appearance: appearance), .red)
        XCTAssertEqual(favoriteAccentAppearanceColor(for: .manga, appearance: appearance), .green)
        XCTAssertEqual(favoriteAccentAppearanceColor(for: .other, appearance: appearance), .purple)
        XCTAssertEqual(favoriteAccentAppearanceColor(for: .unknown, appearance: appearance), .gray)
    }

    func testFavoriteCollectionAccentAppearanceUsesStoredCollectionColor() {
        let appearance = FavoriteAppearanceSettings(collection: .purple)

        XCTAssertEqual(favoriteCollectionAccentAppearanceColor(for: appearance), .purple)
    }

    func testFavoritesViewModelUsesLatestStoredMangaProgressForResume() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=810&mobile=2")!
        let staleChapterURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=810&mobile=2")!
        let latestChapterURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=811&mobile=2")!
        let staleFavorite = Favorite(
            title: "漫画收藏",
            url: originalURL,
            lastPage: 1,
            type: .manga,
            lastMangaURL: staleChapterURL
        )
        try await favoriteStore.saveFavorites([staleFavorite])
        _ = try await favoriteStore.updateMangaProgress(
            for: originalURL,
            chapterURL: latestChapterURL,
            chapterTitle: "第2话",
            pageIndex: 6
        )

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        let target = await viewModel.openTarget(for: staleFavorite, mode: .resume)
        guard case let .manga(context) = target else {
            return XCTFail("Expected manga target")
        }

        XCTAssertEqual(context.chapterURL, latestChapterURL)
        XCTAssertEqual(context.initialPage, 6)
    }

    func testFavoritesViewModelMarksLastReadWhenOpeningFavorite() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "网页收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=812&mobile=2")!,
            type: .other
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        let target = await viewModel.openTarget(for: favorite, mode: .resume)
        guard case .web = target else {
            return XCTFail("Expected web target")
        }

        let updatedFavorite = await favoriteStore.favorite(id: favorite.id)
        XCTAssertNotNil(updatedFavorite?.lastReadAt)
        await MainActor.run {
            XCTAssertNotNil(viewModel.favorites.first?.lastReadAt)
        }
    }

    func testFavoritesViewModelResumesNovelWithoutInjectingLegacyPage() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "小说收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=813&mobile=2")!,
            lastPage: 126,
            lastView: 1,
            lastChapter: "第一章",
            authorID: "42",
            novelResumePoint: ReaderResumePoint(
                view: 1,
                chapterOrdinal: 0,
                chapterTitle: "第一章",
                segmentIndex: 3,
                segmentOffset: 127,
                segmentProgress: 0.25,
                authorID: "42",
                readingModeHint: .vertical
            ),
            type: .novel
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        let target = await viewModel.openTarget(for: favorite, mode: .resume)
        guard case let .reader(context) = target else {
            return XCTFail("Expected reader target")
        }

        XCTAssertNil(context.initialView)
        XCTAssertNil(context.initialPage)
        XCTAssertEqual(context.authorID, "42")
    }

    func testFavoritesViewModelStartsNovelFromFirstPage() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "小说收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=814&mobile=2")!,
            lastPage: 126,
            lastView: 3,
            type: .novel
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()

        let target = await viewModel.openTarget(for: favorite, mode: .start)
        guard case let .reader(context) = target else {
            return XCTFail("Expected reader target")
        }

        XCTAssertEqual(context.initialView, 1)
        XCTAssertEqual(context.initialPage, 0)
    }

    func testNovelFavoriteDetailLinesKeepDisplayProgressText() {
        let favorite = Favorite(
            title: "小说收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=815&mobile=2")!,
            lastPage: 126,
            lastView: 1,
            lastChapter: "第一章",
            novelResumePoint: ReaderResumePoint(
                view: 1,
                chapterOrdinal: 0,
                chapterTitle: "第一章",
                segmentIndex: 5,
                segmentOffset: 400,
                segmentProgress: 0.4,
                authorID: nil,
                readingModeHint: .vertical
            ),
            type: .novel
        )

        XCTAssertEqual(
            favoriteDetailLines(for: favorite),
            ["第一章", "读至第 127 页 · 网页第 1 页"]
        )
    }

    func testFavoritesViewModelDeletesFavoriteAfterRemoteDeleteSucceeds() async throws {
        let keyPrefix = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MangaReaderTestURLProtocol.handler = { request in
            let absolute = request.url?.absoluteString ?? ""
            if absolute.contains("mod=faq") {
                return httpResponse(url: request.url!, body: #"<html><input name="formhash" value="abc12345" /></html>"#)
            }
            if absolute.contains("ac=favorite"), request.httpMethod == "POST" {
                return httpResponse(url: request.url!, body: "<html><body>操作成功</body></html>")
            }
            return httpResponse(url: request.url!, body: "<html></html>", statusCode: 404)
        }

        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "待删除收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=850&mobile=2")!,
            remoteFavoriteID: "55"
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            session: session
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()
        await viewModel.deleteFavorite(favorite)

        await MainActor.run {
            XCTAssertTrue(viewModel.favorites.isEmpty)
            XCTAssertNil(viewModel.errorMessage)
            XCTAssertNil(viewModel.deletingFavoriteID)
        }
    }

    func testFavoritesViewModelRejectsDeleteWhenRemoteFavoriteIDMissing() async throws {
        let keyPrefix = UUID().uuidString
        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "无删除标识收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=851&mobile=2")!
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()
        await viewModel.deleteFavorite(favorite)

        await MainActor.run {
            XCTAssertEqual(viewModel.favorites.count, 1)
            XCTAssertEqual(viewModel.errorMessage, YamiboError.missingFavoriteDeleteID.localizedDescription)
            XCTAssertNil(viewModel.deletingFavoriteID)
        }
    }

    func testFavoritesViewModelKeepsFavoriteWhenRemoteDeleteFails() async throws {
        let keyPrefix = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MangaReaderTestURLProtocol.handler = { request in
            let absolute = request.url?.absoluteString ?? ""
            if absolute.contains("mod=faq") {
                return httpResponse(url: request.url!, body: #"<html><input name="formhash" value="abc12345" /></html>"#)
            }
            if absolute.contains("ac=favorite"), request.httpMethod == "POST" {
                return httpResponse(url: request.url!, body: "<html><body>操作失败</body></html>")
            }
            return httpResponse(url: request.url!, body: "<html></html>", statusCode: 404)
        }

        let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
        let favorite = Favorite(
            title: "删除失败收藏",
            url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=852&mobile=2")!,
            remoteFavoriteID: "88"
        )
        try await favoriteStore.saveFavorites([favorite])

        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: SettingsStore(key: "\(keyPrefix).settings"),
            favoriteStore: favoriteStore,
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            session: session
        )
        let viewModel = await MainActor.run {
            FavoritesViewModel(appContext: appContext, favoriteStore: favoriteStore)
        }
        await viewModel.loadCachedFavorites()
        await viewModel.deleteFavorite(favorite)

        await MainActor.run {
            XCTAssertEqual(viewModel.favorites.count, 1)
            XCTAssertEqual(viewModel.errorMessage, YamiboError.favoriteDeleteFailed.localizedDescription)
            XCTAssertNil(viewModel.deletingFavoriteID)
        }
    }

    func testPageChangesDebounceAndPersistLatestMangaProgress() async throws {
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 4
                )
            ],
            initialFavorites: [
                Favorite(title: "测试漫画", url: originalURL, type: .manga)
            ]
        )

        await MainActor.run {
            model.updateCurrentPage(1)
            model.updateCurrentPage(3)
        }

        try await waitFor {
            let favorite = await modelTestFavoriteStore?.favorite(for: originalURL)
            return favorite?.lastPage == 3
        }

        let favorite = await modelTestFavoriteStore?.favorite(for: originalURL)
        XCTAssertEqual(favorite?.lastPage, 3)
        XCTAssertEqual(favorite?.lastChapter, "第1话")
    }

    func testKeepsLoadedDocumentWindowBoundedToTenChapters() async throws {
        let chapterHTML = Dictionary(uniqueKeysWithValues: (700 ... 711).map { tid in
            let title = "第\(tid - 699)话"
            let links = (700 ... 711)
                .filter { $0 != tid }
                .map { ("\($0)", "第\($0 - 699)话") }
            return ("\(tid)", makeMangaHTML(tid: "\(tid)", title: title, links: links, imageCount: 1))
        })

        let model = try await makeMangaModel(chapterHTMLByTID: chapterHTML)

        for _ in 0 ..< 11 {
            await model.jumpToAdjacentChapter(1)
        }

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第12话")
            XCTAssertEqual(model.pages.count, 10)
            XCTAssertEqual(model.pages.first?.chapterTitle, "第3话")
            XCTAssertEqual(model.pages.last?.chapterTitle, "第12话")
        }
    }

    func testFarJumpEmitsReopenNativeNavigationRequest() async throws {
        let chapterHTML = Dictionary(uniqueKeysWithValues: (700 ... 705).map { tid in
            let title = "第\(tid - 699)话"
            let links = (700 ... 705)
                .filter { $0 != tid }
                .map { ("\($0)", "第\($0 - 699)话") }
            return ("\(tid)", makeMangaHTML(tid: "\(tid)", title: title, links: links, imageCount: 2))
        })

        let model = try await makeMangaModel(chapterHTMLByTID: chapterHTML)
        guard let targetChapter = await MainActor.run(body: { model.currentDirectory?.chapters.last }) else {
            XCTFail("Expected directory to be initialized")
            return
        }

        await model.jumpToChapter(targetChapter)

        await MainActor.run {
            guard case let .reopenNative(context)? = model.navigationRequest else {
                return XCTFail("Expected native reopen navigation")
            }
            XCTAssertEqual(context.chapterURL.absoluteString, "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=705")
            XCTAssertEqual(context.originalThreadURL.absoluteString, "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")
            XCTAssertEqual(model.currentPage?.chapterTitle, "第1话")
            XCTAssertEqual(model.pages.count, 2)
        }
    }

    func testRapidAdjacentJumpsCancelEarlierRequestAndKeepLatestResult() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 0
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话"), ("702", "第3话")],
                    imageCount: 1
                ),
                "702": makeMangaHTML(
                    tid: "702",
                    title: "第3话",
                    links: [("701", "第2话")],
                    imageCount: 0
                )
            ],
            chapterProbe: { context in
                let tid = MangaTitleCleaner.extractTid(from: context.chapterURL.absoluteString)
                if tid == "700" {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    return .success(
                        MangaProbePayload(
                            images: [URL(string: "https://img.example.com/700-probe-0.jpg")!],
                            title: "第1话",
                            html: "<html></html>",
                            sectionName: "中文百合漫画区"
                        )
                    )
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
                return .success(
                    MangaProbePayload(
                        images: [URL(string: "https://img.example.com/702-probe-0.jpg")!],
                        title: "第3话",
                        html: "<html></html>",
                        sectionName: "中文百合漫画区"
                    )
                )
            },
            initialTID: "701"
        )

        async let firstJump: Void = model.jumpToAdjacentChapter(-1)
        try? await Task.sleep(nanoseconds: 80_000_000)
        async let secondJump: Void = model.jumpToAdjacentChapter(1)
        _ = await (firstJump, secondJump)

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.chapterTitle, "第3话")
            XCTAssertEqual(model.currentPage?.tid, "702")
            XCTAssertFalse(model.pages.map(\.tid).contains("700"))
            XCTAssertNil(model.navigationRequest)
            XCTAssertFalse(model.isTransitioningChapter)
        }
    }

    func testPrefetchingPreviousChapterPreservesCurrentFocusAndStablePageIDs() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 2
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话"), ("702", "第3话")],
                    imageCount: 2
                ),
                "702": makeMangaHTML(
                    tid: "702",
                    title: "第3话",
                    links: [("701", "第2话")],
                    imageCount: 2
                )
            ],
            appSettings: AppSettings(
                manga: MangaReaderSettings(readingMode: .paged)
            ),
            initialTID: "701"
        )

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.id, "701#0")
            model.updateCurrentPage(0)
        }
        try await waitFor {
            await MainActor.run { Set(model.pages.map(\.tid)) == Set(["700", "701", "702"]) }
        }

        await MainActor.run {
            XCTAssertEqual(model.currentPage?.tid, "701")
            XCTAssertEqual(model.currentPage?.localIndex, 0)
            XCTAssertEqual(model.currentPage?.id, "701#0")
            XCTAssertTrue(model.pages.map(\.id).contains("700#0"))
            XCTAssertTrue(model.pages.map(\.id).contains("700#1"))
            XCTAssertTrue(model.pages.map(\.id).contains("701#0"))
            XCTAssertEqual(model.viewportRequest?.targetPageID, "701#0")
        }
    }

    func testTwoPageSpreadRequiresPadLandscapePagedModeAndSetting() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 3
                )
            ],
            appSettings: AppSettings(
                manga: MangaReaderSettings(
                    readingMode: .paged,
                    showsTwoPagesInLandscapeOnPad: true
                )
            )
        )

        await MainActor.run {
            XCTAssertFalse(model.isTwoPageSpreadActive)

            model.updatePagedPresentationEnvironment(
                isPad: false,
                viewportSize: CGSize(width: 844, height: 390)
            )
            XCTAssertFalse(model.isTwoPageSpreadActive)

            model.updatePagedPresentationEnvironment(
                isPad: true,
                viewportSize: CGSize(width: 390, height: 844)
            )
            XCTAssertFalse(model.isTwoPageSpreadActive)

            model.updatePagedPresentationEnvironment(
                isPad: true,
                viewportSize: CGSize(width: 844, height: 390)
            )
            XCTAssertTrue(model.isTwoPageSpreadActive)

            model.applySettings(
                MangaReaderSettings(
                    readingMode: .vertical,
                    showsTwoPagesInLandscapeOnPad: true
                )
            )
            XCTAssertFalse(model.isTwoPageSpreadActive)

            model.applySettings(
                MangaReaderSettings(
                    readingMode: .paged,
                    showsTwoPagesInLandscapeOnPad: false
                )
            )
            XCTAssertFalse(model.isTwoPageSpreadActive)
        }
    }

    func testTwoPageSpreadPairsOddPagesAndDoesNotCrossChapters() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 3
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 2
                )
            ],
            appSettings: AppSettings(
                manga: MangaReaderSettings(
                    readingMode: .paged,
                    showsTwoPagesInLandscapeOnPad: true
                )
            )
        )

        await model.jumpToAdjacentChapter(1)

        await MainActor.run {
            model.updatePagedPresentationEnvironment(
                isPad: true,
                viewportSize: CGSize(width: 844, height: 390)
            )

            XCTAssertEqual(
                model.pagedSpreads.map { "\($0.leftPageIndex)-\($0.rightPageIndex.map(String.init) ?? "nil")" },
                ["0-1", "2-nil", "3-4"]
            )
            XCTAssertEqual(model.pagedSpreads[1].chapterTitle, "第1话")
            XCTAssertEqual(model.pagedSpreads[2].chapterTitle, "第2话")
        }
    }

    func testTwoPageSpreadMapsPagingAndProgressToLeftPageAnchor() async throws {
        let originalURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 6
                )
            ],
            appSettings: AppSettings(
                manga: MangaReaderSettings(
                    readingMode: .paged,
                    showsTwoPagesInLandscapeOnPad: true
                )
            ),
            initialFavorites: [
                Favorite(title: "测试漫画", url: originalURL, type: .manga)
            ]
        )

        await MainActor.run {
            model.updatePagedPresentationEnvironment(
                isPad: true,
                viewportSize: CGSize(width: 844, height: 390)
            )
            XCTAssertEqual(
                model.pagedSpreads.map { "\($0.leftPageIndex)-\($0.rightPageIndex.map(String.init) ?? "nil")" },
                ["0-1", "2-3", "4-5"]
            )

            model.requestCurrentChapterPage(1, animated: false)
            XCTAssertEqual(model.currentPage?.localIndex, 0)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "700#0")

            model.requestCurrentChapterPage(5, animated: false)
            XCTAssertEqual(model.currentPage?.localIndex, 4)
            XCTAssertEqual(model.pagedSelectionIndex, 2)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "700#4")

            model.updateCurrentPage(3)
            XCTAssertEqual(model.currentPage?.localIndex, 2)

            model.updatePagedSelection(2)
            XCTAssertEqual(model.currentPage?.localIndex, 4)
        }

        await model.saveProgress()
        let favorite = await modelTestFavoriteStore?.favorite(for: originalURL)
        XCTAssertEqual(favorite?.lastPage, 4)
    }

    func testCurrentPagePrefetchesVisibleImageWindow() async throws {
        let observedRequests = RequestLog()
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 10
                )
            ],
            requestLog: observedRequests
        )

        await MainActor.run {
            model.updateCurrentPage(3)
        }
        try await waitFor {
            let imageRequests = await observedRequests.snapshot().filter {
                $0.host == "img.example.com" && $0.lastPathComponent.hasPrefix("700-")
            }
            return Set(imageRequests.map(\.absoluteString)).count == 10
        }

        let imageRequests = await observedRequests.snapshot()
            .filter { $0.host == "img.example.com" && $0.lastPathComponent.hasPrefix("700-") }
            .map(\.lastPathComponent)

        XCTAssertEqual(
            Set(imageRequests),
            Set((0 ... 9).map { "700-\($0).jpg" })
        )
    }

    func testDataSaverDisablesBackgroundImagePrefetch() async throws {
        let observedRequests = RequestLog()
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 10
                )
            ],
            appSettings: AppSettings(usesDataSaverMode: true),
            requestLog: observedRequests
        )

        await MainActor.run {
            model.updateCurrentPage(3)
        }
        try await Task.sleep(nanoseconds: 300_000_000)

        let imageRequests = await observedRequests.snapshot().filter { $0.host == "img.example.com" }
        XCTAssertTrue(imageRequests.isEmpty)
    }

    func testApplyDirectorySortOrderPersistsPreference() async throws {
        let keyPrefix = UUID().uuidString
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MangaReaderTestURLProtocol.handler = { request in
            let tid = MangaTitleCleaner.extractTid(from: request.url!.absoluteString) ?? "700"
            let html = makeMangaHTML(
                tid: tid,
                title: tid == "700" ? "第1话" : "第2话",
                links: [("700", "第1话"), ("701", "第2话")].filter { $0.0 != tid },
                imageCount: 1
            )
            return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
        }

        let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
        let appContext = YamiboAppContext(
            sessionStore: SessionStore(key: "\(keyPrefix).session"),
            settingsStore: settingsStore,
            favoriteStore: FavoriteStore(key: "\(keyPrefix).favorites"),
            readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaImageCacheStore: MangaImageCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
            session: session
        )

        let firstModel = await MainActor.run {
            MangaReaderModel(
                context: MangaLaunchContext(
                    originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    displayTitle: "测试漫画",
                    source: .forum
                ),
                appContext: appContext
            )
        }
        await firstModel.prepare()
        await MainActor.run {
            firstModel.applyDirectorySortOrder(MangaDirectorySortOrder.descending)
        }
        try await waitFor {
            let loaded = await settingsStore.load()
            return loaded.manga.directorySortOrder == .descending
        }

        let secondModel = await MainActor.run {
            MangaReaderModel(
                context: MangaLaunchContext(
                    originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
                    displayTitle: "测试漫画",
                    source: .forum
                ),
                appContext: appContext
            )
        }
        await secondModel.prepare()

        await MainActor.run {
            XCTAssertEqual(secondModel.settings.directorySortOrder, MangaDirectorySortOrder.descending)
            XCTAssertEqual(secondModel.sortedDirectoryChapters.first?.tid, "701")
        }
    }

    func testAutoTagUpdateShowsForceSearchShortcut() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 1,
                    tagIDs: ["31"]
                )
            ],
            requestHandler: { request in
                let url = request.url!.absoluteString
                guard url.contains("misc.php"), url.contains("id=31"), url.contains("page=1") else {
                    return nil
                }
                return httpResponse(
                    url: request.url!,
                    body: """
                    <table>
                      <tr>
                        <th><a href="thread-700-1-1.html">第1话</a></th>
                        <td class="by"></td>
                        <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-02</span></em></td>
                      </tr>
                      <tr>
                        <th><a href="thread-701-1-1.html">第2话</a></th>
                        <td class="by"></td>
                        <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-03</span></em></td>
                      </tr>
                    </table>
                    """
                )
            }
        )

        await MainActor.run {
            XCTAssertEqual(model.currentDirectory?.strategy, .tag)
            XCTAssertTrue(model.showsForceSearchShortcut)
            XCTAssertGreaterThanOrEqual(model.forceSearchShortcutRemaining, 4)
            XCTAssertEqual(model.directoryUpdateButtonTitle, "全局搜索 \(model.forceSearchShortcutRemaining)s")
            XCTAssertTrue(model.sortedDirectoryChapters.map(\.tid).contains("701"))
        }
    }

    func testForcedSearchStartsDirectoryCooldown() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 1,
                    tagIDs: ["31"]
                )
            ],
            requestHandler: { request in
                let url = request.url!.absoluteString
                if url.contains("misc.php"), url.contains("id=31"), url.contains("page=1") {
                    return httpResponse(
                        url: request.url!,
                        body: """
                        <table>
                          <tr>
                            <th><a href="thread-700-1-1.html">第1话</a></th>
                            <td class="by"></td>
                            <td class="by"><cite><a href="space-uid-77.html">作者甲</a></cite><em><span>2026-01-02</span></em></td>
                          </tr>
                        </table>
                        """
                    )
                }
                if url.contains("search.php") {
                    return httpResponse(
                        url: request.url!,
                        body: """
                        <li class="list">
                          <a href="forum.php?mod=viewthread&tid=700&mobile=2">第1话</a>
                          <h3><a href="space-uid-77.html">作者甲</a></h3>
                        </li>
                        """
                    )
                }
                return nil
            }
        )

        await MainActor.run {
            XCTAssertTrue(model.showsForceSearchShortcut)
        }
        await model.updateDirectoryFromPanel()

        await MainActor.run {
            XCTAssertFalse(model.showsForceSearchShortcut)
            XCTAssertGreaterThanOrEqual(model.directoryCooldownRemaining, 19)
            XCTAssertEqual(model.directoryUpdateButtonTitle, "\(model.directoryCooldownRemaining)s")
        }
    }

    func testSearchCooldownErrorStartsDirectoryCooldown() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 1
                )
            ],
            requestHandler: { request in
                let url = request.url!.absoluteString
                guard url.contains("search.php") else { return nil }
                return httpResponse(
                    url: request.url!,
                    body: """
                    <li class="list">
                      <a href="forum.php?mod=viewthread&tid=700&mobile=2">第1话</a>
                      <h3><a href="space-uid-77.html">作者甲</a></h3>
                    </li>
                    """
                )
            }
        )

        let strategy = await MainActor.run { model.currentDirectory?.strategy }
        XCTAssertEqual(strategy, .pendingSearch)

        await model.updateDirectory(isForcedSearch: true)
        await model.updateDirectory(isForcedSearch: true)

        await MainActor.run {
            XCTAssertEqual(model.errorMessage, YamiboError.searchCooldown(seconds: 20).errorDescription)
            XCTAssertGreaterThanOrEqual(model.directoryCooldownRemaining, 19)
        }
    }

    func testCurrentChapterRemainsStableWhenDirectorySortOrderChanges() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 1
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 1
                )
            ]
        )

        await model.jumpToAdjacentChapter(1)
        await MainActor.run {
            model.applyDirectorySortOrder(.descending)
            XCTAssertEqual(model.currentPage?.tid, "701")
            XCTAssertEqual(model.sortedDirectoryChapters.first?.tid, "701")
            XCTAssertEqual(model.sortedDirectoryChapters.last?.tid, "700")
        }
    }

    func testRequestCurrentChapterPageClampsOutOfBoundsValues() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [],
                    imageCount: 3
                )
            ]
        )

        await MainActor.run {
            model.requestCurrentChapterPage(-8, animated: false)
            XCTAssertEqual(model.currentPage?.localIndex, 0)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "700#0")

            model.requestCurrentChapterPage(99, animated: false)
            XCTAssertEqual(model.currentPage?.localIndex, 2)
            XCTAssertEqual(model.viewportRequest?.targetPageID, "700#2")
        }
    }

    func testProgressLabelsReflectCurrentAndPreviewPages() async throws {
        let model = try await makeMangaModel(
            chapterHTMLByTID: [
                "700": makeMangaHTML(
                    tid: "700",
                    title: "第1话",
                    links: [("701", "第2话")],
                    imageCount: 3
                ),
                "701": makeMangaHTML(
                    tid: "701",
                    title: "第2话",
                    links: [("700", "第1话")],
                    imageCount: 2
                )
            ]
        )

        await MainActor.run {
            XCTAssertEqual(model.progressLabelText, "1 / 3")
            XCTAssertEqual(model.previewLabel(forLocalIndex: -3), "第 1 / 3 页")
            XCTAssertEqual(model.previewLabel(forLocalIndex: 1), "第 2 / 3 页")
            XCTAssertEqual(model.previewLabel(forLocalIndex: 99), "第 3 / 3 页")
        }

        await model.jumpToAdjacentChapter(1)

        await MainActor.run {
            XCTAssertEqual(model.progressLabelText, "1 / 2")
            XCTAssertEqual(model.previewLabel(forLocalIndex: 99), "第 2 / 2 页")
        }
    }
}

private nonisolated(unsafe) var modelTestFavoriteStore: FavoriteStore?
private nonisolated(unsafe) var modelRequestLog: RequestLog?

private func makeMangaModel(
    chapterHTMLByTID: [String: String],
    appSettings: AppSettings = AppSettings(),
    initialFavorites: [Favorite] = [],
    requestLog: RequestLog? = nil,
    requestHandler: ((URLRequest) -> (Data, HTTPURLResponse)?)? = nil,
    chapterProbe: (@MainActor (MangaLaunchContext) async -> MangaProbeOutcome)? = nil,
    initialTID: String = "700",
    initialPage: Int = 0
) async throws -> MangaReaderModel {
    let keyPrefix = UUID().uuidString
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MangaReaderTestURLProtocol.self]
    let session = URLSession(configuration: configuration)
    modelRequestLog = requestLog
    MangaReaderTestURLProtocol.handler = { request in
        Task {
            await modelRequestLog?.record(request.url!)
        }
        if let requestHandler, let customResponse = requestHandler(request) {
            return customResponse
        }
        let url = request.url!.absoluteString
        if request.url?.host == "img.example.com" {
            return (Data([0x01, 0x02, 0x03]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!)
        }
        let tid = MangaTitleCleaner.extractTid(from: url) ?? "700"
        let html = chapterHTMLByTID[tid] ?? ""
        return (Data(html.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
    }

    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    try await settingsStore.save(appSettings)
    try await favoriteStore.saveFavorites(initialFavorites)
    modelTestFavoriteStore = favoriteStore
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(key: "\(keyPrefix).session"),
        settingsStore: settingsStore,
        favoriteStore: favoriteStore,
        readerCacheStore: ReaderCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
        mangaImageCacheStore: MangaImageCacheStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
        mangaDirectoryStore: MangaDirectoryStore(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)),
        session: session
    )
    let model = await MainActor.run {
        let initialURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(initialTID)&mobile=2")!
        return MangaReaderModel(
            context: MangaLaunchContext(
                originalThreadURL: initialURL,
                chapterURL: initialURL,
                displayTitle: "测试漫画",
                source: .forum,
                initialPage: initialPage
            ),
            appContext: appContext,
            chapterProbe: chapterProbe
        )
    }
    await model.prepare()
    return model
}

private func makeMangaHTML(
    tid: String,
    title: String,
    links: [(String, String)],
    imageCount: Int,
    tagIDs: [String] = []
) -> String {
    let linkHTML = links.map { tid, title in
        #"<a href="forum.php?mod=viewthread&tid=\#(tid)&mobile=2">\#(title)</a>"#
    }.joined(separator: "\n")
    let tagHTML = tagIDs.map { tagID in
        #"<a href="misc.php?mod=tag&id=\#(tagID)">tag-\#(tagID)</a>"#
    }.joined(separator: "\n")
    let imageHTML = (0 ..< imageCount).map { index in
        #"<img src="https://img.example.com/\#(tid)-\#(index).jpg" />"#
    }.joined(separator: "\n")
    return """
    <html>
      <head><title>\(title) - 中文百合漫画区 - 百合会</title></head>
      <body>
        <div class="header"><h2><a>中文百合漫画区</a></h2></div>
        <div class="message">
          \(tagHTML)
          \(linkHTML)
          \(imageHTML)
        </div>
      </body>
    </html>
    """
}

private func waitFor(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    predicate: @escaping () async -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
    XCTFail("Timed out waiting for condition")
}

private func httpResponse(url: URL, body: String, statusCode: Int = 200) -> (Data, HTTPURLResponse) {
    (
        Data(body.utf8),
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
    )
}

private final class MangaReaderTestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor RequestLog {
    private var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }

    func snapshot() -> [URL] {
        urls
    }
}
