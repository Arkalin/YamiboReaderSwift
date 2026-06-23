import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MangaReaderDirectoryPanelTests: XCTestCase {
    func testReaderViewWiresFullscreenControlsSheetAndViewportPlacement() throws {
        let source = try mangaReaderSourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        XCTAssertTrue(source.contains("MangaReaderFloatingControls("))
        XCTAssertTrue(source.contains("summary: mangaChromeSummary(from: model.presentation)"))
        XCTAssertTrue(source.contains("struct MangaReaderChromeSummary"))
        XCTAssertTrue(source.contains("MangaChapterDisplayFormatter.readerHeaderTitle("))
        XCTAssertTrue(source.contains("MangaReaderTopChrome("))
        XCTAssertTrue(source.contains("MangaReaderBottomPageSummary("))
        XCTAssertTrue(source.contains(".readerChromePanel(cornerRadius: 18, tint: readerChromePanelTint(for: colorScheme))"))
        XCTAssertTrue(source.contains("L10n.string(\"manga.preview_page\", currentIndex + 1, itemCount)"))
        XCTAssertTrue(source.contains("ReaderDirectoryProgressCapsule("))
        XCTAssertTrue(source.contains("systemName: \"text.bubble\""))
        XCTAssertTrue(source.contains("systemName: \"gearshape\""))
        XCTAssertTrue(source.contains("settingsTitle: L10n.string(\"settings.title\")"))
        XCTAssertTrue(source.contains("onShowSettings: {}"))
        XCTAssertTrue(source.contains("systemName: \"safari\""))
        XCTAssertTrue(source.contains("onOpenOriginalPost: onOpenOriginalPost"))
        XCTAssertTrue(source.contains("systemName: \"bookmark\""))
        XCTAssertTrue(source.contains("systemName: \"square.and.arrow.down\""))
        XCTAssertTrue(source.contains("ReaderVerticalProgressCapsule("))
        XCTAssertTrue(source.contains("ReaderChromeCapsuleButton("))
        XCTAssertTrue(source.contains("MangaReaderStaticActionControls("))
        XCTAssertTrue(source.contains("HStack(spacing: 0)"))
        XCTAssertTrue(source.contains("Spacer(minLength: layout.actionButtonSpacing)"))
        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity)"))
        XCTAssertTrue(source.contains("isEnabled: false"))
        XCTAssertTrue(source.contains("MangaDirectorySheet("))
        XCTAssertTrue(source.contains("MangaChapterCommentsSheet("))
        XCTAssertTrue(source.contains("viewportPlacement: loaded.viewportPlacement"))
        XCTAssertTrue(source.contains("await model.jumpToChapter(chapter)"))
        XCTAssertTrue(source.contains("onJumpToLocalPage: { targetIndex in"))
        XCTAssertTrue(source.contains("await model.jumpToPage(localIndex: targetIndex)"))
        XCTAssertTrue(source.contains("let itemCount = max(currentPage.chapterPageCount, 1)"))
        XCTAssertTrue(source.contains("let currentIndex = min(max(currentPage.localIndex, 0), itemCount - 1)"))
        XCTAssertTrue(source.contains("scrubTargetIndexes: Array(0 ..< itemCount)"))
        XCTAssertFalse(source.contains("await model.jumpToPage(globalIndex: targetIndex)"))
        XCTAssertFalse(source.contains("scrubTargetIndexes: pages.map(\\.globalIndex)"))
        XCTAssertTrue(source.contains("onDeleteChapters:"))
        XCTAssertTrue(source.contains("await model.deleteDirectoryChapters(tids: selectedTIDs)"))
        XCTAssertTrue(source.contains(".ignoresSafeArea()"))
        XCTAssertTrue(source.contains(".statusBar(hidden: true)"))
        XCTAssertTrue(source.contains("windowSafeAreaInsets"))
        XCTAssertFalse(source.contains("ToolbarItem(placement: .primaryAction)"))
        XCTAssertFalse(source.contains("systemName: \"list.bullet\""))
    }

    func testDirectorySheetIsPresentationDriven() throws {
        let source = try mangaReaderSourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Directory/MangaDirectorySheet.swift")

        XCTAssertTrue(source.contains("let panel: MangaDirectoryPanelPresentation"))
        XCTAssertTrue(source.contains("ForEach(chapters)"))
        XCTAssertTrue(source.contains("onSaveCorrection(trimmedDraft)"))
        XCTAssertTrue(source.contains("let onDeleteChapters: (Set<String>) -> Void"))
        XCTAssertTrue(source.contains("@State private var isSelecting = false"))
        XCTAssertTrue(source.contains("@State private var selectedChapterTIDs: Set<String> = []"))
        XCTAssertTrue(source.contains("L10n.string(\"common.invert_selection\")"))
        XCTAssertTrue(source.contains("L10n.string(\"common.done\")"))
        XCTAssertTrue(source.contains("MangaDirectorySelectionActionBar("))
        XCTAssertTrue(source.contains("MangaDirectorySelectionToolbarCapsule("))
        XCTAssertTrue(source.contains("ToolbarItem(placement: .bottomBar)"))
        XCTAssertTrue(source.contains("if #available(iOS 26, *)"))
        XCTAssertTrue(source.contains(".padding(.horizontal, 12)"))
        XCTAssertTrue(source.contains(".frame(width: 66)"))
        XCTAssertTrue(source.contains(".frame(height: 38, alignment: .center)"))
        XCTAssertTrue(source.contains(".disabled(!panel.isUpdateButtonEnabled || isSelecting)"))
        XCTAssertTrue(source.contains("L10n.string(\"manga.delete_current_chapter_failed\")"))
        XCTAssertTrue(source.contains("L10n.string(\"manga.delete_current_chapter_failed_message\")"))
        XCTAssertTrue(source.contains("selectedTIDs.contains(panel.currentChapterTID ?? \"\")"))
        XCTAssertTrue(source.contains("onDeleteChapters([chapter.tid])"))
        XCTAssertTrue(source.contains("private func beginSelection(_ chapter: MangaChapter)"))
        XCTAssertTrue(source.contains("selectedChapterTIDs.insert(chapter.tid)"))
        XCTAssertTrue(source.contains(".onLongPressGesture"))
        XCTAssertTrue(source.contains("DragGesture(minimumDistance: 12, coordinateSpace: .local)"))
        XCTAssertTrue(source.contains("@State private var swipeOffset: CGFloat = 0"))
        XCTAssertTrue(source.contains("transaction.disablesAnimations = true"))
        XCTAssertTrue(source.contains(".opacity(isDeleteActionVisible ? 1 : 0)"))
        XCTAssertTrue(source.contains(".allowsHitTesting(isDeleteActionVisible)"))
        XCTAssertTrue(source.contains("private var canDeleteFromSwipe: Bool {\n        !isCurrent && !isSelecting\n    }"))
        XCTAssertTrue(source.contains(".disabled(!canDeleteFromSwipe || !isDeleteActionVisible)"))
        XCTAssertTrue(source.contains("private var canDelete: Bool {\n        !selectedChapterTIDs.isEmpty\n    }"))
        XCTAssertTrue(source.contains(".sensoryFeedback(.selection, trigger: selectedChapterTIDs)"))
        XCTAssertFalse(source.contains("@ObservedObject var model"))
    }

    func testVerticalViewportAppliesExplicitPlacementWithoutAnimationPolicyInView() throws {
        let source = try mangaReaderSourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")

        XCTAssertTrue(source.contains("let viewportPlacement: MangaReaderViewportPlacement?"))
        XCTAssertTrue(source.contains("placement.revision != lastAppliedPlacementRevision"))
        XCTAssertTrue(source.contains("animated: placement.animated"))
    }

    func testVerticalViewportCoalescesCurrentPagePublishingDuringScroll() throws {
        let source = try mangaReaderSourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")

        XCTAssertTrue(source.contains("private var pendingReportedGlobalIndex: Int?"))
        XCTAssertTrue(source.contains("private var currentPagePublishDisplayLink: CADisplayLink?"))
        XCTAssertTrue(source.contains("currentPagePublishDisplayLink?.invalidate()"))
        XCTAssertTrue(source.contains("pendingReportedGlobalIndex = globalIndex"))
        XCTAssertTrue(source.contains("guard currentPagePublishDisplayLink == nil else { return }"))
        XCTAssertTrue(source.contains("selector: #selector(flushPendingCurrentPagePublish)"))
        XCTAssertTrue(source.contains("@objc private func flushPendingCurrentPagePublish(_ displayLink: CADisplayLink)"))
        XCTAssertTrue(source.contains("lastReportedGlobalIndex = globalIndex"))
        XCTAssertFalse(source.contains("lastReportedGlobalIndex = globalIndex\n            let onCurrentPageChange = parent.onCurrentPageChange"))
        XCTAssertFalse(source.contains("DispatchQueue.main.async"))
    }

    func testInitialTagDirectoryRefreshesAfterPrepareAndOffersForcedSearchShortcut() async throws {
        let dateProvider = ManualDateProvider(now: Date(timeIntervalSince1970: 10_000))
        let fixture = try await makeDirectoryPanelFixture(
            seed: MangaDirectorySeed(
                currentChapter: makeChapter(tid: "700", title: "第1话"),
                tagIDs: ["31"],
                cleanBookName: "测试漫画"
            ),
            tagChapters: [makeChapter(tid: "701", title: "第2话")],
            configuration: MangaDirectoryWorkflowConfiguration(now: { dateProvider.now })
        )

        await fixture.model.prepare()

        guard case let .loaded(initialLoaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(initialLoaded.pages.map(\.tid), ["700"])

        try await waitForDirectoryPanelUpdate {
            guard case let .loaded(loaded) = fixture.model.presentation.state else { return false }
            return loaded.directoryPanel.displayChapters.map(\.tid) == ["700", "701"]
        }

        guard case let .loaded(updatedLoaded) = fixture.model.presentation.state else {
            XCTFail("Expected updated loaded presentation")
            return
        }
        XCTAssertEqual(updatedLoaded.directoryPanel.updateButtonTitle, "全局搜索 5s")
        XCTAssertTrue(updatedLoaded.directoryPanel.shouldForceSearchOnUpdate)
        XCTAssertTrue(updatedLoaded.directoryPanel.isSearchMode)
    }

    func testDirectorySortOrderOnlyChangesPanelProjection() async throws {
        let directory = MangaDirectory(
            cleanBookName: "本地目录",
            strategy: .links,
            sourceKey: "本地目录",
            chapters: [
                makeChapter(tid: "700", title: "第1话"),
                makeChapter(tid: "701", title: "第2话")
            ]
        )
        let fixture = try await makeDirectoryPanelFixture(
            directoryName: "本地目录",
            storedDirectories: [directory],
            appSettings: AppSettings(manga: MangaReaderSettings(directorySortOrder: .descending))
        )

        await fixture.model.prepare()

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.directoryPanel.displayChapters.map(\.tid), ["701", "700"])
        XCTAssertEqual(loaded.currentPage?.tid, "700")
        XCTAssertEqual(loaded.readingPosition, MangaReadingPosition(tid: "700", localIndex: 0))
    }

    func testForcedSearchCooldownIsProjectedAsPanelState() async throws {
        let dateProvider = ManualDateProvider(now: Date(timeIntervalSince1970: 20_000))
        let directory = MangaDirectory(
            cleanBookName: "本地目录",
            strategy: .tag,
            sourceKey: "31",
            chapters: [makeChapter(tid: "700", title: "【作者】作品 第1话")]
        )
        let fixture = try await makeDirectoryPanelFixture(
            directoryName: "本地目录",
            storedDirectories: [directory],
            searchChapters: [makeChapter(tid: "702", title: "第3话")],
            configuration: MangaDirectoryWorkflowConfiguration(now: { dateProvider.now })
        )

        await fixture.model.prepare()
        await fixture.model.updateDirectory(isForcedSearch: true)

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.directoryPanel.updateButtonTitle, "20s")
        XCTAssertFalse(loaded.directoryPanel.isUpdateButtonEnabled)
        XCTAssertEqual(loaded.directoryPanel.displayChapters.map(\.tid), ["700", "702"])
    }

    func testForcedSearchCancelsDeferredAutomaticTagRefresh() async throws {
        let seed = MangaDirectorySeed(
            currentChapter: makeChapter(tid: "700", title: "第1话"),
            tagIDs: ["31"],
            cleanBookName: "测试漫画"
        )
        let repository = DelayedDirectoryPanelRepository(
            seed: seed,
            tagChapters: [makeChapter(tid: "701", title: "第2话")],
            searchChapters: [makeChapter(tid: "702", title: "第3话")]
        )
        let fixture = try await makeDirectoryPanelFixture(
            seed: seed,
            repository: repository
        )

        await fixture.model.prepare()
        try await waitForDirectoryPanelUpdate {
            await repository.hasStartedTagLoad()
        }
        await fixture.model.updateDirectory(isForcedSearch: true)
        try await Task.sleep(nanoseconds: 350_000_000)

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        let searchRequestCount = await repository.searchRequestCount()
        XCTAssertEqual(searchRequestCount, 1)
        XCTAssertEqual(loaded.directoryPanel.displayChapters.map(\.tid), ["700", "702"])
    }

    func testRenameDirectoryUpdatesPanelWithoutLeavingReaderLoadedState() async throws {
        let directory = MangaDirectory(
            cleanBookName: "旧标题",
            strategy: .searched,
            sourceKey: "旧标题",
            chapters: [makeChapter(tid: "700", title: "第1话")]
        )
        let fixture = try await makeDirectoryPanelFixture(
            directoryName: "旧标题",
            storedDirectories: [directory]
        )

        await fixture.model.prepare()
        await fixture.model.renameDirectory(cleanBookName: " 新标题 ", searchKeyword: " 作者 新标题 ")

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.directoryPanel.directoryTitle, "新标题")
        XCTAssertEqual(loaded.directoryTitle, "新标题")
        XCTAssertNil(loaded.directoryPanel.errorMessage)
    }

    func testDirectoryChapterJumpUsesDirectViewportPlacement() async throws {
        let document700 = try makeDocument(tid: "700", pageCount: 1)
        let document701 = try makeDocument(tid: "701", pageCount: 1)
        let directory = MangaDirectory(
            cleanBookName: "本地目录",
            strategy: .links,
            sourceKey: "本地目录",
            chapters: [
                makeChapter(tid: "700", title: "第1话"),
                makeChapter(tid: "701", title: "第2话")
            ]
        )
        let fixture = try await makeDirectoryPanelFixture(
            directoryName: "本地目录",
            document: document700,
            extraDocuments: [document701],
            storedDirectories: [directory]
        )

        await fixture.model.prepare()
        await fixture.model.jumpToChapter(directory.chapters[1])

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.currentPage?.tid, "701")
        XCTAssertEqual(loaded.viewportPlacement?.targetPageIndex, 1)
        XCTAssertEqual(loaded.viewportPlacement?.animated, false)
    }
}

private struct MangaReaderDirectoryPanelFixture {
    let model: MangaReaderModel
    let settingsStore: SettingsStore
}

@MainActor
private func makeDirectoryPanelFixture(
    directoryName: String? = nil,
    document: MangaChapterDocument? = nil,
    extraDocuments: [MangaChapterDocument] = [],
    seed: MangaDirectorySeed? = nil,
    repository: (any MangaDirectoryRepository)? = nil,
    storedDirectories: [MangaDirectory] = [],
    tagChapters: [MangaChapter] = [],
    searchChapters: [MangaChapter] = [],
    appSettings: AppSettings = AppSettings(),
    configuration: MangaDirectoryWorkflowConfiguration = MangaDirectoryWorkflowConfiguration()
) async throws -> MangaReaderDirectoryPanelFixture {
    let keyPrefix = UUID().uuidString
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    try await settingsStore.save(appSettings)

    let resolvedDocument = try document ?? makeDocument(tid: "700", pageCount: 1)
    let originalURL = try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2"))
    let context = MangaLaunchContext(
        originalThreadURL: originalURL,
        chapterURL: resolvedDocument.chapterURL,
        displayTitle: "测试漫画",
        source: .forum,
        directoryName: directoryName
    )
    let resolvedRepository = repository ?? DirectoryPanelRepository(
        seed: seed ?? MangaDirectorySeed(
            currentChapter: makeChapter(tid: resolvedDocument.tid, title: resolvedDocument.chapterTitle),
            cleanBookName: "测试漫画"
        ),
        tagChapters: tagChapters,
        searchChapters: searchChapters
    )
    let documents = Dictionary(
        uniqueKeysWithValues: ([resolvedDocument] + extraDocuments).map { ($0.chapterURL, $0) }
    )
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(key: "\(keyPrefix).session"),
        settingsStore: settingsStore,
        readerResumeRouteStore: ReaderResumeRouteStore(key: "\(keyPrefix).resume"),
        favoriteStore: FavoriteStore(key: "\(keyPrefix).favorites")
    )
    #if os(iOS)
    let dependencies = MangaReaderModelDependencies(
        makeDocumentLoader: { DirectoryPanelDocumentLoader(documents: documents) },
        makeDirectoryRepository: { resolvedRepository },
        makeDirectoryStore: { DirectoryPanelStore(directories: storedDirectories) },
        makeDirectorySearchCooldownState: { MangaDirectorySearchCooldownState() },
        directoryWorkflowConfiguration: configuration,
        makeImageDataLoader: { DirectoryPanelImageDataLoader() },
        progressSync: ProgressSyncModule(
            adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore),
            debounceNanoseconds: 0
        )
    )
    #else
    let dependencies = MangaReaderModelDependencies(
        makeDocumentLoader: { DirectoryPanelDocumentLoader(documents: documents) },
        makeDirectoryRepository: { resolvedRepository },
        makeDirectoryStore: { DirectoryPanelStore(directories: storedDirectories) },
        makeDirectorySearchCooldownState: { MangaDirectorySearchCooldownState() },
        directoryWorkflowConfiguration: configuration,
        progressSync: ProgressSyncModule(
            adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: appContext.favoriteStore),
            debounceNanoseconds: 0
        )
    )
    #endif
    return MangaReaderDirectoryPanelFixture(
        model: MangaReaderModel(context: context, appContext: appContext, dependencies: dependencies),
        settingsStore: settingsStore
    )
}

private actor DirectoryPanelDocumentLoader: MangaChapterDocumentLoading {
    private let documents: [URL: MangaChapterDocument]

    init(documents: [URL: MangaChapterDocument]) {
        self.documents = documents
    }

    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        guard let document = documents[url] else {
            throw YamiboError.unreadableBody
        }
        return document
    }
}

private actor DirectoryPanelRepository: MangaDirectoryRepository {
    private let seed: MangaDirectorySeed
    private let tagChapters: [MangaChapter]
    private let searchChapters: [MangaChapter]

    init(
        seed: MangaDirectorySeed,
        tagChapters: [MangaChapter],
        searchChapters: [MangaChapter]
    ) {
        self.seed = seed
        self.tagChapters = tagChapters
        self.searchChapters = searchChapters
    }

    func loadDirectorySeed(for chapterURL: URL) async throws -> MangaDirectorySeed {
        seed
    }

    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter] {
        tagChapters
    }

    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter] {
        searchChapters
    }
}

private actor DelayedDirectoryPanelRepository: MangaDirectoryRepository {
    private let seed: MangaDirectorySeed
    private let tagChapters: [MangaChapter]
    private let searchChapters: [MangaChapter]
    private var didStartTagLoad = false
    private var searchRequests = 0

    init(
        seed: MangaDirectorySeed,
        tagChapters: [MangaChapter],
        searchChapters: [MangaChapter]
    ) {
        self.seed = seed
        self.tagChapters = tagChapters
        self.searchChapters = searchChapters
    }

    func loadDirectorySeed(for chapterURL: URL) async throws -> MangaDirectorySeed {
        seed
    }

    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter] {
        didStartTagLoad = true
        try await Task.sleep(nanoseconds: 200_000_000)
        return tagChapters
    }

    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter] {
        searchRequests += 1
        return searchChapters
    }

    func hasStartedTagLoad() -> Bool {
        didStartTagLoad
    }

    func searchRequestCount() -> Int {
        searchRequests
    }
}

private actor DirectoryPanelStore: MangaDirectoryPersisting {
    private var directories: [String: MangaDirectory]

    init(directories: [MangaDirectory]) {
        self.directories = Dictionary(uniqueKeysWithValues: directories.map { ($0.cleanBookName, $0) })
    }

    func directory(named name: String) async throws -> MangaDirectory? {
        directories[name.trimmingCharacters(in: .whitespacesAndNewlines)]
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
        directories.removeValue(forKey: name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

#if os(iOS)
private actor DirectoryPanelImageDataLoader: MangaImageDataLoading {
    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        Data()
    }
}
#endif

private final class ManualDateProvider: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private func makeChapter(tid: String, title: String) -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: title,
        chapterNumber: MangaTitleCleaner.extractChapterNumber(title),
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
    )
}

private func makeDocument(tid: String, pageCount: Int) throws -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第1话",
        chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!,
        imageURLs: try (0..<pageCount).map { index in
            try XCTUnwrap(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
        }
    )
}

private func mangaReaderSourceFile(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

@MainActor
private func waitForDirectoryPanelUpdate(
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
