import Foundation
import XCTest
@testable import YamiboReaderCore

@MainActor
final class NovelReadingWorkflowTests: XCTestCase {
    func testStartUsesStoredResumePointBeforeLaunchPage() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9101&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            3: makeNovelDocument(threadURL: threadURL, view: 3, maxView: 5, authorID: "resume-author")
        ])
        let resumePoint = ReaderResumePoint(
            view: 3,
            chapterOrdinal: 1,
            chapterTitle: "第三章",
            segmentIndex: 0,
            segmentOffset: 0,
            segmentProgress: 0,
            authorID: "resume-author",
            readingModeHint: .vertical
        )
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 2,
                initialPage: 4,
                authorID: "launch-author"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )

        let state = try await workflow.start(
            initial: NovelReadingInitialPosition(
                resumePoint: resumePoint,
                favoriteAuthorID: "favorite-author"
            )
        )

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 3, authorID: "resume-author")
        ])
        XCTAssertEqual(state.snapshot.currentView, 3)
        XCTAssertEqual(state.currentAuthorID, "resume-author")
        XCTAssertEqual(state.snapshot.currentPageIndex, 0)
    }

    func testStartUsesLaunchPageAndFavoriteAuthorWhenNoResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9108&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 5, authorID: "favorite-author")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 2,
                initialPage: 1,
                authorID: "launch-author"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )

        let state = try await workflow.start(
            initial: NovelReadingInitialPosition(favoriteAuthorID: "favorite-author")
        )

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "favorite-author")
        ])
        XCTAssertEqual(state.snapshot.currentView, 2)
        XCTAssertEqual(state.snapshot.currentPageIndex, 1)
        XCTAssertEqual(state.currentAuthorID, "favorite-author")
    }

    func testLoadCurrentForceRefreshDeletesOnlyCurrentVariantAndReloadsIgnoringCache() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9102&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeNovelDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 4,
                authorID: "author-2",
                contentSource: .authorFilteredPage
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 2,
                authorID: "author-2"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = try await workflow.loadCurrent(
            preferredPage: 0,
            preferredResumePoint: nil,
            forceRefresh: true
        )

        XCTAssertEqual(repository.deletedViews, [
            RecordingNovelReadingRepository.DeletedViews(
                views: [2],
                threadURL: threadURL,
                authorID: "author-2",
                contentSource: .authorFilteredPage
            )
        ])
        XCTAssertEqual(repository.ignoringCacheRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-2")
        ])
    }

    func testPrefetchNearEndLoadsNextViewWithoutMergingInVerticalMode() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9103&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        let prefetchState = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))
        let state = try XCTUnwrap(prefetchState)

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "author-1"),
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-1")
        ])
        XCTAssertEqual(state.snapshot.currentView, 1)
        XCTAssertNil(state.snapshot.prefetchedStartIndex)
        XCTAssertEqual(Set(state.snapshot.pages.map(\.documentView)), [1])
    }

    func testPromotingPrefetchedViewPublishesRequestedPageImmediately() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9109&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))

        let promotedStateOptional = await workflow.promotePrefetchedDocument(preferredPage: 0, resumePoint: nil)
        let promotedState = try XCTUnwrap(promotedStateOptional)

        XCTAssertEqual(promotedState.snapshot.currentView, 2)
        XCTAssertEqual(promotedState.snapshot.currentPageIndex, 0)
        XCTAssertEqual(Set(promotedState.snapshot.pages.map(\.documentView)), [2])
    }

    func testPrefetchNearEndDoesNotMergeNextViewInPagedMode() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9104&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        let prefetchState = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))
        let state = try XCTUnwrap(prefetchState)

        XCTAssertEqual(state.snapshot.currentView, 1)
        XCTAssertNil(state.snapshot.prefetchedStartIndex)
        XCTAssertEqual(Set(state.snapshot.pages.map(\.documentView)), [1])
    }

    func testRepeatedPrefetchDoesNotReloadAlreadyPrefetchedNextView() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9105&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1"),
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 2, authorID: "author-1")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        let nearEndPage = max(initialState.snapshot.pages.count - 2, 0)

        _ = await workflow.prefetchIfNeeded(forPageIndex: nearEndPage)
        _ = await workflow.prefetchIfNeeded(forPageIndex: nearEndPage)

        XCTAssertEqual(repository.loadRequests, [
            ReaderPageRequest(threadURL: threadURL, view: 1, authorID: "author-1"),
            ReaderPageRequest(threadURL: threadURL, view: 2, authorID: "author-1")
        ])
    }

    func testPrefetchFailureKeepsCurrentSnapshot() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9106&mobile=2")!
        let repository = RecordingNovelReadingRepository(
            documents: [
                1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 2, authorID: "author-1")
            ],
            failingViews: [2]
        )
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        let prefetchState = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))
        let currentState = workflow.state

        XCTAssertNil(prefetchState)
        XCTAssertEqual(currentState, initialState)
    }

    func testCacheContextSeparatesCurrentFallbackAndPrefetchedAuthorFilteredVariants() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9107&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 2,
                authorID: nil,
                contentSource: .fallbackUnfilteredPage
            ),
            2: makeNovelDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 2,
                authorID: "author-2",
                contentSource: .authorFilteredPage
            )
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 1,
                authorID: nil
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = await workflow.prefetchIfNeeded(forPageIndex: max(initialState.snapshot.pages.count - 2, 0))

        let currentContext = workflow.cacheContext(forView: 1)
        let prefetchedContext = workflow.cacheContext(forView: 2)

        XCTAssertEqual(currentContext, NovelReadingCacheContext(authorID: nil, contentSource: .fallbackUnfilteredPage))
        XCTAssertEqual(prefetchedContext, NovelReadingCacheContext(authorID: "author-2", contentSource: .authorFilteredPage))
    }
}

private final class RecordingNovelReadingRepository: NovelReadingPageRepository, @unchecked Sendable {
    struct DeletedViews: Equatable {
        var views: Set<Int>
        var threadURL: URL
        var authorID: String?
        var contentSource: ReaderContentSource?
    }

    private let documents: [Int: ReaderPageDocument]
    private let failingViews: Set<Int>
    private(set) var loadRequests: [ReaderPageRequest] = []
    private(set) var ignoringCacheRequests: [ReaderPageRequest] = []
    private(set) var deletedViews: [DeletedViews] = []

    init(documents: [Int: ReaderPageDocument], failingViews: Set<Int> = []) {
        self.documents = documents
        self.failingViews = failingViews
    }

    func loadPage(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        loadRequests.append(request)
        return try document(for: request)
    }

    func loadPageIgnoringCache(_ request: ReaderPageRequest) async throws -> ReaderPageDocument {
        ignoringCacheRequests.append(request)
        return try document(for: request)
    }

    func cachedViews(
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async -> Set<Int> {
        []
    }

    func deleteCachedViews(
        _ views: Set<Int>,
        for threadURL: URL,
        authorID: String?,
        contentSource: ReaderContentSource?
    ) async throws {
        deletedViews.append(DeletedViews(
            views: views,
            threadURL: threadURL,
            authorID: authorID,
            contentSource: contentSource
        ))
    }

    private func document(for request: ReaderPageRequest) throws -> ReaderPageDocument {
        if failingViews.contains(request.view) {
            throw URLError(.cannotLoadFromNetwork)
        }
        guard let document = documents[request.view] else {
            throw URLError(.badServerResponse)
        }
        return document
    }
}

private func makeNovelDocument(
    threadURL: URL,
    view: Int,
    maxView: Int,
    authorID: String? = nil,
    contentSource: ReaderContentSource = .authorFilteredPage
) -> ReaderPageDocument {
    ReaderPageDocument(
        threadURL: threadURL,
        view: view,
        maxView: maxView,
        resolvedAuthorID: authorID,
        contentSource: contentSource,
        segments: [
            .text(String(repeating: "第\(view)页正文。", count: 80), chapterTitle: "第\(view)章")
        ]
    )
}
