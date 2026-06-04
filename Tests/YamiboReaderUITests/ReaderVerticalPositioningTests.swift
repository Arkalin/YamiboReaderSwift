import CoreGraphics
import XCTest
import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderVerticalPositioningTests: XCTestCase {
    func testPageDistanceReportsZeroOnlyWhenReferenceLineCrossesFrame() {
        let containingFrame = CGRect(x: 0, y: 120, width: 320, height: 500)
        let aboveFrame = CGRect(x: 0, y: 240, width: 320, height: 500)
        let belowFrame = CGRect(x: 0, y: -300, width: 320, height: 400)

        XCTAssertEqual(ReaderVerticalPositioning.pageDistance(from: 160, to: containingFrame), 0)
        XCTAssertEqual(ReaderVerticalPositioning.pageDistance(from: 160, to: aboveFrame), 80)
        XCTAssertEqual(ReaderVerticalPositioning.pageDistance(from: 160, to: belowFrame), 60)
    }

    func testReaderContainerViewDoesNotUseFrameSamplerForVerticalTextPosition() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"))

        XCTAssertFalse(source.contains("ReaderVerticalPositioning.sample("))
        XCTAssertFalse(source.contains("intraPageProgress: sample.intraPageProgress"))
    }

    func testTextKitDisplayOffsetMapsToSegmentLocalNovelTextViewportSample() {
        let displayValue = NovelTextDisplayValue(
            text: "第一段正文\n\n第二段正文",
            chapterTitle: "第一章",
            ranges: [
                ReaderRenderedTextRange(segmentIndex: 0, startOffset: 10, endOffset: 15),
                ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 45)
            ]
        )

        let sample = ReaderVerticalViewportTextOffsetMapper.sample(
            displayOffset: 9,
            displayValue: displayValue,
            documentView: 3,
            pageIndex: 7
        )

        XCTAssertEqual(sample?.documentView, 3)
        XCTAssertEqual(sample?.pageIndex, 7)
        XCTAssertEqual(sample?.segmentIndex, 2)
        XCTAssertEqual(sample?.segmentOffset, 42)
    }

    func testTextAnchorMapsBackToDisplayOffsetForTextKitRestore() {
        let displayValue = NovelTextDisplayValue(
            text: "第一段正文\n\n第二段正文",
            chapterTitle: "第一章",
            ranges: [
                ReaderRenderedTextRange(segmentIndex: 0, startOffset: 10, endOffset: 15),
                ReaderRenderedTextRange(segmentIndex: 2, startOffset: 40, endOffset: 45)
            ]
        )

        let displayOffset = ReaderVerticalViewportTextOffsetMapper.displayOffset(
            for: ReaderVerticalTextAnchor(segmentIndex: 2, segmentOffset: 42),
            displayValue: displayValue
        )

        XCTAssertEqual(displayOffset, 9)
    }
}

private func projectFilePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(relativePath)
        .path
}
