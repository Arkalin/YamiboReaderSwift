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

    func testUpdatingSettingsThrowsWhenAuthoritativeLayoutFailsAndKeepsSnapshot() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9110&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
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
            repository: repository,
            pagination: { document, settings, layout in
                if settings.fontScale > 1 {
                    throw NovelTextLayoutFailure.unableToLayoutText
                }
                return try NovelTextLayout.renderedPages(
                    document: document,
                    settings: settings,
                    layout: layout
                )
            }
        )
        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())

        do {
            _ = try workflow.updateSettings(
                ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged)
            )
            XCTFail("Expected Novel Text Layout failure")
        } catch let failure as NovelTextLayoutFailure {
            XCTAssertEqual(failure, .unableToLayoutText)
        }

        XCTAssertEqual(workflow.state, initialState)
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

    func testVerticalViewportSampleUpdatesSessionBackedNovelReadingPosition() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9111&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: makeNovelDocument(threadURL: threadURL, view: 1, maxView: 1, authorID: "author-1")
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
            repository: repository,
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第一页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章",
                            segmentIndex: 99,
                            segmentStartOffset: 900,
                            segmentEndOffset: 950
                        ),
                        ReaderRenderedPage(
                            index: 1,
                            blocks: [
                                .text(
                                    "第二页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章",
                            segmentIndex: 99,
                            segmentStartOffset: 950,
                            segmentEndOffset: 990
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                    ]
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        let state = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.25)
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(state.snapshot.currentPageIndex, 1)
        XCTAssertEqual(state.snapshot.currentPageIntraProgress, 0.25, accuracy: 0.001)
        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 0)
        XCTAssertEqual(resumePoint.chapterTitle, "第一章")
        XCTAssertEqual(resumePoint.segmentIndex, 2)
        XCTAssertEqual(resumePoint.segmentOffset, 50)
        XCTAssertEqual(resumePoint.authorID, "author-1")
        XCTAssertEqual(resumePoint.readingModeHint, .vertical)
    }

    func testCurrentProgressPositionUsesSessionBackedResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9112&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            2: makeNovelDocument(threadURL: threadURL, view: 2, maxView: 3, authorID: "author-2")
        ])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .forum,
                initialView: 2,
                authorID: "launch-author"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第一页",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        ReaderRenderedPage(
                            index: 1,
                            blocks: [
                                .text(
                                    "第二页",
                                    chapterTitle: "第二章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 1, startOffset: 20, endOffset: 60)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0),
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 1)
                    ]
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.5)

        let position = workflow.currentProgressPosition()

        XCTAssertEqual(position.threadURL, threadURL)
        XCTAssertEqual(position.view, 2)
        XCTAssertEqual(position.page, 1)
        XCTAssertEqual(position.chapterTitle, "第二章")
        XCTAssertEqual(position.authorID, "author-2")
        XCTAssertEqual(position.resumePoint?.view, 2)
        XCTAssertEqual(position.resumePoint?.chapterOrdinal, 1)
        XCTAssertEqual(position.resumePoint?.chapterTitle, "第二章")
        XCTAssertEqual(position.resumePoint?.segmentIndex, 1)
        XCTAssertEqual(position.resumePoint?.segmentOffset, 40)
    }

    func testPreviewSourceTextStartsAtRestoredNovelReadingPosition() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9113&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("前文不应进入预览", chapterTitle: "第一章"),
                .text("0123456789目标预览文本", chapterTitle: "第二章"),
                .text("后续段落", chapterTitle: "第二章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "Thread",
                source: .favorites,
                initialView: 1,
                authorID: "author-1"
            ),
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: previewSourcePagination
        )
        let resumePoint = ReaderResumePoint(
            view: 1,
            chapterOrdinal: 1,
            chapterTitle: "第二章",
            segmentIndex: 1,
            segmentOffset: 10,
            segmentProgress: 0,
            authorID: "author-1",
            readingModeHint: .vertical
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition(resumePoint: resumePoint))

        let previewText = workflow.currentPreviewSourceText()

        XCTAssertTrue(previewText.hasPrefix("目标预览文本"))
        XCTAssertTrue(previewText.contains("后续段落"))
        XCTAssertFalse(previewText.contains("前文不应进入预览"))
    }

    func testPreviewSourceTextFollowsVerticalViewportMovement() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9114&mobile=2")!
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-1",
            contentSource: .authorFilteredPage,
            segments: [
                .text("第一段预览", chapterTitle: "第一章"),
                .text("第二段预览", chapterTitle: "第一章"),
                .text("0123456789第三段预览", chapterTitle: "第一章")
            ]
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
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
            repository: repository,
            pagination: previewSourcePagination
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            pageIndex: 2,
            intraPageProgress: Double("0123456789".count) / Double("0123456789第三段预览".count)
        )
        let previewText = workflow.currentPreviewSourceText()

        XCTAssertTrue(previewText.hasPrefix("第三段预览"))
        XCTAssertFalse(previewText.contains("第一段预览"))
        XCTAssertFalse(previewText.contains("第二段预览"))
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

        let promotedStateOptional = try await workflow.promotePrefetchedDocument(preferredPage: 0, resumePoint: nil)
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

private func previewSourcePagination(
    document: ReaderPageDocument,
    settings: ReaderAppearanceSettings,
    layout: ReaderContainerLayout
) -> ReaderPaginationResult {
    ReaderPaginationResult(
        pages: document.segments.enumerated().map { index, segment in
            let text: String
            switch segment {
            case let .text(value, _):
                text = value
            case .image:
                text = ""
            }
            return ReaderRenderedPage(
                index: index,
                blocks: [
                    .text(
                        text,
                        chapterTitle: segment.chapterTitle,
                        ranges: [
                            ReaderRenderedTextRange(
                                segmentIndex: index,
                                startOffset: 0,
                                endOffset: text.count
                            )
                        ]
                    )
                ],
                documentView: document.view,
                chapterOrdinal: index,
                chapterTitle: segment.chapterTitle
            )
        },
        chapters: document.segments.enumerated().map { index, segment in
            ReaderChapter(
                ordinal: index,
                title: segment.chapterTitle ?? "Chapter \(index + 1)",
                startIndex: index
            )
        }
    )
}
