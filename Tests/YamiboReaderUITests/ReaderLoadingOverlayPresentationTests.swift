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

    func testReaderPageDocumentNavigationPresentsOverlayOverExistingSurfaces() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: true,
            isApplyingAppearanceSettings: false,
            isNavigatingReaderPageDocument: true,
            shouldConcealViewportContent: false
        )

        XCTAssertEqual(presentation.reason, .readerPageDocumentNavigation)
        XCTAssertTrue(presentation.isPresented)
        XCTAssertFalse(presentation.allowsChrome)
    }

    func testVerticalRestoreTakesPriorityOverReaderPageDocumentNavigation() {
        let presentation = ReaderLoadingOverlayPresentation(
            isLoading: true,
            hasSurfaces: true,
            isApplyingAppearanceSettings: false,
            isNavigatingReaderPageDocument: true,
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

    func testReaderContainerContentDoesNotOwnCommonLoadingProgressView() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let body = try XCTUnwrap(functionBody(named: "content(topInset", in: source))

        XCTAssertFalse(body.contains("ProgressView(L10n.string(\"common.loading\"))"))
    }

    func testReaderContainerChromeIsHiddenWhileLoadingOverlayIsPresented() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("if loadingOverlayPresentation.allowsChrome"))
        XCTAssertTrue(source.contains("if chromeState.showsChrome"))
        XCTAssertTrue(source.contains("bottomChrome(bottomInset: bottomInset, isVisible: chromeState.showsChrome)"))
    }

    func testReaderContainerChromeDoesNotUseEdgeMoveTransitions() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".move(edge: .top)"))
        XCTAssertFalse(source.contains(".move(edge: .bottom)"))
        XCTAssertTrue(source.contains(".transition(.opacity)"))
    }
}

private func functionBody(named name: String, in source: String) -> String? {
    guard let range = source.range(of: name),
          let openingBrace = source[range.upperBound...].firstIndex(of: "{") else {
        return nil
    }

    var depth = 0
    var index = openingBrace
    while index < source.endIndex {
        let character = source[index]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[source.index(after: openingBrace) ..< index])
            }
        }
        index = source.index(after: index)
    }
    return nil
}
