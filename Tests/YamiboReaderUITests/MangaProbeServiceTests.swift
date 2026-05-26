import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class MangaProbeServiceTests: XCTestCase {
    @MainActor
    func testServiceUsesHiddenAdapterOnlyWhenImmediateOutcomeNeedsDynamicProbe() async {
        let context = makeLaunchContext()
        var dynamicProbeInputs: [(MangaLaunchContext, String?)] = []
        let dynamicOutcome = MangaProbeOutcome.fallback(
            reason: .timeout,
            suggestedWebContext: MangaProbeService.makeSuggestedWebContext(from: context)
        )
        let service = MangaProbeService(appContext: YamiboAppContext()) { launchContext, fallbackTitle in
            dynamicProbeInputs.append((launchContext, fallbackTitle))
            return dynamicOutcome
        }

        let successHTML = makeProbeHTML(
            title: "第1话 - 中文百合漫画区 - 百合会",
            section: "中文百合漫画区",
            imageCount: 1
        )
        _ = await service.probe(
            launchContext: context,
            currentHTML: successHTML,
            currentTitle: "第1话"
        )

        let notMangaHTML = makeProbeHTML(
            title: "小说 - 原创小说区 - 百合会",
            section: "原创小说区",
            imageCount: 1
        )
        _ = await service.probe(
            launchContext: context,
            currentHTML: notMangaHTML,
            currentTitle: "小说"
        )

        let noImagesHTML = makeProbeHTML(
            title: "第2话 - 中文百合漫画区 - 百合会",
            section: "中文百合漫画区",
            imageCount: 0
        )
        let outcome = await service.probe(
            launchContext: context,
            currentHTML: noImagesHTML,
            currentTitle: "第2话"
        )

        XCTAssertEqual(dynamicProbeInputs.count, 1)
        XCTAssertEqual(dynamicProbeInputs.first?.0, context)
        XCTAssertEqual(dynamicProbeInputs.first?.1, "第2话")
        XCTAssertEqual(outcome, dynamicOutcome)
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

        XCTAssertEqual(MangaProbeClassifier.classify(snapshot), .notManga)
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

        XCTAssertEqual(MangaProbeClassifier.classify(snapshot), .notManga)
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

        XCTAssertEqual(MangaProbeClassifier.classify(snapshot), .noImages)
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

        guard case let .success(payload) = MangaProbeClassifier.classify(snapshot) else {
            return XCTFail("Expected success classification")
        }
        XCTAssertEqual(payload.images, [imageURL])
        XCTAssertEqual(payload.title, "第1话")
        XCTAssertEqual(payload.html, html)
        XCTAssertEqual(payload.sectionName, "中文百合漫画区")
    }

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

    func testImmediateProbeCompletionPolicyKeepsNoImagesDynamicButStopsNotManga() {
        let context = makeLaunchContext()
        let webContext = MangaProbeService.makeSuggestedWebContext(from: context)

        XCTAssertTrue(
            MangaProbeService.shouldCompleteAfterImmediateOutcome(
                .fallback(reason: .notManga, suggestedWebContext: webContext)
            )
        )
        XCTAssertFalse(
            MangaProbeService.shouldCompleteAfterImmediateOutcome(
                .fallback(reason: .noImages, suggestedWebContext: webContext)
            )
        )
        XCTAssertTrue(
            MangaProbeService.shouldCompleteAfterImmediateOutcome(
                .success(MangaProbePayload(images: [], title: "第1话"))
            )
        )
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
