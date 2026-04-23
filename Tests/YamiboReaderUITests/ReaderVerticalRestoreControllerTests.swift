import XCTest
@testable import YamiboReaderUI

final class ReaderVerticalRestoreControllerTests: XCTestCase {
    func testActiveRestoreSuppressesViewportSamplingIncludingForcedSave() {
        var controller = ReaderVerticalRestoreController()
        let request = ReaderVerticalScrollRequest(pageIndex: 81, intraPageProgress: 0.0194)

        controller.beginScrolling(to: request)

        XCTAssertEqual(controller.activeRequest, request)
        XCTAssertFalse(controller.canSampleViewport(now: 10))
    }

    func testScrollingRestoreStaysActiveForLateFrameRetryUntilFineTuneSettles() {
        var controller = ReaderVerticalRestoreController()
        let request = ReaderVerticalScrollRequest(pageIndex: 81, intraPageProgress: 0.0194)

        controller.beginScrolling(to: request)
        controller.refresh(now: 100)
        XCTAssertEqual(controller.scrollingRequest, request)

        controller.beginFineTuning(request)
        XCTAssertFalse(controller.canSampleViewport(now: 101))

        controller.beginSettling(request, now: 101, duration: 0.45)
        XCTAssertFalse(controller.canSampleViewport(now: 101.44))
        XCTAssertTrue(controller.canSampleViewport(now: 101.45))
        XCTAssertNil(controller.activeRequest)
    }

    func testUserScrollCancelSuppressesViewportSamplingUntilCooldownEnds() {
        var controller = ReaderVerticalRestoreController()
        let request = ReaderVerticalScrollRequest(pageIndex: 80, intraPageProgress: 0.97)

        controller.beginScrolling(to: request)
        controller.cancel(now: 20, samplingCooldown: 0.25)

        XCTAssertNil(controller.activeRequest)
        XCTAssertFalse(controller.canSampleViewport(now: 20.24))
        XCTAssertTrue(controller.canSampleViewport(now: 20.25))
    }

    func testFineTuneSettlingSuppressesForcedSaveSamplingUntilDeadline() {
        var controller = ReaderVerticalRestoreController()
        let request = ReaderVerticalScrollRequest(pageIndex: 12, intraPageProgress: 0.59)

        controller.beginFineTuning(request)
        controller.beginSettling(request, now: 30, duration: 0.45)

        XCTAssertFalse(controller.canSampleViewport(now: 30.44))
        XCTAssertTrue(controller.canSampleViewport(now: 30.45))
    }
}
