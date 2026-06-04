import CoreGraphics
import XCTest
import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderVerticalPositioningTests: XCTestCase {
    func testSamplesNearestVerticalPageAtReferenceLine() {
        let frames = [
            0: CGRect(x: 0, y: -300, width: 320, height: 400),
            1: CGRect(x: 0, y: 120, width: 320, height: 500)
        ]

        let sample = ReaderVerticalPositioning.sample(
            frames: frames,
            referenceLineY: 160
        )

        XCTAssertEqual(sample?.pageIndex, 1)
        XCTAssertEqual(sample?.intraPageProgress ?? -1, 0.08, accuracy: 0.001)
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
