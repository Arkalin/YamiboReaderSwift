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
            startsAtParagraphBoundary: false,
            settings: settings
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

    func testNovelReadingSessionTextBlockDisplayPlanUsesSnapshotDisplayValueSemantics() throws {
        let snapshotSettings = ReaderAppearanceSettings(
            fontScale: 1.4,
            fontFamily: .systemSerif,
            lineHeightScale: 1.85,
            characterSpacingScale: 0.14,
            usesJustifiedText: true,
            indentsParagraphFirstLine: true,
            readingMode: .paged
        )
        let liveSettings = ReaderAppearanceSettings(
            fontScale: 0.85,
            fontFamily: .rounded,
            lineHeightScale: 1.1,
            characterSpacingScale: 0,
            usesJustifiedText: false,
            indentsParagraphFirstLine: false,
            readingMode: .vertical
        )
        let block = ReaderRenderedBlock.text(
            "已经排版的阅读会话文本块必须使用快照中的显示语义。",
            chapterTitle: "第一章",
            settings: snapshotSettings
        )

        let plan = try XCTUnwrap(ReaderBlockTextDisplayPlanner.displayPlan(
            for: block,
            settings: liveSettings,
            baseFontSize: 20
        ))

        XCTAssertEqual(plan.style.fontScale, 1.4)
        XCTAssertEqual(plan.style.fontFamily, .systemSerif)
        XCTAssertEqual(plan.style.pointSize, 28, accuracy: 0.001)
        XCTAssertEqual(plan.style.lineHeightScale, 1.85)
        XCTAssertEqual(plan.style.characterSpacingScale, 0.14)
        XCTAssertTrue(plan.style.usesJustifiedText)
        XCTAssertTrue(plan.style.indentsParagraphFirstLine)
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

    func testNovelReadingSessionDisplayPathDoesNotRetainUIKitTextViewFallback() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readerSupportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSettingsViews.swift"),
            encoding: .utf8
        )
        let productionDisplaySources = readerSupportSource + "\n" + settingsSource

        XCTAssertFalse(productionDisplaySources.contains("ReaderRichTextView"))
        XCTAssertFalse(productionDisplaySources.contains("UITextView"))
    }

    func testNovelReadingSessionBlockPassesDisplayValueIntoNativeTextKitAdapter() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readerSupportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(readerSupportSource.contains("displayValue: displayValue"))
        XCTAssertFalse(readerSupportSource.contains("text: displayValue.text"))
    }

    func testNovelTextLayoutDisplayStyleCoversFontSizeSpacingIndentAndChapterTitleForNovelReadingSession() throws {
        let settings = ReaderAppearanceSettings(
            fontScale: 1.3,
            fontFamily: .systemSerif,
            lineHeightScale: 1.8,
            characterSpacingScale: 0.16,
            indentsParagraphFirstLine: true,
            readingMode: .paged
        )

        let plan = try XCTUnwrap(ReaderBlockTextDisplayPlanner.displayPlan(
            for: .text(
                "第一章\n正文需要覆盖字体、字号、行距、字距和段首缩进。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: true,
                settings: settings
            ),
            settings: settings
        ))

        XCTAssertEqual(plan.style.fontFamily, .systemSerif)
        XCTAssertEqual(plan.style.pointSize, 28.6, accuracy: 0.001)
        XCTAssertEqual(plan.style.lineHeightScale, 1.8)
        XCTAssertEqual(plan.style.characterSpacingScale, 0.16)
        XCTAssertTrue(plan.style.indentsParagraphFirstLine)
        XCTAssertTrue(plan.style.includesChapterTitle)
    }

    func testNovelReadingPositionDisplayFailureDoesNotPublishUIKitOrEstimatedFallback() throws {
        let text = String(repeating: "Novel Reading Position must not advance through fallback display. ", count: 12)
        let document = ReaderPageDocument(
            threadURL: try XCTUnwrap(URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=124&mobile=2")),
            view: 1,
            maxView: 1,
            segments: [.text(text, chapterTitle: "第一章")]
        )

        XCTAssertThrowsError(
            try NovelTextLayout.renderedPages(
                document: document,
                settings: ReaderAppearanceSettings(readingMode: .paged),
                layout: ReaderContainerLayout(width: 320, height: 568),
                requiresAuthoritativePagedLayout: true,
                pagedLayout: { _, _, _, _ in [] }
            )
        ) { error in
            XCTAssertEqual(error as? NovelTextLayoutFailure, .unableToLayoutText)
        }
    }
}
