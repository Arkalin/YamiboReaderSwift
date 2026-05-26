import Foundation

public enum ReaderChapterCommentsState: Equatable, Sendable {
    case idle
    case unsupported
    case loading(ReaderChapterCommentTarget)
    case loaded(ReaderChapterCommentTarget, ChapterCommentsPage)
    case failed(ReaderChapterCommentTarget, String)
}

public struct ReaderChapterCommentsUnavailableError: LocalizedError, Sendable {
    public init() {}

    public var errorDescription: String? {
        L10n.string("reader.chapter_comments_failed")
    }
}

public final class ReaderChapterCommentsModule {
    public struct Adapter {
        public var loadInitial: @MainActor (ReaderChapterCommentTarget) async throws -> ChapterCommentsPage
        public var loadMore: @MainActor (ReaderChapterCommentTarget, Int) async throws -> ChapterCommentsPage

        public init(
            loadInitial: @escaping @MainActor (ReaderChapterCommentTarget) async throws -> ChapterCommentsPage,
            loadMore: @escaping @MainActor (ReaderChapterCommentTarget, Int) async throws -> ChapterCommentsPage
        ) {
            self.loadInitial = loadInitial
            self.loadMore = loadMore
        }
    }

    public private(set) var state: ReaderChapterCommentsState = .idle
    public private(set) var isLoadingMore = false
    public private(set) var loadMoreError: String?
    public private(set) var refreshError: String?

    private let adapter: Adapter
    private var cache: [ReaderChapterCommentTarget: ChapterCommentsPage] = [:]
    private var onChange: (@MainActor (ReaderChapterCommentsModule) -> Void)?

    public init(
        adapter: Adapter,
        onChange: (@MainActor (ReaderChapterCommentsModule) -> Void)?
    ) {
        self.adapter = adapter
        self.onChange = onChange
    }

    @MainActor
    public func load(_ target: ReaderChapterCommentTarget?) async {
        guard let target else {
            state = .unsupported
            notifyChange()
            return
        }
        if let cached = cache[target] {
            refreshError = nil
            state = .loaded(target, cached)
            notifyChange()
            return
        }
        await refresh(target)
    }

    @MainActor
    public func refresh(_ target: ReaderChapterCommentTarget?) async {
        guard let target else {
            state = .unsupported
            notifyChange()
            return
        }
        state = .loading(target)
        loadMoreError = nil
        refreshError = nil
        notifyChange()
        do {
            let page = try await adapter.loadInitial(target)
            cache[target] = page
            state = .loaded(target, page)
        } catch {
            if let cached = cache[target] {
                refreshError = error.localizedDescription
                state = .loaded(target, cached)
            } else {
                state = .failed(target, error.localizedDescription)
            }
        }
        notifyChange()
    }

    @MainActor
    public func loadNextPage() async {
        guard case let .loaded(target, currentPage) = state,
              let nextView = currentPage.nextView,
              !isLoadingMore else {
            return
        }

        isLoadingMore = true
        loadMoreError = nil
        notifyChange()
        do {
            let nextPage = try await adapter.loadMore(target, nextView)
            let mergedPage = ChapterCommentsPage(
                target: target,
                comments: currentPage.comments + nextPage.comments,
                isBoundaryClosed: nextPage.isBoundaryClosed,
                nextView: nextPage.nextView
            )
            cache[target] = mergedPage
            state = .loaded(target, mergedPage)
            refreshError = nil
        } catch {
            loadMoreError = error.localizedDescription
        }
        isLoadingMore = false
        notifyChange()
    }

    @MainActor
    private func notifyChange() {
        onChange?(self)
    }
}
