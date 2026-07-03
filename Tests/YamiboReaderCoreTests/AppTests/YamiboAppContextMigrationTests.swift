@preconcurrency import Foundation
import Testing
@preconcurrency import GRDB
@testable import YamiboReaderCore

@MainActor
@Test func appContextFreshStartupUsesSeededGRDBAndIgnoresLegacyJSONDefaults() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "app-context-grdb-fresh")
    let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
    let rootDirectory = makeTemporaryAppRoot()
    let legacyLibraryData = Data(#"{"items":[{"id":"legacy-library"}]}"#.utf8)
    let legacyProgressData = Data(#"{"records":[{"id":"legacy-progress"}]}"#.utf8)
    defaults.set(legacyLibraryData, forKey: "yamibo.favoriteLibrary.localFirst")
    defaults.set(legacyProgressData, forKey: "yamibo.readingProgress.records")
    let appContext = try makeIsolatedAppContext(suiteName: suiteName, rootDirectory: rootDirectory)

    let library = await appContext.localFavoriteLibraryStore.load()
    let progress = await appContext.readingProgressStore.loadAll()

    #expect(library.defaultCategory.id == FavoriteCategory.defaultID)
    #expect(library.items.isEmpty)
    #expect(progress.isEmpty)
    #expect(defaults.data(forKey: "yamibo.favoriteLibrary.localFirst") == legacyLibraryData)
    #expect(defaults.data(forKey: "yamibo.readingProgress.records") == legacyProgressData)
}

@MainActor
@Test func appContextDefaultsWriteMigratedStateToSharedGRDBRoot() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "app-context-grdb-shared")
    _ = try YamiboTestDefaults.make(suiteName: suiteName)
    let rootDirectory = makeTemporaryAppRoot()
    let appContext = try makeIsolatedAppContext(suiteName: suiteName, rootDirectory: rootDirectory)
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7001"))
    let imageURL = try #require(URL(string: "https://img.example.test/7001-1.jpg"))

    try await saveMigratedAppState(appContext: appContext, chapterURL: chapterURL, imageURL: imageURL)
    try await appContext.readerCacheStore.save(
        ReaderPageDocument(
            threadURL: chapterURL,
            view: 1,
            maxView: 1,
            segments: [.text("Reader GRDB cache", chapterTitle: nil)]
        )
    )
    try await appContext.forumCacheStore.saveThreadPage(
        ForumThreadPage(
            thread: ThreadIdentity(tid: "8001"),
            title: "GRDB thread cache",
            posts: []
        ),
        thread: ThreadIdentity(tid: "8001")
    )

    let database = try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory)
    let counts = try await database.read { db in
        [
            "favorite_items": try tableCount("favorite_items", in: db),
            "reading_progress": try tableCount("reading_progress", in: db),
            "manga_directories": try tableCount("manga_directories", in: db),
            "manga_chapter_documents": try tableCount("manga_chapter_documents", in: db),
            "manga_offline_cache_memberships": try tableCount("manga_offline_cache_memberships", in: db),
            "cache_entries": try tableCount("cache_entries", in: db),
        ]
    }

    #expect(counts["favorite_items"] == 1)
    #expect(counts["reading_progress"] == 1)
    #expect(counts["manga_directories"] == 1)
    #expect(counts["manga_chapter_documents"] == 0)
    #expect(counts["manga_offline_cache_memberships"] == 1)
    #expect(counts["cache_entries"] == 3)
    let readerCacheEntriesTableExists = try await database.read { db in
        try db.tableExists("reader_cache_entries")
    }
    #expect(!readerCacheEntriesTableExists)
    let imageDataCacheEntriesTableExists = try await database.read { db in
        try db.tableExists("image_data_cache_entries")
    }
    #expect(!imageDataCacheEntriesTableExists)
    let jsonCacheNamespaces = try await database.read { db in
        try String.fetchAll(db, sql: "SELECT namespace FROM cache_entries ORDER BY namespace")
    }
    #expect(jsonCacheNamespaces == ["forum_thread_pages", "manga_reader_projections", "novel_reader_projections"])
    #expect(!FileManager.default.fileExists(atPath: rootDirectory.appendingPathComponent("reader-cache/index.json", isDirectory: false).path))
    #expect(!FileManager.default.fileExists(atPath: rootDirectory.appendingPathComponent("image-data/index.json", isDirectory: false).path))
}

@MainActor
@Test func appContextResetClearsGRDBStateAndManagedCacheFilesWithoutDeletingLegacyJSON() async throws {
    let suiteName = YamiboTestDefaults.suiteName(prefix: "app-context-grdb-reset")
    let defaults = try YamiboTestDefaults.make(suiteName: suiteName)
    let rootDirectory = makeTemporaryAppRoot()
    let legacyLibraryData = Data(#"{"items":[{"id":"legacy-library"}]}"#.utf8)
    let legacyProgressData = Data(#"{"records":[{"id":"legacy-progress"}]}"#.utf8)
    defaults.set(legacyLibraryData, forKey: "yamibo.favoriteLibrary.localFirst")
    defaults.set(legacyProgressData, forKey: "yamibo.readingProgress.records")
    let appContext = try makeIsolatedAppContext(suiteName: suiteName, rootDirectory: rootDirectory)
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7002"))
    let imageURL = try #require(URL(string: "https://img.example.test/7002-1.jpg"))

    try await saveMigratedAppState(appContext: appContext, chapterURL: chapterURL, imageURL: imageURL)
    try await appContext.readerCacheStore.save(
        ReaderPageDocument(
            threadURL: chapterURL,
            view: 1,
            maxView: 1,
            segments: [.text("Reader reset cache", chapterTitle: nil)]
        )
    )
    try await appContext.forumCacheStore.saveHome(
        ForumHomePage(categories: [], fetchedAt: Date(timeIntervalSince1970: 100))
    )
    try await appContext.forumCacheStore.saveBoard(
        ForumBoardPage(
            board: ForumBoardSummary(
                fid: "49",
                name: "百合小说",
                url: ForumRouteResolver.boardURL(fid: "49")
            ),
            fetchedAt: Date(timeIntervalSince1970: 100)
        ),
        fid: "49"
    )
    try await appContext.forumCacheStore.saveThreadPage(
        ForumThreadPage(
            thread: ThreadIdentity(tid: "8002"),
            title: "Reset thread cache",
            posts: []
        ),
        thread: ThreadIdentity(tid: "8002")
    )
    #expect(FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("novel_reader_projections", isDirectory: true)
            .path
    ))
    #expect(FileManager.default.fileExists(atPath: rootDirectory.appendingPathComponent("manga-reader/offline-cache/images", isDirectory: true).path))
    #expect(FileManager.default.fileExists(atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory).path))
    #expect(FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("forum_home", isDirectory: true)
            .path
    ))
    #expect(FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("forum_boards", isDirectory: true)
            .path
    ))

    try await appContext.resetApplicationData()

    let database = try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory)
    let counts = try await database.read { db in
        [
            "favorite_categories": try tableCount("favorite_categories", in: db),
            "favorite_items": try tableCount("favorite_items", in: db),
            "reading_progress": try tableCount("reading_progress", in: db),
            "manga_directories": try tableCount("manga_directories", in: db),
            "manga_chapter_documents": try tableCount("manga_chapter_documents", in: db),
            "manga_offline_cache_memberships": try tableCount("manga_offline_cache_memberships", in: db),
            "manga_offline_cache_images": try tableCount("manga_offline_cache_images", in: db),
            "cache_entries": try tableCount("cache_entries", in: db),
        ]
    }

    #expect(counts["favorite_categories"] == 1)
    #expect(counts["favorite_items"] == 0)
    #expect(counts["reading_progress"] == 0)
    #expect(counts["manga_directories"] == 0)
    #expect(counts["manga_chapter_documents"] == 0)
    #expect(counts["manga_offline_cache_memberships"] == 0)
    #expect(counts["manga_offline_cache_images"] == 0)
    #expect(counts["cache_entries"] == 0)
    let readerCacheEntriesTableExists = try await database.read { db in
        try db.tableExists("reader_cache_entries")
    }
    #expect(!readerCacheEntriesTableExists)
    let imageDataCacheEntriesTableExists = try await database.read { db in
        try db.tableExists("image_data_cache_entries")
    }
    #expect(!imageDataCacheEntriesTableExists)
    #expect(!FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("novel_reader_projections", isDirectory: true)
            .path
    ))
    #expect(!FileManager.default.fileExists(atPath: rootDirectory.appendingPathComponent("manga-reader/offline-cache", isDirectory: true).path))
    #expect(!FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("forum_home", isDirectory: true)
            .path
    ))
    #expect(!FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("forum_boards", isDirectory: true)
            .path
    ))
    #expect(!FileManager.default.fileExists(
        atPath: YamiboDatabase.cacheDirectoryURL(rootDirectory: rootDirectory)
            .appendingPathComponent("forum_thread_pages", isDirectory: true)
            .path
    ))
    #expect(defaults.data(forKey: "yamibo.favoriteLibrary.localFirst") == legacyLibraryData)
    #expect(defaults.data(forKey: "yamibo.readingProgress.records") == legacyProgressData)
}

private func makeTemporaryAppRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("yamibo-app-context-grdb-\(UUID().uuidString)", isDirectory: true)
}

private func makeIsolatedAppContext(suiteName: String, rootDirectory: URL) throws -> YamiboAppContext {
    let database = try YamiboDatabase.openSharedPool(rootDirectory: rootDirectory)
    return YamiboAppContext(
        sessionStore: SessionStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "session"),
        profileStore: YamiboProfileStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "profile"),
        checkInStore: YamiboCheckInStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), keyPrefix: "check-in"),
        settingsStore: SettingsStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "settings"),
        webDAVSyncSettingsStore: WebDAVSyncSettingsStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "webdav"),
        readerResumeRouteStore: ReaderResumeRouteStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "resume-route"),
        localFavoriteLibraryStore: FavoriteLibraryStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), databasePool: database),
        favoriteUpdateStore: FavoriteUpdateStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "favorite-updates"),
        readingProgressStore: ReadingProgressStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), databasePool: database),
        contentCoverStore: ContentCoverStore(defaults: try YamiboTestDefaults.defaults(suiteName: suiteName), key: "content-covers"),
        grdbRootDirectory: rootDirectory,
        uiDefaults: try YamiboTestDefaults.defaults(suiteName: suiteName),
        clearsWebDataOnReset: false
    )
}

private func saveMigratedAppState(
    appContext: YamiboAppContext,
    chapterURL: URL,
    imageURL: URL
) async throws {
    var library = FavoriteLibraryDocument()
    let favoriteTarget = FavoriteContentTarget(kind: .novelThread, threadURL: chapterURL)
    library.addItem(
        try FavoriteItem(
            target: favoriteTarget,
            title: "Shared GRDB favorite",
            locations: [.category(library.defaultCategory.id)]
        )
    )
    try await appContext.localFavoriteLibraryStore.save(library)
    try await appContext.readingProgressStore.saveNovel(
        NovelReadingPosition(threadURL: chapterURL, view: 3)
    )
    let chapter = MangaChapter(
        tid: "7001",
        rawTitle: "第一话",
        chapterNumber: 1,
        url: chapterURL
    )
    try await appContext.mangaDirectoryStore.saveDirectory(
        MangaDirectory(
            cleanBookName: "Shared GRDB Manga",
            strategy: .links,
            sourceKey: "shared-grdb",
            chapters: [chapter]
        )
    )
    try await appContext.mangaReaderProjectionStore.save(
        MangaReaderProjection(
            tid: chapter.tid,
            chapterTitle: chapter.rawTitle,
            chapterURL: chapterURL,
            imageURLs: [imageURL]
        )
    )
    try await appContext.mangaOfflineCacheStore.saveMembership(
        MangaOfflineCacheMembership(
            ownerName: "Shared GRDB Manga",
            tid: chapter.tid,
            chapterTitle: chapter.rawTitle,
            chapterURL: chapterURL,
            imageURLs: [imageURL]
        )
    )
    try await appContext.mangaOfflineCacheStore.saveOfflineImageData(Data("offline".utf8), for: imageURL)
}

private func tableCount(_ table: String, in db: Database) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
}
