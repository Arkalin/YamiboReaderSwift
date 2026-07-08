import Foundation
import Testing
@testable import YamiboReaderCore

@Test func localFavoriteProjectionFiltersBySourceGroupForThreadNovelMangaAndUnknown() throws {
    let (document, items) = try makeProjectionDocument()

    let forumCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(selectedSourceFilters: [.forumBoard(id: "fid-1", label: "版块A")])
    )
    let mangaCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(selectedSourceFilters: [.manga])
    )
    let unknownCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(selectedSourceFilters: [.unknown])
    )
    let combinedCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(selectedSourceFilters: [
            .forumBoard(id: "fid-1", label: "版块A"),
            .manga,
        ])
    )

    #expect(Set(forumCards.map(\.id)) == [items.normal.id, items.novel.id])
    #expect(mangaCards.map(\.id) == [items.manga.id])
    #expect(unknownCards.map(\.id) == [items.unknown.id])
    #expect(Set(combinedCards.map(\.id)) == [items.normal.id, items.novel.id, items.manga.id])
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
        query: LocalFavoriteLibraryQuery(selectedSourceFilters: [.forumBoard(id: "30", label: "新版名")])
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
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .contentUpdatedAt)).map(\.id).prefix(3) == [items.normal.id, items.novel.id, items.manga.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .yamiboRemoteOrder)).map(\.id).prefix(2) == [items.novel.id, items.normal.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .displayTitle, sortsDescending: true)).map(\.id).first == items.novel.id)
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt), readingProgress: progress).map(\.id).prefix(2) == [items.novel.id, items.normal.id])
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt, sortsDescending: true), readingProgress: progress).map(\.id).suffix(2) == [items.normal.id, items.novel.id])
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
            chapterThreadID: "703",
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
    // Items carry no cover of their own; the library derivation fills card
    // covers from ContentCoverStore.
    #expect(mangaCard.coverURL == nil)
    #expect(document.items.first { $0.id == items.manga.id }?.mangaChapterMetadata == items.manga.mangaChapterMetadata)
}

@Test func localFavoriteMixedEntriesKeepsCollectionsPinnedInOrganizationOrder() throws {
    let (document, _, collection) = try makeMixedEntryDocument()
    let cards = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .organization))

    let entries = LocalFavoriteLibraryProjection.mixedEntries(
        cards: cards,
        collections: [collection],
        // A summary that would sort the collection dead last under any of
        // the auto criteria — proves organization mode ignores it entirely.
        collectionSummaries: [collection.id: FavoriteCollectionSortSummary(minRemoteOrder: 999)],
        sortOrder: .organization,
        descending: false
    )

    #expect(entries.first?.id == "collection-\(collection.id)")
    #expect(Array(entries.dropFirst()).map(\.id) == cards.map { "item-\($0.id)" })
}

@Test func localFavoriteMixedEntriesInterleavesCollectionsWithCardsOutsideOrganizationOrder() throws {
    let (document, items, collection) = try makeMixedEntryDocument()
    let cards = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .displayTitle))

    let entries = LocalFavoriteLibraryProjection.mixedEntries(
        cards: cards,
        collections: [collection],
        collectionSummaries: [:],
        sortOrder: .displayTitle,
        descending: false
    )

    // Collection name "条目M" sorts between item titles "条目A" and "条目Z" —
    // it is not pinned ahead of every card.
    #expect(entries.map(\.id) == ["item-\(items.first.id)", "collection-\(collection.id)", "item-\(items.second.id)"])
}

@Test func localFavoriteMixedEntriesUsesLatestMemberUpdateAsCollectionProxyForUpdatedAtSort() throws {
    let (document, items, collection) = try makeMixedEntryDocument()
    let cards = LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .contentUpdatedAt))

    // Collection's proxy update time sits strictly between the two cards'.
    let entries = LocalFavoriteLibraryProjection.mixedEntries(
        cards: cards,
        collections: [collection],
        collectionSummaries: [collection.id: FavoriteCollectionSortSummary(latestUpdatedAt: Date(timeIntervalSince1970: 150))],
        sortOrder: .contentUpdatedAt,
        descending: false
    )

    #expect(entries.map(\.id) == ["item-\(items.first.id)", "collection-\(collection.id)", "item-\(items.second.id)"])
}

@Test func localFavoriteMixedEntriesUsesLatestMemberReadAsCollectionProxyForLastReadAtSort() throws {
    let (document, items, collection) = try makeMixedEntryDocument()
    let progress = [
        ReadingProgressRecord(
            contentTarget: items.first.target,
            threadID: "801",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 10),
            lastReadAt: Date(timeIntervalSince1970: 50),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 10)
        ),
        ReadingProgressRecord(
            contentTarget: items.second.target,
            threadID: "802",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 20),
            lastReadAt: Date(timeIntervalSince1970: 250),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 20)
        )
    ]
    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt),
        readingProgress: progress
    )

    // Collection's proxy read time (150) sits strictly between the two
    // cards' recentReadingAt (50 and 250).
    let entries = LocalFavoriteLibraryProjection.mixedEntries(
        cards: cards,
        collections: [collection],
        collectionSummaries: [collection.id: FavoriteCollectionSortSummary(latestReadAt: Date(timeIntervalSince1970: 150))],
        sortOrder: .lastReadAt,
        descending: false
    )

    #expect(entries.map(\.id) == ["item-\(items.first.id)", "collection-\(collection.id)", "item-\(items.second.id)"])
}

@Test func localFavoriteMixedEntriesPutsNeverReadEntriesFirstWhenLastReadAtSortsDescending() throws {
    let (document, items, collection) = try makeMixedEntryDocument()
    // Only the first item has ever been read; the second item and the
    // collection (no collectionSummaries entry) have no read history.
    let progress = [
        ReadingProgressRecord(
            contentTarget: items.first.target,
            threadID: "801",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 10),
            lastReadAt: Date(timeIntervalSince1970: 50),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 10)
        )
    ]
    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt),
        readingProgress: progress
    )

    let entries = LocalFavoriteLibraryProjection.mixedEntries(
        cards: cards,
        collections: [collection],
        collectionSummaries: [:],
        sortOrder: .lastReadAt,
        descending: true
    )

    // Pins down a known, deliberately-kept quirk (see
    // favorites-collection-sort-mixing memory): undated entries sort last
    // ascending, and descending reverses the WHOLE list, so the never-read
    // collection and never-read card land ahead of the card that was
    // actually read. This is intentionally NOT "fixed" here.
    #expect(entries.map(\.id) == ["item-\(items.second.id)", "collection-\(collection.id)", "item-\(items.first.id)"])
}

private func makeMixedEntryDocument() throws -> (FavoriteLibraryDocument, MixedEntryItems, LocalFavoriteCollection) {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let collection = document.createCollection(categoryID: categoryID, name: "条目M")
    let first = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "801"),
        title: "条目A",
        contentUpdatedAt: Date(timeIntervalSince1970: 100),
        locations: [.category(categoryID)]
    )
    let second = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "802"),
        title: "条目Z",
        contentUpdatedAt: Date(timeIntervalSince1970: 200),
        locations: [.category(categoryID)]
    )
    document.addItem(first)
    document.addItem(second)
    return (document, MixedEntryItems(first: first, second: second), collection)
}

private struct MixedEntryItems {
    var first: FavoriteItem
    var second: FavoriteItem
}

private func makeProjectionDocument() throws -> (FavoriteLibraryDocument, ProjectionItems) {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let collection = document.createCollection(categoryID: categoryID, name: "合集A")
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
        contentUpdatedAt: Date(timeIntervalSince1970: 300),
        mangaChapterMetadata: FavoriteMangaChapterMetadata(
            chapterTID: "703",
            chapterView: 1
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
