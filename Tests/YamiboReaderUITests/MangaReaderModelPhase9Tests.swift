import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@MainActor
final class MangaReaderModelPhase9Tests: XCTestCase {
    func testUpdateCurrentPageSchedulesAdjacentPrefetchNearEnd() async throws {
        let document700 = try makePhase9Document(tid: "700", pageCount: 10)
        let document701 = try makePhase9Document(tid: "701", pageCount: 1)
        let fixture = try await makePhase9Fixture(
            document: document700,
            extraDocuments: [document701],
            directory: makePhase9Directory(tids: ["700", "701"])
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 8)

        try await waitForPhase9 {
            guard case let .loaded(loaded) = fixture.model.presentation.state else { return false }
            return loaded.pages.map(\.id).contains("701#0")
        }

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.currentPage?.id, "700#8")
        XCTAssertEqual(loaded.viewportPlacement?.targetPageIndex, 8)
    }

    func testPreviousPrefetchKeepsCurrentPageIdentityAndStablePlacement() async throws {
        let document699 = try makePhase9Document(tid: "699", pageCount: 3)
        let document700 = try makePhase9Document(tid: "700", pageCount: 4)
        let fixture = try await makePhase9Fixture(
            document: document700,
            initialPage: 1,
            extraDocuments: [document699],
            directory: makePhase9Directory(tids: ["699", "700"])
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 1)

        try await waitForPhase9 {
            guard case let .loaded(loaded) = fixture.model.presentation.state else { return false }
            return loaded.pages.first?.id == "699#0"
        }

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.currentPage?.id, "700#1")
        XCTAssertEqual(loaded.currentPageIndex, 4)
        XCTAssertEqual(loaded.viewportPlacement?.targetPageIndex, 4)
        XCTAssertEqual(loaded.viewportPlacement?.animated, false)
    }

    func testDirectoryJumpSupersedesInFlightAdjacentPrefetch() async throws {
        let document700 = try makePhase9Document(tid: "700", pageCount: 10)
        let document701 = try makePhase9Document(tid: "701", pageCount: 1)
        let document702 = try makePhase9Document(tid: "702", pageCount: 1)
        let delayedURL = document701.chapterURL
        let loader = Phase9DocumentLoader(
            documents: [document700, document701, document702],
            delayedURLs: [delayedURL]
        )
        let directory = makePhase9Directory(tids: ["700", "701", "702"])
        let fixture = try await makePhase9Fixture(
            document: document700,
            loader: loader,
            directory: directory
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 8)
        try await waitForPhase9 {
            await loader.hasRequested(delayedURL)
        }

        await fixture.model.jumpToChapter(directory.chapters[2])
        await loader.release(delayedURL)
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.pages.map(\.id), ["702#0"])
        XCTAssertEqual(loaded.currentPage?.id, "702#0")
        XCTAssertFalse(loaded.pages.map(\.tid).contains("701"))
    }

    func testAdjacentPrefetchDoesNotDuplicateUnchangedProgress() async throws {
        let progressAdapter = RecordingPhase9ProgressAdapter()
        let document700 = try makePhase9Document(tid: "700", pageCount: 10)
        let document701 = try makePhase9Document(tid: "701", pageCount: 1)
        let fixture = try await makePhase9Fixture(
            document: document700,
            extraDocuments: [document701],
            directory: makePhase9Directory(tids: ["700", "701"]),
            progressSync: ProgressSyncModule(adapter: progressAdapter, debounceNanoseconds: 0)
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 8)

        try await waitForPhase9 {
            await progressAdapter.savedPositions.count == 1
        }

        try await waitForPhase9 {
            guard case let .loaded(loaded) = fixture.model.presentation.state else { return false }
            return loaded.pages.map(\.id).contains("701#0")
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        let savedPositions = await progressAdapter.savedPositions
        XCTAssertEqual(savedPositions.map(\.chapterURL), [document700.chapterURL])
        XCTAssertEqual(savedPositions.map(\.pageIndex), [8])
    }

    func testDirectoryJumpQueuesNewProgress() async throws {
        let progressAdapter = RecordingPhase9ProgressAdapter()
        let document700 = try makePhase9Document(tid: "700", pageCount: 1)
        let document701 = try makePhase9Document(tid: "701", pageCount: 1)
        let directory = makePhase9Directory(tids: ["700", "701"])
        let fixture = try await makePhase9Fixture(
            document: document700,
            extraDocuments: [document701],
            directory: directory,
            progressSync: ProgressSyncModule(adapter: progressAdapter, debounceNanoseconds: 0)
        )

        await fixture.model.prepare()
        await fixture.model.jumpToChapter(directory.chapters[1])

        try await waitForPhase9 {
            await progressAdapter.savedPositions.contains {
                $0.chapterURL == document701.chapterURL && $0.pageIndex == 0
            }
        }

        guard case let .manga(.native(savedContext))? = await fixture.resumeRouteStore.load() else {
            XCTFail("Expected saved manga resume route")
            return
        }
        XCTAssertEqual(savedContext.chapterURL, document701.chapterURL)
        XCTAssertEqual(savedContext.initialPage, 0)
    }

    func testAdjacentPrefetchFailureDoesNotSetDirectoryPanelError() async throws {
        let document700 = try makePhase9Document(tid: "700", pageCount: 10)
        let missingURL = makePhase9URL(tid: "701")
        let loader = Phase9DocumentLoader(documents: [document700])
        let fixture = try await makePhase9Fixture(
            document: document700,
            loader: loader,
            directory: makePhase9Directory(tids: ["700", "701"])
        )

        await fixture.model.prepare()
        fixture.model.updateCurrentPage(globalIndex: 8)
        try await waitForPhase9 {
            await loader.hasRequested(missingURL)
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        guard case let .loaded(loaded) = fixture.model.presentation.state else {
            XCTFail("Expected loaded presentation")
            return
        }
        XCTAssertEqual(loaded.pages.map(\.id), (0..<10).map { "700#\($0)" })
        XCTAssertNil(loaded.directoryPanel.errorMessage)
    }
}

private struct Phase9Fixture {
    let model: MangaReaderModel
    let resumeRouteStore: ReaderResumeRouteStore
}

@MainActor
private func makePhase9Fixture(
    document: MangaChapterDocument,
    initialPage: Int = 0,
    extraDocuments: [MangaChapterDocument] = [],
    loader: Phase9DocumentLoader? = nil,
    directory: MangaDirectory,
    progressSync: ProgressSyncModule? = nil
) async throws -> Phase9Fixture {
    let keyPrefix = UUID().uuidString
    let settingsStore = SettingsStore(key: "\(keyPrefix).settings")
    try await settingsStore.save(AppSettings())
    let resumeRouteStore = ReaderResumeRouteStore(key: "\(keyPrefix).resume")
    let favoriteStore = FavoriteStore(key: "\(keyPrefix).favorites")
    let appContext = YamiboAppContext(
        sessionStore: SessionStore(key: "\(keyPrefix).session"),
        settingsStore: settingsStore,
        readerResumeRouteStore: resumeRouteStore,
        favoriteStore: favoriteStore
    )
    let resolvedLoader = loader ?? Phase9DocumentLoader(documents: [document] + extraDocuments)
    let resolvedProgressSync = progressSync ?? ProgressSyncModule(
        adapter: FavoriteLibraryProgressSyncAdapter(favoriteStore: favoriteStore),
        debounceNanoseconds: 0
    )
    #if os(iOS)
    let dependencies = MangaReaderModelDependencies(
        makeDocumentLoader: { resolvedLoader },
        makeDirectoryRepository: { Phase9DirectoryRepository(seed: makePhase9Seed(document: document)) },
        makeDirectoryStore: { Phase9DirectoryStore(directories: [directory]) },
        makeDirectorySearchCooldownState: { MangaDirectorySearchCooldownState() },
        makeImageDataLoader: { Phase9ImageDataLoader() },
        progressSync: resolvedProgressSync
    )
    #else
    let dependencies = MangaReaderModelDependencies(
        makeDocumentLoader: { resolvedLoader },
        makeDirectoryRepository: { Phase9DirectoryRepository(seed: makePhase9Seed(document: document)) },
        makeDirectoryStore: { Phase9DirectoryStore(directories: [directory]) },
        makeDirectorySearchCooldownState: { MangaDirectorySearchCooldownState() },
        progressSync: resolvedProgressSync
    )
    #endif
    let originalURL = makePhase9URL(tid: "700")
    let context = MangaLaunchContext(
        originalThreadURL: originalURL,
        chapterURL: document.chapterURL,
        displayTitle: "测试漫画",
        source: .forum,
        initialPage: initialPage,
        directoryName: directory.cleanBookName
    )
    return Phase9Fixture(
        model: MangaReaderModel(context: context, appContext: appContext, dependencies: dependencies),
        resumeRouteStore: resumeRouteStore
    )
}

private actor Phase9DocumentLoader: MangaChapterDocumentLoading {
    private let documents: [URL: MangaChapterDocument]
    private let delayedURLs: Set<URL>
    private var continuations: [URL: CheckedContinuation<Void, Never>] = [:]
    private var requestedURLs: [URL] = []

    init(documents: [MangaChapterDocument], delayedURLs: Set<URL> = []) {
        self.documents = Dictionary(uniqueKeysWithValues: documents.map { ($0.chapterURL, $0) })
        self.delayedURLs = delayedURLs
    }

    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        requestedURLs.append(url)
        if delayedURLs.contains(url) {
            await withCheckedContinuation { continuation in
                continuations[url] = continuation
            }
        }
        guard let document = documents[url] else {
            throw YamiboError.unreadableBody
        }
        return document
    }

    func hasRequested(_ url: URL) -> Bool {
        requestedURLs.contains(url)
    }

    func release(_ url: URL) {
        continuations.removeValue(forKey: url)?.resume()
    }
}

private actor Phase9DirectoryRepository: MangaDirectoryRepository {
    private let seed: MangaDirectorySeed

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

private actor Phase9DirectoryStore: MangaDirectoryPersisting {
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
private actor Phase9ImageDataLoader: MangaImageDataLoading {
    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        Data()
    }
}
#endif

private actor RecordingPhase9ProgressAdapter: ProgressSyncAdapter {
    private var saved: [MangaProgressReadingPosition] = []

    var savedPositions: [MangaProgressReadingPosition] {
        saved
    }

    func saveNovelReadingPosition(_ position: NovelReadingPosition) async throws {}

    func saveMangaReadingPosition(_ position: MangaProgressReadingPosition) async throws {
        saved.append(position)
    }
}

private func makePhase9Directory(tids: [String]) -> MangaDirectory {
    MangaDirectory(
        cleanBookName: "Resolved Directory",
        strategy: .links,
        sourceKey: "Resolved Directory",
        chapters: tids.map { makePhase9Chapter(tid: $0) }
    )
}

private func makePhase9Chapter(tid: String) -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: "第\(tid)话",
        chapterNumber: Double(tid) ?? 0,
        url: makePhase9URL(tid: tid)
    )
}

private func makePhase9Seed(document: MangaChapterDocument) -> MangaDirectorySeed {
    MangaDirectorySeed(
        currentChapter: MangaChapter(
            tid: document.tid,
            rawTitle: document.chapterTitle,
            chapterNumber: MangaTitleCleaner.extractChapterNumber(document.chapterTitle),
            url: document.chapterURL
        ),
        cleanBookName: "Resolved Directory"
    )
}

private func makePhase9Document(tid: String, pageCount: Int) throws -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第\(tid)话",
        chapterURL: makePhase9URL(tid: tid),
        imageURLs: try (0..<pageCount).map { index in
            try XCTUnwrap(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
        }
    )
}

private func makePhase9URL(tid: String) -> URL {
    URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
}

@MainActor
private func waitForPhase9(
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
