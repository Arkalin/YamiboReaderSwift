import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MangaReaderModelSettingsProgressTests: XCTestCase {
    func testPrepareExposesPersistedMangaSettingsWithClampedBrightness() async throws {
        let fixture = try await makeFixture(
            appSettings: AppSettings(
                manga: MangaReaderSettings(
                    readingMode: .paged,
                    brightness: 2.0,
                    zoomEnabled: false,
                    showsTwoPagesInLandscapeOnPad: true,
                    directorySortOrder: .descending
                )
            )
        )

        await fixture.model.prepare()

        XCTAssertEqual(fixture.model.presentation.settings.readingMode, .paged)
        XCTAssertEqual(fixture.model.presentation.settings.brightness, 1.5)
        XCTAssertFalse(fixture.model.presentation.settings.zoomEnabled)
        XCTAssertTrue(fixture.model.presentation.settings.showsTwoPagesInLandscapeOnPad)
        XCTAssertEqual(fixture.model.presentation.settings.directorySortOrder, .descending)
    }

    func testApplySettingsUpdatesPresentationAndPersistsOnlyMangaSettings() async throws {
        let initialReaderSettings = ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical)
        let initialApplePencilSettings = ApplePencilPageTurnSettings(
            isEnabled: true,
            behavior: .doubleTapNextSqueezePrevious
        )
        let fixture = try await makeFixture(
            appSettings: AppSettings(
                reader: initialReaderSettings,
                manga: MangaReaderSettings(brightness: 0.8),
                applePencilPageTurn: initialApplePencilSettings,
                usesDataSaverMode: true
            )
        )

        let updatedMangaSettings = MangaReaderSettings(
            readingMode: .vertical,
            brightness: -1,
            zoomEnabled: false,
            showsTwoPagesInLandscapeOnPad: true,
            directorySortOrder: .descending
        )
        fixture.model.applySettings(updatedMangaSettings)

        XCTAssertEqual(fixture.model.presentation.settings.brightness, 0.25)
        XCTAssertEqual(fixture.model.presentation.settings.readingMode, .vertical)
        XCTAssertFalse(fixture.model.presentation.settings.zoomEnabled)

        try await waitFor {
            let loaded = await fixture.settingsStore.load()
            return loaded.manga.brightness == 0.25 &&
                loaded.manga.readingMode == .vertical &&
                loaded.manga.zoomEnabled == false
        }

        let loaded = await fixture.settingsStore.load()
        XCTAssertEqual(loaded.reader, initialReaderSettings)
        XCTAssertEqual(loaded.applePencilPageTurn, initialApplePencilSettings)
        XCTAssertTrue(loaded.usesDataSaverMode)
    }

    func testInitialSamePageViewportReportQueuesMangaProgressAndSavesResumeRoute() async throws {
        let progressAdapter = RecordingMangaProgressAdapter()
        let fixture = try await makeFixture(
            initialPage: 1,
            progressSync: ProgressSyncModule(adapter: progressAdapter, debounceNanoseconds: 0)
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 1)

        try await waitFor {
            await progressAdapter.savedPositions.count == 1
        }

        let savedPositions = await progressAdapter.savedPositions
        let savedPosition = try XCTUnwrap(savedPositions.first)
        XCTAssertEqual(savedPosition.threadURL, fixture.originalURL)
        XCTAssertEqual(savedPosition.chapterURL, fixture.chapterURL)
        XCTAssertEqual(savedPosition.chapterTitle, "第1话")
        XCTAssertEqual(savedPosition.pageIndex, 1)

        guard case let .manga(.native(savedContext))? = await fixture.resumeRouteStore.load() else {
            XCTFail("Expected saved manga resume route")
            return
        }
        XCTAssertEqual(savedContext.source, .resume)
        XCTAssertEqual(savedContext.chapterURL, fixture.chapterURL)
        XCTAssertEqual(savedContext.initialPage, 1)
        XCTAssertEqual(savedContext.directoryName, "Resolved Directory")
    }

    func testRepeatedSamePageViewportReportsAreDedupedByProgressSync() async throws {
        let progressAdapter = RecordingMangaProgressAdapter()
        let fixture = try await makeFixture(
            initialPage: 1,
            progressSync: ProgressSyncModule(adapter: progressAdapter, debounceNanoseconds: 0)
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 1)
        try await waitFor {
            await progressAdapter.savedPositions.count == 1
        }

        fixture.model.updateCurrentPage(globalIndex: 1)
        try await Task.sleep(nanoseconds: 80_000_000)

        let savedCount = await progressAdapter.savedPositions.count
        XCTAssertEqual(savedCount, 1)
    }

    func testSaveProgressFlushesLatestPageIntoExistingFavoriteAndResumeRoute() async throws {
        let favoriteStore = FavoriteStore(key: "\(UUID().uuidString).favorites")
        let fixture = try await makeFixture(
            favoriteStore: favoriteStore,
            progressSync: ProgressSyncModule(
                adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: favoriteStore),
                debounceNanoseconds: 100_000_000
            )
        )
        try await favoriteStore.saveFavorites([
            Favorite(title: "收藏漫画", url: fixture.originalURL, type: .manga)
        ])

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 2)
        let route = await fixture.model.saveProgress()

        let favorite = await favoriteStore.favorite(for: fixture.originalURL)
        XCTAssertEqual(favorite?.lastMangaURL, fixture.chapterURL)
        XCTAssertEqual(favorite?.lastChapter, "第1话")
        XCTAssertEqual(favorite?.mangaPageIndex, 2)

        guard case let .native(savedContext) = route else {
            XCTFail("Expected native manga route")
            return
        }
        XCTAssertEqual(savedContext.source, .resume)
        XCTAssertEqual(savedContext.initialPage, 2)
        XCTAssertEqual(savedContext.directoryName, "Resolved Directory")
        let storedResumeRoute = await fixture.resumeRouteStore.load()
        XCTAssertEqual(storedResumeRoute, .manga(route))
    }

    func testSaveProgressDoesNotCreateMissingFavorite() async throws {
        let favoriteStore = FavoriteStore(key: "\(UUID().uuidString).favorites")
        let fixture = try await makeFixture(
            favoriteStore: favoriteStore,
            progressSync: ProgressSyncModule(
                adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: favoriteStore),
                debounceNanoseconds: 0
            )
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 2)
        _ = await fixture.model.saveProgress()

        let favorites = await favoriteStore.loadFavorites()
        XCTAssertTrue(favorites.isEmpty)
    }

    func testCurrentChapterCommentTargetUsesCurrentMangaPageProjection() async throws {
        let fixture = try await makeFixture()

        await fixture.model.prepare()

        let target = try XCTUnwrap(fixture.model.currentChapterCommentTarget)
        XCTAssertEqual(target.threadURL, fixture.chapterURL)
        XCTAssertEqual(target.view, 1)
        XCTAssertEqual(target.ownerPostID, "9001")
        XCTAssertEqual(target.title, "第1话")
    }

    func testNilMangaChapterCommentTargetShowsEmptyCommentsState() async throws {
        let fixture = try await makeFixture()

        await fixture.model.loadChapterComments(for: nil)

        guard case let .loaded(_, page) = fixture.model.chapterCommentsState else {
            XCTFail("Expected empty loaded comments state")
            return
        }
        XCTAssertTrue(page.comments.isEmpty)
        XCTAssertNil(page.nextView)
    }

    func testJumpToPagePublishesViewportPlacementForSharedScrubberCommit() async throws {
        let fixture = try await makeFixture()

        await fixture.model.prepare()
        await fixture.model.jumpToPage(globalIndex: 2)

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.currentPageIndex, 2)
        XCTAssertEqual(loaded.currentPage?.globalIndex, 2)
        XCTAssertEqual(loaded.viewportPlacement?.targetPageIndex, 2)
    }

    func testSaveProgressInLoadingStateDoesNotOverwriteExistingResumeRoute() async throws {
        let progressAdapter = RecordingMangaProgressAdapter()
        let fixture = try await makeFixture(
            progressSync: ProgressSyncModule(adapter: progressAdapter, debounceNanoseconds: 0)
        )
        let existingRoute = ReaderResumeRoute.manga(
            .native(
                MangaLaunchContext(
                    originalThreadURL: fixture.originalURL,
                    chapterURL: fixture.chapterURL,
                    displayTitle: "Existing",
                    source: .resume,
                    initialPage: 6,
                    directoryName: "Existing Directory"
                )
            )
        )
        try await fixture.resumeRouteStore.save(existingRoute)

        let route = await fixture.model.saveProgress()

        XCTAssertEqual(route, .native(fixture.context))
        let storedResumeRoute = await fixture.resumeRouteStore.load()
        let savedPositions = await progressAdapter.savedPositions
        XCTAssertEqual(storedResumeRoute, existingRoute)
        XCTAssertTrue(savedPositions.isEmpty)
    }

    func testDismissMangaOpeningForumPreservesSuppliedLatestSuspendedRoute() throws {
        let appModel = YamiboAppModel(
            appContext: YamiboAppContext(
                sessionStore: SessionStore(key: "\(UUID().uuidString).session"),
                settingsStore: SettingsStore(key: "\(UUID().uuidString).settings"),
                readerResumeRouteStore: ReaderResumeRouteStore(key: "\(UUID().uuidString).resume"),
                favoriteStore: FavoriteStore(key: "\(UUID().uuidString).favorites")
            )
        )
        let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))
        let oldChapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=701&mobile=2"))
        let latestChapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=702&mobile=2"))
        let originalContext = MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: oldChapterURL,
            displayTitle: "测试漫画",
            source: .forum,
            initialPage: 0,
            directoryName: "Old Directory"
        )
        let latestRoute = MangaPresentationRoute.native(
            MangaLaunchContext(
                originalThreadURL: originalURL,
                chapterURL: latestChapterURL,
                displayTitle: "测试漫画",
                source: .resume,
                initialPage: 4,
                directoryName: "Resolved Directory"
            )
        )

        appModel.presentManga(originalContext)
        appModel.dismissManga(openThreadInForum: originalURL, suspendedRoute: latestRoute)

        XCTAssertNil(appModel.activeMangaRoute)
        XCTAssertEqual(appModel.suspendedMangaRoute, latestRoute)
        XCTAssertEqual(appModel.selectedTab, .forum)
    }

    func testReaderViewAppliesBrightnessOverlayFromPresentationSettings() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        XCTAssertTrue(source.contains("brightnessOverlay(brightness: presentation.settings.brightness)"))
        XCTAssertTrue(source.contains("Color.black.opacity(min(0.7, abs(delta)))"))
        XCTAssertTrue(source.contains("Color.white.opacity(min(0.18, delta * 0.18))"))
    }

    func testReaderStillUsesVerticalViewportWithoutPagedOrZoomImplementation() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        XCTAssertTrue(source.contains("MangaVerticalCollectionViewport("))
        XCTAssertFalse(source.contains("MangaPaged"))
        XCTAssertFalse(source.contains("zoomEnabled:"))
    }
}

private struct MangaReaderModelSettingsProgressFixture {
    let model: MangaReaderModel
    let context: MangaLaunchContext
    let originalURL: URL
    let chapterURL: URL
    let settingsStore: SettingsStore
    let resumeRouteStore: ReaderResumeRouteStore
}

@MainActor
private func makeFixture(
    initialPage: Int = 0,
    appSettings: AppSettings = AppSettings(),
    favoriteStore: FavoriteStore = FavoriteStore(key: "\(UUID().uuidString).favorites"),
    progressSync: ProgressSyncModule? = nil
) async throws -> MangaReaderModelSettingsProgressFixture {
    let keyPrefix = UUID().uuidString
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    let resumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).resume")
    try await settingsStore.save(appSettings)

    let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))
    let chapterURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=701&mobile=2"))
    let context = MangaLaunchContext(
        originalThreadURL: originalURL,
        chapterURL: chapterURL,
        displayTitle: "测试漫画",
        source: .forum,
        initialPage: initialPage,
        directoryName: nil
    )
    let document = MangaChapterDocument(
        tid: "701",
        ownerPostID: "9001",
        chapterTitle: "第1话",
        chapterURL: chapterURL,
        imageURLs: [
            try XCTUnwrap(URL(string: "https://img.example.com/701-0.jpg")),
            try XCTUnwrap(URL(string: "https://img.example.com/701-1.jpg")),
            try XCTUnwrap(URL(string: "https://img.example.com/701-2.jpg"))
        ]
    )
    let repository = StubMangaDirectoryRepository(
        seed: MangaDirectorySeed(
            currentChapter: MangaChapter(
                tid: "701",
                rawTitle: "第1话",
                chapterNumber: 1,
                url: chapterURL
            ),
            cleanBookName: "Resolved Directory",
            firstPostID: "9001"
        )
    )
    let store = StubMangaDirectoryStore()
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(key: "\(keyPrefix).session"),
        settingsStore: settingsStore,
        readerResumeRouteStore: resumeRouteStore,
        favoriteStore: favoriteStore
    )
    let resolvedProgressSync = progressSync ?? ProgressSyncModule(
        adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: favoriteStore),
        debounceNanoseconds: 0
    )
    #if os(iOS)
    let dependencies = MangaReaderModelDependencies(
        makeDocumentLoader: { StubMangaChapterDocumentLoader(document: document) },
        makeDirectoryRepository: { repository },
        makeDirectoryStore: { store },
        makeImageDataLoader: { StubMangaImageDataLoader() },
        progressSync: resolvedProgressSync
    )
    #else
    let dependencies = MangaReaderModelDependencies(
        makeDocumentLoader: { StubMangaChapterDocumentLoader(document: document) },
        makeDirectoryRepository: { repository },
        makeDirectoryStore: { store },
        progressSync: resolvedProgressSync
    )
    #endif
    let model = MangaReaderModel(
        context: context,
        appContext: appContext,
        dependencies: dependencies
    )

    return MangaReaderModelSettingsProgressFixture(
        model: model,
        context: context,
        originalURL: originalURL,
        chapterURL: chapterURL,
        settingsStore: settingsStore,
        resumeRouteStore: resumeRouteStore
    )
}

private actor StubMangaChapterDocumentLoader: MangaChapterDocumentLoading {
    let document: MangaChapterDocument

    init(document: MangaChapterDocument) {
        self.document = document
    }

    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        document
    }
}

private actor StubMangaDirectoryRepository: MangaDirectoryRepository {
    let seed: MangaDirectorySeed

    init(seed: MangaDirectorySeed) {
        self.seed = seed
    }

    func loadDirectorySeed(for chapterURL: URL) async throws -> MangaDirectorySeed {
        seed
    }

    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter] {
        []
    }

    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter] {
        []
    }
}

private actor StubMangaDirectoryStore: MangaDirectoryPersisting {
    private var directories: [String: MangaDirectory] = [:]

    func directory(named name: String) async throws -> MangaDirectory? {
        directories[name]
    }

    func directory(containingTID tid: String) async throws -> MangaDirectory? {
        directories.values.first { directory in
            directory.chapters.contains { $0.tid == tid }
        }
    }

    func saveDirectory(_ directory: MangaDirectory) async throws {
        directories[directory.cleanBookName] = directory
    }

    func deleteDirectory(named name: String) async throws {
        directories.removeValue(forKey: name)
    }
}

#if os(iOS)
private actor StubMangaImageDataLoader: MangaImageDataLoading {
    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        Data()
    }
}
#endif

private actor RecordingMangaProgressAdapter: ProgressSyncAdapter {
    private var saved: [MangaProgressReadingPosition] = []

    var savedPositions: [MangaProgressReadingPosition] {
        saved
    }

    func saveNovelReadingPosition(_ position: NovelReadingPosition) async throws {}

    func saveMangaReadingPosition(_ position: MangaProgressReadingPosition) async throws {
        saved.append(position)
    }
}

@MainActor
private func waitFor(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 20_000_000,
    predicate: @escaping @MainActor @Sendable () async -> Bool
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

private func sourceFile(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}
