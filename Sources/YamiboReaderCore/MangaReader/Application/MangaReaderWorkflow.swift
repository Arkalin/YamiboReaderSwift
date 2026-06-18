import Foundation

@MainActor
public final class MangaReaderWorkflow {
    public private(set) var presentation: MangaReaderPresentation

    private let context: MangaLaunchContext
    private let documentLoader: any MangaChapterDocumentLoading
    private let directoryRepository: any MangaDirectoryRepository
    private let directoryStore: any MangaDirectoryPersisting
    private var window: MangaChapterWindow?

    public init(
        context: MangaLaunchContext,
        documentLoader: any MangaChapterDocumentLoading,
        directoryRepository: any MangaDirectoryRepository,
        directoryStore: any MangaDirectoryPersisting
    ) {
        self.context = context
        self.documentLoader = documentLoader
        self.directoryRepository = directoryRepository
        self.directoryStore = directoryStore
        self.presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )
    }

    @discardableResult
    public func prepare() async -> MangaReaderPresentation {
        window = nil
        presentation = MangaReaderPresentation(
            state: .loading(MangaReaderLoadingPresentation(title: Self.presentationTitle(for: context)))
        )

        do {
            let document = try await documentLoader.loadChapterDocument(at: context.chapterURL)
            let directory = try await resolveDirectory()
            let requestedPosition = MangaReadingPosition(
                tid: document.tid,
                localIndex: context.initialPage
            )
            let window = MangaChapterWindow(
                directory: directory,
                initialDocument: document,
                position: requestedPosition
            )
            self.window = window
            presentation = loadedPresentation(from: window)
        } catch {
            window = nil
            presentation = MangaReaderPresentation(
                state: .failed(
                    MangaReaderErrorPresentation(
                        title: L10n.string("common.load_failed"),
                        message: error.localizedDescription
                    )
                )
            )
        }

        return presentation
    }

    @discardableResult
    public func moveToLoadedPage(at globalIndex: Int) -> MangaReaderPresentation {
        guard var window else { return presentation }
        _ = window.moveToLoadedPage(at: globalIndex)
        self.window = window
        presentation = loadedPresentation(from: window)
        return presentation
    }

    private func resolveDirectory() async throws -> MangaDirectory {
        if let directoryName = normalizedDirectoryName(context.directoryName),
           let existing = try await directoryStore.directory(named: directoryName) {
            return existing
        }

        let seed = try await directoryRepository.loadDirectorySeed(for: context.chapterURL)
        let directory = MangaDirectoryInitialization.directory(from: seed)
        try await directoryStore.saveDirectory(directory)
        return directory
    }

    private func normalizedDirectoryName(_ directoryName: String?) -> String? {
        let normalized = directoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private func loadedPresentation(from window: MangaChapterWindow) -> MangaReaderPresentation {
        let pages = MangaReaderPageProjection.projections(from: window)
        let currentPageIndex = MangaReaderPageProjection.resolvedPageIndex(for: window)
        let currentPage = currentPageIndex.flatMap { index in
            pages.indices.contains(index) ? pages[index] : nil
        }

        return MangaReaderPresentation(
            state: .loaded(
                MangaReaderLoadedPresentation(
                    title: Self.presentationTitle(for: context),
                    directoryTitle: window.directory.cleanBookName,
                    pages: pages,
                    currentPage: currentPage,
                    currentPageIndex: currentPageIndex,
                    readingPosition: window.resolvedPosition
                )
            )
        )
    }

    private static func presentationTitle(for context: MangaLaunchContext) -> String {
        let title = context.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? L10n.string("manga.reader.title") : title
    }
}
