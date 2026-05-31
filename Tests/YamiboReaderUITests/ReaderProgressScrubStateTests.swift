import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderProgressScrubStateTests: XCTestCase {
    func testUpdatingScrubClampsValueAndBuildsPreviewWithoutCommit() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .paged,
            pageCount: 5,
            currentProgressPercent: 20,
            targetPageIndex: { value in min(max(Int(value.rounded()), 0), 4) },
            chapterTitle: { index in index >= 2 ? "第二章" : "第一章" },
            chapterTickStartIndex: { index in index == 2 ? 2 : nil }
        )

        let update = state.update(value: 99, context: context)

        XCTAssertEqual(state.phase, .scrubbing)
        XCTAssertEqual(state.value, 4)
        XCTAssertEqual(state.targetRenderedPageIndex, 4)
        XCTAssertEqual(state.preview, ReaderProgressScrubPreview(chapterTitle: "第二章", pageNumber: 5))
        XCTAssertNil(update.committedPageIndex)
    }

    func testCommitReturnsOneTargetPageAndCommitHaptic() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .paged,
            pageCount: 5,
            currentProgressPercent: 0,
            targetPageIndex: { value in Int(value.rounded()) },
            chapterTitle: { _ in nil },
            chapterTickStartIndex: { _ in nil }
        )

        _ = state.update(value: 3, context: context)
        let commit = state.end()

        XCTAssertEqual(state.phase, .ended)
        XCTAssertEqual(commit.committedPageIndex, 3)
        XCTAssertEqual(commit.haptics, [.commit])
    }

    func testHapticsFireForStartAndChapterTickButNotEveryPage() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .paged,
            pageCount: 6,
            currentProgressPercent: 0,
            targetPageIndex: { value in Int(value.rounded()) },
            chapterTitle: { _ in nil },
            chapterTickStartIndex: { index in [0, 2, 5].contains(index) ? index : nil }
        )

        XCTAssertEqual(state.update(value: 1, context: context).haptics, [.start])
        XCTAssertEqual(state.update(value: 2, context: context).haptics, [.chapterTick])
        XCTAssertEqual(state.update(value: 3, context: context).haptics, [])
    }

    func testPreviewFallsBackToPageOnlyWhenChapterTitleIsUnavailable() {
        var state = ReaderProgressScrubState()
        let context = ReaderProgressScrubContext(
            readingMode: .vertical,
            pageCount: 6,
            currentProgressPercent: 40,
            targetPageIndex: { value in Int((value / 100 * 5).rounded()) },
            chapterTitle: { _ in nil },
            chapterTickStartIndex: { _ in nil }
        )

        _ = state.update(value: 50, context: context)

        XCTAssertEqual(state.preview?.displayText, "第4页")
    }
}
