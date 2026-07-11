import Foundation
@preconcurrency import GRDB
import Testing
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

/// Regression coverage for the precise directory-scoped reading-progress
/// lookup `ForumMangaDetailViewModel` must use once its `MangaDirectory` is
/// known — see `ForumMangaDetailViewModel.loadReadingProgress()`. Mirrors
/// `LocalFavoriteOpenTargetResolver.mangaDirectoryResumeTarget`'s existing
/// pattern and the collision scenario documented there.
@MainActor
@Test func forumMangaDetailReloadUsesDirectoryLevelProgressNotStaleChapterThreadRecord() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "manga-detail-precise-progress")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let mangaDirectoryStore = try makeForumMangaDetailTestDirectoryStore(suiteName: suiteName)
    let readingProgressStore = ReadingProgressStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
        key: "reading-progress"
    )

    let directory = MangaDirectory(
        cleanBookName: "测试漫画",
        strategy: .tag,
        sourceKey: "测试漫画",
        chapters: [
            MangaChapter(tid: "910", rawTitle: "第一话", chapterNumber: 1, view: 1),
            MangaChapter(tid: "911", rawTitle: "第二话", chapterNumber: 2, view: 2)
        ]
    )
    try await mangaDirectoryStore.saveDirectory(directory)

    // The directory's TRUE current position: chapter 911, page 5 — written
    // the way a mode-on session actually advances the directory-level row.
    _ = try await readingProgressStore.saveMangaTitle(
        cleanBookName: directory.cleanBookName,
        chapterThreadID: "911",
        chapterView: 2,
        chapterTitle: "第二话",
        pageIndex: 5,
        mangaID: directory.favoriteIdentity
    )

    // A STALE, unrelated per-chapter record for chapter 910 — this is what
    // the old fuzzy `load(threadID:)` query would coincidentally match when
    // this view model is opened for chapter 910's own thread, since its
    // `thread_id`/`manga_chapter_thread_id` columns literally equal "910".
    _ = try await readingProgressStore.saveMangaThread(
        MangaProgressReadingPosition(
            chapterThreadID: "910",
            chapterView: 1,
            chapterTitle: "第一话",
            pageIndex: 0
        )
    )

    let dependencies = try makeForumMangaDetailDependencies(
        readingProgressStore: readingProgressStore,
        mangaDirectoryStore: mangaDirectoryStore,
        projectionLoader: FakeMangaReaderProjectionLoader(projectionsByTID: [
            "910": makeTestMangaReaderProjection(tid: "910", chapterTitle: "第一话")
        ])
    )
    let model = makeForumMangaDetailViewModel(dependencies: dependencies, threadTID: "910")

    await model.reload()

    #expect(model.errorMessage == nil)
    let resolvedDirectory = try #require(model.directory)
    #expect(resolvedDirectory.cleanBookName == "测试漫画")

    let context = try #require(model.continueLaunchContext())
    #expect(context.chapterTID == "911")
    #expect(context.chapterView == 2)
    #expect(context.initialPage == 5)
    #expect(context.chapterTID != "910")
}

/// Live-update regression test: after `reload()` has resolved `directory`,
/// a progress update saved elsewhere (e.g. Favorites reading the same
/// directory) must reach `readingProgress` via the same precise
/// directory-scoped query, not just at `reload()` time. Mirrors
/// `forumNovelDetailRefreshesReadingProgressWhenReadingProgressStoreChanges`'s
/// polling style, since the update arrives asynchronously through
/// `ReadingProgressStore.didChangeNotification`.
@MainActor
@Test func forumMangaDetailLiveUpdateUsesDirectoryLevelProgressAfterReload() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "manga-detail-live-progress")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let mangaDirectoryStore = try makeForumMangaDetailTestDirectoryStore(suiteName: suiteName)
    let readingProgressStore = ReadingProgressStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
        key: "reading-progress"
    )

    let directory = MangaDirectory(
        cleanBookName: "测试漫画二",
        strategy: .tag,
        sourceKey: "测试漫画二",
        chapters: [
            MangaChapter(tid: "920", rawTitle: "第一话", chapterNumber: 1, view: 1),
            MangaChapter(tid: "921", rawTitle: "第二话", chapterNumber: 2, view: 2)
        ]
    )
    try await mangaDirectoryStore.saveDirectory(directory)

    // A stale chapter-920-specific record sharing this view model's own tid,
    // matching the collision fixture pattern used in the reload test above.
    _ = try await readingProgressStore.saveMangaThread(
        MangaProgressReadingPosition(
            chapterThreadID: "920",
            chapterView: 1,
            chapterTitle: "第一话",
            pageIndex: 0
        )
    )

    let dependencies = try makeForumMangaDetailDependencies(
        readingProgressStore: readingProgressStore,
        mangaDirectoryStore: mangaDirectoryStore,
        projectionLoader: FakeMangaReaderProjectionLoader(projectionsByTID: [
            "920": makeTestMangaReaderProjection(tid: "920", chapterTitle: "第一话")
        ])
    )
    let model = makeForumMangaDetailViewModel(dependencies: dependencies, threadTID: "920")

    await model.reload()
    #expect(model.directory != nil)
    #expect(model.readingProgress?.manga?.chapterThreadID != "921")

    // Simulate a live progress update arriving from elsewhere (e.g. the
    // user advancing this same directory through Favorites) after reload.
    _ = try await readingProgressStore.saveMangaTitle(
        cleanBookName: directory.cleanBookName,
        chapterThreadID: "921",
        chapterView: 2,
        chapterTitle: "第二话",
        pageIndex: 3,
        mangaID: directory.favoriteIdentity
    )

    for _ in 0..<50 where model.readingProgress?.manga?.chapterThreadID != "921" {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(model.readingProgress?.manga?.chapterThreadID == "921")
    #expect(model.readingProgress?.manga?.mangaPageIndex == 3)
}

/// `MangaStoreTestSupport.swift`'s `makeTestMangaDirectoryStore` lives in the
/// `YamiboReaderCoreTests` target only, so this file builds its own GRDB pool
/// directly — mirroring `LocalFavoriteOpenTargetResolverTests
/// .makeMangaDirectoryStore(suiteName:)`.
private func makeForumMangaDetailTestDirectoryStore(suiteName: String) throws -> MangaDirectoryStore {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("forum-manga-detail-view-model-tests", isDirectory: true)
        .appendingPathComponent(suiteName, isDirectory: true)
    let database = try YamiboDatabase.openPool(rootDirectory: root)
    return MangaDirectoryStore(databasePool: database)
}

/// Builds a `ForumDependencies` package backed by isolated per-test stores.
/// Factories for repositories this file never exercises trap loudly — the
/// manga directory is always pre-seeded so `MangaDirectoryWorkflow
/// .resolveInitialDirectory` resolves it via `store.directory(containingTID:)`
/// without ever reaching `makeMangaDirectoryRepository`. Unlike
/// `ForumNovelDetailViewModel`, `ForumMangaDetailViewModel` has no injectable
/// provider for its projection loader — it calls
/// `dependencies.makeMangaReaderProjectionLoader()` directly — so the fake
/// loader is threaded straight into that factory closure here.
@MainActor
private func makeForumMangaDetailDependencies(
    readingProgressStore: ReadingProgressStore,
    mangaDirectoryStore: MangaDirectoryStore,
    projectionLoader: FakeMangaReaderProjectionLoader
) throws -> ForumDependencies {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "manga-detail-deps")
    let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
    let sessionStore = SessionStore(defaults: defaults, key: "session")
    let session = YamiboNetworkConfiguration.makeSession()
    @Sendable func makeClient() async -> YamiboClient {
        let sessionState = await sessionStore.load()
        return YamiboClient(
            session: session,
            cookie: sessionState.cookie,
            userAgent: sessionState.userAgent
        )
    }
    let forumCacheStore = ForumCacheStore(
        baseDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    )
    return ForumDependencies(
        sessionStore: sessionStore,
        profileStore: YamiboProfileStore(defaults: defaults, key: "profile"),
        localFavoriteLibraryStore: FavoriteLibraryStore(defaults: defaults, key: "local-favorites"),
        readingProgressStore: readingProgressStore,
        settingsStore: SettingsStore(defaults: defaults, key: "settings"),
        contentCoverStore: ContentCoverStore(defaults: defaults, key: "content-covers"),
        mangaDirectoryStore: mangaDirectoryStore,
        mangaDirectorySearchCooldownState: MangaDirectorySearchCooldownState(),
        makeForumRepository: { ForumRepository(client: await makeClient(), cacheStore: forumCacheStore) },
        makeForumThreadReaderRepository: { ForumThreadReaderRepository(client: await makeClient(), cacheStore: forumCacheStore) },
        makeUserSpaceRepository: { UserSpaceRepository(client: await makeClient()) },
        makeBlogReaderRepository: { BlogReaderRepository(client: await makeClient()) },
        makeFavoriteRepository: { FavoriteRepository(client: await makeClient()) },
        makeNovelReaderRepository: { fatalError("makeNovelReaderRepository is not exercised by ForumMangaDetailViewModelTests") },
        makeMangaReaderProjectionLoader: { projectionLoader },
        makeMangaDirectoryRepository: { UnusedMangaDirectoryRepository() },
        makeThreadRouteResolver: { YamiboThreadRouteResolver(client: await makeClient()) }
    )
}

@MainActor
private func makeForumMangaDetailViewModel(
    dependencies: ForumDependencies,
    threadTID: String
) -> ForumMangaDetailViewModel {
    ForumMangaDetailViewModel(
        context: MangaDetailLaunchContext(
            thread: ThreadIdentity(tid: threadTID, fid: "30"),
            title: "测试漫画"
        ),
        dependencies: dependencies
    )
}

private func makeTestMangaReaderProjection(tid: String, chapterTitle: String) -> MangaReaderProjection {
    MangaReaderProjection(
        tid: tid,
        ownerAuthorID: "42",
        chapterTitle: chapterTitle,
        imageURLs: [URL(string: "https://img.example.com/\(tid)/1.jpg")!]
    )
}

/// Never actually invoked: every test here pre-seeds a real `MangaDirectory`
/// covering the tid it uses, so `MangaDirectoryWorkflow.resolveInitialDirectory`
/// always resolves via `store.directory(containingTID:)` before it would ever
/// fall back to a repository call.
private struct UnusedMangaDirectoryRepository: MangaDirectoryRepository {
    func loadDirectorySeed(for threadID: String) async throws -> MangaDirectorySeed {
        fatalError("loadDirectorySeed is not exercised by ForumMangaDetailViewModelTests")
    }

    func loadTagDirectory(tagIDs: [String], allowedForumID: String) async throws -> [MangaChapter] {
        fatalError("loadTagDirectory is not exercised by ForumMangaDetailViewModelTests")
    }

    func searchDirectory(keyword: String, forumID: String) async throws -> [MangaChapter] {
        fatalError("searchDirectory is not exercised by ForumMangaDetailViewModelTests")
    }
}

private final class FakeMangaReaderProjectionLoader: MangaReaderProjectionSnapshotLoading, @unchecked Sendable {
    private let projectionsByTID: [String: MangaReaderProjection]

    init(projectionsByTID: [String: MangaReaderProjection]) {
        self.projectionsByTID = projectionsByTID
    }

    func loadReaderProjection(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjection {
        guard let projection = projectionsByTID[request.threadID] else {
            throw FakeMangaReaderProjectionLoaderError.missingProjection(tid: request.threadID)
        }
        return projection
    }

    func loadReaderProjectionSnapshot(_ request: MangaReaderProjectionRequest) async throws -> MangaReaderProjectionSnapshot {
        fatalError("loadReaderProjectionSnapshot is not exercised by ForumMangaDetailViewModelTests")
    }
}

private enum FakeMangaReaderProjectionLoaderError: Error {
    case missingProjection(tid: String)
}
