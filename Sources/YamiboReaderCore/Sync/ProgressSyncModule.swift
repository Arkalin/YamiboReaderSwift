import Foundation

public struct NovelReadingPosition: Hashable, Sendable {
    public var threadURL: URL
    public var view: Int
    public var maxView: Int?
    public var chapterTitle: String?
    public var authorID: String?
    public var resumePoint: ReaderResumePoint?

    public init(
        threadURL: URL,
        view: Int,
        maxView: Int? = nil,
        chapterTitle: String? = nil,
        authorID: String? = nil,
        resumePoint: ReaderResumePoint? = nil
    ) {
        self.threadURL = threadURL
        self.view = max(1, view)
        self.maxView = maxView.map { max(self.view, $0) }
        self.chapterTitle = resumePoint?.chapterTitle ?? chapterTitle
        self.authorID = resumePoint?.authorID ?? authorID
        self.resumePoint = resumePoint
    }
}

public struct MangaProgressReadingPosition: Hashable, Sendable {
    public var threadURL: URL
    public var chapterURL: URL
    public var chapterTitle: String
    public var pageIndex: Int

    public init(threadURL: URL, chapterURL: URL, chapterTitle: String, pageIndex: Int) {
        self.threadURL = threadURL
        self.chapterURL = chapterURL
        self.chapterTitle = chapterTitle
        self.pageIndex = max(0, pageIndex)
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
    private let favoriteStore: FavoriteStore

    public init(favoriteStore: FavoriteStore) {
        self.favoriteStore = favoriteStore
    }

    public func saveNovelReadingPosition(_ position: NovelReadingPosition) async throws {
        _ = try await favoriteStore.updateNovelReadingPosition(
            position,
            createIfMissing: false
        )
    }

    public func saveMangaReadingPosition(_ position: MangaProgressReadingPosition) async throws {
        _ = try await favoriteStore.updateMangaProgress(
            for: position.threadURL,
            chapterURL: position.chapterURL,
            chapterTitle: position.chapterTitle,
            pageIndex: position.pageIndex,
            createIfMissing: false
        )
    }
}
