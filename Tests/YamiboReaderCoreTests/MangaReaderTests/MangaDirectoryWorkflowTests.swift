import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Directory Workflow")
struct MangaDirectoryWorkflowTests {
    @Test func initialDirectoryReusesNameThenTIDBeforeSeeding() async throws {
        let named = makeDirectory(name: "命名目录", strategy: .searched, sourceKey: "named", tids: ["900"])
        let containing = makeDirectory(name: "包含目录", strategy: .searched, sourceKey: "containing", tids: ["700"])
        let store = RecordingDirectoryStore(directories: [named, containing])
        let repository = RecordingDirectoryRepository(seed: makeSeed(tid: "700", tagIDs: ["31"]))
        let workflow = MangaDirectoryWorkflow(repository: repository, store: store)
        let document = try makeDocument(tid: "700")
        let context = try makeContext(tid: "700", directoryName: " 命名目录 ")

        let resolvedByName = try await workflow.resolveInitialDirectory(context: context, document: document)
        #expect(resolvedByName.directory.cleanBookName == "命名目录")
        #expect(!resolvedByName.shouldAutoUpdateAfterInitialLoad)
        #expect(await repository.seedURLs.isEmpty)
        #expect(await store.savedDirectories.isEmpty)

        let missingContext = try makeContext(tid: "700", directoryName: "missing")
        let resolvedByTID = try await workflow.resolveInitialDirectory(context: missingContext, document: document)
        #expect(resolvedByTID.directory.cleanBookName == "包含目录")
        #expect(await repository.seedURLs.isEmpty)
    }

    @Test func initialTagDirectoryIsSeededAndMarkedForDeferredRefresh() async throws {
        let store = RecordingDirectoryStore()
        let repository = RecordingDirectoryRepository(
            seed: makeSeed(tid: "700", tagIDs: [" 31 ", "", "31"])
        )
        let workflow = MangaDirectoryWorkflow(repository: repository, store: store)
        let context = try makeContext(tid: "700")
        let document = try makeDocument(tid: "700")

        let resolved = try await workflow.resolveInitialDirectory(context: context, document: document)

        #expect(resolved.directory.strategy == .tag)
        #expect(resolved.directory.sourceKey == "31")
        #expect(resolved.shouldAutoUpdateAfterInitialLoad)
        #expect(await repository.seedURLs == [context.chapterURL])
        #expect(await store.savedDirectories.map(\.cleanBookName) == ["测试漫画"])
    }

    @Test func tagUpdateMergesRemoteChaptersAndOffersForcedSearchShortcut() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let directory = makeDirectory(name: "测试漫画", strategy: .tag, sourceKey: "31", tids: ["700"])
        let store = RecordingDirectoryStore(directories: [directory])
        let repository = RecordingDirectoryRepository(
            seed: makeSeed(tid: "700"),
            tagChapters: [makeChapter(tid: "701", title: "第2话")]
        )
        let workflow = MangaDirectoryWorkflow(
            repository: repository,
            store: store,
            configuration: MangaDirectoryWorkflowConfiguration(now: { now })
        )

        let result = try await workflow.updateDirectory(directory, currentTID: "700")

        #expect(result.directory.strategy == .tag)
        #expect(result.directory.chapters.map(\.tid) == ["700", "701"])
        #expect(result.directory.lastUpdatedAt == now)
        #expect(!result.searchPerformed)
        #expect(result.shouldOfferForcedSearch)
        #expect(result.cooldownExpiresAt == nil)
        #expect(await repository.tagDirectoryRequests == [["31"]])
        #expect(await repository.searchRequests.isEmpty)
    }

    @Test func tagUpdatePrunesExistingNonChapterRowsFilteredFromRemoteTag() async throws {
        let directory = makeDirectory(
            name: "因为今天女友不在",
            strategy: .tag,
            sourceKey: "20013",
            chapters: [
                makeChapter(tid: "518460", title: "01"),
                makeChapter(tid: "568431", title: "【提灯喵汉化组】因为今天女友不在 37"),
                makeChapter(tid: "570528", title: "香询问大家因为今天女友不在的漫画价格"),
            ],
            searchKeyword: "提灯喵汉化组 因为今天女友不在"
        )
        let store = RecordingDirectoryStore(directories: [directory])
        let repository = RecordingDirectoryRepository(
            seed: makeSeed(tid: "568431"),
            tagChapters: [
                makeChapter(tid: "568431", title: "【提灯喵汉化组】因为今天女友不在 37"),
                makeChapter(tid: "571415", title: "【提灯喵汉化组】因为今天女友不在 38"),
            ]
        )
        let workflow = MangaDirectoryWorkflow(repository: repository, store: store)

        let result = try await workflow.updateDirectory(directory, currentTID: "568431")

        #expect(result.directory.chapters.map(\.tid) == ["518460", "568431", "571415"])
    }

    @Test func emptyTagUpdateFallsBackToSearchAndStartsCooldown() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let directory = makeDirectory(
            name: "测试漫画",
            strategy: .tag,
            sourceKey: "31",
            chapters: [makeChapter(tid: "700", title: "【作者】测试漫画 第1话")]
        )
        let store = RecordingDirectoryStore(directories: [directory])
        let repository = RecordingDirectoryRepository(
            seed: makeSeed(tid: "700"),
            tagChapters: [],
            searchChapters: [makeChapter(tid: "702", title: "第3话")]
        )
        let cooldown = MangaDirectorySearchCooldownState()
        let workflow = MangaDirectoryWorkflow(
            repository: repository,
            store: store,
            configuration: MangaDirectoryWorkflowConfiguration(now: { now }),
            searchCooldownState: cooldown
        )

        let result = try await workflow.updateDirectory(directory, currentTID: "700")

        #expect(result.directory.strategy == .tag)
        #expect(result.directory.chapters.map(\.tid) == ["700", "702"])
        #expect(result.searchPerformed)
        #expect(!result.shouldOfferForcedSearch)
        #expect(result.cooldownExpiresAt == now.addingTimeInterval(20))
        #expect(await cooldown.cooldownExpiresAt(now: now) == now.addingTimeInterval(20))
        #expect(await repository.searchRequests.map(\.forumID) == ["30"])
        #expect(await repository.searchRequests.first?.keyword == "作者 测试漫画")
    }

    @Test func forcedSearchBypassesTagAndUsesTypedCooldownError() async throws {
        let firstNow = Date(timeIntervalSince1970: 3_000)
        let secondNow = Date(timeIntervalSince1970: 3_005)
        let dateProvider = ManualDateProvider(now: firstNow)
        let directory = makeDirectory(name: "测试漫画", strategy: .tag, sourceKey: "31", tids: ["700"])
        let store = RecordingDirectoryStore(directories: [directory])
        let repository = RecordingDirectoryRepository(
            seed: makeSeed(tid: "700"),
            tagChapters: [makeChapter(tid: "701", title: "第2话")],
            searchChapters: [makeChapter(tid: "703", title: "第4话")]
        )
        let workflow = MangaDirectoryWorkflow(
            repository: repository,
            store: store,
            configuration: MangaDirectoryWorkflowConfiguration(now: { dateProvider.now }),
            searchCooldownState: MangaDirectorySearchCooldownState()
        )

        _ = try await workflow.updateDirectory(directory, currentTID: "700", isForcedSearch: true)
        dateProvider.now = secondNow

        await #expect(throws: YamiboError.searchCooldown(seconds: 15)) {
            _ = try await workflow.updateDirectory(directory, currentTID: "700", isForcedSearch: true)
        }
        #expect(await repository.tagDirectoryRequests.isEmpty)
        #expect(await repository.searchRequests.count == 1)
    }

    @Test func renameMergesIntoExistingTargetAndKeepsTargetSource() async throws {
        let now = Date(timeIntervalSince1970: 4_000)
        let current = makeDirectory(name: "旧标题", strategy: .searched, sourceKey: "旧标题", tids: ["700", "701"])
        let target = makeDirectory(name: "新标题", strategy: .tag, sourceKey: "31", tids: ["701", "702"])
        let store = RecordingDirectoryStore(directories: [current, target])
        let workflow = MangaDirectoryWorkflow(
            repository: RecordingDirectoryRepository(seed: makeSeed(tid: "700")),
            store: store,
            configuration: MangaDirectoryWorkflowConfiguration(now: { now })
        )

        let renamed = try await workflow.renameDirectory(
            current,
            cleanBookName: " 新标题 ",
            searchKeyword: " 作者 新标题 "
        )

        #expect(renamed.cleanBookName == "新标题")
        #expect(renamed.strategy == .tag)
        #expect(renamed.sourceKey == "31")
        #expect(renamed.searchKeyword == "作者 新标题")
        #expect(renamed.lastUpdatedAt == now)
        #expect(renamed.chapters.map(\.tid) == ["700", "701", "702"])
        #expect(await store.deletedNames == ["旧标题"])
    }

    @Test func renameUsesTransactionalStoreCapabilityWhenAvailable() async throws {
        let current = makeDirectory(name: "旧标题", strategy: .searched, sourceKey: "旧标题", tids: ["700"])
        let store = RecordingRenamingDirectoryStore(directories: [current])
        let workflow = MangaDirectoryWorkflow(
            repository: RecordingDirectoryRepository(seed: makeSeed(tid: "700")),
            store: store
        )

        let renamed = try await workflow.renameDirectory(
            current,
            cleanBookName: "新标题",
            searchKeyword: ""
        )

        #expect(renamed.cleanBookName == "新标题")
        #expect(await store.renameRequests.map(\.oldName) == ["旧标题"])
        #expect(await store.savedDirectories.isEmpty)
        #expect(await store.deletedNames.isEmpty)
        #expect(try await store.directory(named: "旧标题") == nil)
        #expect(try await store.directory(named: "新标题")?.chapters.map(\.tid) == ["700"])
    }

    @Test func editDraftPreservesNameAndSplitsExistingKeyword() {
        let directory = makeDirectory(
            name: "作品",
            strategy: .searched,
            sourceKey: "作品",
            chapters: [makeChapter(tid: "700", title: "【作者】作品 第1话")],
            searchKeyword: "作者 作品"
        )
        let workflow = MangaDirectoryWorkflow(
            repository: RecordingDirectoryRepository(seed: makeSeed(tid: "700")),
            store: RecordingDirectoryStore()
        )

        let draft = workflow.editDraft(for: directory, currentTID: "700")

        #expect(draft.cleanBookName == "作品")
        #expect(draft.primaryKeyword == "作者")
        #expect(draft.secondaryKeyword == "作品")
        #expect(MangaDirectoryWorkflow.searchKeyword(from: draft) == "作者 作品")
    }

    @Test func mergeAndSortDeduplicatesAndInfersMissingChapterNumbers() {
        let existing = [
            makeChapter(tid: "701", title: "第2话", chapterNumber: 2),
            makeChapter(tid: "700", title: "第1话", chapterNumber: 1)
        ]
        let incoming = [
            makeChapter(tid: "701", title: "第2话 修订", chapterNumber: 2),
            makeChapter(tid: "702", title: "幕间", chapterNumber: 0)
        ]

        let merged = MangaDirectoryMerge.mergeAndSort(existing, incoming)

        #expect(merged.map(\.tid) == ["700", "701", "702"])
        #expect(merged[1].rawTitle == "第2话 修订")
        #expect(merged[2].chapterNumber == 2.1)
    }
}

private actor RecordingDirectoryRepository: MangaDirectoryRepository {
    private let seed: MangaDirectorySeed
    private let tagChapters: [MangaChapter]
    private let searchChapters: [MangaChapter]
    private(set) var seedURLs: [URL] = []
    private(set) var tagDirectoryRequests: [[String]] = []
    private(set) var searchRequests: [(keyword: String, forumID: String)] = []

    init(
        seed: MangaDirectorySeed,
        tagChapters: [MangaChapter] = [],
        searchChapters: [MangaChapter] = []
    ) {
        self.seed = seed
        self.tagChapters = tagChapters
        self.searchChapters = searchChapters
    }

    func loadDirectorySeed(for chapterURL: URL) async throws -> MangaDirectorySeed {
        seedURLs.append(chapterURL)
        return seed
    }

    func loadTagDirectory(tagIDs: [String]) async throws -> [MangaChapter] {
        tagDirectoryRequests.append(tagIDs)
        return tagChapters
    }

    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter] {
        searchRequests.append((keyword, forumID))
        return searchChapters
    }
}

private final class ManualDateProvider: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private actor RecordingDirectoryStore: MangaDirectoryPersisting {
    private var directories: [String: MangaDirectory]
    private(set) var savedDirectories: [MangaDirectory] = []
    private(set) var deletedNames: [String] = []

    init(directories: [MangaDirectory] = []) {
        self.directories = Dictionary(uniqueKeysWithValues: directories.map { ($0.cleanBookName, $0) })
    }

    func directory(named name: String) async throws -> MangaDirectory? {
        directories[name.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    func directory(containingTID tid: String) async throws -> MangaDirectory? {
        directories.values.first { directory in
            directory.chapters.contains { $0.tid == tid.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    func saveDirectory(_ directory: MangaDirectory) async throws {
        savedDirectories.append(directory)
        directories[directory.cleanBookName] = directory
    }

    func deleteDirectory(named name: String) async throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        deletedNames.append(normalized)
        directories.removeValue(forKey: normalized)
    }
}

private actor RecordingRenamingDirectoryStore: MangaDirectoryPersisting, MangaDirectoryRenaming {
    private var directories: [String: MangaDirectory]
    private(set) var savedDirectories: [MangaDirectory] = []
    private(set) var deletedNames: [String] = []
    private(set) var renameRequests: [(oldName: String, newName: String)] = []

    init(directories: [MangaDirectory] = []) {
        self.directories = Dictionary(uniqueKeysWithValues: directories.map { ($0.cleanBookName, $0) })
    }

    func directory(named name: String) async throws -> MangaDirectory? {
        directories[name.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    func directory(containingTID tid: String) async throws -> MangaDirectory? {
        directories.values.first { directory in
            directory.chapters.contains { $0.tid == tid.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }

    func saveDirectory(_ directory: MangaDirectory) async throws {
        savedDirectories.append(directory)
        directories[directory.cleanBookName] = directory
    }

    func deleteDirectory(named name: String) async throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        deletedNames.append(normalized)
        directories.removeValue(forKey: normalized)
    }

    func renameDirectory(from oldName: String, to newDirectory: MangaDirectory) async throws {
        let normalized = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        renameRequests.append((oldName: normalized, newName: newDirectory.cleanBookName))
        directories.removeValue(forKey: normalized)
        directories[newDirectory.cleanBookName] = newDirectory
    }
}

private func makeSeed(tid: String, tagIDs: [String] = []) -> MangaDirectorySeed {
    MangaDirectorySeed(
        currentChapter: makeChapter(tid: tid, title: "第1话", chapterNumber: 1),
        tagIDs: tagIDs,
        cleanBookName: "测试漫画"
    )
}

private func makeDirectory(
    name: String,
    strategy: MangaDirectoryStrategy,
    sourceKey: String,
    tids: [String]
) -> MangaDirectory {
    makeDirectory(
        name: name,
        strategy: strategy,
        sourceKey: sourceKey,
        chapters: tids.map { makeChapter(tid: $0, title: "第\($0)话", chapterNumber: Double($0) ?? 0) }
    )
}

private func makeDirectory(
    name: String,
    strategy: MangaDirectoryStrategy,
    sourceKey: String,
    chapters: [MangaChapter],
    searchKeyword: String? = nil
) -> MangaDirectory {
    MangaDirectory(
        cleanBookName: name,
        strategy: strategy,
        sourceKey: sourceKey,
        chapters: chapters,
        searchKeyword: searchKeyword
    )
}

private func makeChapter(
    tid: String,
    title: String,
    chapterNumber: Double? = nil
) -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: title,
        chapterNumber: chapterNumber ?? MangaTitleCleaner.extractChapterNumber(title),
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!
    )
}

private func makeDocument(tid: String) throws -> MangaChapterDocument {
    MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第1话",
        chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2")!,
        imageURLs: [
            try #require(URL(string: "https://img.example.com/\(tid)-0.jpg"))
        ]
    )
}

private func makeContext(tid: String, directoryName: String? = nil) throws -> MangaLaunchContext {
    let url = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&mobile=2"))
    return MangaLaunchContext(
        originalThreadURL: url,
        chapterURL: url,
        displayTitle: "测试漫画",
        source: .forum,
        directoryName: directoryName
    )
}
