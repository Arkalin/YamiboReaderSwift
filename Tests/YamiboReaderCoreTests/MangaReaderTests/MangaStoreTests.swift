import Foundation
@preconcurrency import GRDB
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: GRDB Manga Stores")
struct MangaReaderTestsGRDBMangaStores {
    @Test func directorySaveLoadAndContainingTidUseStructuredRows() async throws {
        let database = try YamiboDatabase.openPool(rootDirectory: makeGRDBMangaStoreRoot())
        let store = GRDBMangaDirectoryStore(databasePool: database)
        let firstUpdate = Date(timeIntervalSince1970: 1_800)
        let secondUpdate = Date(timeIntervalSince1970: 2_400)

        try await store.saveDirectory(MangaDirectory(
            cleanBookName: "第一本",
            strategy: .links,
            sourceKey: "chapter:900",
            chapters: [
                makeChapter(tid: "900", title: "第1话", order: 1),
                makeChapter(tid: "901", title: "第2话", order: 2),
            ],
            lastUpdatedAt: firstUpdate
        ))
        try await store.saveDirectory(MangaDirectory(
            cleanBookName: "第一本",
            strategy: .links,
            sourceKey: "chapter:900",
            chapters: [
                makeChapter(tid: "901", title: "第2话", order: 2),
                makeChapter(tid: "902", title: "第3话", order: 3),
            ],
            lastUpdatedAt: secondUpdate,
            searchKeyword: "第一本"
        ))

        let loaded = try #require(try await store.directory(named: "第一本"))
        #expect(loaded.cleanBookName == "第一本")
        #expect(loaded.strategy == .links)
        #expect(loaded.sourceKey == "chapter:900")
        #expect(loaded.lastUpdatedAt == secondUpdate)
        #expect(loaded.searchKeyword == "第一本")
        #expect(loaded.chapters.map(\.tid) == ["901", "902"])
        #expect(loaded.chapters.map(\.rawTitle) == ["第2话", "第3话"])
        #expect(loaded.chapters.map { $0.url.absoluteString } == [
            "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=901",
            "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=902",
        ])

        let containing = try #require(try await store.directory(containingTID: "902"))
        #expect(containing.cleanBookName == "第一本")

        let databaseState = try await database.read { db in
            (
                directoryChapterColumns: try columnNames(table: "manga_directory_chapters", in: db),
                tidIndexColumns: try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info('manga_directory_chapters_tid_idx')"),
                persistedTextValues: try String.fetchAll(
                    db,
                    sql: """
                    SELECT clean_book_name FROM manga_directories
                    UNION ALL
                    SELECT source_key FROM manga_directories
                    UNION ALL
                    SELECT raw_title FROM manga_directory_chapters
                    """
                )
            )
        }
        #expect(databaseState.directoryChapterColumns == [
            "directory_name",
            "tid",
            "raw_title",
            "chapter_number",
            "author_uid",
            "author_name",
            "group_index",
            "publish_time",
            "manual_order",
        ])
        #expect(databaseState.tidIndexColumns == ["tid"])
        #expect(databaseState.persistedTextValues.allSatisfy { !$0.contains("forum.php") })
    }

    @Test func directoryRenameReplacesIdentityInOneStoreOperation() async throws {
        let database = try YamiboDatabase.openPool(rootDirectory: makeGRDBMangaStoreRoot())
        let store = GRDBMangaDirectoryStore(databasePool: database)

        try await store.saveDirectory(MangaDirectory(
            cleanBookName: "旧书名",
            strategy: .links,
            sourceKey: "chapter:910",
            chapters: [makeChapter(tid: "910", title: "第1话", order: 1)]
        ))

        try await store.renameDirectory(
            from: "旧书名",
            to: MangaDirectory(
                cleanBookName: "新书名",
                strategy: .links,
                sourceKey: "chapter:910",
                chapters: [
                    makeChapter(tid: "910", title: "第1话", order: 1),
                    makeChapter(tid: "911", title: "第2话", order: 2),
                ]
            )
        )

        #expect(try await store.directory(named: "旧书名") == nil)
        let renamed = try #require(try await store.directory(named: "新书名"))
        #expect(renamed.chapters.map(\.tid) == ["910", "911"])
        #expect(try await store.directory(containingTID: "911")?.cleanBookName == "新书名")
    }

    @Test func directoryRenameUpdatesRelatedStructuredMetadataTransactionally() async throws {
        let database = try YamiboDatabase.openPool(rootDirectory: makeGRDBMangaStoreRoot())
        let directoryStore = GRDBMangaDirectoryStore(databasePool: database)
        let favoriteDefaults = try #require(UserDefaults(suiteName: "GRDBMangaStoreFavorites.\(UUID().uuidString)"))
        let progressDefaults = try #require(UserDefaults(suiteName: "GRDBMangaStoreProgress.\(UUID().uuidString)"))
        let favoriteStore = LocalFirstFavoriteLibraryStore(defaults: favoriteDefaults, key: "favorites", databasePool: database)
        let progressStore = ReadingProgressStore(defaults: progressDefaults, key: "progress", databasePool: database)
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=912&page=4&mobile=2"))

        var favorites = FavoriteLibraryDocument()
        _ = try favorites.addMangaTitleFavorite(cleanBookName: "旧书名")
        try await favoriteStore.save(favorites)
        _ = try await progressStore.saveMangaTitle(
            cleanBookName: "旧书名",
            chapterURL: chapterURL,
            chapterTitle: "第3话",
            pageIndex: 6
        )
        try await directoryStore.saveDirectory(MangaDirectory(
            cleanBookName: "旧书名",
            strategy: .links,
            sourceKey: "旧书名",
            chapters: [makeChapter(tid: "912", title: "第3话", order: 3)]
        ))

        try await directoryStore.renameDirectory(
            from: "旧书名",
            to: MangaDirectory(
                cleanBookName: "新书名",
                strategy: .links,
                sourceKey: "旧书名",
                chapters: [makeChapter(tid: "912", title: "第3话", order: 3)]
            )
        )

        let favorite = try #require(await favoriteStore.load().items.first)
        #expect(favorite.target == FavoriteContentTarget(mangaID: "旧书名", mangaCleanBookName: "新书名"))
        #expect(favorite.title == "新书名")
        #expect(favorite.sourceGroup == .mangaTitle(mangaID: "旧书名", cleanBookName: "新书名"))
        #expect(await progressStore.load(for: FavoriteContentTarget(mangaCleanBookName: "旧书名")) == nil)
        let progress = await progressStore.load(for: FavoriteContentTarget(mangaCleanBookName: "新书名"))
        #expect(progress?.manga?.mangaPageIndex == 6)
        #expect(progress?.manga?.chapterThreadID == "912")
    }

    @Test func chapterDocumentSaveLoadPreservesOrderedImageURLsByTid() async throws {
        let database = try YamiboDatabase.openPool(rootDirectory: makeGRDBMangaStoreRoot())
        let store = GRDBMangaChapterDocumentStore(databasePool: database)
        let boundaryURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=920&page=5&authorid=42"))
        let variantURL = try #require(URL(string: "https://bbs.yamibo.com/thread-920-2-1.html"))
        let firstImages = try [
            #require(URL(string: "https://img.example.com/920-1.jpg")),
            #require(URL(string: "https://img.example.com/920-2.jpg")),
        ]
        let updatedImages = try [
            #require(URL(string: "https://img.example.com/920-a.jpg")),
            #require(URL(string: "https://cdn.example.net/920-b.png")),
            #require(URL(string: "https://img.example.com/920-c.webp")),
        ]

        try await store.save(MangaChapterDocument(
            tid: " ",
            ownerPostID: " 8001 ",
            chapterTitle: "第5话",
            chapterURL: boundaryURL,
            imageURLs: firstImages
        ), for: boundaryURL)
        try await store.save(MangaChapterDocument(
            tid: "920",
            ownerPostID: "8002",
            chapterTitle: "第5话 修订",
            chapterURL: variantURL,
            imageURLs: updatedImages
        ))

        let loadedByTID = try #require(await store.document(forTID: "920"))
        let loadedByURL = try #require(await store.document(for: variantURL))

        #expect(loadedByTID == loadedByURL)
        #expect(loadedByTID.tid == "920")
        #expect(loadedByTID.ownerPostID == "8002")
        #expect(loadedByTID.chapterTitle == "第5话 修订")
        #expect(loadedByTID.chapterURL.absoluteString == "https://bbs.yamibo.com/forum.php?mobile=2&mod=viewthread&page=1&tid=920")
        #expect(loadedByTID.imageURLs == updatedImages)

        let databaseState = try await database.read { db in
            (
                documentColumns: try columnNames(table: "manga_chapter_documents", in: db),
                imageColumns: try columnNames(table: "manga_chapter_document_images", in: db),
                imageRows: try String.fetchAll(
                    db,
                    sql: """
                    SELECT image_url
                    FROM manga_chapter_document_images
                    WHERE tid = ?
                    ORDER BY manual_order ASC
                    """,
                    arguments: ["920"]
                )
            )
        }
        #expect(databaseState.documentColumns == ["tid", "owner_post_id", "chapter_title"])
        #expect(databaseState.imageColumns == ["tid", "manual_order", "image_url"])
        #expect(databaseState.imageRows == updatedImages.map(\.absoluteString))
    }

    @Test func appContextDefaultsUseGRDBMangaDirectoryAndDocumentStores() {
        let appContext = YamiboAppContext()

        #expect(appContext.mangaDirectoryStore is GRDBMangaDirectoryStore)
        #expect(appContext.mangaChapterDocumentStore is GRDBMangaChapterDocumentStore)
    }

    @Test func readerResumeRoutePersistsMangaNativeContextByTidWithoutThreadURLs() async throws {
        let suiteName = "GRDBMangaRouteNative.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = ReaderResumeRouteStore(defaults: defaults, key: "resume")
        let originalURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=930&mobile=2"))
        let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=931&page=8&mobile=2"))
        let route = ReaderResumeRoute.manga(.native(MangaLaunchContext(
            originalThreadURL: originalURL,
            chapterURL: chapterURL,
            displayTitle: "测试漫画",
            source: .resume,
            initialPage: 4,
            directoryName: "测试漫画",
            offlineCacheFavoriteID: "favorite-1"
        )))

        try await store.save(route)

        let data = try #require(defaults.data(forKey: "resume"))
        let payload = try #require(String(data: data, encoding: .utf8))
        #expect(!payload.contains("forum.php"))
        #expect(!payload.contains("chapterURL"))
        #expect(!payload.contains("originalThreadURL"))
        #expect(payload.contains(#""chapterTID":"931""#))
        #expect(payload.contains(#""originalThreadID":"930""#))
        let loaded = try #require(await store.load())
        #expect(loaded == .manga(.native(MangaLaunchContext(
            originalThreadURL: try #require(YamiboRoute.chapterURL(forTID: "930")),
            chapterURL: try #require(YamiboRoute.chapterURL(forTID: "931")),
            displayTitle: "测试漫画",
            source: .resume,
            initialPage: 4,
            directoryName: "测试漫画",
            offlineCacheFavoriteID: "favorite-1"
        ))))
    }

    @Test func readerResumeRoutePersistsMangaWebContextByTidWithoutThreadURLs() async throws {
        let suiteName = "GRDBMangaRouteWeb.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = ReaderResumeRouteStore(defaults: defaults, key: "resume")
        let currentURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=941&page=3&mobile=2"))
        let originalURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=940&mobile=2"))
        let route = ReaderResumeRoute.manga(.web(MangaWebContext(
            currentURL: currentURL,
            originalThreadURL: originalURL,
            source: .forum,
            initialPage: 2,
            autoOpenNative: true,
            waitingForNativeReturn: true
        )))

        try await store.save(route)

        let data = try #require(defaults.data(forKey: "resume"))
        let payload = try #require(String(data: data, encoding: .utf8))
        #expect(!payload.contains("forum.php"))
        #expect(!payload.contains("currentURL"))
        #expect(!payload.contains("originalThreadURL"))
        #expect(payload.contains(#""currentTID":"941""#))
        #expect(payload.contains(#""originalThreadID":"940""#))
        let loaded = try #require(await store.load())
        #expect(loaded == .manga(.web(MangaWebContext(
            currentURL: YamiboRoute.threadByID(tid: "941", page: 3, authorID: nil, reverse: false).url,
            originalThreadURL: YamiboRoute.threadByID(tid: "940", page: 1, authorID: nil, reverse: false).url,
            source: .forum,
            initialPage: 2,
            autoOpenNative: true,
            waitingForNativeReturn: true
        ))))
    }
}

private func makeGRDBMangaStoreRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private func makeChapter(tid: String, title: String, order: Double) -> MangaChapter {
    MangaChapter(
        tid: tid,
        rawTitle: title,
        chapterNumber: order,
        url: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=\(tid)&page=7&authorid=42&mobile=2")!,
        authorUID: "77",
        authorName: "作者甲",
        groupIndex: Int(order),
        publishTime: Date(timeIntervalSince1970: 1_000 + order)
    )
}

private func columnNames(table: String, in db: Database) throws -> [String] {
    try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { row in
        let name: String = row["name"]
        return name
    }
}
