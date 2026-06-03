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
}
