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
    let contentUpdatedAt = Date(timeIntervalSince1970: 521)
    let directory = MangaDirectory(
        cleanBookName: "Directory Title",
        strategy: .links,
        sourceKey: "source",
        chapters: [
            MangaChapter(tid: "520", rawTitle: "第1话", chapterNumber: 1, url: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=520"))),
            MangaChapter(tid: "521", rawTitle: "第2话", chapterNumber: 2, url: chapterURL)
        ],
        lastUpdatedAt: contentUpdatedAt
    )
    var document = FavoriteLibraryDocument()

    let item = try document.importMangaChapterFavorite(
        chapterTID: "521",
        chapterURL: chapterURL,
        chapterTitle: "第2话",
        directories: [directory],
        fallbackCleanBookName: "Fallback Title"
    )

    #expect(item.target == FavoriteContentTarget(mangaID: "links:source", mangaCleanBookName: "Directory Title"))
    #expect(item.sourceGroup == .mangaTitle(mangaID: "links:source", cleanBookName: "Directory Title"))
    #expect(item.mangaChapterMetadata?.chapterTID == "521")
    #expect(item.mangaChapterMetadata?.chapterURL == chapterURL)
    #expect(item.mangaChapterMetadata?.chapterTitle == "第2话")
    #expect(item.contentUpdatedAt == contentUpdatedAt)
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

    #expect(item.target == FavoriteContentTarget(mangaID: "chapter:522", mangaCleanBookName: "Probed Title"))
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

    #expect(imported.target == FavoriteContentTarget(mangaID: "chapter:523", mangaCleanBookName: "Manga Title Extra"))
    #expect(document.items.map(\.target).contains(FavoriteContentTarget(mangaCleanBookName: "Manga Title")))
    #expect(document.items.count == 2)
}

@Test func mangaChapterFavoriteImportRetargetsChapterFallbackWhenDirectoryAppears() throws {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=526"))
    let directory = MangaDirectory(
        cleanBookName: "Stable Title",
        strategy: .links,
        sourceKey: "first-post-9001",
        chapters: [
            MangaChapter(tid: "526", rawTitle: "第6话", chapterNumber: 6, url: chapterURL)
        ]
    )
    var document = FavoriteLibraryDocument()
    let remoteMapping = FavoriteRemoteMapping(yamiboFavoriteID: "remote-526", yamiboRemoteOrder: 2)

    let fallback = try document.importMangaChapterFavorite(
        chapterTID: "526",
        chapterURL: chapterURL,
        directories: [],
        fallbackCleanBookName: "Stable Title",
        remoteMapping: remoteMapping
    )
    let stable = try document.importMangaChapterFavorite(
        chapterTID: "526",
        chapterURL: chapterURL,
        directories: [directory],
        fallbackCleanBookName: "Stable Title"
    )

    #expect(fallback.target == FavoriteContentTarget(mangaID: "chapter:526", mangaCleanBookName: "Stable Title"))
    #expect(stable.target == FavoriteContentTarget(mangaID: "links:first-post-9001", mangaCleanBookName: "Stable Title"))
    #expect(document.items.count == 1)
    #expect(document.items.first?.remoteMapping?.yamiboFavoriteID == "remote-526")
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

@Test func mangaDirectoryRenameUpdatesMangaTitleDisplayNameWithoutChangingStableIdentity() throws {
    var document = FavoriteLibraryDocument()
    let oldTarget = FavoriteContentTarget(mangaCleanBookName: "Old Title")
    _ = try document.addMangaTitleFavorite(cleanBookName: "Old Title")

    document.renameMangaTitle(from: "Old Title", to: "New Title")

    let item = try #require(document.items.first)
    #expect(item.target.id == oldTarget.id)
    #expect(item.target.mangaCleanBookName == "New Title")
    #expect(item.title == "New Title")
    #expect(item.sourceGroup == .mangaTitle(mangaID: "Old Title", cleanBookName: "New Title"))
}

@Test func mangaDirectoryRenameMigratesReadingProgressMangaTitleKey() async throws {
    let suite = try #require(UserDefaults(suiteName: "FavoriteMangaItemPathTests.\(UUID().uuidString)"))
    let store = ReadingProgressStore(defaults: suite, key: "progress")
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

@Test func mangaDirectoryRenameUpdatesStableReadingProgressDisplayNameInPlace() async throws {
    let suite = try #require(UserDefaults(suiteName: "FavoriteMangaStableProgressTests.\(UUID().uuidString)"))
    let store = ReadingProgressStore(defaults: suite, key: "progress")
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=526"))
    let target = FavoriteContentTarget(mangaID: "links:source", mangaCleanBookName: "Old Title")

    _ = try await store.saveMangaTitle(
        cleanBookName: "Old Title",
        chapterURL: chapterURL,
        chapterTitle: "第6话",
        pageIndex: 5,
        mangaID: "links:source"
    )
    try await store.migrateMangaTitleKey(from: "Old Title", to: "New Title")

    let oldDisplayTargetRecord = await store.load(for: target)
    let renamedTarget = FavoriteContentTarget(mangaID: "links:source", mangaCleanBookName: "New Title")
    let renamedRecord = await store.load(for: renamedTarget)
    #expect(oldDisplayTargetRecord?.contentTarget?.mangaCleanBookName == "New Title")
    #expect(renamedRecord?.manga?.lastMangaURL == chapterURL)
    #expect(renamedRecord?.manga?.mangaPageIndex == 5)
}

@Test func mangaReadingProgressRetargetsChapterFallbackWhenDirectoryIdentityAppears() async throws {
    let suite = try #require(UserDefaults(suiteName: "FavoriteMangaProgressRetargetTests.\(UUID().uuidString)"))
    let store = ReadingProgressStore(defaults: suite, key: "progress")
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=527"))

    _ = try await store.saveMangaTitle(
        cleanBookName: "Stable Title",
        chapterURL: chapterURL,
        chapterTitle: "第7话",
        pageIndex: 1,
        mangaID: "chapter:527"
    )
    _ = try await store.saveMangaTitle(
        cleanBookName: "Stable Title",
        chapterURL: chapterURL,
        chapterTitle: "第7话",
        pageIndex: 2,
        mangaID: "links:first-post-9001"
    )

    let chapterRecord = await store.load(for: FavoriteContentTarget(mangaID: "chapter:527", mangaCleanBookName: "Stable Title"))
    let stableRecord = await store.load(for: FavoriteContentTarget(mangaID: "links:first-post-9001", mangaCleanBookName: "Stable Title"))
    #expect(chapterRecord == nil)
    #expect(stableRecord?.manga?.mangaPageIndex == 2)
}
