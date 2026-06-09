import CoreGraphics
import XCTest
import YamiboReaderCore
@testable import YamiboReaderUI

final class ReaderVerticalPositioningTests: XCTestCase {
    func testViewportReadingAnchorLineMatchesProgressSamplingAnchor() {
        let bounds = CGRect(x: 0, y: 12, width: 393, height: 852)

        XCTAssertEqual(ReaderVerticalPositioning.viewportReadingAnchorLineY(in: bounds), 136.32, accuracy: 0.001)
    }

    func testViewportReadingAnchorLineUsesTopReadingArea() {
        let bounds = CGRect(x: 0, y: 12, width: 393, height: 852)

        XCTAssertEqual(ReaderVerticalPositioning.viewportReadingAnchorLineY(in: bounds), 136.32, accuracy: 0.001)
    }

    func testVerticalSamplingAndRestoreUseSharedReadingAnchorLine() {
        let boundsSamples = [
            CGRect(x: 0, y: 0, width: 320, height: 568),
            CGRect(x: 0, y: 12, width: 393, height: 852),
            CGRect(x: 0, y: 24, width: 768, height: 1024),
        ]

        for bounds in boundsSamples {
            XCTAssertEqual(ReaderVerticalPositioning.viewportReadingAnchorLineY(in: bounds), expectedAnchorLineY(for: bounds), accuracy: 0.001)
        }
    }

    func testViewportReadingAnchorLineIgnoresScrollOffsetOrigin() {
        let scrolledBounds = CGRect(x: 0, y: 7_403, width: 393, height: 852)

        XCTAssertEqual(ReaderVerticalPositioning.viewportReadingAnchorLineY(in: scrolledBounds), 136.32, accuracy: 0.001)
        XCTAssertNotEqual(ReaderVerticalPositioning.viewportReadingAnchorLineY(in: scrolledBounds), scrolledBounds.midY)
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
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"))

        XCTAssertFalse(source.contains("ReaderVerticalPositioning.sample("))
        XCTAssertFalse(source.contains("intraPageProgress: sample.intraPageProgress"))
    }

    func testChromeStateUpdateDoesNotStartVerticalRestore() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"))
        let body = try functionBody(
            signature: "private func updateChromeForContentState()",
            in: source
        )

        XCTAssertFalse(body.contains("requestVerticalScrollToCurrentPage()"))
        XCTAssertFalse(body.contains("restoreVerticalPositionIfNeeded()"))
    }

    func testSheetPresentationChangesOnlyUpdateChrome() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerPresentationModifiers.swift"))
        let body = try functionBody(
            signature: "struct ReaderContainerStateObserverModifier: ViewModifier",
            in: source
        )
        let sheetStateNames = [
            "showingSettings",
            "showingCachePanel",
            "showingCacheProgress",
            "showingChapterSheet",
            "showingChapterComments",
        ]

        for stateName in sheetStateNames {
            let expectedBlock = ".onChange(of: \(stateName)) { _, _ in\n                onUpdateChromeForContentState()\n            }"
            XCTAssertTrue(body.contains(expectedBlock), "Unexpected onChange body for \(stateName)")
        }
    }

    func testImageBrowserDoesNotForceReaderChromeVisible() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"))
        let updateChromeBody = try functionBody(
            signature: "private func updateChromeForContentState()",
            in: source
        )
        let presentedOverlayBody = try functionBody(
            signature: "private var hasPresentedOverlay: Bool",
            in: source
        )
        let chromeOverlayBody = try functionBody(
            signature: "private var hasChromePresentedOverlay: Bool",
            in: source
        )

        XCTAssertTrue(updateChromeBody.contains("hasPresentedOverlay: hasChromePresentedOverlay"))
        XCTAssertTrue(presentedOverlayBody.contains("imageBrowserItem != nil"))
        XCTAssertFalse(chromeOverlayBody.contains("imageBrowserItem"))
    }

    func testImageTapHidesVisibleChromeBeforeOpeningBrowser() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"))
        let body = try functionBody(
            signature: "private func handleImageTap(url: URL, title: String?)",
            in: source
        )

        XCTAssertTrue(body.contains("guard !chromeState.showsChrome else"))
        XCTAssertTrue(body.contains("enterImmersiveMode()"))
        XCTAssertTrue(body.contains("return"))
        XCTAssertTrue(body.contains("openImageBrowser(url: url, title: title)"))
        XCTAssertLessThan(
            body.range(of: "enterImmersiveMode()")!.lowerBound,
            body.range(of: "openImageBrowser(url: url, title: title)")!.lowerBound
        )
        XCTAssertEqual(source.components(separatedBy: "isChromeVisible: chromeState.showsChrome").count - 1, 3)
        XCTAssertEqual(source.components(separatedBy: "onChromeVisibleImageTap: {\n                        enterImmersiveMode()\n                    }").count - 1, 2)
        XCTAssertTrue(source.contains("onChromeVisibleImageTap: {\n                enterImmersiveMode()\n            }"))
    }

    func testExplicitVerticalNavigationStillRequestsRestore() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"))
        let navigationSignatures = [
            "private func commitProgressSlider(_ targetIndex: Int)",
            "private func jumpAdjacentChapter(_ delta: Int)",
            "private func jumpToChapter(_ chapter: ReaderChapter)",
            "private func jumpToChapterDirectoryChapter(_ chapter: ReaderChapter) async",
            "private func jumpToWebView(_ view: Int, preferredSurfaceOrdinal: Int) async",
            "private func goRelativePage(_ delta: Int) async",
            "private func commitVerticalProgressScrub(_ target: Int)",
        ]

        for signature in navigationSignatures {
            let body = try functionBody(signature: signature, in: source)
            XCTAssertTrue(body.contains("restoreVerticalPositionIfNeeded()"), "\(signature) should restore vertical position")
        }
    }

}

private func expectedAnchorLineY(for bounds: CGRect) -> CGFloat {
    min(max(bounds.height * 0.16, 96), max(bounds.height - 96, 0))
}

private func projectFilePath(_ relativePath: String) -> String {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(relativePath)
        .path
}

private func functionBody(signature: String, in source: String) throws -> String {
    let signatureRange = try XCTUnwrap(source.range(of: signature), "Missing function signature: \(signature)")
    let searchRange = signatureRange.upperBound..<source.endIndex
    let openingBrace = try XCTUnwrap(source.range(of: "{", range: searchRange)?.lowerBound)
    var depth = 0
    var index = openingBrace

    while index < source.endIndex {
        let character = source[index]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[openingBrace...index])
            }
        }
        index = source.index(after: index)
    }

    XCTFail("Unterminated function body for \(signature)")
    return ""
}
