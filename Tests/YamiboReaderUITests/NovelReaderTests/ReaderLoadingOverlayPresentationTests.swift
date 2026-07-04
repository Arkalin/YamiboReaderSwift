import XCTest
@testable import YamiboReaderUI

final class ReaderLoadingOverlayPresentationTests: XCTestCase {
    func testInitialContentLoadPresentsOverlay() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: false,
            isApplyingAppearanceSettings: false,
            shouldConcealViewportContent: false
        )

        XCTAssertEqual(presentation.reason, .initialContentLoad)
        XCTAssertTrue(presentation.isPresented)
        XCTAssertFalse(presentation.allowsChrome)
    }

    func testInitialLoadErrorDoesNotPresentOverlay() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: false,
            hasInitialLoadError: true,
            isApplyingAppearanceSettings: false,
            shouldConcealViewportContent: false
        )

        XCTAssertNil(presentation.reason)
        XCTAssertFalse(presentation.isPresented)
        XCTAssertTrue(presentation.allowsChrome)
    }

    func testAppearanceSettingsApplyTakesPriority() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: false,
            isApplyingAppearanceSettings: true,
            shouldConcealViewportContent: true
        )

        XCTAssertEqual(presentation.reason, .appearanceSettingsApply)
    }

    func testVerticalRestoreTakesPriorityOverInitialContentLoad() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: false,
            isApplyingAppearanceSettings: false,
            shouldConcealViewportContent: true
        )

        XCTAssertEqual(presentation.reason, .verticalRestore)
    }

    func testNovelReaderProjectionNavigationPresentsOverlayOverExistingSurfaces() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: true,
            isApplyingAppearanceSettings: false,
            isNavigatingNovelReaderProjection: true,
            shouldConcealViewportContent: false
        )

        XCTAssertEqual(presentation.reason, .readerPageDocumentNavigation)
        XCTAssertTrue(presentation.isPresented)
        XCTAssertFalse(presentation.allowsChrome)
    }

    func testVerticalRestoreTakesPriorityOverNovelReaderProjectionNavigation() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: true,
            isApplyingAppearanceSettings: false,
            isNavigatingNovelReaderProjection: true,
            shouldConcealViewportContent: true
        )

        XCTAssertEqual(presentation.reason, .verticalRestore)
    }

    func testNoLoadingStateDoesNotPresentOverlay() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: false,
            hasSurfaces: true,
            isApplyingAppearanceSettings: false,
            shouldConcealViewportContent: false
        )

        XCTAssertNil(presentation.reason)
        XCTAssertFalse(presentation.isPresented)
    }

}
