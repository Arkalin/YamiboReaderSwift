import Foundation
import Testing
@testable import YamiboReaderCore

@Test func localFavoriteProjectionFiltersBySourceGroupForThreadNovelMangaAndUnknown() throws {
    let (document, items) = try makeProjectionDocument()

    let forumCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sourceGroupFilter: .group(.forumBoard(id: "fid-1", label: "版块A")))
    )
    let mangaCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sourceGroupFilter: .group(.mangaTitle(cleanBookName: "漫画A")))
    )
    let unknownCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sourceGroupFilter: .group(.unknown))
    )

    #expect(Set(forumCards.map(\.id)) == [items.normal.id, items.novel.id])
    #expect(mangaCards.map(\.id) == [items.manga.id])
    #expect(unknownCards.map(\.id) == [items.unknown.id])
}

@Test func localFavoriteProjectionSortsForumGroupsByExplicitForumName() throws {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let first = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "711"),
        title: "第一条",
        sourceGroup: .forumBoard(id: "10", label: "旧标签Z"),
        forumName: "版块A",
        locations: [.category(categoryID)]
    )
    let second = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "712"),
        title: "第二条",
        sourceGroup: .forumBoard(id: "20", label: "旧标签A"),
        forumName: "版块B",
        locations: [.category(categoryID)]
    )
    document.addItem(second)
    document.addItem(first)

    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sortOrder: .sourceGroup)
    )

    #expect(cards.map(\.id) == [first.id, second.id])
    #expect(cards.map(\.item.forumName) == ["版块A", "版块B"])
}

@Test func localFavoriteProjectionMatchesForumSourceFilterByForumID() throws {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let current = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "713"),
        title: "当前版名",
        sourceGroup: .forumBoard(id: "30", label: "新版名"),
        locations: [.category(categoryID)]
    )
    let legacy = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "714"),
        title: "旧版名",
        sourceGroup: .forumBoard(id: "30", label: "旧版名"),
        locations: [.category(categoryID)]
    )
    document.addItem(current)
    document.addItem(legacy)

    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sourceGroupFilter: .group(.forumBoard(id: "30", label: "新版名")))
    )

    #expect(Set(cards.map(\.id)) == [current.id, legacy.id])
}

@Test func localFavoriteProjectionSearchesAllowedFieldsOnly() throws {
    let (document, items) = try makeProjectionDocument()

    let displayName = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(searchText: "本地名"))
    let title = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(searchText: "小说"))
    let sourceGroup = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(searchText: "版块A"))
    let collection = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(searchText: "合集A"))
    let rawURL = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(searchText: "tid=701"))
    let remoteID = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(searchText: "remote-701"))

    #expect(displayName.map(\.id) == [items.normal.id])
    #expect(title.map(\.id) == [items.novel.id])
    #expect(Set(sourceGroup.map(\.id)) == [items.normal.id, items.novel.id])
    #expect(collection.isEmpty)
    #expect(rawURL.isEmpty)
    #expect(remoteID.isEmpty)
}

@Test func localFavoriteProjectionSupportsExpectedSortModesWithoutProgressSort() throws {
    let (document, items) = try makeProjectionDocument()
    let progress = [
        ReadingProgressRecord(
            contentTarget: items.normal.target,
            threadID: "701",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 10),
            lastReadAt: Date(timeIntervalSince1970: 30),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 30)
        ),
        ReadingProgressRecord(
            contentTarget: items.novel.target,
            threadID: "702",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 20),
            lastReadAt: Date(timeIntervalSince1970: 20),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 80)
        )
    ]

    #expect(LocalFavoriteLibraryProjection.supportedSortOrders == [.organization, .contentUpdatedAt, .yamiboRemoteOrder, .displayTitle, .sourceGroup, .lastReadAt])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .organization)).map(\.id).prefix(2) == [items.novel.id, items.normal.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .contentUpdatedAt)).map(\.id).prefix(3) == [items.manga.id, items.novel.id, items.normal.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .yamiboRemoteOrder)).map(\.id).prefix(2) == [items.novel.id, items.normal.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .displayTitle, sortsDescending: true)).map(\.id).first == items.novel.id)
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt), readingProgress: progress).map(\.id).prefix(2) == [items.normal.id, items.novel.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt, sortsDescending: true), readingProgress: progress).map(\.id).suffix(2) == [items.novel.id, items.normal.id])
}

@Test func localFavoriteProjectionBuildsCardMetadataFromReadingProgressWithoutMutatingItems() throws {
    let (document, items) = try makeProjectionDocument()
    let mangaProgress = ReadingProgressRecord(
        contentTarget: items.manga.target,
        threadID: "703",
        kind: .manga,
        updatedAt: Date(timeIntervalSince1970: 50),
        lastReadAt: Date(timeIntervalSince1970: 60),
        manga: MangaReadingProgressRecord(
            lastMangaURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703")),
            lastChapter: "第3话",
            mangaPageIndex: 4,
            mangaPageCount: 10
        )
    )

    let cards = LocalFavoriteLibraryProjection.cards(in: document, readingProgress: [mangaProgress])
    let mangaCard = try #require(cards.first { $0.id == items.manga.id })

    #expect(mangaCard.recentReadingAt == Date(timeIntervalSince1970: 60))
    #expect(mangaCard.lastUpdatedAt == Date(timeIntervalSince1970: 300))
    #expect(mangaCard.progressPercent == 50)
    #expect(mangaCard.chapterPageProgress == L10n.string("favorites.progress.manga_page_total", "第3话", 5, 10))
    #expect(mangaCard.chapterPageProgress != nil)
    #expect(mangaCard.coverURL == items.manga.coverURL)
    #expect(document.items.first { $0.id == items.manga.id }?.mangaChapterMetadata == items.manga.mangaChapterMetadata)
}

private func makeProjectionDocument() throws -> (FavoriteLibraryDocument, ProjectionItems) {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let collection = document.createCollection(categoryID: categoryID, name: "合集A")
    let coverURL = try #require(URL(string: "https://img.example.test/manga.jpg"))
    let normal = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "701"),
        title: "普通主题",
        displayName: "本地名",
        sourceGroup: .forumBoard(id: "fid-1", label: "版块A"),
        contentUpdatedAt: Date(timeIntervalSince1970: 100),
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-701", yamiboRemoteOrder: 2),
        locations: [.category(categoryID), .collection(categoryID: categoryID, collectionID: collection.id)],
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let novel = try FavoriteItem(
        target: FavoriteContentTarget(kind: .novelThread, threadID: "702"),
        title: "小说主题",
        sourceGroup: .forumBoard(id: "fid-1", label: "版块A"),
        contentUpdatedAt: Date(timeIntervalSince1970: 200),
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-702", yamiboRemoteOrder: 1),
        locations: [.category(categoryID)],
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let manga = try FavoriteItem(
        target: FavoriteContentTarget(mangaCleanBookName: "漫画A"),
        title: "漫画A",
        sourceGroup: .mangaTitle(cleanBookName: "漫画A"),
        coverURL: coverURL,
        contentUpdatedAt: Date(timeIntervalSince1970: 300),
        mangaChapterMetadata: FavoriteMangaChapterMetadata(
            chapterTID: "703",
            chapterURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=703"))
        ),
        locations: [.category(categoryID)],
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let unknown = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "704"),
        title: "未知来源",
        sourceGroup: .unknown,
        locations: [.category(categoryID)],
        updatedAt: Date(timeIntervalSince1970: 40)
    )
    document.addItem(normal)
    document.addItem(novel)
    document.addItem(manga)
    document.addItem(unknown)
    return (document, ProjectionItems(normal: normal, novel: novel, manga: manga, unknown: unknown))
}

private struct ProjectionItems {
    var normal: FavoriteItem
    var novel: FavoriteItem
    var manga: FavoriteItem
    var unknown: FavoriteItem
}
