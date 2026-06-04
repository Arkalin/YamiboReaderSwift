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

    func testVerticalViewportSampleUsesTextKitIndexPositionInsteadOfFrameProgress() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9153&mobile=2")!
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
                            chapterTitle: "第一章"
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
                            chapterTitle: "第一章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 20)
                                ]
                            ),
                            NovelTextViewportIndexPage(
                                pageIndex: 1,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.25)

        let state = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(
                sample: NovelTextViewportSample(
                    documentView: 1,
                    pageIndex: 1,
                    segmentIndex: 2,
                    segmentOffset: 68
                )
            )
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(state.snapshot.currentPageIndex, 1)
        XCTAssertEqual(state.snapshot.currentPageIntraProgress, 0.7, accuracy: 0.001)
        XCTAssertEqual(resumePoint.segmentIndex, 2)
        XCTAssertEqual(resumePoint.segmentOffset, 68)
        XCTAssertNotEqual(resumePoint.segmentOffset, 50)
    }

    func testVerticalViewportSamplePreservesExactOffsetInsideMultiRangePage() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9157&mobile=2")!
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
                let ranges = [
                    ReaderRenderedTextRange(segmentIndex: 15, startOffset: 0, endOffset: 2_000),
                    ReaderRenderedTextRange(segmentIndex: 16, startOffset: 1_101, endOffset: 2_000)
                ]
                return ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第六十页",
                                    chapterTitle: "第二章",
                                    ranges: ranges
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章",
                            viewportTextRanges: ranges
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .vertical,
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: ranges
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 1, title: "第二章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(
                documentView: 1,
                pageIndex: 0,
                segmentIndex: 16,
                segmentOffset: 1_256
            )
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(resumePoint.segmentIndex, 16)
        XCTAssertEqual(resumePoint.segmentOffset, 1_256)
        XCTAssertNotEqual(resumePoint.segmentOffset, 1_101)
    }

    func testExternalBlockViewportMovementPreservesTextOnlyResumeUntilNextTextSample() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9154&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 1,
                resolvedAuthorID: "author-1",
                segments: [
                    .text("前文正文", chapterTitle: "第一章"),
                    .image(URL(string: "https://example.com/image.jpg")!, chapterTitle: "第一章"),
                    .text("后文正文", chapterTitle: "第一章")
                ]
            )
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
                                    "前文正文",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 30)
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
                                .image(URL(string: "https://example.com/image.jpg")!, chapterTitle: "第一章")
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        ),
                        ReaderRenderedPage(
                            index: 2,
                            blocks: [
                                .text(
                                    "后文正文",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 80)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 0,
                            chapterTitle: "第一章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                    ]
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(documentView: 1, pageIndex: 0, segmentIndex: 0, segmentOffset: 15)
        )
        let beforeImage = try XCTUnwrap(workflow.captureNovelReadingPosition())
        _ = workflow.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.5)
        let onImage = try XCTUnwrap(workflow.captureNovelReadingPosition())
        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(documentView: 1, pageIndex: 2, segmentIndex: 2, segmentOffset: 64)
        )
        let afterImage = try XCTUnwrap(workflow.captureNovelReadingPosition())

        XCTAssertEqual(beforeImage.segmentIndex, 0)
        XCTAssertEqual(beforeImage.segmentOffset, 15)
        XCTAssertEqual(onImage.segmentIndex, 0)
        XCTAssertEqual(onImage.segmentOffset, 15)
        XCTAssertEqual(afterImage.segmentIndex, 2)
        XCTAssertEqual(afterImage.segmentOffset, 64)
    }

    func testNoTextReaderPageDocumentPreservesPreviousTextOnlyResumePoint() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9254&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 2,
                resolvedAuthorID: "author-1",
                segments: [
                    .text("有正文的网页", chapterTitle: "第一章")
                ]
            ),
            2: ReaderPageDocument(
                threadURL: threadURL,
                view: 2,
                maxView: 2,
                resolvedAuthorID: "author-1",
                segments: [
                    .image(URL(string: "https://example.com/only-image.jpg")!, chapterTitle: "第二章")
                ]
            )
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
                if document.view == 1 {
                    return ReaderPaginationResult(
                        pages: [
                            ReaderRenderedPage(
                                index: 0,
                                blocks: [
                                    .text(
                                        "有正文的网页",
                                        chapterTitle: "第一章",
                                        ranges: [
                                            ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 40)
                                        ]
                                    )
                                ],
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章"
                            )
                        ],
                        chapters: [
                            ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
                        ]
                    )
                }
                return ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .image(URL(string: "https://example.com/only-image.jpg")!, chapterTitle: "第二章")
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 0)
                    ]
                )
            }
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())
        _ = workflow.updateVerticalViewportPosition(
            sample: NovelTextViewportSample(documentView: 1, pageIndex: 0, segmentIndex: 0, segmentOffset: 24)
        )

        _ = try await workflow.loadView(2, preferredPage: 0, preferredResumePoint: nil, forceRefresh: false)
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())
        let progressPosition = workflow.currentProgressPosition()

        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 0)
        XCTAssertEqual(resumePoint.chapterTitle, "第一章")
        XCTAssertEqual(resumePoint.segmentIndex, 0)
        XCTAssertEqual(resumePoint.segmentOffset, 24)
        XCTAssertEqual(progressPosition.view, 2)
        XCTAssertEqual(progressPosition.page, 0)
        XCTAssertEqual(progressPosition.resumePoint?.view, 1)
        XCTAssertEqual(progressPosition.resumePoint?.segmentOffset, 24)
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

    func testCurrentProgressPositionSurvivesNavigationSettingsAndLayoutChanges() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9115&mobile=2")!
        let repository = RecordingNovelReadingRepository(documents: [
            1: ReaderPageDocument(
                threadURL: threadURL,
                view: 1,
                maxView: 1,
                resolvedAuthorID: "author-1",
                contentSource: .authorFilteredPage,
                segments: [
                    .text(String(repeating: "第一章 内容。", count: 120), chapterTitle: "第一章")
                ]
            )
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
            pagination: workflowRepaginationRanges(
                defaultRanges: [0 ..< 100, 100 ..< 200, 200 ..< 300],
                repaginatedRanges: [0 ..< 60, 60 ..< 120, 120 ..< 180, 180 ..< 240, 240 ..< 300]
            )
        )
        _ = try await workflow.start(initial: NovelReadingInitialPosition())

        _ = workflow.jumpToRenderedPage(1)
        let navigatedPosition = workflow.currentProgressPosition()

        XCTAssertEqual(navigatedPosition.threadURL, threadURL)
        XCTAssertEqual(navigatedPosition.view, 1)
        XCTAssertEqual(navigatedPosition.page, 1)
        XCTAssertEqual(navigatedPosition.chapterTitle, "第一章")
        XCTAssertEqual(navigatedPosition.authorID, "author-1")
        XCTAssertEqual(navigatedPosition.resumePoint?.segmentOffset, 100)

        _ = try workflow.updateSettings(ReaderAppearanceSettings(fontScale: 1.25, readingMode: .paged))
        let settingsPosition = workflow.currentProgressPosition()

        XCTAssertEqual(settingsPosition.resumePoint?.segmentOffset, 100)
        XCTAssertEqual(settingsPosition.page, 1)

        _ = try workflow.updateLayout(ReaderContainerLayout(width: 390, height: 844, readingMode: .paged))
        let layoutPosition = workflow.currentProgressPosition()

        XCTAssertEqual(layoutPosition.resumePoint?.segmentOffset, 100)
        XCTAssertEqual(layoutPosition.page, 1)
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

    func testLongCurrentWebpageViewportPublishesExactIndexAndRestoresAcrossReaderChanges() async throws {
        let threadURL = URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1520&mobile=2")!
        let chapterTitles = (1...6).map { "第\($0)章" }
        let document = ReaderPageDocument(
            threadURL: threadURL,
            view: 1,
            maxView: 1,
            resolvedAuthorID: "author-152",
            contentSource: .fallbackUnfilteredPage,
            segments: chapterTitles.map { title in
                .text(String(repeating: "\(title) 长篇当前页正文。", count: 50), chapterTitle: title)
            }
        )
        let repository = RecordingNovelReadingRepository(documents: [1: document])
        let workflow = NovelReadingWorkflow(
            context: ReaderLaunchContext(
                threadURL: threadURL,
                threadTitle: "测试线程",
                source: .forum,
                initialView: 1,
                authorID: "author-152"
            ),
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            repository: repository,
            pagination: currentWebpageViewportPagination
        )

        let initialState = try await workflow.start(initial: NovelReadingInitialPosition())
        assertLongCurrentWebpageViewportState(
            initialState,
            chapterTitles: chapterTitles,
            currentPageIndex: 0,
            currentChapterTitle: "第1章"
        )
        XCTAssertEqual(initialState.snapshot.pages.map(\.blocks).filter(\.isEmpty).count, 6)
        XCTAssertEqual(initialState.snapshot.viewportContext?.diagnostics.indexBuildCount, 1)
        XCTAssertEqual(initialState.snapshot.viewportContext?.diagnostics.visibleLayoutPassCount, 0)
        XCTAssertEqual(initialState.snapshot.viewportContext?.diagnostics.compatibilityTextDisplayValueCount, 0)

        let movedState = try XCTUnwrap(
            workflow.updateVerticalViewportPosition(pageIndex: 4, intraPageProgress: 0.5)
        )
        assertLongCurrentWebpageViewportState(
            movedState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )
        let resumePoint = try XCTUnwrap(workflow.captureNovelReadingPosition())
        let fifthChapterLength: Int
        if case let .text(text, _) = document.segments[4] {
            fifthChapterLength = text.count
        } else {
            throw XCTSkip("Expected text segment")
        }
        XCTAssertEqual(resumePoint.view, 1)
        XCTAssertEqual(resumePoint.chapterOrdinal, 4)
        XCTAssertEqual(resumePoint.chapterTitle, "第5章")
        XCTAssertEqual(resumePoint.segmentIndex, 4)
        XCTAssertEqual(resumePoint.segmentOffset, fifthChapterLength / 2)
        XCTAssertEqual(resumePoint.authorID, "author-152")
        XCTAssertEqual(resumePoint.readingModeHint, .paged)

        let appearanceState = try XCTUnwrap(
            workflow.updateSettings(ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged))
        )
        assertLongCurrentWebpageViewportState(
            appearanceState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )

        let rotatedState = try XCTUnwrap(
            workflow.updateLayout(ReaderContainerLayout(width: 568, height: 320, readingMode: .paged))
        )
        assertLongCurrentWebpageViewportState(
            rotatedState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )

        let verticalState = try XCTUnwrap(
            workflow.updateSettings(ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical))
        )
        assertLongCurrentWebpageViewportState(
            verticalState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )

        let translatedState = try XCTUnwrap(
            workflow.updateSettings(
                ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical, translationMode: .simplified)
            )
        )
        assertLongCurrentWebpageViewportState(
            translatedState,
            chapterTitles: chapterTitles,
            currentPageIndex: 4,
            currentChapterTitle: "第5章"
        )
        XCTAssertEqual(translatedState.snapshot.viewportIndex?.pages[4].ranges.first?.segmentIndex, 4)
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

private func workflowRepaginationRanges(
    defaultRanges: [Range<Int>],
    repaginatedRanges: [Range<Int>]
) -> NovelTextPagination {
    { document, settings, layout in
        let ranges = settings.fontScale > 1 || layout.width > 320
            ? repaginatedRanges
            : defaultRanges
        return ReaderPaginationResult(
            pages: ranges.enumerated().map { index, range in
                ReaderRenderedPage(
                    index: index,
                    blocks: [
                        .text(
                            "slice-\(range.lowerBound)-\(range.upperBound)",
                            chapterTitle: "第一章",
                            ranges: [
                                ReaderRenderedTextRange(
                                    segmentIndex: 0,
                                    startOffset: range.lowerBound,
                                    endOffset: range.upperBound
                                )
                            ]
                        )
                    ],
                    documentView: document.view,
                    chapterOrdinal: 0,
                    chapterTitle: "第一章",
                    segmentIndex: 0,
                    segmentStartOffset: range.lowerBound,
                    segmentEndOffset: range.upperBound
                )
            },
            chapters: [
                ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
            ]
        )
    }
}

private func currentWebpageViewportPagination(
    document: ReaderPageDocument,
    settings: ReaderAppearanceSettings,
    layout: ReaderContainerLayout
) throws -> ReaderPaginationResult {
    try NovelTextLayout.renderedPages(
        document: document,
        settings: settings,
        layout: layout,
        requiresAuthoritativePagedLayout: false,
        requiresAuthoritativeVerticalLayout: false,
        pagedLayout: { text, _, _, _ in
            [TextSlice(text: text, startOffset: 0, endOffset: text.count)]
        },
        verticalLayout: { text, _, _, _ in
            [TextSlice(text: text, startOffset: 0, endOffset: text.count)]
        },
        usesViewportIndexCache: false
    )
}

private func assertLongCurrentWebpageViewportState(
    _ state: NovelReadingWorkflowState,
    chapterTitles: [String],
    currentPageIndex: Int,
    currentChapterTitle: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(state.snapshot.pages.count, chapterTitles.count, file: file, line: line)
    XCTAssertTrue(state.snapshot.pages.allSatisfy { $0.blocks.isEmpty }, file: file, line: line)
    XCTAssertEqual(state.snapshot.chapters.map(\.title), chapterTitles, file: file, line: line)
    XCTAssertEqual(state.snapshot.chapters.map(\.startIndex), Array(chapterTitles.indices), file: file, line: line)
    XCTAssertEqual(state.snapshot.currentPageIndex, currentPageIndex, file: file, line: line)
    XCTAssertEqual(state.snapshot.currentChapterTitle, currentChapterTitle, file: file, line: line)
    XCTAssertEqual(state.snapshot.viewportContext?.identity.documentView, 1, file: file, line: line)
    XCTAssertEqual(state.snapshot.viewportContext?.diagnostics.indexBuildCount, 1, file: file, line: line)
    XCTAssertEqual(state.snapshot.viewportContext?.diagnostics.visibleLayoutPassCount, 0, file: file, line: line)
    XCTAssertEqual(
        state.snapshot.viewportContext?.diagnostics.compatibilityTextDisplayValueCount,
        0,
        file: file,
        line: line
    )
    XCTAssertEqual(state.snapshot.viewportIndex?.pages.count, chapterTitles.count, file: file, line: line)
    XCTAssertEqual(
        state.snapshot.viewportIndex?.pages[currentPageIndex].ranges.first?.segmentIndex,
        currentPageIndex,
        file: file,
        line: line
    )
}
