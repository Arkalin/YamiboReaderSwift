import Foundation
import XCTest
@testable import YamiboReaderCore

final class NovelReadingSessionTests: XCTestCase {
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
        let pagination = ReaderPaginator.paginate(document: document, settings: settings, layout: layout)
        let savedPage = try XCTUnwrap(
            pagination.pages.first { $0.chapterTitle == "第三章" && $0.segmentIndex != nil }
        )
        let savedOffset = savedPage.segmentStartOffset + max(1, (savedPage.segmentEndOffset - savedPage.segmentStartOffset) / 2)
        let resumePoint = ReaderResumePoint(
            view: 2,
            chapterOrdinal: try XCTUnwrap(savedPage.chapterOrdinal),
            chapterTitle: savedPage.chapterTitle,
            segmentIndex: try XCTUnwrap(savedPage.segmentIndex),
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
        XCTAssertEqual(session.snapshot.currentPageIndex, savedPage.index)
        XCTAssertEqual(session.snapshot.pages[session.snapshot.currentPageIndex].segmentIndex, savedPage.segmentIndex)
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
        let targetPage = try XCTUnwrap(session.snapshot.pages.dropFirst().first { $0.segmentIndex != nil })
        let targetOffset = targetPage.segmentStartOffset + max(1, (targetPage.segmentEndOffset - targetPage.segmentStartOffset) / 2)

        session.updateVerticalViewportPosition(pageIndex: targetPage.index, intraPageProgress: 0.5)
        session.applySettings(ReaderAppearanceSettings(readingMode: .vertical))

        let restoredPage = session.snapshot.pages[session.snapshot.currentPageIndex]
        XCTAssertEqual(restoredPage.chapterTitle, "第一章")
        XCTAssertTrue(pageContainsSegmentOffset(restoredPage, segmentIndex: try XCTUnwrap(targetPage.segmentIndex), offset: targetOffset))
    }

    func testVerticalModeMergesPrefetchedReaderPageDocument() {
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
        XCTAssertEqual(session.snapshot.prefetchedStartIndex, 1)
        XCTAssertEqual(session.snapshot.pages.map(\.documentView), [1, 2])
        XCTAssertEqual(session.snapshot.chapters.map(\.title), ["第一章", "第二章"])
    }

    func testPromotesPrefetchedReaderPageDocument() {
        let current = makeNovelDocument(view: 1, maxView: 2, segments: [("第一章", "当前页正文")])
        let prefetched = makeNovelDocument(view: 2, maxView: 2, segments: [("第二章", "预取页正文")])
        var session = NovelReadingSession(
            document: current,
            settings: ReaderAppearanceSettings(readingMode: .vertical),
            layout: ReaderContainerLayout(width: 320, height: 568)
        )
        session.acceptPrefetchedDocument(prefetched)

        session.promotePrefetchedDocument()

        XCTAssertEqual(session.snapshot.currentView, 2)
        XCTAssertEqual(session.snapshot.maxView, 2)
        XCTAssertNil(session.snapshot.prefetchedStartIndex)
        XCTAssertEqual(session.snapshot.pages.map(\.documentView), [2])
        XCTAssertEqual(session.snapshot.currentChapterTitle, "第二章")
    }

    func testTwoPageSpreadNormalizesSelectionToLeftPage() {
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

        session.updatePagedPresentationEnvironment(isPad: true)
        session.updateLayout(ReaderContainerLayout(width: 844, height: 390, readingMode: .paged))
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

private func pageContainsSegmentOffset(_ page: ReaderRenderedPage, segmentIndex: Int, offset: Int) -> Bool {
    let matchingRanges = page.textRanges.filter { $0.segmentIndex == segmentIndex }
    if !matchingRanges.isEmpty {
        return matchingRanges.contains { range in
            if range.startOffset == range.endOffset {
                return offset <= range.startOffset
            }
            return offset >= range.startOffset && offset < range.endOffset
        }
    }
    guard page.segmentIndex == segmentIndex else { return false }
    if page.segmentStartOffset == page.segmentEndOffset {
        return offset <= page.segmentStartOffset
    }
    return offset >= page.segmentStartOffset && offset < page.segmentEndOffset
}
