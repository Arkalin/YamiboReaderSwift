import Foundation
import Observation
import YamiboReaderCore

@MainActor
@Observable
final class ForumMangaDetailViewModel {
    var directory: MangaDirectory?
    var currentDocument: MangaReaderProjection?
    var readingProgress: ReadingProgressRecord?
    var isLoading = false
    var errorMessage: String?

    let context: MangaDetailLaunchContext

    @ObservationIgnored private let dependencies: ForumDependencies
    @ObservationIgnored private var readingProgressUpdatesTask: Task<Void, Never>?

    init(context: MangaDetailLaunchContext, dependencies: ForumDependencies) {
        self.context = context
        self.dependencies = dependencies
        readingProgressUpdatesTask = Task { @MainActor [weak self, readingProgressStore = dependencies.readingProgressStore] in
            for await notification in NotificationCenter.default.notifications(named: ReadingProgressStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[ReadingProgressStore.changeIDUserInfoKey] as? String,
                      changeID == readingProgressStore.changeID else {
                    continue
                }
                readingProgress = await self.loadReadingProgress()
            }
        }
    }

    deinit {
        readingProgressUpdatesTask?.cancel()
    }

    var navigationTitle: String {
        directory?.cleanBookName ?? context.title
    }

    var focusedChapterTID: String? {
        context.focusedChapterTID ?? currentDocument?.tid
    }

    func load() async {
        guard directory == nil else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        readingProgress = await loadReadingProgress()
        defer { isLoading = false }

        do {
            let loader = await dependencies.makeMangaReaderProjectionLoader()
            let repository = await dependencies.makeMangaDirectoryRepository()
            let store = dependencies.mangaDirectoryStore
            let document = try await loader.loadReaderProjection(
                MangaReaderProjectionRequest(threadID: context.thread.tid)
            )
            let workflow = MangaDirectoryWorkflow(
                repository: repository,
                store: store,
                searchCooldownState: dependencies.mangaDirectorySearchCooldownState
            )
            let launchContext = MangaLaunchContext(
                originalThreadID: context.thread.tid,
                chapterTID: context.thread.tid,
                displayTitle: context.title,
                source: .forum,
                directoryName: context.directoryNameHint,
                forumID: context.thread.fid,
                // `ForumMangaDetailView` (and this view model) is only ever
                // reached via `YamiboThreadRouteTarget.manga`, which
                // `YamiboThreadRouteResolver` only produces when the board's
                // Smart Comic Mode is on — the mode-off case routes to
                // `.mangaDirect` instead and never reaches here. Hardcoding
                // `true` (rather than re-querying `AppSettings`) keeps this
                // view model from needing its own settings dependency for a
                // fact its caller already established.
                isSmartModeEnabled: true
            )
            let resolution = try await workflow.resolveInitialDirectory(
                context: launchContext,
                projection: document
            )
            let resolvedDirectory = try await ensuringDirectoryContainsCurrentChapter(
                resolution.directory,
                document: document,
                store: store
            )

            currentDocument = document
            directory = resolvedDirectory
            // Only now is `directory`'s stable identity known, so only now can
            // the precise directory-scoped query replace whatever the fuzzy
            // fetch above (before `directory` was known) happened to find.
            readingProgress = await loadReadingProgress()
        } catch {
            currentDocument = nil
            directory = nil
            readingProgress = await loadReadingProgress()
            errorMessage = error.localizedDescription
        }
    }

    var hasReadingProgress: Bool {
        readingProgress?.manga != nil
    }

    func continueLaunchContext() -> MangaLaunchContext? {
        guard let directory else { return nil }
        let manga = readingProgress?.manga
        let fallbackChapter = directory.chapters.first
        let fallbackChapterTID = fallbackChapter?.tid ?? currentDocument?.tid ?? context.thread.tid
        let fallbackChapterView = fallbackChapter?.view ?? currentDocument?.sourceIdentity.view ?? 1
        return MangaLaunchContext(
            originalThreadID: context.thread.tid,
            chapterTID: manga?.chapterThreadID ?? fallbackChapterTID,
            displayTitle: directory.cleanBookName,
            source: manga == nil ? .forum : .resume,
            chapterView: manga?.chapterView ?? fallbackChapterView,
            initialPage: manga?.mangaPageIndex ?? 0,
            directoryName: directory.cleanBookName,
            forumID: context.thread.fid,
            // See the comment in `reload()`: this view model only exists
            // for mode-on boards.
            isSmartModeEnabled: true
        )
    }

    func launchContext(for chapter: MangaChapter) -> MangaLaunchContext {
        MangaLaunchContext(
            originalThreadID: context.thread.tid,
            chapterTID: chapter.tid,
            displayTitle: directory?.cleanBookName ?? context.title,
            source: .forum,
            chapterView: chapter.view,
            directoryName: directory?.cleanBookName ?? context.directoryNameHint,
            forumID: context.thread.fid,
            // See the comment in `reload()`: this view model only exists
            // for mode-on boards.
            isSmartModeEnabled: true
        )
    }

    /// Once `directory` is known, its stable `mangaID`+`cleanBookName`
    /// identity is the precise lookup key for this manga's reading progress
    /// — mirrors `LocalFavoriteOpenTargetResolver.mangaDirectoryResumeTarget`.
    /// `ReadingProgressStore.saveMangaTitle` upserts a single directory-level
    /// row whose `thread_id`/`manga_chapter_thread_id` columns both hold
    /// whatever chapter tid was current *at save time* — so a chapter that
    /// was never the "current" one when that row was written can still have
    /// its own stale `.mangaThread` row sharing this same tid. The generic
    /// `load(threadID:)` OR-matches on either column and would happily
    /// return whichever row was updated most recently regardless of kind,
    /// coincidentally latching onto that stale per-chapter row instead of
    /// the directory's true current position. Before `directory` resolves
    /// there is no directory identity yet to query by, so the coincidental
    /// OR-match remains the only option in that narrow window.
    private func loadReadingProgress() async -> ReadingProgressRecord? {
        guard let directory else {
            return await dependencies.readingProgressStore.load(threadID: context.thread.tid)
        }
        let target = FavoriteContentTarget(mangaID: directory.favoriteIdentity, mangaCleanBookName: directory.cleanBookName)
        return await dependencies.readingProgressStore.load(for: target)
    }

    private func ensuringDirectoryContainsCurrentChapter(
        _ directory: MangaDirectory,
        document: MangaReaderProjection,
        store: any MangaDirectoryPersisting
    ) async throws -> MangaDirectory {
        guard !directory.chapters.contains(where: { $0.tid == document.tid }) else {
            return directory
        }

        var updated = directory
        updated.chapters = MangaDirectoryMerge.mergeAndSort(
            directory.chapters,
            [
                MangaChapter(
                    tid: document.tid,
                    rawTitle: document.chapterTitle,
                    chapterNumber: MangaTitleCleaner.extractChapterNumber(document.chapterTitle),
                    view: document.sourceIdentity.view,
                    authorUID: document.sourceIdentity.authorID,
                    authorName: document.ownerAuthorName
                )
            ]
        )
        updated.lastUpdatedAt = Date()
        try await store.saveDirectory(updated)
        return updated
    }
}
