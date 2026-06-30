import Foundation
import Observation
import YamiboReaderCore

@MainActor
@Observable
final class ForumMangaDetailViewModel {
    var directory: MangaDirectory?
    var currentDocument: MangaChapterDocument?
    var isLoading = false
    var errorMessage: String?

    let context: MangaDetailLaunchContext

    @ObservationIgnored private let appContext: YamiboAppContext

    init(context: MangaDetailLaunchContext, appContext: YamiboAppContext) {
        self.context = context
        self.appContext = appContext
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
        defer { isLoading = false }

        do {
            let loader = await appContext.makeMangaChapterDocumentLoader()
            let repository = await appContext.makeMangaDirectoryRepository()
            let store = appContext.makeMangaDirectoryStore()
            let document = try await loader.loadChapterDocument(at: context.thread.canonicalURL)
            let workflow = MangaDirectoryWorkflow(
                repository: repository,
                store: store,
                searchCooldownState: appContext.mangaDirectorySearchCooldownState
            )
            let launchContext = MangaLaunchContext(
                originalThreadURL: context.thread.canonicalURL,
                chapterURL: context.thread.canonicalURL,
                displayTitle: context.title,
                source: .forum,
                directoryName: context.directoryNameHint
            )
            let resolution = try await workflow.resolveInitialDirectory(
                context: launchContext,
                document: document
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
            errorMessage = error.localizedDescription
        }
    }

    func launchContext(for chapter: MangaChapter) -> MangaLaunchContext {
        MangaLaunchContext(
            originalThreadURL: context.thread.canonicalURL,
            chapterURL: chapter.url,
            displayTitle: directory?.cleanBookName ?? context.title,
            source: .forum,
            directoryName: directory?.cleanBookName ?? context.directoryNameHint
        )
    }

    private func ensuringDirectoryContainsCurrentChapter(
        _ directory: MangaDirectory,
        document: MangaChapterDocument,
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
}
