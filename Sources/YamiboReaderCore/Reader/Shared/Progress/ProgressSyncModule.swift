import Foundation

public struct NovelReadingPosition: Hashable, Sendable {
    public var threadID: String
    public var view: Int
    public var maxView: Int?
    public var chapterTitle: String?
    public var authorID: String?
    public var resumePoint: NovelResumePoint?
    public var documentSurfaceProgressPercent: Int?

    public init(
        threadID: String,
        view: Int,
        maxView: Int? = nil,
        chapterTitle: String? = nil,
        authorID: String? = nil,
        resumePoint: NovelResumePoint? = nil,
        documentSurfaceProgressPercent: Int? = nil
    ) {
        let normalizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedThreadID.isEmpty, "NovelReadingPosition requires a Yamibo thread tid")
        self.threadID = normalizedThreadID
        self.view = max(1, view)
        self.maxView = maxView.map { max(self.view, $0) }
        self.chapterTitle = resumePoint?.chapterTitle ?? chapterTitle
        self.authorID = resumePoint?.authorID ?? authorID
        self.resumePoint = resumePoint
        self.documentSurfaceProgressPercent = documentSurfaceProgressPercent.map { min(max($0, 0), 100) }
    }
}

public struct MangaProgressReadingPosition: Hashable, Sendable {
    public var threadID: String
    public var chapterThreadID: String
    public var chapterView: Int
    public var chapterTitle: String
    public var pageIndex: Int
    public var pageCount: Int?
    public var mangaID: String?
    public var directoryName: String?

    public init(
        threadID: String? = nil,
        chapterThreadID: String,
        chapterView: Int = 1,
        chapterTitle: String,
        pageIndex: Int,
        pageCount: Int? = nil,
        mangaID: String? = nil,
        directoryName: String? = nil
    ) {
        let normalizedChapterThreadID = chapterThreadID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedChapterThreadID.isEmpty, "MangaProgressReadingPosition requires a Yamibo chapter tid")
        self.chapterThreadID = normalizedChapterThreadID
        self.threadID = threadID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? normalizedChapterThreadID
        self.chapterView = max(1, chapterView)
        self.chapterTitle = chapterTitle
        self.pageIndex = max(0, pageIndex)
        self.pageCount = pageCount.map { max(1, $0) }
        self.mangaID = mangaID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.directoryName = directoryName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public enum ProgressSyncPosition: Hashable, Sendable {
    case novel(NovelReadingPosition)
    case manga(MangaProgressReadingPosition)
}

public protocol ProgressSyncAdapter: Sendable {
    func saveNovelReadingPosition(_ position: NovelReadingPosition) async throws
    func saveMangaReadingPosition(_ position: MangaProgressReadingPosition) async throws
}

public actor ProgressSyncModule {
    private let adapter: any ProgressSyncAdapter
    private let debounceNanoseconds: UInt64
    private var pendingTask: Task<Void, Never>?
    private var lastQueuedPosition: ProgressSyncPosition?
    private var lastSyncedPosition: ProgressSyncPosition?
    private var needsRetry = false

    public init(adapter: any ProgressSyncAdapter, debounceNanoseconds: UInt64 = 350_000_000) {
        self.adapter = adapter
        self.debounceNanoseconds = debounceNanoseconds
    }

    public func queue(_ position: ProgressSyncPosition) {
        guard position != lastQueuedPosition || needsRetry else { return }

        lastQueuedPosition = position
        pendingTask?.cancel()
        pendingTask = Task { [weak self, debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            try? await self?.flushQueuedPosition()
        }
    }

    public func flush(_ latestPosition: ProgressSyncPosition? = nil) async throws {
        pendingTask?.cancel()
        pendingTask = nil

        if let latestPosition {
            lastQueuedPosition = latestPosition
        }

        guard let position = lastQueuedPosition else { return }
        try await saveIfNeeded(position)
    }

    public func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        lastQueuedPosition = nil
        needsRetry = false
    }

    private func flushQueuedPosition() async throws {
        pendingTask = nil
        guard let position = lastQueuedPosition else { return }
        try await saveIfNeeded(position)
    }

    private func saveIfNeeded(_ position: ProgressSyncPosition) async throws {
        guard position != lastSyncedPosition || needsRetry else { return }

        do {
            switch position {
            case let .novel(position):
                try await adapter.saveNovelReadingPosition(position)
            case let .manga(position):
                try await adapter.saveMangaReadingPosition(position)
            }
            lastSyncedPosition = position
            lastQueuedPosition = position
            needsRetry = false
        } catch {
            needsRetry = true
            throw error
        }
    }
}

public struct FavoriteLibraryProgressSyncAdapter: ProgressSyncAdapter {
    private let readingProgressStore: ReadingProgressStore

    public init(readingProgressStore: ReadingProgressStore) {
        self.readingProgressStore = readingProgressStore
    }

    public func saveNovelReadingPosition(_ position: NovelReadingPosition) async throws {
        _ = try await readingProgressStore.saveNovel(position)
    }

    public func saveMangaReadingPosition(_ position: MangaProgressReadingPosition) async throws {
        _ = try await readingProgressStore.saveManga(position)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
