import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class NovelTextDisplayAdapterTests: XCTestCase {
    func testNovelTextLayoutSettingsPreviewUsesTextKit2DisplayAdapterWithDraftReadingSettings() {
        let settings = ReaderAppearanceSettings(
            fontScale: 1.25,
            fontFamily: .systemSerif,
            lineHeightScale: 1.7,
            characterSpacingScale: 0.18,
            horizontalPadding: 28,
            usesJustifiedText: true,
            indentsParagraphFirstLine: true,
            readingMode: .paged
        )

        let plan = NovelTextDisplayAdapter.displayPlan(
            surface: .settingsPreview,
            text: "设置预览应该直接显示草稿正文。",
            chapterTitle: nil,
            startsAtParagraphBoundary: true,
            settings: settings,
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )

        XCTAssertEqual(plan.surface, .settingsPreview)
        XCTAssertEqual(plan.backend, .textKit2DisplayAdapter)
        XCTAssertEqual(plan.style.fontFamily, .systemSerif)
        XCTAssertEqual(plan.style.fontScale, 1.25)
        XCTAssertEqual(plan.style.lineHeightScale, 1.7)
        XCTAssertEqual(plan.style.characterSpacingScale, 0.18)
        XCTAssertTrue(plan.style.indentsParagraphFirstLine)
        XCTAssertEqual(plan.style.textColor, .settingsPreviewPrimaryText)
        XCTAssertNil(plan.chapterTitle)
    }

    func testNovelReadingSessionTextBlockUsesSameNovelTextLayoutDisplayAdapterAsSettingsPreview() {
        let settings = ReaderAppearanceSettings(
            fontScale: 1.1,
            fontFamily: .rounded,
            lineHeightScale: 1.6,
            characterSpacingScale: 0.08,
            indentsParagraphFirstLine: true,
            readingMode: .vertical
        )
        let textBlock = ReaderRenderedBlock.text(
            "正文文本块应该由 Novel Text Layout 绘制。",
            chapterTitle: "第一章",
            startsAtParagraphBoundary: false
        )

        let plan = ReaderBlockTextDisplayPlanner.displayPlan(
            for: textBlock,
            settings: settings
        )
        let previewPlan = NovelTextDisplayAdapter.displayPlan(
            surface: .settingsPreview,
            text: "设置预览文本。",
            chapterTitle: nil,
            startsAtParagraphBoundary: true,
            settings: settings,
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )

        XCTAssertEqual(plan?.surface, .novelReadingSessionTextBlock)
        XCTAssertEqual(plan?.backend, previewPlan.backend)
        XCTAssertEqual(plan?.style.fontFamily, .rounded)
        XCTAssertEqual(plan?.style.lineHeightScale, 1.6)
        XCTAssertEqual(plan?.chapterTitle, "第一章")
        XCTAssertEqual(plan?.startsAtParagraphBoundary, false)
    }

    func testNovelTextLayoutDisplayMeasurementUsesSameTextKit2DisplayAdapterForPreviewAndReadingSessionBlocks() {
        let settings = ReaderAppearanceSettings(
            fontScale: 1.05,
            lineHeightScale: 1.55,
            characterSpacingScale: 0.05,
            indentsParagraphFirstLine: true,
            readingMode: .vertical
        )
        let previewPlan = NovelTextDisplayAdapter.displayPlan(
            surface: .settingsPreview,
            text: "设置预览测高应该跟显示走同一条 Novel Text Layout 路径。",
            chapterTitle: nil,
            startsAtParagraphBoundary: true,
            settings: settings,
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )
        let blockPlan = ReaderBlockTextDisplayPlanner.displayPlan(
            for: .text(
                "纵向阅读正文块测高也不能回退到独立 text view fitting。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: true
            ),
            settings: settings
        )

        XCTAssertEqual(previewPlan.measurementBackend, .textKit2DisplayAdapter)
        XCTAssertEqual(blockPlan?.measurementBackend, previewPlan.measurementBackend)
        XCTAssertEqual(blockPlan?.surface, .novelReadingSessionTextBlock)
    }
}
