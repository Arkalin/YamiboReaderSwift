import Foundation
import Testing
@testable import YamiboReaderCore

@MainActor
@Suite("MangaReaderTests: Workflow")
struct MangaReaderTestsWorkflow {
    @Test func workflowStartsLoadingAndPublishesLoadedPresentation() async throws {
        let document = try makeWorkflowDocument(tid: "700", pageCount: 2)
        let seed = makeWorkflowSeed(currentTID: "700", tagIDs: ["12"])
        let loader = RecordingMangaChapterDocumentLoader(output: .document(document))
        let repository = RecordingMangaDirectoryRepository(output: .seed(seed))
        let store = RecordingMangaDirectoryStore()
        let context = try makeWorkflowContext(tid: "700", initialPage: 1)
        let workflow = MangaReaderWorkflow(
            context: context,
            documentLoader: loader,
            directoryRepository: repository,
            directoryStore: store
        )

        #expect(workflow.presentation == MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: "测试漫画"))
        ))

        let presentation = await workflow.prepare()

        guard case let .loaded(loaded) = presentation.state else {
            Issue.record("Expected loaded presentation")
            return
        }
        #expect(loaded.title == "测试漫画")
        #expect(loaded.directoryTitle == "测试漫画")
        #expect(loaded.pages.map(\.id) == ["700#0", "700#1"])
        #expect(loaded.currentPage?.id == "700#1")
        #expect(loaded.currentPageIndex == 1)
        #expect(loaded.readingPosition == MangaReadingPosition(tid: "700", localIndex: 1))
        #expect(await loader.loadedURLs == [context.chapterURL])
        #expect(await repository.seedURLs == [context.chapterURL])
        #expect(await store.savedDirectories.count == 1)
    }

    @Test func initialPageIsClampedThroughChapterWindow() async throws {
        let document = try makeWorkflowDocument(tid: "700", pageCount: 2)
        let seed = makeWorkflowSeed(currentTID: "700", tagIDs: ["12"])
        let presentation = await makeLoadedPresentation(
            context: try makeWorkflowContext(tid: "700", initialPage: 99),
            document: document,
            seed: seed
        )

        guard case let .loaded(loaded) = presentation.state else {
            Issue.record("Expected loaded presentation")
            return
        }
        #expect(loaded.currentPage?.id == "700#1")
        #expect(loaded.currentPageIndex == 1)
        #expect(loaded.readingPosition == MangaReadingPosition(tid: "700", localIndex: 1))
    }

    @Test func workflowMovesReadingPositionInMemoryByLoadedPageIndex() async throws {
        let document = try makeWorkflowDocument(tid: "700", pageCount: 3)
        let loader = RecordingMangaChapterDocumentLoader(output: .document(document))
        let repository = RecordingMangaDirectoryRepository(
            output: .seed(makeWorkflowSeed(currentTID: "700", tagIDs: ["12"]))
        )
        let store = RecordingMangaDirectoryStore()
        let workflow = MangaReaderWorkflow(
            context: try makeWorkflowContext(tid: "700", initialPage: 0),
            documentLoader: loader,
            directoryRepository: repository,
            directoryStore: store
        )

        _ = await workflow.prepare()
        let presentation = workflow.moveToLoadedPage(at: 2)

        guard case let .loaded(loaded) = presentation.state else {
            Issue.record("Expected loaded presentation")
            return
        }
        #expect(loaded.currentPage?.id == "700#2")
        #expect(loaded.currentPageIndex == 2)
        #expect(loaded.readingPosition == MangaReadingPosition(tid: "700", localIndex: 2))
        #expect(await store.savedDirectories.count == 1)
        #expect(await store.deletedNames.isEmpty)
    }

    @Test func workflowClampsMovedReadingPositionThroughChapterWindow() async throws {
        let document = try makeWorkflowDocument(tid: "700", pageCount: 2)
        let workflow = MangaReaderWorkflow(
            context: try makeWorkflowContext(tid: "700", initialPage: 0),
            documentLoader: RecordingMangaChapterDocumentLoader(output: .document(document)),
            directoryRepository: RecordingMangaDirectoryRepository(
                output: .seed(makeWorkflowSeed(currentTID: "700", tagIDs: ["12"]))
            ),
            directoryStore: RecordingMangaDirectoryStore()
        )

        _ = await workflow.prepare()
        guard case let .loaded(firstPage) = workflow.moveToLoadedPage(at: -10).state,
              case let .loaded(lastPage) = workflow.moveToLoadedPage(at: 99).state else {
            Issue.record("Expected loaded presentations")
            return
        }

        #expect(firstPage.currentPage?.id == "700#0")
        #expect(firstPage.currentPageIndex == 0)
        #expect(firstPage.readingPosition == MangaReadingPosition(tid: "700", localIndex: 0))
        #expect(lastPage.currentPage?.id == "700#1")
        #expect(lastPage.currentPageIndex == 1)
        #expect(lastPage.readingPosition == MangaReadingPosition(tid: "700", localIndex: 1))
    }

    @Test func existingDirectoryNameIsReusedWithoutSeedOrSave() async throws {
        let document = try makeWorkflowDocument(tid: "700", pageCount: 1)
        let existingDirectory = makeWorkflowDirectory(
            name: "本地目录",
            strategy: .searched,
            sourceKey: "local",
            tids: ["999"]
        )
        let loader = RecordingMangaChapterDocumentLoader(output: .document(document))
        let repository = RecordingMangaDirectoryRepository(
            output: .seed(makeWorkflowSeed(currentTID: "700", tagIDs: ["12"]))
        )
        let store = RecordingMangaDirectoryStore(directories: [existingDirectory])
        let context = try makeWorkflowContext(
            tid: "700",
            initialPage: 0,
            directoryName: " 本地目录 "
        )
        let workflow = MangaReaderWorkflow(
            context: context,
            documentLoader: loader,
            directoryRepository: repository,
            directoryStore: store
        )

        let presentation = await workflow.prepare()

        guard case let .loaded(loaded) = presentation.state else {
            Issue.record("Expected loaded presentation")
            return
        }
        #expect(loaded.directoryTitle == "本地目录")
        #expect(loaded.pages.map(\.id) == ["700#0"])
        #expect(loaded.readingPosition == MangaReadingPosition(tid: "700", localIndex: 0))
        #expect(await store.requestedNames == ["本地目录"])
        #expect(await repository.seedURLs.isEmpty)
        #expect(await store.savedDirectories.isEmpty)
    }

    @Test func seedDirectoryInitializesTagStrategyAndDoesNotLoadRemoteDirectory() async throws {
        let document = try makeWorkflowDocument(tid: "700", pageCount: 1)
        let seed = MangaDirectorySeed(
            currentChapter: makeWorkflowChapter(tid: "700", title: "第1话"),
            tagIDs: [" 12 ", "", "12", "34"],
            samePageChapters: [
                makeWorkflowChapter(tid: "700", title: "duplicate"),
                makeWorkflowChapter(tid: "701", title: "第2话")
            ],
            cleanBookName: " 测试漫画 ",
            firstPostID: "9001"
        )
        let loader = RecordingMangaChapterDocumentLoader(output: .document(document))
        let repository = RecordingMangaDirectoryRepository(output: .seed(seed))
        let store = RecordingMangaDirectoryStore()
        let workflow = MangaReaderWorkflow(
            context: try makeWorkflowContext(tid: "700"),
            documentLoader: loader,
            directoryRepository: repository,
            directoryStore: store
        )

        _ = await workflow.prepare()

        let saved = try #require(await store.savedDirectories.first)
        #expect(saved.cleanBookName == "测试漫画")
        #expect(saved.strategy == .tag)
        #expect(saved.sourceKey == "12,34")
        #expect(saved.chapters.map(\.tid) == ["700", "701"])
        #expect(await repository.tagDirectoryRequests.isEmpty)
        #expect(await repository.searchRequests.isEmpty)
    }

    @Test func seedDirectoryInitializesLinksStrategy() async throws {
        let seed = MangaDirectorySeed(
            currentChapter: makeWorkflowChapter(tid: "700", title: "第1话"),
            samePageChapters: [makeWorkflowChapter(tid: "701", title: "第2话")],
            cleanBookName: "测试漫画",
            firstPostID: "9001"
        )

        let directory = MangaDirectoryInitialization.directory(from: seed)

        #expect(directory.strategy == .links)
        #expect(directory.sourceKey == "9001")
        #expect(directory.chapters.map(\.tid) == ["700", "701"])
    }

    @Test func seedDirectoryInitializesPendingSearchStrategy() async throws {
        let seed = MangaDirectorySeed(
            currentChapter: makeWorkflowChapter(tid: "700", title: "第1话"),
            cleanBookName: "测试漫画"
        )

        let directory = MangaDirectoryInitialization.directory(from: seed)

        #expect(directory.strategy == .pendingSearch)
        #expect(directory.sourceKey == "测试漫画")
        #expect(directory.chapters.map(\.tid) == ["700"])
    }

    @Test func seedDirectoryDoesNotTreatDuplicateCurrentLinkAsLinksStrategy() async throws {
        let seed = MangaDirectorySeed(
            currentChapter: makeWorkflowChapter(tid: "700", title: "第1话"),
            samePageChapters: [makeWorkflowChapter(tid: "700", title: "duplicate")],
            cleanBookName: "测试漫画",
            firstPostID: "9001"
        )

        let directory = MangaDirectoryInitialization.directory(from: seed)

        #expect(directory.strategy == .pendingSearch)
        #expect(directory.sourceKey == "测试漫画")
        #expect(directory.chapters.map(\.tid) == ["700"])
    }

    @Test func documentLoadingFailurePublishesFailedPresentation() async throws {
        let loader = RecordingMangaChapterDocumentLoader(output: .failure(.offline))
        let repository = RecordingMangaDirectoryRepository(
            output: .seed(makeWorkflowSeed(currentTID: "700", tagIDs: ["12"]))
        )
        let store = RecordingMangaDirectoryStore()
        let workflow = MangaReaderWorkflow(
            context: try makeWorkflowContext(tid: "700"),
            documentLoader: loader,
            directoryRepository: repository,
            directoryStore: store
        )

        let presentation = await workflow.prepare()

        guard case let .failed(error) = presentation.state else {
            Issue.record("Expected failed presentation")
            return
        }
        #expect(error.title == L10n.string("common.load_failed"))
        #expect(error.message == YamiboError.offline.localizedDescription)
        #expect(await repository.seedURLs.isEmpty)
        #expect(await store.savedDirectories.isEmpty)
    }
}

@MainActor
private func makeLoadedPresentation(
    context: MangaLaunchContext,
    document: MangaChapterDocument,
    seed: MangaDirectorySeed
) async -> MangaReaderPresentation {
    let workflow = MangaReaderWorkflow(
        context: context,
        documentLoader: RecordingMangaChapterDocumentLoader(output: .document(document)),
        directoryRepository: RecordingMangaDirectoryRepository(output: .seed(seed)),
        directoryStore: RecordingMangaDirectoryStore()
    )
    return await workflow.prepare()
}

private actor RecordingMangaChapterDocumentLoader: MangaChapterDocumentLoading {
    enum Output: Sendable {
        case document(MangaChapterDocument)
        case failure(YamiboError)
    }

    private let output: Output
    private(set) var loadedURLs: [URL] = []

    init(output: Output) {
        self.output = output
    }

    func loadChapterDocument(at url: URL) async throws -> MangaChapterDocument {
        loadedURLs.append(url)
        switch output {
        case let .document(document):
            return document
        case let .failure(error):
            throw error
        }
    }
}

private actor RecordingMangaDirectoryRepository: MangaDirectoryRepository {
    enum Output: Sendable {
        case seed(MangaDirectorySeed)
        case failure(YamiboError)
    }

    private let output: Output
    private(set) var seedURLs: [URL] = []
    private(set) var tagDirectoryRequests: [[String]] = []
    private(set) var searchRequests: [(keyword: String, forumID: String)] = []

    init(output: Output) {
        self.output = output
    }

    func loadDirectorySeed(for chapterURL: URL) async throws -> MangaDirectorySeed {
        seedURLs.append(chapterURL)
        switch output {
        case let .seed(seed):
            return seed
        case let .failure(error):
            throw error
        }
    }

    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter] {
        tagDirectoryRequests.append(tagIDs)
        return []
    }

    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter] {
        searchRequests.append((keyword, forumID))
        return []
    }
}

private actor RecordingMangaDirectoryStore: MangaDirectoryPersisting {
    private var directories: [String: MangaDirectory]
    private(set) var requestedNames: [String] = []
    private(set) var savedDirectories: [MangaDirectory] = []
    private(set) var deletedNames: [String] = []

    init(directories: [MangaDirectory] = []) {
        self.directories = Dictionary(
            uniqueKeysWithValues: directories.map { (Self.normalizedName($0.cleanBookName), $0) }
        )
    }

    func directory(named name: String) async throws -> MangaDirectory? {
        let normalized = Self.normalizedName(name)
        requestedNames.append(normalized)
        return directories[normalized]
    }

    func saveDirectory(_ directory: MangaDirectory) async throws {
        savedDirectories.append(directory)
        directories[Self.normalizedName(directory.cleanBookName)] = directory
    }

    func deleteDirectory(named name: String) async throws {
        let normalized = Self.normalizedName(name)
        deletedNames.append(normalized)
        directories.removeValue(forKey: normalized)
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func makeWorkflowContext(
    tid: String,
    initialPage: Int = 0,
    directoryName: String? = nil
) throws -> MangaLaunchContext {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    return MangaLaunchContext(
        originalThreadURL: url,
        chapterURL: url,
        displayTitle: "测试漫画",
        source: .forum,
        initialPage: initialPage,
        directoryName: directoryName
    )
}

private func makeWorkflowSeed(
    currentTID: String,
    tagIDs: [String] = []
) -> MangaDirectorySeed {
    MangaDirectorySeed(
        currentChapter: makeWorkflowChapter(tid: currentTID, title: "第1话"),
        tagIDs: tagIDs,
        cleanBookName: "测试漫画"
    )
}

private func makeWorkflowDirectory(
    name: String,
    strategy: MangaDirectoryStrategy,
    sourceKey: String,
    tids: [String]
) -> MangaDirectory {
    MangaDirectory(
        cleanBookName: name,
        strategy: strategy,
        sourceKey: sourceKey,
        chapters: tids.map { makeWorkflowChapter(tid: $0, title: "第\($0)话") }
    )
}

private func makeWorkflowChapter(tid: String, title: String) -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: title,
        chapterNumber: Double(tid) ?? 0,
        url: makeWorkflowURL(tid: tid)
    )
}

private func makeWorkflowDocument(tid: String, pageCount: Int) throws -> MangaChapterDocument {
    let imageURLs = try (0..<pageCount).map { index in
        try #require(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
    }
    return MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第\(tid)话",
        chapterURL: makeWorkflowURL(tid: tid),
        imageURLs: imageURLs
    )
}

private func makeWorkflowURL(tid: String) -> URL {
    URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
}
