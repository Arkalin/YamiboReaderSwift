import XCTest
@testable import YamiboReaderUI

final class ReaderChromeStateTests: XCTestCase {
    func testInitialContentLoadAutoHidesOnce() {
        var state = ReaderChromeState()

        state.update(
            isLoading: true,
            errorMessage: nil,
            hasPages: false,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .loading)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .immersiveHidden)
        XCTAssertTrue(state.hasCompletedInitialAutoHide)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .immersiveHidden)
    }

    func testManualVisibleStateSurvivesRepeatedContentUpdates() {
        var state = ReaderChromeState()
        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        state.toggleChrome()
        XCTAssertEqual(state.mode, .visible)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .visible)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .visible)
    }

    func testManualHiddenStateSurvivesRotationLikeLayoutUpdates() {
        var state = ReaderChromeState()
        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .immersiveHidden)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .immersiveHidden)
    }

    func testOverlayRestoresPreviousVisibleState() {
        var state = ReaderChromeState()
        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        state.toggleChrome()
        XCTAssertEqual(state.mode, .visible)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: true
        )
        XCTAssertEqual(state.mode, .visible)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .visible)
    }

    func testOverlayRestoresPreviousHiddenState() {
        var state = ReaderChromeState()
        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .immersiveHidden)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: true
        )
        XCTAssertEqual(state.mode, .visible)

        state.update(
            isLoading: false,
            errorMessage: nil,
            hasPages: true,
            hasPresentedOverlay: false
        )
        XCTAssertEqual(state.mode, .immersiveHidden)
    }
}
