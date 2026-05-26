import XCTest
@testable import YamiboReaderCore

final class MangaProbeDecisionTests: XCTestCase {
    func testImmediateOutcomeReturnsSuccessForValidMangaHTML() {
        let context = makeLaunchContext()
        let html = makeProbeHTML(
            title: "第1话 - 中文百合漫画区 - 百合会",
            section: "中文百合漫画区",
            imageCount: 2
        )

        let outcome = MangaProbeDecision.immediateOutcome(
            launchContext: context,
            html: html,
            title: "第1话"
        )

        guard case let .success(payload) = outcome else {
            return XCTFail("Expected success outcome")
        }
        XCTAssertEqual(payload.images.count, 2)
        XCTAssertEqual(payload.title, "第1话 - 中文百合漫画区 - 百合会")
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

        let outcome = MangaProbeDecision.immediateOutcome(
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

        let outcome = MangaProbeDecision.immediateOutcome(
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

    func testClassifierMarksAnnouncementSnapshotAsNotManga() {
        let snapshot = MangaProbeSnapshot(
            title: "公告",
            html: nil,
            sectionName: "中文百合漫画区",
            isAnnouncement: true,
            imageURLs: [
                URL(string: "https://img.example.com/probe.jpg")!
            ],
            baseURL: makeLaunchContext().chapterURL
        )

        XCTAssertEqual(MangaProbeDecision.classify(snapshot), .notManga)
    }

    func testClassifierMarksDisallowedSectionSnapshotAsNotManga() {
        let snapshot = MangaProbeSnapshot(
            title: "小说章节",
            html: nil,
            sectionName: "原创小说区",
            isAnnouncement: false,
            imageURLs: [
                URL(string: "https://img.example.com/probe.jpg")!
            ],
            baseURL: makeLaunchContext().chapterURL
        )

        XCTAssertEqual(MangaProbeDecision.classify(snapshot), .notManga)
    }

    func testClassifierMarksAllowedMangaSnapshotWithoutImagesAsNoImages() {
        let snapshot = MangaProbeSnapshot(
            title: "第1话",
            html: nil,
            sectionName: "中文百合漫画区",
            isAnnouncement: false,
            imageURLs: [],
            baseURL: makeLaunchContext().chapterURL
        )

        XCTAssertEqual(MangaProbeDecision.classify(snapshot), .noImages)
    }

    func testClassifierReturnsSuccessForAllowedMangaSnapshotWithImages() {
        let imageURL = URL(string: "https://img.example.com/probe.jpg")!
        let html = makeProbeHTML(
            title: "第1话 - 中文百合漫画区 - 百合会",
            section: "中文百合漫画区",
            imageCount: 1
        )
        let snapshot = MangaProbeSnapshot(
            title: "第1话",
            html: html,
            sectionName: "中文百合漫画区",
            isAnnouncement: false,
            imageURLs: [imageURL],
            baseURL: makeLaunchContext().chapterURL
        )

        guard case let .success(payload) = MangaProbeDecision.classify(snapshot) else {
            return XCTFail("Expected success classification")
        }
        XCTAssertEqual(payload.images, [imageURL])
        XCTAssertEqual(payload.title, "第1话")
        XCTAssertEqual(payload.html, html)
        XCTAssertEqual(payload.sectionName, "中文百合漫画区")
    }

    func testClassifierMarksUnlikelyMangaHTMLAsNotMangaBeforeCheckingImages() {
        let snapshot = MangaProbeSnapshot(
            title: "普通帖子",
            html: "<html><body><p>只有普通文字</p></body></html>",
            sectionName: "中文百合漫画区",
            isAnnouncement: false,
            imageURLs: [URL(string: "https://img.example.com/probe.jpg")!],
            baseURL: makeLaunchContext().chapterURL
        )

        XCTAssertEqual(MangaProbeDecision.classify(snapshot), .notManga)
    }

    func testCompletionPolicyCompletesSuccessAndNotMangaButContinuesNoImages() {
        let context = makeLaunchContext()
        let webContext = MangaProbeDecision.suggestedWebContext(from: context)

        XCTAssertTrue(
            MangaProbeDecision.shouldCompleteAfterImmediateOutcome(
                .fallback(reason: .notManga, suggestedWebContext: webContext)
            )
        )
        XCTAssertFalse(
            MangaProbeDecision.shouldCompleteAfterImmediateOutcome(
                .fallback(reason: .noImages, suggestedWebContext: webContext)
            )
        )
        XCTAssertTrue(
            MangaProbeDecision.shouldCompleteAfterImmediateOutcome(
                .success(MangaProbePayload(images: [], title: "第1话"))
            )
        )
    }

    func testSuggestedWebContextPreservesLaunchContextAndAutoOpenNative() {
        let context = makeLaunchContext()

        let webContext = MangaProbeDecision.suggestedWebContext(from: context)

        XCTAssertEqual(webContext.currentURL, context.chapterURL)
        XCTAssertEqual(webContext.originalThreadURL, context.originalThreadURL)
        XCTAssertEqual(webContext.source, context.source)
        XCTAssertEqual(webContext.initialPage, context.initialPage)
        XCTAssertTrue(webContext.autoOpenNative)
        XCTAssertFalse(webContext.waitingForNativeReturn)
    }

    func testFailureReasonTreatsURLDomainErrorsAsRetryableNetwork() {
        XCTAssertEqual(
            MangaProbeDecision.failureReason(for: URLError(.timedOut)),
            .retryableNetwork
        )
    }

    func testFailureReasonTreatsNonURLErrorAsTimeout() {
        XCTAssertEqual(
            MangaProbeDecision.failureReason(for: CocoaError(.fileNoSuchFile)),
            .timeout
        )
    }
}

private func makeLaunchContext() -> MangaLaunchContext {
    MangaLaunchContext(
        originalThreadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=700&mobile=2")!,
        chapterURL: URL(string: "https://bbs.yamibo.com/thread-700-2-1.html")!,
        displayTitle: "测试漫画",
        source: .favorites,
        initialPage: 3
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
