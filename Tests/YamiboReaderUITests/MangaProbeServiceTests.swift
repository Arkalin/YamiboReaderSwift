import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class MangaProbeServiceTests: XCTestCase {
    func testImmediateOutcomeReturnsSuccessForValidMangaHTML() {
        let context = makeLaunchContext()
        let html = makeProbeHTML(
            title: "第1话 - 中文百合漫画区 - 百合会",
            section: "中文百合漫画区",
            imageCount: 2
        )

        let outcome = MangaProbeService.immediateOutcome(
            launchContext: context,
            html: html,
            title: "第1话"
        )

        guard case let .success(payload) = outcome else {
            return XCTFail("Expected success outcome")
        }
        XCTAssertEqual(payload.images.count, 2)
        XCTAssertEqual(payload.sectionName, "中文百合漫画区")
    }

    func testImmediateOutcomeMarksAnnouncementAsNotManga() {
        let context = makeLaunchContext()
        let html = """
        <html>
          <head><title>公告 - 中文百合漫画区 - 百合会</title></head>
          <body>
            <div class="header"><h2><a>中文百合漫画区</a></h2></div>
            <div class="view_tit"><em>公告</em></div>
          </body>
        </html>
        """

        let outcome = MangaProbeService.immediateOutcome(
            launchContext: context,
            html: html,
            title: "公告"
        )

        guard case let .fallback(reason, suggestedWebContext) = outcome else {
            return XCTFail("Expected fallback outcome")
        }
        XCTAssertEqual(reason, .notManga)
        XCTAssertTrue(suggestedWebContext.autoOpenNative)
    }

    func testImmediateOutcomeFallsBackWhenImagesAreMissing() {
        let context = makeLaunchContext()
        let html = makeProbeHTML(
            title: "第1话 - 中文百合漫画区 - 百合会",
            section: "中文百合漫画区",
            imageCount: 0
        )

        let outcome = MangaProbeService.immediateOutcome(
            launchContext: context,
            html: html,
            title: "第1话"
        )

        guard case let .fallback(reason, suggestedWebContext) = outcome else {
            return XCTFail("Expected fallback outcome")
        }
        XCTAssertEqual(reason, .noImages)
        XCTAssertEqual(suggestedWebContext.currentURL, context.chapterURL)
    }

    func testFailureReasonTreatsURLDomainErrorsAsRetryableNetwork() {
        XCTAssertEqual(
            MangaProbeService.failureReason(for: URLError(.timedOut)),
            .retryableNetwork
        )
    }
}

private func makeLaunchContext() -> MangaLaunchContext {
    MangaLaunchContext(
        originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
        chapterURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
        displayTitle: "测试漫画",
        source: .forum
    )
}

private func makeProbeHTML(title: String, section: String, imageCount: Int) -> String {
    let imageHTML = (0 ..< imageCount).map { index in
        #"<img src="https://img.example.com/probe-\#(index).jpg" />"#
    }.joined(separator: "\n")

    return """
    <html>
      <head><title>\(title)</title></head>
      <body>
        <div class="header"><h2><a>\(section)</a></h2></div>
        <div class="message">
          \(imageHTML)
        </div>
      </body>
    </html>
    """
}
