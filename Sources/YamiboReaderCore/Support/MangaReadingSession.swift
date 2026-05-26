import Foundation

public protocol MangaReadingDirectoryResolving: Sendable {
    func resolveInitialDirectory(
        context: MangaLaunchContext,
        document: MangaChapterDocument
    ) async throws -> MangaDirectory
}

public actor MangaReadingSession {
    public typealias DocumentLoader = @Sendable (URL, String?) async throws -> MangaChapterDocument

    public struct Snapshot: Equatable, Sendable {
        public var directory: MangaDirectory
        public var window: MangaChapterWindowSnapshot

        public init(directory: MangaDirectory, window: MangaChapterWindowSnapshot) {
            self.directory = directory
            self.window = window
        }
    }

    public enum JumpResult: Equatable, Sendable {
        case loaded(MangaChapterWindowSnapshot)
        case alreadyLoaded(pageIndex: Int)
        case reopenNative(MangaLaunchContext)
    }

    private let context: MangaLaunchContext
    private let documentLoader: DocumentLoader
    private let directoryResolver: any MangaReadingDirectoryResolving
    private let maxLoadedDocuments: Int
    private var directory: MangaDirectory?
    private var window: MangaChapterWindow?
    private var documentTasks: [String: Task<MangaChapterDocument, Error>] = [:]

    public init(
        context: MangaLaunchContext,
        documentLoader: @escaping DocumentLoader,
        directoryResolver: any MangaReadingDirectoryResolving,
        maxLoadedDocuments: Int = 10
    ) {
        self.context = context
        self.documentLoader = documentLoader
        self.directoryResolver = directoryResolver
        self.maxLoadedDocuments = max(1, maxLoadedDocuments)
    }

    public func prepare() async throws -> Snapshot {
        let document = try await loadDocument(for: context.chapterURL, htmlOverride: nil)
        let resolvedDirectory = try await directoryResolver.resolveInitialDirectory(
            context: context,
            document: document
        )
        let readingPosition = MangaReadingPosition(
            tid: document.tid,
            localIndex: context.initialPage
        )
        let chapterWindow = MangaChapterWindow(
            directory: resolvedDirectory,
            initialDocument: document,
            position: readingPosition,
            maxLoadedDocuments: maxLoadedDocuments
        )
        directory = resolvedDirectory
        window = chapterWindow
        return Snapshot(directory: resolvedDirectory, window: chapterWindow.snapshot)
    }

    public func moveToLoadedPage(_ pageIndex: Int) throws -> MangaChapterWindowSnapshot {
        guard var chapterWindow = window else {
            throw YamiboError.underlying("Manga reading session is not prepared.")
        }
        let snapshot = chapterWindow.moveToLoadedPage(at: pageIndex)
        window = chapterWindow
        return snapshot
    }

    public func prefetchIfNeeded(around pageIndex: Int) async throws -> MangaChapterWindowSnapshot? {
        guard var chapterWindow = window else {
            throw YamiboError.underlying("Manga reading session is not prepared.")
        }

        let pages = chapterWindow.snapshot.pages
        guard !pages.isEmpty else { return nil }

        var latestSnapshot: MangaChapterWindowSnapshot?
        if pageIndex >= pages.count - 6 {
            latestSnapshot = try await loadAdjacentDocument(delta: 1, window: &chapterWindow)
        }
        if pageIndex <= 2 {
            latestSnapshot = try await loadAdjacentDocument(delta: -1, window: &chapterWindow) ?? latestSnapshot
        }
        window = chapterWindow
        return latestSnapshot
    }

    public func updateDirectory(
        _ updatedDirectory: MangaDirectory,
        preserving position: MangaReadingPosition?
    ) throws -> MangaChapterWindowSnapshot {
        guard var chapterWindow = window else {
            throw YamiboError.underlying("Manga reading session is not prepared.")
        }
        let snapshot = chapterWindow.updateDirectory(updatedDirectory, preserving: position)
        directory = updatedDirectory
        window = chapterWindow
        return snapshot
    }

    public func jump(
        to chapter: MangaChapter,
        from position: MangaReadingPosition?
    ) async throws -> JumpResult {
        guard var chapterWindow = window, let currentDirectory = directory else {
            throw YamiboError.underlying("Manga reading session is not prepared.")
        }

        if let loadedIndex = chapterWindow.snapshot.pages.firstIndex(where: { page in
            page.tid == chapter.tid && page.localIndex == 0
        }) {
            let snapshot = chapterWindow.moveToLoadedPage(at: loadedIndex)
            window = chapterWindow
            return .alreadyLoaded(pageIndex: snapshot.resolvedPageIndex ?? loadedIndex)
        }

        let currentPosition = position ?? chapterWindow.snapshot.resolvedPosition
        guard let currentPosition,
              let targetIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == chapter.tid }),
              let currentIndex = currentDirectory.chapters.firstIndex(where: { $0.tid == currentPosition.tid }) else {
            return .reopenNative(makeNativeLaunchContext(for: chapter, directory: currentDirectory))
        }

        guard abs(targetIndex - currentIndex) <= 1 else {
            return .reopenNative(makeNativeLaunchContext(for: chapter, directory: currentDirectory))
        }

        let document = try await loadDocument(for: chapter.url, htmlOverride: nil)
        let targetPosition = MangaReadingPosition(tid: document.tid, localIndex: 0)
        let result = chapterWindow.insertAdjacentDocument(document, preserving: targetPosition)
        let snapshot: MangaChapterWindowSnapshot
        switch result {
        case let .changed(changedSnapshot):
            snapshot = changedSnapshot
        case let .unchanged(unchangedSnapshot, reason):
            if reason == .duplicateChapter {
                snapshot = unchangedSnapshot
            } else {
                snapshot = chapterWindow.reset(to: document, position: targetPosition)
            }
        }
        window = chapterWindow
        return .loaded(snapshot)
    }

    public func applyLoadedDocument(
        _ document: MangaChapterDocument,
        preserving position: MangaReadingPosition,
        allowsReset: Bool
    ) throws -> MangaChapterWindowSnapshot {
        guard var chapterWindow = window else {
            throw YamiboError.underlying("Manga reading session is not prepared.")
        }
        let result = chapterWindow.insertAdjacentDocument(document, preserving: position)
        let snapshot: MangaChapterWindowSnapshot
        switch result {
        case let .changed(changedSnapshot):
            snapshot = changedSnapshot
        case let .unchanged(unchangedSnapshot, reason):
            if reason == .duplicateChapter {
                snapshot = unchangedSnapshot
            } else if allowsReset {
                snapshot = chapterWindow.reset(to: document, position: position)
            } else {
                return unchangedSnapshot
            }
        }
        window = chapterWindow
        return snapshot
    }

    private func loadAdjacentDocument(
        delta: Int,
        window chapterWindow: inout MangaChapterWindow
    ) async throws -> MangaChapterWindowSnapshot? {
        guard let chapter = chapterWindow.adjacentChapterForLoadedRange(delta: delta) else { return nil }
        let position = chapterWindow.snapshot.resolvedPosition
        let document = try await loadDocument(for: chapter.url, htmlOverride: nil)
        let result = chapterWindow.insertAdjacentDocument(document, preserving: position)
        switch result {
        case let .changed(snapshot):
            return snapshot
        case .unchanged:
            return nil
        }
    }

    private func loadDocument(for url: URL, htmlOverride: String?) async throws -> MangaChapterDocument {
        let tid = MangaTitleCleaner.extractTid(from: url.absoluteString) ?? url.absoluteString
        if let existingTask = documentTasks[tid] {
            return try await existingTask.value
        }
        let loader = documentLoader
        let task = Task {
            try await loader(url, htmlOverride)
        }
        documentTasks[tid] = task
        defer { documentTasks.removeValue(forKey: tid) }
        return try await task.value
    }

    private func makeNativeLaunchContext(
        for chapter: MangaChapter,
        directory: MangaDirectory
    ) -> MangaLaunchContext {
        MangaLaunchContext(
            originalThreadURL: context.originalThreadURL,
            chapterURL: chapter.url,
            displayTitle: directory.cleanBookName,
            source: context.source,
            initialPage: 0,
            directoryName: directory.cleanBookName
        )
    }
}
