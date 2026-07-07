import Foundation
import Testing
@testable import YamiboReaderCore

// MARK: - Test scaffolding

private func makeLibraryStore(function: String = #function) -> FavoriteLibraryStore {
    let suiteName = "favorite-sync-engine-\(function)-\(UUID().uuidString)"
    return FavoriteLibraryStore(
        defaults: UserDefaults(suiteName: suiteName)!,
        key: "favorites"
    )
}

private func makeSnapshot(categoryID: String, categoryName: String = "分类") -> FavoriteRemoteSyncSnapshot {
    FavoriteRemoteSyncSnapshot(
        status: .running,
        targetCategoryID: categoryID,
        targetCategoryName: categoryName,
        phase: .queued,
        logEntries: [.started(categoryName: categoryName)]
    )
}

private actor SyncCallRecorder {
    private(set) var probedThreadIDs: [String] = []
    private(set) var addedThreadIDs: [String] = []
    private(set) var fetchPageCalls = 0

    func recordProbe(_ threadID: String) { probedThreadIDs.append(threadID) }
    func recordAdd(_ threadID: String) { addedThreadIDs.append(threadID) }
    func recordFetch() -> Int {
        fetchPageCalls += 1
        return fetchPageCalls
    }
}

private func threadProbe(_ threadID: String, title: String = "标题") -> FavoriteThreadProbeResult {
    FavoriteThreadProbeResult(
        target: FavoriteContentTarget(kind: .normalThread, threadID: threadID),
        title: title,
        sourceGroup: .forumBoard(id: "fid", label: "版块")
    )
}

private func singlePageClient(
    entries: [YamiboRemoteFavoriteEntry],
    recorder: SyncCallRecorder,
    probe: @escaping @Sendable (YamiboRemoteFavoriteEntry) async throws -> FavoriteThreadProbeResult = { entry in
        threadProbe(entry.threadID, title: entry.title ?? "标题")
    }
) -> FavoriteYamiboSyncClient {
    FavoriteYamiboSyncClient(
        fetchPage: { _ in
            _ = await recorder.recordFetch()
            return FavoriteYamiboRemotePage(entries: entries, currentPage: 1, totalPages: 1)
        },
        probe: { entry in
            await recorder.recordProbe(entry.threadID)
            return try await probe(entry)
        },
        addFavorite: { threadID in
            await recorder.recordAdd(threadID)
        }
    )
}

private func runEngine(
    store: FavoriteLibraryStore,
    client: FavoriteYamiboSyncClient,
    snapshot: FavoriteRemoteSyncSnapshot
) async -> FavoriteRemoteSyncSnapshot {
    let engine = FavoriteYamiboSyncEngine(libraryStore: store, client: client)
    return await engine.run(snapshot: snapshot, persist: { _ in })
}

// MARK: - Importing

@Test func engineImportsRemoteOnlyThreadIntoTargetCategory() async throws {
    let store = makeLibraryStore()
    var document = try await store.load()
    let category = document.createCategory(name: "远端")
    try await store.save(document)

    let recorder = SyncCallRecorder()
    let client = singlePageClient(
        entries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-901", threadID: "901", title: "远端小说")],
        recorder: recorder
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: category.id))

    #expect(final.status == .completed)
    #expect(final.importedCount == 1)
    #expect(final.uploadTargetCount == 0)
    let saved = try await store.load()
    let item = try #require(saved.items.first)
    #expect(item.locations == [.category(category.id)])
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-901")
    #expect(item.remoteMapping?.yamiboRemoteOrder == 0)
    let probed = await recorder.probedThreadIDs
    #expect(probed == ["901"])
}

@Test func engineImportsMangaChapterViaProbe() async throws {
    let store = makeLibraryStore()
    let document = try await store.load()
    let categoryID = document.defaultCategory.id

    let recorder = SyncCallRecorder()
    let client = singlePageClient(
        entries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-905", threadID: "905", title: "第5话")],
        recorder: recorder,
        probe: { _ in
            FavoriteThreadProbeResult(
                target: FavoriteContentTarget(mangaCleanBookName: "漫画书名"),
                title: "第5话",
                sourceGroup: .mangaTitle(cleanBookName: "漫画书名")
            )
        }
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: categoryID))

    #expect(final.status == .completed)
    #expect(final.importedCount == 1)
    let saved = try await store.load()
    let item = try #require(saved.items.first)
    #expect(item.target == FavoriteContentTarget(mangaID: "chapter:905", mangaCleanBookName: "漫画书名"))
    #expect(item.mangaChapterMetadata?.chapterTID == "905")
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-905")
}

@Test func engineAddsCategoryLocationToExistingUnmappedItemWithoutProbe() async throws {
    let store = makeLibraryStore()
    var document = try await store.load()
    let category = document.createCategory(name: "远端")
    let existing = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "902"),
        title: "本地已有",
        locations: [.category(document.defaultCategory.id)]
    )
    document.addItem(existing)
    try await store.save(document)

    let recorder = SyncCallRecorder()
    let client = singlePageClient(
        entries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-902", threadID: "902")],
        recorder: recorder
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: category.id))

    #expect(final.status == .completed)
    #expect(final.importedCount == 1)
    #expect(final.skippedCount == 0)
    let saved = try await store.load()
    let item = try #require(saved.items.first)
    #expect(Set(item.locations) == [.category(document.defaultCategory.id), .category(category.id)])
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-902")
    let probed = await recorder.probedThreadIDs
    #expect(probed.isEmpty)
}

@Test func engineSkipsAlreadyMappedItemAndRefreshesMapping() async throws {
    let store = makeLibraryStore()
    var document = try await store.load()
    let existing = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "903"),
        title: "已映射",
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "r-old", yamiboRemoteOrder: 9),
        locations: [.category(document.defaultCategory.id)]
    )
    document.addItem(existing)
    let categoryID = document.defaultCategory.id
    try await store.save(document)

    let recorder = SyncCallRecorder()
    let client = singlePageClient(
        entries: [YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-new", threadID: "903")],
        recorder: recorder
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: categoryID))

    #expect(final.status == .completed)
    #expect(final.skippedCount == 1)
    #expect(final.importedCount == 0)
    #expect(final.logEntries.contains { entry in
        if case .skippedSyncedItems = entry { return true }
        return false
    })
    let saved = try await store.load()
    let item = try #require(saved.items.first)
    #expect(item.remoteMapping?.yamiboFavoriteID == "r-new")
    #expect(item.remoteMapping?.yamiboRemoteOrder == 0)
}

@Test func engineRecordsItemFailureAndContinues() async throws {
    let store = makeLibraryStore()
    let document = try await store.load()
    let categoryID = document.defaultCategory.id

    let recorder = SyncCallRecorder()
    let client = singlePageClient(
        entries: [
            YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-bad", threadID: "111", title: "坏帖"),
            YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-good", threadID: "222", title: "好帖"),
        ],
        recorder: recorder,
        probe: { entry in
            if entry.threadID == "111" {
                throw YamiboError.parsingFailed(context: "boom")
            }
            return threadProbe(entry.threadID)
        }
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: categoryID))

    #expect(final.status == .completed)
    #expect(final.failedCount == 1)
    #expect(final.importedCount == 1)
    #expect(final.warnings.contains { warning in
        if case .importFailedItem = warning { return true }
        return false
    })
    let saved = try await store.load()
    #expect(saved.items.count == 1)
    // Failed probes retry before giving up: 3 attempts for the bad entry.
    let probed = await recorder.probedThreadIDs
    #expect(probed.filter { $0 == "111" }.count == 3)
}

// MARK: - Uploading & reconciling

@Test func engineUploadsLocalOnlyThreadsIncludingRemoteDeletedAndReconciles() async throws {
    let store = makeLibraryStore()
    var document = try await store.load()
    let categoryID = document.defaultCategory.id
    let unmapped = try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadID: "301"),
        title: "从未同步",
        locations: [.category(categoryID)]
    )
    // Mapped but no longer on the website: local is truth, so sync re-uploads it.
    let remoteDeleted = try FavoriteItem(
        target: FavoriteContentTarget(kind: .novelThread, threadID: "302"),
        title: "网站已删",
        remoteMapping: FavoriteRemoteMapping(yamiboFavoriteID: "r-302-old"),
        locations: [.category(categoryID)]
    )
    let manga = try FavoriteItem(
        target: FavoriteContentTarget(mangaCleanBookName: "漫画"),
        title: "漫画",
        locations: [.category(categoryID)]
    )
    document.addItem(unmapped)
    document.addItem(remoteDeleted)
    document.addItem(manga)
    try await store.save(document)

    let recorder = SyncCallRecorder()
    let client = FavoriteYamiboSyncClient(
        fetchPage: { _ in
            // First fetch (phase 2) sees an empty remote list; the reconcile
            // fetch after uploading sees both uploaded threads.
            let call = await recorder.recordFetch()
            if call == 1 {
                return FavoriteYamiboRemotePage(entries: [], currentPage: 1, totalPages: 1)
            }
            return FavoriteYamiboRemotePage(
                entries: [
                    YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-301", threadID: "301"),
                    YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-302", threadID: "302"),
                ],
                currentPage: 1,
                totalPages: 1
            )
        },
        probe: { entry in
            await recorder.recordProbe(entry.threadID)
            return threadProbe(entry.threadID)
        },
        addFavorite: { threadID in
            await recorder.recordAdd(threadID)
        }
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: categoryID))

    #expect(final.status == .completed)
    #expect(final.uploadTargetCount == 2)
    #expect(final.uploadedCount == 2)
    let added = await recorder.addedThreadIDs
    #expect(Set(added) == ["301", "302"])
    let saved = try await store.load()
    let savedUnmapped = try #require(saved.items.first { $0.target.threadID == "301" })
    let savedRemoteDeleted = try #require(saved.items.first { $0.target.threadID == "302" })
    #expect(savedUnmapped.remoteMapping?.yamiboFavoriteID == "r-301")
    #expect(savedRemoteDeleted.remoteMapping?.yamiboFavoriteID == "r-302")
}

// MARK: - Fetching

@Test func enginePaginatesAndRecordsProgress() async throws {
    let store = makeLibraryStore()
    let document = try await store.load()
    let categoryID = document.defaultCategory.id

    let recorder = SyncCallRecorder()
    let client = FavoriteYamiboSyncClient(
        fetchPage: { page in
            _ = await recorder.recordFetch()
            let entry = YamiboRemoteFavoriteEntry(remoteFavoriteID: "r-\(page)", threadID: "\(1000 + page)")
            return FavoriteYamiboRemotePage(entries: [entry], currentPage: page, totalPages: 2)
        },
        probe: { entry in
            await recorder.recordProbe(entry.threadID)
            return threadProbe(entry.threadID)
        },
        addFavorite: { _ in }
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: categoryID))

    #expect(final.status == .completed)
    #expect(final.scannedCount == 2)
    #expect(final.currentPage == 2)
    #expect(final.totalPages == 2)
    #expect(final.importedCount == 2)
    let fetchedPageLogs = final.logEntries.filter { entry in
        if case .fetchedPage = entry { return true }
        return false
    }
    #expect(fetchedPageLogs.count == 2)
}

// MARK: - Failure modes

@Test func engineFailsRunOnNotAuthenticated() async throws {
    let store = makeLibraryStore()
    let document = try await store.load()
    let categoryID = document.defaultCategory.id

    let client = FavoriteYamiboSyncClient(
        fetchPage: { _ in throw YamiboError.notAuthenticated },
        probe: { _ in throw YamiboError.notAuthenticated },
        addFavorite: { _ in }
    )
    let final = await runEngine(store: store, client: client, snapshot: makeSnapshot(categoryID: categoryID))

    #expect(final.status == .failed)
    #expect(final.phase == .failed)
    #expect(!final.errorMessages.isEmpty)
}

@Test func engineFailsWhenTargetCategoryMissing() async throws {
    let store = makeLibraryStore()
    let recorder = SyncCallRecorder()
    let client = singlePageClient(entries: [], recorder: recorder)

    let final = await runEngine(
        store: store,
        client: client,
        snapshot: makeSnapshot(categoryID: "no-such-category")
    )

    #expect(final.status == .failed)
    let fetches = await recorder.fetchPageCalls
    #expect(fetches == 0)
}
