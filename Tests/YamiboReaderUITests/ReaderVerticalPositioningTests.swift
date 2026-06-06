import CoreGraphics
import XCTest
import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderVerticalPositioningTests: XCTestCase {
    func testViewportReferenceLineMatchesProgressSamplingAnchor() {
        let bounds = CGRect(x: 0, y: 12, width: 393, height: 852)

        XCTAssertEqual(ReaderVerticalPositioning.viewportReferenceLineY(in: bounds), 426)
    }

    func testViewportRestoreLineUsesTopReadingArea() {
        let bounds = CGRect(x: 0, y: 12, width: 393, height: 852)

        XCTAssertEqual(ReaderVerticalPositioning.viewportRestoreLineY(in: bounds), 136.32, accuracy: 0.001)
        XCTAssertLessThan(ReaderVerticalPositioning.viewportRestoreLineY(in: bounds), ReaderVerticalPositioning.viewportReferenceLineY(in: bounds))
    }

    func testViewportReferenceLineIgnoresScrollOffsetOrigin() {
        let scrolledBounds = CGRect(x: 0, y: 7_403, width: 393, height: 852)

        XCTAssertEqual(ReaderVerticalPositioning.viewportReferenceLineY(in: scrolledBounds), 426)
        XCTAssertNotEqual(ReaderVerticalPositioning.viewportReferenceLineY(in: scrolledBounds), scrolledBounds.midY)
    }

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

}

private func projectFilePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(relativePath)
        .path
}
