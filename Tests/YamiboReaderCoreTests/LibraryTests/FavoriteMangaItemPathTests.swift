import Foundation
import Testing
@testable import YamiboReaderCore

@Test func mangaTitleFavoriteItemsCanBeAddedDisplayedAndOpened() throws {
    var document = FavoriteLibraryDocument()

    let item = try document.addMangaTitleFavorite(cleanBookName: "Clean Book", title: "漫画标题")

    #expect(item.target == FavoriteContentTarget(mangaCleanBookName: "Clean Book"))
    #expect(item.title == "漫画标题")
    #expect(item.sourceGroup == .mangaTitle(cleanBookName: "Clean Book"))
    #expect(document.openRoute(for: item) == .mangaTitle(cleanBookName: "Clean Book"))
}

@Test func mangaChapterFavoriteImportResolvesOwningTitleByDirectoryTID() throws {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=521"))
    let directory = MangaDirectory(
        cleanBookName: "Directory Title",
        strategy: .links,
        sourceKey: "source",
        chapters: [
            MangaChapter(tid: "520", rawTitle: "第1话", chapterNumber: 1, url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=520"))),
            MangaChapter(tid: "521", rawTitle: "第2话", chapterNumber: 2, url: chapterURL)
        ]
    )
    var document = FavoriteLibraryDocument()

    let item = try document.importMangaChapterFavorite(
        chapterTID: "521",
        chapterURL: chapterURL,
        chapterTitle: "第2话",
        directories: [directory],
        fallbackCleanBookName: "Fallback Title"
    )

    #expect(item.target == FavoriteContentTarget(mangaCleanBookName: "Directory Title"))
    #expect(item.mangaChapterMetadata?.chapterTID == "521")
    #expect(item.mangaChapterMetadata?.chapterURL == chapterURL)
    #expect(item.mangaChapterMetadata?.chapterTitle == "第2话")
}

@Test func mangaChapterFavoriteImportFallsBackToProbedTitleMetadata() throws {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=522"))
    var document = FavoriteLibraryDocument()

    let item = try document.importMangaChapterFavorite(
        chapterTID: "522",
        chapterURL: chapterURL,
        directories: [],
        fallbackCleanBookName: "Probed Title"
    )

    #expect(item.target == FavoriteContentTarget(mangaCleanBookName: "Probed Title"))
    #expect(item.mangaChapterMetadata?.chapterTID == "522")
}

@Test func mangaChapterFavoriteImportDoesNotFuzzyMergeTitles() throws {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=523"))
    var document = FavoriteLibraryDocument()
    _ = try document.addMangaTitleFavorite(cleanBookName: "Manga Title")

    let imported = try document.importMangaChapterFavorite(
        chapterTID: "523",
        chapterURL: chapterURL,
        directories: [],
        fallbackCleanBookName: "Manga Title Extra"
    )

    #expect(imported.target == FavoriteContentTarget(mangaCleanBookName: "Manga Title Extra"))
    #expect(document.items.map(\.target).contains(FavoriteContentTarget(mangaCleanBookName: "Manga Title")))
    #expect(document.items.count == 2)
}

@Test func deletingMangaTitleItemDoesNotDeleteImportedRemoteChapterFavoriteMetadataElsewhere() throws {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524"))
    var document = FavoriteLibraryDocument()
    let item = try document.importMangaChapterFavorite(
        chapterTID: "524",
        chapterURL: chapterURL,
        directories: [],
        fallbackCleanBookName: "Delete Test"
    )
    let metadata = try #require(item.mangaChapterMetadata)

    document.removeItem(target: item.target)

    #expect(document.items.isEmpty)
    #expect(metadata.chapterTID == "524")
    #expect(metadata.chapterURL == chapterURL)
}

@Test func mangaDirectoryRenameRetargetsMangaTitleFavoriteItem() throws {
    var document = FavoriteLibraryDocument()
    let oldTarget = FavoriteContentTarget(mangaCleanBookName: "Old Title")
    let newTarget = FavoriteContentTarget(mangaCleanBookName: "New Title")
    _ = try document.addMangaTitleFavorite(cleanBookName: "Old Title")

    document.renameMangaTitle(from: "Old Title", to: "New Title")

    #expect(!document.items.map(\.target).contains(oldTarget))
    let item = try #require(document.items.first)
    #expect(item.target == newTarget)
    #expect(item.title == "New Title")
    #expect(item.sourceGroup == .mangaTitle(cleanBookName: "New Title"))
}

@Test func mangaDirectoryRenameMigratesReadingProgressMangaTitleKey() async throws {
    let suite = try #require(UserDefaults(suiteName: "FavoriteMangaItemPathTests.\(UUID().uuidString)"))
    let store = ReadingProgressStore(defaults: suite, key: "progress", migratedFromFavoritesKey: "migrated")
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=525"))

    _ = try await store.saveMangaTitle(
        cleanBookName: "Old Title",
        chapterURL: chapterURL,
        chapterTitle: "第5话",
        pageIndex: 4
    )
    try await store.migrateMangaTitleKey(from: "Old Title", to: "New Title")

    let oldRecord = await store.load(for: FavoriteContentTarget(mangaCleanBookName: "Old Title"))
    let newRecord = await store.load(for: FavoriteContentTarget(mangaCleanBookName: "New Title"))
    #expect(oldRecord == nil)
    #expect(newRecord?.manga?.lastMangaURL == chapterURL)
    #expect(newRecord?.manga?.mangaPageIndex == 4)
}
