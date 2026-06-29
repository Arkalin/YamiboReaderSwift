import XCTest
@testable import YamiboReaderUI

final class ReaderVerticalViewportPositionUpdateTimingTests: XCTestCase {
    func testTextViewportSampleChangeAppliesProgressImmediately() {
        XCTAssertEqual(
            ReaderVerticalViewportPositionUpdateTiming.updateMode(for: .textViewportSampleChanged),
            .immediate
        )
    }

    func testViewportGeometryChangeMayStayDeferred() {
        XCTAssertEqual(
            ReaderVerticalViewportPositionUpdateTiming.updateMode(for: .viewportGeometryChanged),
            .deferred
        )
    }
}
