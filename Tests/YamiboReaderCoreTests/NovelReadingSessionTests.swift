import Foundation
import XCTest
@testable import YamiboReaderCore

final class NovelReadingSessionTests: XCTestCase {
    func testPublishesNovelTextViewportContextAfterSuccessfulIndexBuild() throws {
        let document = makeNovelDocument(
            view: 2,
            maxView: 3,
            segments: [
                ("第一章", "第一章正文"),
                ("第二章", "第二章正文")
            ]
        )
        let context = NovelTextViewportContext(
            identity: NovelTextViewportIdentity(
                threadURL: document.threadURL,
                documentView: document.view,
                maxView: document.maxView,
                fetchedAt: document.fetchedAt,
                contentSource: document.contentSource,
                appearance: ReaderAppearanceSettings(readingMode: .paged),
                layout: ReaderContainerLayout(width: 320, height: 568)
            ),
            document: NovelTextViewportDocument(
                text: "第一章正文\n\n第二章正文",
                textRangesBySegment: [
                    0: ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 5),
                    1: ReaderRenderedTextRange(segmentIndex: 1, startOffset: 7, endOffset: 12)
                ],
                insertedSeparatorRanges: [
                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 5, endOffset: 7)
                ]
            ),
            externalBlocks: [],
            diagnostics: NovelTextViewportDiagnostics(indexBuildCount: 1)
        )

        let session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [.text("第一章正文", chapterTitle: "第一章")],
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
                        readingMode: .paged,
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 0,
                                chapterTitle: "第一章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 5)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                        ]
                    ),
                    viewportContext: context
                )
            }
        )

        XCTAssertEqual(session.snapshot.viewportContext, context)
        XCTAssertEqual(session.snapshot.viewportContext?.diagnostics.indexBuildCount, 1)
    }

    func testRestoresNovelReadingPositionFromNovelTextViewportIndexRanges() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 20)),
                ("第二章", String(repeating: "第二章 内容。", count: 20)),
            ]
        )
        let resumePoint = ReaderResumePoint(
            view: 1,
            chapterOrdinal: 1,
            chapterTitle: "第二章",
            segmentIndex: 1,
            segmentOffset: 15,
            segmentProgress: 0.4,
            readingModeHint: .paged
        )
        let viewportCommentTarget = ReaderChapterCommentTarget(
            threadURL: document.threadURL,
            view: document.view,
            ownerPostID: "viewport-post",
            title: "第二章"
        )

        let session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            resumePoint: resumePoint,
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "viewport-backed page text",
                                    chapterTitle: "第二章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 99, startOffset: 0, endOffset: 1)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 99, title: "错误章节", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .paged,
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 1, startOffset: 10, endOffset: 20)
                                ],
                                chapterCommentTarget: viewportCommentTarget
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(
                                ordinal: 1,
                                title: "第二章",
                                startPageIndex: 0,
                                chapterCommentTarget: viewportCommentTarget
                            )
                        ]
                    )
                )
            }
        )

        XCTAssertEqual(session.snapshot.currentPageIndex, 0)
        XCTAssertEqual(session.snapshot.currentChapterTitle, "第二章")
        XCTAssertEqual(session.snapshot.currentPageIntraProgress, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.snapshot.chapters.map(\.title), ["第二章"])
        XCTAssertEqual(session.snapshot.chapters.first?.chapterCommentTarget?.ownerPostID, "viewport-post")
        XCTAssertEqual(session.snapshot.pages.first?.chapterCommentTarget?.ownerPostID, "viewport-post")
    }

    func testCapturesNovelReadingPositionFromNovelTextViewportIndexRanges() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", "第一段正文"),
                ("第一章", "第二段正文"),
                ("第一章", "第三段正文")
            ]
        )
        var session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "viewport-backed page text",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 99, startOffset: 900, endOffset: 950)
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
                                    ReaderRenderedTextRange(segmentIndex: 1, startOffset: 10, endOffset: 30),
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 4, endOffset: 24)
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

        session.updateVerticalViewportPosition(pageIndex: 0, intraPageProgress: 0.75)
        let position = try XCTUnwrap(session.captureNovelReadingPosition())

        XCTAssertEqual(position.segmentIndex, 2)
        XCTAssertEqual(position.segmentOffset, 14)
        XCTAssertEqual(position.segmentProgress, 0.75, accuracy: 0.001)
        XCTAssertEqual(position.readingModeHint, .vertical)
    }

    func testNoIndexedTextPreservesPreviousNovelReadingPosition() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 40))
            ]
        )
        var session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            pagination: { document, settings, _ in
                let hasIndexedText = settings.fontScale <= 1
                let indexedRanges = hasIndexedText
                    ? [ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 100)]
                    : []
                return ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "stale display value range",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 99, startOffset: 0, endOffset: 1)
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
                                ranges: indexedRanges
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )

        session.updateVerticalViewportPosition(pageIndex: 0, intraPageProgress: 0.5)
        let savedPosition = try XCTUnwrap(session.captureNovelReadingPosition())

        try session.applySettings(
            ReaderAppearanceSettings(fontScale: 1.2, readingMode: .vertical)
        )
        let restoredPosition = try XCTUnwrap(session.captureNovelReadingPosition())

        XCTAssertEqual(savedPosition.segmentIndex, 0)
        XCTAssertEqual(savedPosition.segmentOffset, 50)
        XCTAssertEqual(restoredPosition.segmentIndex, savedPosition.segmentIndex)
        XCTAssertEqual(restoredPosition.segmentOffset, savedPosition.segmentOffset)
        XCTAssertEqual(restoredPosition.segmentProgress, savedPosition.segmentProgress)
    }

    func testRestoresNovelReadingPositionFromViewportIndexRangesWithoutRenderedPageMetadata() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 20)),
                ("第二章", String(repeating: "第二章 内容。", count: 20)),
            ]
        )
        let resumePoint = ReaderResumePoint(
            view: 1,
            chapterOrdinal: 1,
            chapterTitle: "第二章",
            segmentIndex: 1,
            segmentOffset: 15,
            segmentProgress: 0.4,
            readingModeHint: .paged
        )

        let session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            resumePoint: resumePoint,
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "第二章 display value text",
                                    chapterTitle: "第二章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 1, startOffset: 10, endOffset: 20)
                                    ]
                                )
                            ],
                            documentView: document.view,
                            chapterOrdinal: 1,
                            chapterTitle: "第二章"
                        )
                    ],
                    chapters: [
                        ReaderChapter(ordinal: 1, title: "第二章", startIndex: 0)
                    ],
                    viewportIndex: NovelTextViewportIndex(
                        documentView: document.view,
                        readingMode: .paged,
                        pages: [
                            NovelTextViewportIndexPage(
                                pageIndex: 0,
                                documentView: document.view,
                                chapterOrdinal: 1,
                                chapterTitle: "第二章",
                                ranges: [
                                    ReaderRenderedTextRange(segmentIndex: 1, startOffset: 10, endOffset: 20)
                                ]
                            )
                        ],
                        chapters: [
                            NovelTextViewportIndexChapter(ordinal: 1, title: "第二章", startPageIndex: 0)
                        ]
                    )
                )
            }
        )

        XCTAssertEqual(session.snapshot.currentPageIndex, 0)
        XCTAssertEqual(session.snapshot.currentChapterTitle, "第二章")
        XCTAssertEqual(session.snapshot.currentPageIntraProgress, 0.5, accuracy: 0.001)
    }

    func testCapturesNovelReadingPositionFromViewportIndexRangesWithoutRenderedPageMetadata() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", "第一段正文"),
                ("第一章", "第二段正文"),
                ("第一章", "第三段正文")
            ]
        )
        var session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            pagination: { document, _, _ in
                ReaderPaginationResult(
                    pages: [
                        ReaderRenderedPage(
                            index: 0,
                            blocks: [
                                .text(
                                    "display value from multiple source ranges",
                                    chapterTitle: "第一章",
                                    ranges: [
                                        ReaderRenderedTextRange(segmentIndex: 1, startOffset: 10, endOffset: 30),
                                        ReaderRenderedTextRange(segmentIndex: 2, startOffset: 4, endOffset: 24)
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
                                    ReaderRenderedTextRange(segmentIndex: 1, startOffset: 10, endOffset: 30),
                                    ReaderRenderedTextRange(segmentIndex: 2, startOffset: 4, endOffset: 24)
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

        session.updateVerticalViewportPosition(pageIndex: 0, intraPageProgress: 0.75)
        let position = try XCTUnwrap(session.captureNovelReadingPosition())

        XCTAssertEqual(position.view, 1)
        XCTAssertEqual(position.chapterOrdinal, 0)
        XCTAssertEqual(position.chapterTitle, "第一章")
        XCTAssertEqual(position.segmentIndex, 2)
        XCTAssertEqual(position.segmentOffset, 14)
        XCTAssertEqual(position.segmentProgress, 0.75, accuracy: 0.001)
        XCTAssertEqual(position.readingModeHint, .vertical)
    }

    func testRestoresNovelReadingPositionWithinChapter() throws {
        let document = makeNovelDocument(
            view: 2,
            maxView: 2,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 120)),
                ("第二章", String(repeating: "第二章 内容。", count: 120)),
                ("第三章", String(repeating: "第三章 内容。", count: 120)),
            ]
        )
        let settings = ReaderAppearanceSettings(readingMode: .vertical)
        let layout = ReaderContainerLayout(width: 320, height: 568)
        let pagination = try NovelTextLayout.renderedPages(document: document, settings: settings, layout: layout)
        let savedViewportPage = try XCTUnwrap(
            pagination.viewportIndex?.pages.first { $0.chapterTitle == "第三章" && !$0.ranges.isEmpty }
        )
        let savedRange = try XCTUnwrap(savedViewportPage.ranges.first)
        let savedOffset = savedRange.startOffset + max(1, savedRange.length / 2)
        let resumePoint = ReaderResumePoint(
            view: 2,
            chapterOrdinal: try XCTUnwrap(savedViewportPage.chapterOrdinal),
            chapterTitle: savedViewportPage.chapterTitle,
            segmentIndex: savedRange.segmentIndex,
            segmentOffset: savedOffset,
            segmentProgress: 0.5,
            readingModeHint: .vertical
        )

        let session = NovelReadingSession(
            document: document,
            settings: settings,
            layout: layout,
            resumePoint: resumePoint
        )

        XCTAssertEqual(session.snapshot.currentView, 2)
        XCTAssertEqual(session.snapshot.currentChapterTitle, "第三章")
        XCTAssertEqual(session.snapshot.currentPageIndex, savedViewportPage.pageIndex)
        XCTAssertEqual(session.snapshot.viewportIndex?.pages[session.snapshot.currentPageIndex].ranges.first?.segmentIndex, savedRange.segmentIndex)
        XCTAssertGreaterThan(session.snapshot.currentPageIntraProgress, 0.2)
    }

    func testChangingReadingModePreservesNovelReadingPositionOffset() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 260)),
            ]
        )
        var session = NovelReadingSession(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let targetViewportPage = try XCTUnwrap(session.snapshot.viewportIndex?.pages.dropFirst().first { !$0.ranges.isEmpty })
        let targetRange = try XCTUnwrap(targetViewportPage.ranges.first)
        let targetOffset = targetRange.startOffset + max(1, targetRange.length / 2)

        session.updateVerticalViewportPosition(pageIndex: targetViewportPage.pageIndex, intraPageProgress: 0.5)
        try session.applySettings(ReaderAppearanceSettings(readingMode: .vertical))

        let restoredViewportPage = try XCTUnwrap(session.snapshot.viewportIndex?.pages[session.snapshot.currentPageIndex])
        let restoredPage = session.snapshot.pages[restoredViewportPage.pageIndex]
        XCTAssertEqual(restoredPage.chapterTitle, "第一章")
        XCTAssertTrue(viewportPageContainsSegmentOffset(restoredViewportPage, segmentIndex: targetRange.segmentIndex, offset: targetOffset))
    }

    func testEnablingParagraphFirstLineIndentPreservesNovelReadingPositionOffset() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 320)),
            ]
        )
        var session = NovelReadingSession(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        let targetViewportPage = try XCTUnwrap(session.snapshot.viewportIndex?.pages.dropFirst().first { !$0.ranges.isEmpty })
        let targetRange = try XCTUnwrap(targetViewportPage.ranges.first)
        let targetOffset = targetRange.startOffset + max(1, targetRange.length / 2)

        session.updateVerticalViewportPosition(pageIndex: targetViewportPage.pageIndex, intraPageProgress: 0.5)
        try session.applySettings(
            ReaderAppearanceSettings(
                indentsParagraphFirstLine: true,
                readingMode: .paged
            )
        )

        let restoredViewportPage = try XCTUnwrap(session.snapshot.viewportIndex?.pages[session.snapshot.currentPageIndex])
        let restoredPage = session.snapshot.pages[restoredViewportPage.pageIndex]
        XCTAssertEqual(restoredPage.chapterTitle, "第一章")
        XCTAssertTrue(viewportPageContainsSegmentOffset(restoredViewportPage, segmentIndex: targetRange.segmentIndex, offset: targetOffset))
    }

    func testPagedTextKitRepaginationPreservesSemanticReadingPosition() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 90)),
            ]
        )
        var session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568),
            pagination: textRangePagination(
                defaultRanges: [0 ..< 100, 100 ..< 200, 200 ..< 300],
                repaginatedRanges: [0 ..< 60, 60 ..< 120, 120 ..< 180, 180 ..< 240, 240 ..< 300]
            )
        )

        session.updateVerticalViewportPosition(pageIndex: 1, intraPageProgress: 0.5)
        let savedPosition = try XCTUnwrap(session.captureNovelReadingPosition())

        try session.applySettings(
            ReaderAppearanceSettings(
                fontScale: 1.25,
                lineHeightScale: 1.7,
                horizontalPadding: 24,
                readingMode: .paged
            )
        )

        let restoredViewportPage = try XCTUnwrap(session.snapshot.viewportIndex?.pages[session.snapshot.currentPageIndex])
        XCTAssertEqual(savedPosition.view, 1)
        XCTAssertEqual(savedPosition.chapterOrdinal, 0)
        XCTAssertEqual(savedPosition.chapterTitle, "第一章")
        XCTAssertEqual(savedPosition.segmentIndex, 0)
        XCTAssertEqual(savedPosition.segmentOffset, 150)
        XCTAssertEqual(savedPosition.readingModeHint, .paged)
        XCTAssertTrue(viewportPageContainsSegmentOffset(restoredViewportPage, segmentIndex: 0, offset: savedPosition.segmentOffset))
        XCTAssertEqual(restoredViewportPage.ranges.first?.startOffset, 120)
        XCTAssertEqual(restoredViewportPage.ranges.first?.endOffset, 180)
        XCTAssertEqual(session.snapshot.currentPageIntraProgress, 0.5, accuracy: 0.001)
    }

    func testVerticalTextKitViewportRepaginationPreservesIntraPageProgress() throws {
        let document = makeNovelDocument(
            view: 1,
            maxView: 1,
            segments: [
                ("第一章", String(repeating: "第一章 内容。", count: 90)),
            ]
        )
        var session = try NovelReadingSession(
            validating: document,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568),
            pagination: textRangePagination(
                defaultRanges: [0 ..< 200, 200 ..< 300],
                repaginatedRanges: [0 ..< 40, 40 ..< 80, 80 ..< 120, 120 ..< 160, 160 ..< 200, 200 ..< 240, 240 ..< 300]
            )
        )

        session.updateVerticalViewportPosition(pageIndex: 0, intraPageProgress: 0.25)
        let savedPosition = try XCTUnwrap(session.captureNovelReadingPosition())

        try session.updateLayout(
            ReaderContainerLayout(
                containerSize: CGSize(width: 390, height: 844),
                safeAreaInsets: ReaderLayoutInsets(top: 59, bottom: 34),
                contentInsets: ReaderLayoutInsets(top: 16, leading: 20, bottom: 24, trailing: 20),
                chromeInsets: ReaderLayoutInsets(top: 72, bottom: 96),
                readingMode: .vertical
            )
        )

        let restoredViewportPage = try XCTUnwrap(session.snapshot.viewportIndex?.pages[session.snapshot.currentPageIndex])
        XCTAssertEqual(savedPosition.segmentOffset, 50)
        XCTAssertEqual(savedPosition.segmentProgress, 0.25, accuracy: 0.001)
        XCTAssertEqual(savedPosition.readingModeHint, .vertical)
        XCTAssertTrue(viewportPageContainsSegmentOffset(restoredViewportPage, segmentIndex: 0, offset: savedPosition.segmentOffset))
        XCTAssertEqual(restoredViewportPage.ranges.first?.startOffset, 40)
        XCTAssertEqual(restoredViewportPage.ranges.first?.endOffset, 80)
        XCTAssertEqual(session.snapshot.currentPageIntraProgress, 0.25, accuracy: 0.001)
    }

    func testVerticalModeKeepsPrefetchedReaderPageDocumentSeparate() {
        let current = makeNovelDocument(view: 1, maxView: 2, segments: [("第一章", "当前页正文")])
        let prefetched = makeNovelDocument(view: 2, maxView: 2, segments: [("第二章", "预取页正文")])
        var session = NovelReadingSession(
            document: current,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )

        session.acceptPrefetchedDocument(prefetched)

        XCTAssertEqual(session.snapshot.currentView, 1)
        XCTAssertEqual(session.snapshot.maxView, 2)
        XCTAssertNil(session.snapshot.prefetchedStartIndex)
        XCTAssertEqual(session.snapshot.pages.map(\.documentView), [1])
        XCTAssertEqual(session.snapshot.chapters.map(\.title), ["第一章"])
    }

    func testPromotesPrefetchedReaderPageDocument() throws {
        let current = makeNovelDocument(view: 1, maxView: 2, segments: [("第一章", "当前页正文")])
        let prefetched = makeNovelDocument(view: 2, maxView: 2, segments: [("第二章", "预取页正文")])
        var session = NovelReadingSession(
            document: current,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        session.acceptPrefetchedDocument(prefetched)

        try session.promotePrefetchedDocument()

        XCTAssertEqual(session.snapshot.currentView, 2)
        XCTAssertEqual(session.snapshot.maxView, 2)
        XCTAssertNil(session.snapshot.prefetchedStartIndex)
        XCTAssertEqual(session.snapshot.pages.map(\.documentView), [2])
        XCTAssertEqual(session.snapshot.currentChapterTitle, "第二章")
    }

    func testTwoPageSpreadNormalizesSelectionToLeftPage() throws {
        let document = ReaderPageDocument(
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9002&mobile=2")!,
            view: 1,
            maxView: 1,
            contentSource: .fallbackUnfilteredPage,
            segments: (0 ..< 6).map { .image(URL(string: "https://example.com/\($0).jpg")!, chapterTitle: "第一章") }
        )
        var session = NovelReadingSession(
            document: document,
            settings: ReaderAppearanceSettings(
                showsTwoPagesInLandscapeOnPad: true,
                readingMode: .paged
            ),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )

        try session.updatePagedPresentationEnvironment(isPad: true)
        try session.updateLayout(ReaderContainerLayout(width: 844, height: 390, readingMode: .paged))
        session.jumpToRenderedPage(3)

        XCTAssertEqual(
            session.snapshot.pagedSpreads.map { "\($0.leftPageIndex)-\($0.rightPageIndex.map(String.init) ?? "nil")" },
            ["0-1", "2-3", "4-5"]
        )
        XCTAssertEqual(session.snapshot.currentPageIndex, 2)
    }

    func testJumpRelativePageRequestsNextWebViewPageWhenNeeded() {
        let document = makeNovelDocument(
            view: 1,
            maxView: 2,
            segments: [("第一章", "当前页正文")]
        )
        var session = NovelReadingSession(
            document: document,
            settings: ReaderAppearanceSettings(readingMode: .paged),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )

        let request = session.jumpRelativePage(1)

        XCTAssertEqual(request, .loadView(view: 2, preferredPage: 0, resumePoint: nil))
        XCTAssertEqual(session.snapshot.currentView, 1)
    }
}

private func makeNovelDocument(
    view: Int,
    maxView: Int,
    segments: [(chapterTitle: String, text: String)]
) -> ReaderPageDocument {
    ReaderPageDocument(
        threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9001&mobile=2")!,
        view: view,
        maxView: maxView,
        contentSource: .fallbackUnfilteredPage,
        segments: segments.map { .text($0.text, chapterTitle: $0.chapterTitle) }
    )
}

private func viewportPageContainsSegmentOffset(_ page: NovelTextViewportIndexPage, segmentIndex: Int, offset: Int) -> Bool {
    page.ranges.filter { $0.segmentIndex == segmentIndex }.contains { range in
        if range.startOffset == range.endOffset {
            return offset <= range.startOffset
        }
        return offset >= range.startOffset && offset < range.endOffset
    }
}

private func textRangePagination(
    defaultRanges: [Range<Int>],
    repaginatedRanges: [Range<Int>]
) -> NovelTextPagination {
    { document, settings, layout in
        let ranges = settings.fontScale > 1 || settings.lineHeightScale > 1.45 || settings.horizontalPadding > 16 || layout.width > 320
            ? repaginatedRanges
            : defaultRanges
        return ReaderPaginationResult(
            pages: ranges.enumerated().map { index, range in
                ReaderRenderedPage(
                    index: index,
                    blocks: [],
                    documentView: document.view,
                    chapterOrdinal: 0,
                    chapterTitle: "第一章"
                )
            },
            chapters: [
                ReaderChapter(ordinal: 0, title: "第一章", startIndex: 0)
            ],
            viewportIndex: NovelTextViewportIndex(
                documentView: document.view,
                readingMode: settings.readingMode,
                pages: ranges.enumerated().map { index, range in
                    NovelTextViewportIndexPage(
                        pageIndex: index,
                        documentView: document.view,
                        chapterOrdinal: 0,
                        chapterTitle: "第一章",
                        ranges: [
                            ReaderRenderedTextRange(
                                segmentIndex: 0,
                                startOffset: range.lowerBound,
                                endOffset: range.upperBound
                            )
                        ]
                    )
                },
                chapters: [
                    NovelTextViewportIndexChapter(ordinal: 0, title: "第一章", startPageIndex: 0)
                ]
            )
        )
    }
}
