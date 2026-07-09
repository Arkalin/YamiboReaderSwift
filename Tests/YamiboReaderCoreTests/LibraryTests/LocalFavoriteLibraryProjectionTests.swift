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
        target: FavoriteItemTarget(kind: .normalThread, threadID: "711"),
        title: "第一条",
        sourceGroup: .forumBoard(id: "10", label: "旧标签Z"),
        forumName: "版块A",
        locations: [.category(categoryID)]
    )
    let second = try FavoriteItem(
        target: FavoriteItemTarget(kind: .normalThread, threadID: "712"),
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
        target: FavoriteItemTarget(kind: .normalThread, threadID: "713"),
        title: "当前版名",
        sourceGroup: .forumBoard(id: "30", label: "新版名"),
        locations: [.category(categoryID)]
    )
    let legacy = try FavoriteItem(
        target: FavoriteItemTarget(kind: .normalThread, threadID: "714"),
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
    // `items.normal.target`/`items.novel.target` are `FavoriteItemTarget`
    // values now (favorites-side type); `ReadingProgressRecord.contentTarget`
    // is the separate reading-progress-side `FavoriteContentTarget` type
    // (smart-comic-mode design decision #9's second correction), so these
    // are rebuilt directly rather than reused — the id format is identical
    // for `.normalThread`/`.novelThread` on both types.
    let progress = [
        ReadingProgressRecord(
            contentTarget: .normalThread(threadID: "701"),
            threadID: "701",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 10),
            lastReadAt: Date(timeIntervalSince1970: 30),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 30)
        ),
        ReadingProgressRecord(
            contentTarget: .novelThread(threadID: "702"),
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
    // Undated items (manga/unknown, no progress record) stay last even in
    // descending order; the two read items keep the correct most-recent-first
    // relative order (normal@30 before novel@20) at the front.
    #expect(LocalFavoriteLibraryProjection.cards(in: document, query: LocalFavoriteLibraryQuery(sortOrder: .lastReadAt, sortsDescending: true), readingProgress: progress).map(\.id).prefix(2) == [items.normal.id, items.novel.id])
}

@Test func localFavoriteProjectionBuildsCardMetadataFromReadingProgressWithoutMutatingItems() throws {
    let (document, items) = try makeProjectionDocument()
    // `.mangaThread(threadID:)` is deliberately formatted with the same id
    // on both the favorites-side `FavoriteItemTarget` (items.manga.target)
    // and this reading-progress-side `FavoriteContentTarget`, so the direct
    // id lookup (`progressKey(for:)`) finds this record without any
    // cleanBookName fallback (smart-comic-mode design decision #15).
    let mangaProgress = ReadingProgressRecord(
        contentTarget: .mangaThread(threadID: "703"),
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
}

@Test func localFavoriteProjectionMergesModeOnMangaThreadFavoritesSharingADirectory() throws {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let collection = document.createCollection(categoryID: categoryID, name: "追番")

    let directory = MangaDirectory(
        cleanBookName: "测试漫画",
        strategy: .links,
        sourceKey: "chapter:801",
        chapters: [
            MangaChapter(tid: "801", rawTitle: "第1话", chapterNumber: 1),
            MangaChapter(tid: "802", rawTitle: "第2话", chapterNumber: 2),
        ]
    )

    let firstChapterFavorite = try FavoriteItem(
        target: .mangaThread(threadID: "801"),
        title: "第1话",
        forumID: "30",
        locations: [.category(categoryID)]
    )
    let secondChapterFavorite = try FavoriteItem(
        target: .mangaThread(threadID: "802"),
        title: "第2话",
        forumID: "30",
        locations: [.collection(categoryID: categoryID, collectionID: collection.id)]
    )
    document.addItem(firstChapterFavorite)
    document.addItem(secondChapterFavorite)

    let mangaDirectoriesByTID = ["801": directory, "802": directory]
    // Board 30 is mode-on by `SmartComicModeSettings`'s own default.
    let settings = SmartComicModeSettings()

    let categoryCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(categoryID: categoryID),
        mangaDirectoriesByTID: mangaDirectoriesByTID,
        smartComicModeSettings: settings
    )
    // Decision #5: the merged card appears in the category view even though
    // only one of its two members has that location directly — the union.
    #expect(categoryCards.count == 1)
    let mergedCard = try #require(categoryCards.first)
    #expect(mergedCard.mangaDirectory?.cleanBookName == "测试漫画")
    #expect(mergedCard.isMergedGroup)
    #expect(mergedCard.mergedMembers?.map(\.target.threadID) == ["801", "802"])
    // Earliest chapter (801) is the representative.
    #expect(mergedCard.item.target.threadID == "801")
    // The card's id is deliberately still the representative (earliest-
    // chapter) member's own real id, not a synthetic directory-based one —
    // see `FavoriteCardProjection.id`'s doc comment for why.
    #expect(mergedCard.id == firstChapterFavorite.id)

    let collectionCards = LocalFavoriteLibraryProjection.cards(
        in: document,
        query: LocalFavoriteLibraryQuery(categoryID: categoryID, collectionID: collection.id),
        mangaDirectoriesByTID: mangaDirectoriesByTID,
        smartComicModeSettings: settings
    )
    // Same merged card also surfaces in the collection view (the other
    // member's own location) — same stable id as the category view's card.
    #expect(collectionCards.map(\.id) == [mergedCard.id])
}

@Test func localFavoriteProjectionKeepsModeOffMangaThreadFavoritesStandaloneEvenWithAResolvedDirectory() throws {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id

    let directory = MangaDirectory(
        cleanBookName: "关闭板块漫画",
        strategy: .links,
        sourceKey: "chapter:811",
        chapters: [
            MangaChapter(tid: "811", rawTitle: "第1话", chapterNumber: 1),
            MangaChapter(tid: "812", rawTitle: "第2话", chapterNumber: 2),
        ]
    )
    let first = try FavoriteItem(
        target: .mangaThread(threadID: "811"),
        title: "第1话",
        forumID: "46",
        locations: [.category(categoryID)]
    )
    let second = try FavoriteItem(
        target: .mangaThread(threadID: "812"),
        title: "第2话",
        forumID: "46",
        locations: [.category(categoryID)]
    )
    document.addItem(first)
    document.addItem(second)

    // fid 46 is off by `SmartComicModeSettings`'s own default — the
    // directory resolves locally (e.g. leftover from when the board used to
    // be on), but decision #5's addendum says mode-off favorites never merge.
    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        mangaDirectoriesByTID: ["811": directory, "812": directory],
        smartComicModeSettings: SmartComicModeSettings()
    )

    #expect(Set(cards.map(\.id)) == [first.id, second.id])
    #expect(cards.allSatisfy { $0.mangaDirectory == nil && !$0.isMergedGroup })
}

@Test func localFavoriteProjectionUsesDirectoryLevelProgressForMergedAndLoneResolvedCards() throws {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id

    let mergedDirectory = MangaDirectory(
        cleanBookName: "合并进度漫画",
        strategy: .links,
        sourceKey: "chapter:821",
        chapters: [
            MangaChapter(tid: "821", rawTitle: "第1话", chapterNumber: 1),
            MangaChapter(tid: "822", rawTitle: "第2话", chapterNumber: 2),
        ]
    )
    let firstMember = try FavoriteItem(target: .mangaThread(threadID: "821"), title: "第1话", forumID: "30", locations: [.category(categoryID)])
    let secondMember = try FavoriteItem(target: .mangaThread(threadID: "822"), title: "第2话", forumID: "30", locations: [.category(categoryID)])
    document.addItem(firstMember)
    document.addItem(secondMember)

    let loneDirectory = MangaDirectory(
        cleanBookName: "单独进度漫画",
        strategy: .links,
        sourceKey: "chapter:831",
        chapters: [MangaChapter(tid: "831", rawTitle: "第1话", chapterNumber: 1)]
    )
    let loneMember = try FavoriteItem(target: .mangaThread(threadID: "831"), title: "第1话", forumID: "30", locations: [.category(categoryID)])
    document.addItem(loneMember)

    // The merged card's own representative (821)'s per-thread progress is a
    // stale earlier page; the directory-level record is the manga's actual
    // current position and must win.
    let staleOwnThreadProgress = ReadingProgressRecord(
        contentTarget: .mangaThread(threadID: "821"),
        threadID: "821",
        kind: .manga,
        updatedAt: Date(timeIntervalSince1970: 10),
        manga: MangaReadingProgressRecord(chapterThreadID: "821", lastChapter: "第1话", mangaPageIndex: 0, mangaPageCount: 10)
    )
    let directoryLevelProgress = ReadingProgressRecord(
        contentTarget: FavoriteContentTarget(mangaID: mergedDirectory.favoriteIdentity, mangaCleanBookName: mergedDirectory.cleanBookName),
        threadID: "822",
        kind: .manga,
        updatedAt: Date(timeIntervalSince1970: 20),
        manga: MangaReadingProgressRecord(chapterThreadID: "822", lastChapter: "第2话", mangaPageIndex: 9, mangaPageCount: 10)
    )
    let loneDirectoryLevelProgress = ReadingProgressRecord(
        contentTarget: FavoriteContentTarget(mangaID: loneDirectory.favoriteIdentity, mangaCleanBookName: loneDirectory.cleanBookName),
        threadID: "831",
        kind: .manga,
        updatedAt: Date(timeIntervalSince1970: 30),
        manga: MangaReadingProgressRecord(chapterThreadID: "831", lastChapter: "第1话", mangaPageIndex: 4, mangaPageCount: 5)
    )

    let cards = LocalFavoriteLibraryProjection.cards(
        in: document,
        readingProgress: [staleOwnThreadProgress, directoryLevelProgress, loneDirectoryLevelProgress],
        mangaDirectoriesByTID: [
            "821": mergedDirectory, "822": mergedDirectory,
            "831": loneDirectory,
        ],
        smartComicModeSettings: SmartComicModeSettings()
    )

    let mergedCard = try #require(cards.first { $0.mangaDirectory?.cleanBookName == "合并进度漫画" })
    #expect(mergedCard.progressPercent == 100)
    #expect(mergedCard.chapterPageProgress == L10n.string("favorites.progress.manga_page_total", "第2话", 10, 10))

    // A lone resolved-directory favorite (no sibling yet) still prefers its
    // directory-level record over its own per-thread progress.
    let loneCard = try #require(cards.first { $0.mangaDirectory?.cleanBookName == "单独进度漫画" })
    #expect(loneCard.mergedMembers == nil)
    #expect(loneCard.progressPercent == 100)
    #expect(loneCard.chapterPageProgress == L10n.string("favorites.progress.manga_page_total", "第1话", 5, 5))
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
            contentTarget: .normalThread(threadID: "801"),
            threadID: "801",
            kind: .novel,
            updatedAt: Date(timeIntervalSince1970: 10),
            lastReadAt: Date(timeIntervalSince1970: 50),
            novel: NovelReadingProgressRecord(novelDocumentSurfaceProgressPercent: 10)
        ),
        ReadingProgressRecord(
            contentTarget: .normalThread(threadID: "802"),
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

@Test func localFavoriteMixedEntriesPutsNeverReadEntriesLastRegardlessOfSortDirection() throws {
    let (document, items, collection) = try makeMixedEntryDocument()
    // Only the first item has ever been read; the second item and the
    // collection (no collectionSummaries entry) have no read history.
    let progress = [
        ReadingProgressRecord(
            contentTarget: .normalThread(threadID: "801"),
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

    // The never-read collection and never-read card stay behind the card
    // that was actually read even in descending ("most recently read
    // first") order — switching direction no longer fast-forwards undated
    // entries to the top ahead of real read history.
    #expect(entries.map(\.id) == ["item-\(items.first.id)", "collection-\(collection.id)", "item-\(items.second.id)"])
}

private func makeMixedEntryDocument() throws -> (FavoriteLibraryDocument, MixedEntryItems, LocalFavoriteCollection) {
    var document = FavoriteLibraryDocument()
    let categoryID = document.defaultCategory.id
    let collection = document.createCollection(categoryID: categoryID, name: "条目M")
    let first = try FavoriteItem(
        target: FavoriteItemTarget(kind: .normalThread, threadID: "801"),
        title: "条目A",
        contentUpdatedAt: Date(timeIntervalSince1970: 100),
        locations: [.category(categoryID)]
    )
    let second = try FavoriteItem(
        target: FavoriteItemTarget(kind: .normalThread, threadID: "802"),
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
        target: FavoriteItemTarget(kind: .normalThread, threadID: "701"),
        title: "普通主题",
        displayName: "本地名",
        sourceGroup: .forumBoard(id: "fid-1", label: "版块A"),
        contentUpdatedAt: Date(timeIntervalSince1970: 100),
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-701", yamiboRemoteOrder: 2),
        locations: [.category(categoryID), .collection(categoryID: categoryID, collectionID: collection.id)],
        updatedAt: Date(timeIntervalSince1970: 10)
    )
    let novel = try FavoriteItem(
        target: FavoriteItemTarget(kind: .novelThread, threadID: "702"),
        title: "小说主题",
        sourceGroup: .forumBoard(id: "fid-1", label: "版块A"),
        contentUpdatedAt: Date(timeIntervalSince1970: 200),
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "remote-702", yamiboRemoteOrder: 1),
        locations: [.category(categoryID)],
        updatedAt: Date(timeIntervalSince1970: 20)
    )
    let manga = try FavoriteItem(
        target: .mangaThread(threadID: "703"),
        title: "漫画A",
        sourceGroup: .smartManga(cleanBookName: "漫画A"),
        contentUpdatedAt: Date(timeIntervalSince1970: 300),
        locations: [.category(categoryID)],
        updatedAt: Date(timeIntervalSince1970: 30)
    )
    let unknown = try FavoriteItem(
        target: FavoriteItemTarget(kind: .normalThread, threadID: "704"),
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
