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

    @ObservationIgnored private let appContext: YamiboAppContext
    @ObservationIgnored private var readingProgressUpdatesTask: Task<Void, Never>?

    init(context: MangaDetailLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
        readingProgressUpdatesTask = Task { @MainActor [weak self, readingProgressStore = appContext.readingProgressStore] in
            for await notification in NotificationCenter.default.notifications(named: ReadingProgressStore.didChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let changeID = notification.userInfo?[ReadingProgressStore.changeIDUserInfoKey] as? String,
                      changeID == readingProgressStore.changeID else {
                    continue
                }
                readingProgress = await readingProgressStore.load(threadID: context.thread.tid)
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
        readingProgress = await appContext.readingProgressStore.load(threadID: context.thread.tid)
        defer { isLoading = false }

        do {
            let loader = await appContext.makeMangaReaderProjectionLoader()
            let repository = await appContext.makeMangaDirectoryRepository()
            let store = appContext.makeMangaDirectoryStore()
            let document = try await loader.loadReaderProjection(
                MangaReaderProjectionRequest(threadID: context.thread.tid)
            )
            let workflow = MangaDirectoryWorkflow(
                repository: repository,
                store: store,
                searchCooldownState: appContext.mangaDirectorySearchCooldownState
            )
            let launchContext = MangaLaunchContext(
                originalThreadID: context.thread.tid,
                chapterTID: context.thread.tid,
                displayTitle: context.title,
                source: .forum,
                directoryName: context.directoryNameHint
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
        } catch {
            currentDocument = nil
            directory = nil
            readingProgress = await appContext.readingProgressStore.load(threadID: context.thread.tid)
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
        let progressChapterTID = (manga?.lastMangaURL).flatMap(Self.threadID(from:))
        return MangaLaunchContext(
            originalThreadID: context.thread.tid,
            chapterTID: progressChapterTID ?? fallbackChapterTID,
            displayTitle: directory.cleanBookName,
            source: manga == nil ? .forum : .resume,
            chapterView: (manga?.lastMangaURL).map(Self.page(from:)) ?? fallbackChapterView,
            initialPage: manga?.mangaPageIndex ?? 0,
            directoryName: directory.cleanBookName
        )
    }

    func launchContext(for chapter: MangaChapter) -> MangaLaunchContext {
        MangaLaunchContext(
            originalThreadID: context.thread.tid,
            chapterTID: chapter.tid,
            displayTitle: directory?.cleanBookName ?? context.title,
            source: .forum,
            chapterView: chapter.view,
            directoryName: directory?.cleanBookName ?? context.directoryNameHint
        )
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
                    url: document.chapterURL
                )
            ]
        )
        updated.lastUpdatedAt = Date()
        try await store.saveDirectory(updated)
        return updated
    }

    private static func threadID(from url: URL) -> String? {
        let value = MangaTitleCleaner.extractTid(from: url.absoluteString)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func page(from url: URL) -> Int {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
            .flatMap(Int.init) ?? 1
        return max(1, page)
    }
}
