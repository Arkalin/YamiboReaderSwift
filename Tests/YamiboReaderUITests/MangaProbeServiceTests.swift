import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class MangaProbeServiceTests: XCTestCase {
    @MainActor
    func testServiceUsesDynamicProbeOnlyWhenImmediateOutcomeNeedsDynamicProbe() async {
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

    @MainActor
    func testServiceCallsDynamicProbeWhenCurrentHTMLMissing() async {
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

        let outcome = await service.probe(
            launchContext: context,
            currentHTML: nil,
            currentTitle: "第3话"
        )

        XCTAssertEqual(dynamicProbeInputs.count, 1)
        XCTAssertEqual(dynamicProbeInputs.first?.0, context)
        XCTAssertEqual(dynamicProbeInputs.first?.1, "第3话")
        XCTAssertEqual(outcome, dynamicOutcome)
    }

    func testServiceStaticHelpersForwardToCoreDecision() {
        let context = makeLaunchContext()

        XCTAssertEqual(
            MangaProbeService.makeSuggestedWebContext(from: context),
            MangaProbeDecision.suggestedWebContext(from: context)
        )
        XCTAssertEqual(
            MangaProbeService.failureReason(for: URLError(.timedOut)),
            MangaProbeDecision.failureReason(for: URLError(.timedOut))
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
