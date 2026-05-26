import CoreGraphics
import XCTest
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
}
