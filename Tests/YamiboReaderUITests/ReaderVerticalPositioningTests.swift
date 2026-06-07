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

    func testChromeStateUpdateDoesNotStartVerticalRestore() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"))
        let body = try functionBody(
            signature: "private func updateChromeForContentState()",
            in: source
        )

        XCTAssertFalse(body.contains("requestVerticalScrollToCurrentPage()"))
        XCTAssertFalse(body.contains("restoreVerticalPositionIfNeeded()"))
    }

    func testSheetPresentationChangesOnlyUpdateChrome() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"))
        let sheetStateNames = [
            "showingSettings",
            "showingCachePanel",
            "showingCacheProgress",
            "showingChapterSheet",
            "showingChapterComments",
        ]

        for stateName in sheetStateNames {
            let expectedBlock = ".onChange(of: \(stateName)) { _, _ in\n                updateChromeForContentState()\n            }"
            XCTAssertTrue(source.contains(expectedBlock), "Unexpected onChange body for \(stateName)")
        }
    }

    func testExplicitVerticalNavigationStillRequestsRestore() throws {
        let source = try String(contentsOfFile: projectFilePath("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"))
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
