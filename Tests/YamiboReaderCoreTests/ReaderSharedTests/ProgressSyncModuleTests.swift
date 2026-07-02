import Foundation
import Testing
@testable import YamiboReaderCore

@Test func progressSyncFlushCancelsPendingAndPersistsLatestPosition() async throws {
    let adapter = RecordingProgressSyncAdapter()
    let sync = ProgressSyncModule(adapter: adapter, debounceNanoseconds: 100_000_000)
    let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=2&mobile=2")!

    await sync.queue(.novel(NovelReadingPosition(threadURL: threadURL, view: 1)))
    try await sync.flush(.novel(NovelReadingPosition(threadURL: threadURL, view: 3)))
    try await Task.sleep(nanoseconds: 140_000_000)

    let saved = await adapter.savedPositions
    #expect(saved == [
        .novel(NovelReadingPosition(threadURL: threadURL, view: 3))
    ])
}

@Test func progressSyncCancelPendingDoesNotPersistQueuedPosition() async throws {
    let adapter = RecordingProgressSyncAdapter()
    let sync = ProgressSyncModule(adapter: adapter, debounceNanoseconds: 20_000_000)
    let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=3&mobile=2")!

    await sync.queue(.novel(NovelReadingPosition(threadURL: threadURL, view: 1)))
    await sync.cancelPending()
    try await Task.sleep(nanoseconds: 60_000_000)

    let saved = await adapter.savedPositions
    #expect(saved.isEmpty)
}

@Test func progressSyncDedupesRepeatedPosition() async throws {
    let adapter = RecordingProgressSyncAdapter()
    let sync = ProgressSyncModule(adapter: adapter, debounceNanoseconds: 20_000_000)
    let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=4&mobile=2")!
    let position = ProgressSyncPosition.novel(NovelReadingPosition(threadURL: threadURL, view: 4))

    await sync.queue(position)
    try await Task.sleep(nanoseconds: 60_000_000)
    await sync.queue(position)
    try await Task.sleep(nanoseconds: 60_000_000)

    let saved = await adapter.savedPositions
    #expect(saved == [position])
}

@Test func favoriteLibraryProgressSyncDoesNotCreateMissingFavorite() async throws {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "progress-sync-missing-favorite")
    let localFavoriteLibraryStore = LocalFirstFavoriteLibraryStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: defaultsSuiteName),
        key: "local-favorites"
    )
    let readingProgressStore = try ReadingProgressStore(testSuiteName: defaultsSuiteName, key: "reading-progress")
    let adapter = FavoriteLibraryProgressSyncAdapter(
        readingProgressStore: readingProgressStore
    )
    let sync = ProgressSyncModule(adapter: adapter, debounceNanoseconds: 0)
    let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=6&mobile=2")!

    try await sync.flush(.novel(NovelReadingPosition(threadURL: threadURL, view: 6)))

    #expect(await localFavoriteLibraryStore.load().items.isEmpty)
    let progress = await readingProgressStore.load(for: threadURL)
    #expect(progress?.novel?.lastView == 6)
}

@Test func favoriteLibraryProgressSyncWritesIndependentProgressWithoutMutatingFavorites() async throws {
    let defaultsSuiteName = YamiboTestDefaults.suiteName(prefix: "progress-sync-existing-favorite")
    let localFavoriteLibraryStore = LocalFirstFavoriteLibraryStore(
        defaults: try YamiboTestDefaults.defaults(suiteName: defaultsSuiteName),
        key: "local-favorites"
    )
    let readingProgressStore = try ReadingProgressStore(testSuiteName: defaultsSuiteName, key: "reading-progress")
    let adapter = FavoriteLibraryProgressSyncAdapter(
        readingProgressStore: readingProgressStore
    )
    let sync = ProgressSyncModule(adapter: adapter, debounceNanoseconds: 0)
    let novelURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=7&mobile=2")!
    let mangaURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=8&mobile=2")!
    let chapterURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9&mobile=2")!
    var favoriteLibrary = FavoriteLibraryDocument()
    favoriteLibrary.addItem(try FavoriteItem(
        target: FavoriteContentTarget(kind: .novelThread, threadURL: novelURL),
        title: "小说",
        locations: [.category(favoriteLibrary.defaultCategory.id)]
    ))
    favoriteLibrary.addItem(try FavoriteItem(
        target: FavoriteContentTarget(kind: .normalThread, threadURL: mangaURL),
        title: "漫画",
        locations: [.category(favoriteLibrary.defaultCategory.id)]
    ))
    try await localFavoriteLibraryStore.save(favoriteLibrary)

    try await sync.flush(.novel(NovelReadingPosition(
        threadURL: novelURL,
        view: 2,
        maxView: 7,
        chapterTitle: "第二章",
        authorID: "42",
        resumePoint: ReaderResumePoint(
            view: 2,
            displayedTextOffset: 120,
            chapterOrdinal: 1,
            chapterTitle: "第二章",
            segmentProgress: 0.5,
            authorID: "42",
            readingModeHint: .paged
        )
    )))
    try await sync.flush(.manga(MangaProgressReadingPosition(
        threadURL: mangaURL,
        chapterURL: chapterURL,
        chapterTitle: "第9话",
        pageIndex: 4,
        pageCount: 9
    )))

    let storedFavoriteLibrary = await localFavoriteLibraryStore.load()
    let novelProgress = await readingProgressStore.load(for: novelURL)
    let mangaProgress = await readingProgressStore.load(for: mangaURL)
    #expect(storedFavoriteLibrary == favoriteLibrary)
    #expect(novelProgress?.novel?.novelResumePoint?.displayedTextOffset == 120)
    #expect(mangaProgress?.manga?.lastMangaURL.absoluteString == "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9")
    #expect(mangaProgress?.manga?.chapterThreadID == "9")
    #expect(mangaProgress?.manga?.mangaPageIndex == 4)
    #expect(mangaProgress?.manga?.mangaPageCount == 9)
}

private actor RecordingProgressSyncAdapter: ProgressSyncAdapter {
    private var saved: [ProgressSyncPosition] = []
    private var remainingFailures = 0
    private var failures = 0

    var savedPositions: [ProgressSyncPosition] {
        saved
    }

    var failureCount: Int {
        failures
    }

    func failNextSave() {
        remainingFailures += 1
    }

    func saveNovelReadingPosition(_ position: NovelReadingPosition) async throws {
        try failIfNeeded()
        saved.append(.novel(position))
    }

    func saveMangaReadingPosition(_ position: MangaProgressReadingPosition) async throws {
        try failIfNeeded()
        saved.append(.manga(position))
    }

    private func failIfNeeded() throws {
        guard remainingFailures > 0 else { return }
        remainingFailures -= 1
        failures += 1
        throw TestProgressSyncError.saveFailed
    }
}

private enum TestProgressSyncError: Error {
    case saveFailed
}
