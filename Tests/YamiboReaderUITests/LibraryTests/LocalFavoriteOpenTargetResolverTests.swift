import XCTest
@testable import YamiboReaderCore
import YamiboReaderTestSupport
@testable import YamiboReaderUI

@MainActor
final class LocalFavoriteOpenTargetResolverTests: XCTestCase {
    func testNormalThreadOpenTargetUsesNativeReaderWithoutMutatingFavoriteUpdatedAt() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_000)
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: FavoriteItemTarget(kind: .normalThread, threadID: "901"),
            title: "普通主题",
            locations: [.category(document.defaultCategory.id)],
            updatedAt: originalUpdatedAt
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: try makeMangaDirectoryStore(suiteName: suiteName)
        )
        let opened = try await resolver.openTarget(for: item)

        guard case let .nativeThread(openedURL, title)? = opened else {
            return XCTFail("Expected a native thread open target")
        }
        XCTAssertEqual(openedURL, YamiboRoute.threadByID(tid: "901", page: 1, authorID: nil, reverse: false).url)
        XCTAssertEqual(title, "普通主题")
        let storedItem = try await localFavoriteLibraryStore.load().items.first { $0.id == item.id }
        XCTAssertEqual(storedItem?.updatedAt, originalUpdatedAt)
    }

    // `.mangaThread` favorites always resolve straight to the manga reader
    // (smart-comic-mode design decision #7) and, unlike the old `.mangaTitle`
    // merged identity, always have a real chapter tid to fall back to when
    // there is no reading-progress record yet — the old `mangaTitleUnresolved`
    // failure mode can no longer occur (see LocalFavoriteOpenTargetResolver).
    //
    // This item has no `forumID`, which reports mode-off under the strict
    // rule (only a board currently configured as `.manga(smartEnabled:
    // true)` is on — a missing fid can never match), so this exercises the
    // mode-off single-thread resume branch: the favorite's own
    // `.mangaThread` progress (here, none at all), never a merged
    // directory.
    func testMangaThreadOpenTargetFallsBackToOwnThreadWithoutReadingProgress() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target-manga")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: .mangaThread(threadID: "902"),
            title: "漫画章节",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: try makeMangaDirectoryStore(suiteName: suiteName)
        )
        let opened = try await resolver.openTarget(for: item)

        guard case let .mangaReader(context)? = opened else {
            return XCTFail("Expected a manga reader open target")
        }
        XCTAssertEqual(context.originalThreadID, "902")
        XCTAssertEqual(context.chapterTID, "902")
        XCTAssertEqual(context.initialPage, 0)
        XCTAssertNil(context.directoryName)
        XCTAssertFalse(context.isSmartModeEnabled)
    }

    // Mode-on resume (smart-comic-mode design decision #15/#7): the favorite
    // is a single chapter thread, but its `MangaDirectory` is already
    // resolved locally with an upserted directory-level `.mangaTitle`
    // progress record pointing at a *different* chapter than the one the
    // favorite itself was created from. Resuming must follow the
    // directory-level record (not the favorited thread's own tid).
    func testMangaThreadOpenTargetOnModeOnBoardResumesViaDirectoryLevelProgress() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target-manga-mode-on")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let mangaDirectoryStore = try makeMangaDirectoryStore(suiteName: suiteName)
        let directory = MangaDirectory(
            cleanBookName: "测试漫画",
            strategy: .tag,
            sourceKey: "测试漫画",
            chapters: [
                MangaChapter(tid: "1001", rawTitle: "第一话", chapterNumber: 1, view: 1),
                MangaChapter(tid: "1002", rawTitle: "第二话", chapterNumber: 2, view: 1),
                MangaChapter(tid: "1003", rawTitle: "第三话", chapterNumber: 3, view: 1)
            ]
        )
        try await mangaDirectoryStore.saveDirectory(directory)
        _ = try await readingProgressStore.saveMangaTitle(
            cleanBookName: directory.cleanBookName,
            chapterThreadID: "1002",
            chapterTitle: "第二话",
            pageIndex: 4,
            mangaID: directory.favoriteIdentity
        )

        var document = FavoriteLibraryDocument()
        // The favorite itself points at chapter 1's thread — the merged
        // board (fid "30" is on by default) should still resume at chapter
        // 2, following the directory-level record, not this thread's own id.
        let item = try FavoriteItem(
            target: .mangaThread(threadID: "1001"),
            title: "测试漫画 第一话",
            sourceGroup: .forumBoard(id: "30", label: "中文百合漫画区"),
            forumID: "30",
            forumName: "中文百合漫画区",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: mangaDirectoryStore
        )
        let opened = try await resolver.openTarget(for: item)

        guard case let .mangaReader(context)? = opened else {
            return XCTFail("Expected a manga reader open target")
        }
        XCTAssertEqual(context.originalThreadID, "1001")
        XCTAssertEqual(context.chapterTID, "1002")
        XCTAssertEqual(context.initialPage, 4)
        XCTAssertEqual(context.directoryName, "测试漫画")
        XCTAssertTrue(context.isSmartModeEnabled)
    }

    // Same directory/progress setup as above, but the resolved directory has
    // no progress record at all yet — resume should fall back to the
    // directory's earliest chapter (smart-comic-mode design decision #7).
    func testMangaThreadOpenTargetOnModeOnBoardFallsBackToEarliestChapterWithoutProgress() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target-manga-mode-on-fallback")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let mangaDirectoryStore = try makeMangaDirectoryStore(suiteName: suiteName)
        let directory = MangaDirectory(
            cleanBookName: "无进度漫画",
            strategy: .tag,
            sourceKey: "无进度漫画",
            chapters: [
                MangaChapter(tid: "2001", rawTitle: "第一话", chapterNumber: 1, view: 1),
                MangaChapter(tid: "2002", rawTitle: "第二话", chapterNumber: 2, view: 1)
            ]
        )
        try await mangaDirectoryStore.saveDirectory(directory)

        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: .mangaThread(threadID: "2002"),
            title: "无进度漫画 第二话",
            sourceGroup: .forumBoard(id: "30", label: "中文百合漫画区"),
            forumID: "30",
            forumName: "中文百合漫画区",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: mangaDirectoryStore
        )
        let opened = try await resolver.openTarget(for: item)

        guard case let .mangaReader(context)? = opened else {
            return XCTFail("Expected a manga reader open target")
        }
        XCTAssertEqual(context.chapterTID, "2001")
        XCTAssertEqual(context.initialPage, 0)
        XCTAssertEqual(context.directoryName, "无进度漫画")
    }

    // Mode-off (smart-comic-mode design decision #15): resume must use only
    // this thread's own `.mangaThread` progress record, never the
    // directory-level one, even when a resolved directory with progress
    // exists for the same tid (e.g. left over from before the board was
    // switched off).
    func testMangaThreadOpenTargetOnModeOffBoardResumesViaOwnThreadProgressOnly() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target-manga-mode-off")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let mangaDirectoryStore = try makeMangaDirectoryStore(suiteName: suiteName)
        let directory = MangaDirectory(
            cleanBookName: "已关闭板块漫画",
            strategy: .tag,
            sourceKey: "已关闭板块漫画",
            chapters: [
                MangaChapter(tid: "3001", rawTitle: "第一话", chapterNumber: 1, view: 1)
            ]
        )
        try await mangaDirectoryStore.saveDirectory(directory)
        // Stale directory-level record from before the board was switched
        // off — must be ignored entirely by the mode-off resume path.
        _ = try await readingProgressStore.saveMangaTitle(
            cleanBookName: directory.cleanBookName,
            chapterThreadID: "3001",
            chapterTitle: "第一话",
            pageIndex: 9,
            mangaID: directory.favoriteIdentity
        )
        _ = try await readingProgressStore.saveMangaThread(MangaProgressReadingPosition(
            chapterThreadID: "3001",
            chapterTitle: "第一话",
            pageIndex: 2
        ))

        var document = FavoriteLibraryDocument()
        // fid "46" is off by default (smart-comic-mode design decision #1).
        let item = try FavoriteItem(
            target: .mangaThread(threadID: "3001"),
            title: "已关闭板块漫画 第一话",
            sourceGroup: .forumBoard(id: "46", label: "关闭板块"),
            forumID: "46",
            forumName: "关闭板块",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: mangaDirectoryStore
        )
        let opened = try await resolver.openTarget(for: item)

        guard case let .mangaReader(context)? = opened else {
            return XCTFail("Expected a manga reader open target")
        }
        XCTAssertEqual(context.originalThreadID, "3001")
        XCTAssertEqual(context.chapterTID, "3001")
        XCTAssertEqual(context.initialPage, 2)
        XCTAssertNil(context.directoryName)
        XCTAssertFalse(context.isSmartModeEnabled)
    }

    // The "查看归档收藏" archive page opens its members with
    // `mangaScope: .singleThread`: even on a mode-ON board with a resolved
    // directory and a directory-level progress record pointing at a
    // different chapter, the tapped member must open as exactly its own
    // thread (single-thread reading, own `.mangaThread` progress) — matching
    // the ordinary non-smart card the page renders it as.
    func testMangaThreadOpenTargetWithSingleThreadScopeIgnoresModeOnBoard() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target-manga-single-thread-scope")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        let mangaDirectoryStore = try makeMangaDirectoryStore(suiteName: suiteName)
        let directory = MangaDirectory(
            cleanBookName: "归档页漫画",
            strategy: .tag,
            sourceKey: "归档页漫画",
            chapters: [
                MangaChapter(tid: "4001", rawTitle: "第一话", chapterNumber: 1, view: 1),
                MangaChapter(tid: "4002", rawTitle: "第二话", chapterNumber: 2, view: 1)
            ]
        )
        try await mangaDirectoryStore.saveDirectory(directory)
        // A merged-reading session left the directory-level record at
        // chapter 2 — the boardDefault scope would resume there, but the
        // archive page's single-thread scope must not.
        _ = try await readingProgressStore.saveMangaTitle(
            cleanBookName: directory.cleanBookName,
            chapterThreadID: "4002",
            chapterTitle: "第二话",
            pageIndex: 7,
            mangaID: directory.favoriteIdentity
        )
        _ = try await readingProgressStore.saveMangaThread(MangaProgressReadingPosition(
            chapterThreadID: "4001",
            chapterTitle: "第一话",
            pageIndex: 3
        ))

        var document = FavoriteLibraryDocument()
        // fid "30" is on by default (smart-comic-mode design decision #1).
        let item = try FavoriteItem(
            target: .mangaThread(threadID: "4001"),
            title: "归档页漫画 第一话",
            sourceGroup: .forumBoard(id: "30", label: "中文百合漫画区"),
            forumID: "30",
            forumName: "中文百合漫画区",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: mangaDirectoryStore
        )
        let opened = try await resolver.openTarget(for: item, mangaScope: .singleThread)

        guard case let .mangaReader(context)? = opened else {
            return XCTFail("Expected a manga reader open target")
        }
        XCTAssertEqual(context.originalThreadID, "4001")
        XCTAssertEqual(context.chapterTID, "4001")
        XCTAssertEqual(context.initialPage, 3)
        XCTAssertNil(context.directoryName)
        XCTAssertFalse(context.isSmartModeEnabled)
    }

    // Same single-thread scope, launched from the context menu's "从头阅读"
    // (`.start`): opens the member's own thread at page 0 with Smart Comic
    // Mode off, never the merged directory.
    func testMangaThreadOpenTargetWithSingleThreadScopeStartsOwnThreadFromPageZero() async throws {
        let suiteName = YamiboTestDefaults.suiteName(prefix: "local-favorites-open-target-manga-single-thread-start")
        _ = try YamiboTestDefaults.make(suiteName: suiteName)
        let localFavoriteLibraryStore = FavoriteLibraryStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "local-favorites"
        )
        let readingProgressStore = ReadingProgressStore(
            defaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
            key: "reading-progress"
        )
        var document = FavoriteLibraryDocument()
        let item = try FavoriteItem(
            target: .mangaThread(threadID: "4101"),
            title: "归档页漫画 第一话",
            sourceGroup: .forumBoard(id: "30", label: "中文百合漫画区"),
            forumID: "30",
            forumName: "中文百合漫画区",
            locations: [.category(document.defaultCategory.id)]
        )
        document.addItem(item)
        try await localFavoriteLibraryStore.save(document)

        let resolver = LocalFavoriteOpenTargetResolver(
            libraryStore: localFavoriteLibraryStore,
            readingProgressStore: readingProgressStore,
            mangaDirectoryStore: try makeMangaDirectoryStore(suiteName: suiteName)
        )
        let opened = try await resolver.openTarget(for: item, mode: .start, mangaScope: .singleThread)

        guard case let .mangaReader(context)? = opened else {
            return XCTFail("Expected a manga reader open target")
        }
        XCTAssertEqual(context.chapterTID, "4101")
        XCTAssertEqual(context.initialPage, 0)
        XCTAssertNil(context.directoryName)
        XCTAssertFalse(context.isSmartModeEnabled)
    }

    private func makeMangaDirectoryStore(suiteName: String) throws -> MangaDirectoryStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-favorite-open-target-resolver-tests", isDirectory: true)
            .appendingPathComponent(suiteName, isDirectory: true)
        let database = try YamiboDatabase.openPool(rootDirectory: root)
        return MangaDirectoryStore(databasePool: database)
    }
}
