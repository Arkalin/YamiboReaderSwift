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

        let displayValue = NovelTextDisplayValue(
            text: "设置预览应该直接显示草稿正文。",
            chapterTitle: nil,
            settings: settings
        )

        let materialization = NovelTextDisplayAdapter.materialization(
            surface: .settingsPreview,
            displayValue: displayValue,
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )

        XCTAssertEqual(materialization.surface, .settingsPreview)
        XCTAssertEqual(materialization.backend, .novelTextViewport)
        XCTAssertEqual(materialization.style.fontFamily, .systemSerif)
        XCTAssertEqual(materialization.style.fontScale, 1.25)
        XCTAssertEqual(materialization.style.lineHeightScale, 1.7)
        XCTAssertEqual(materialization.style.characterSpacingScale, 0.18)
        XCTAssertTrue(materialization.style.indentsParagraphFirstLine)
        XCTAssertEqual(materialization.style.textColor, .settingsPreviewPrimaryText)
        XCTAssertNil(materialization.chapterTitle)
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

        let materialization = ReaderBlockNovelTextDisplayMaterializer.materialization(
            for: textBlock,
            settings: settings
        )
        let previewDisplayValue = NovelTextDisplayValue(
            text: "设置预览文本。",
            chapterTitle: nil,
            settings: settings
        )
        let previewMaterialization = NovelTextDisplayAdapter.materialization(
            surface: .settingsPreview,
            displayValue: previewDisplayValue,
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )

        XCTAssertEqual(materialization?.surface, .novelReadingSessionTextBlock)
        XCTAssertEqual(materialization?.backend, previewMaterialization.backend)
        XCTAssertEqual(materialization?.style.fontFamily, .rounded)
        XCTAssertEqual(materialization?.style.lineHeightScale, 1.6)
        XCTAssertEqual(materialization?.chapterTitle, "第一章")
        XCTAssertEqual(materialization?.startsAtParagraphBoundary, false)
    }

    func testNovelReadingSessionTextBlockMaterializationUsesSnapshotDisplayValueSemantics() throws {
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

        let materialization = try XCTUnwrap(ReaderBlockNovelTextDisplayMaterializer.materialization(
            for: block,
            settings: liveSettings,
            baseFontSize: 20
        ))

        XCTAssertEqual(materialization.style.fontScale, 1.4)
        XCTAssertEqual(materialization.style.fontFamily, .systemSerif)
        XCTAssertEqual(materialization.style.pointSize, 28, accuracy: 0.001)
        XCTAssertEqual(materialization.style.lineHeightScale, 1.85)
        XCTAssertEqual(materialization.style.characterSpacingScale, 0.14)
        XCTAssertTrue(materialization.style.usesJustifiedText)
        XCTAssertTrue(materialization.style.indentsParagraphFirstLine)
    }

    func testNovelTextLayoutDisplayMeasurementUsesSameTextKit2DisplayAdapterForPreviewAndReadingSessionBlocks() {
        let settings = ReaderAppearanceSettings(
            fontScale: 1.05,
            lineHeightScale: 1.55,
            characterSpacingScale: 0.05,
            indentsParagraphFirstLine: true,
            readingMode: .vertical
        )
        let previewDisplayValue = NovelTextDisplayValue(
            text: "设置预览测高应该跟显示走同一条 Novel Text Layout 路径。",
            chapterTitle: nil,
            settings: settings
        )
        let previewMaterialization = NovelTextDisplayAdapter.materialization(
            surface: .settingsPreview,
            displayValue: previewDisplayValue,
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )
        let blockMaterialization = ReaderBlockNovelTextDisplayMaterializer.materialization(
            for: .text(
                "纵向阅读正文块测高也不能回退到独立 text view fitting。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: true
            ),
            settings: settings
        )

        XCTAssertEqual(previewMaterialization.measurementBackend, .novelTextLayoutMeasurement)
        XCTAssertEqual(blockMaterialization?.measurementBackend, previewMaterialization.measurementBackend)
        XCTAssertEqual(blockMaterialization?.surface, .novelReadingSessionTextBlock)
    }

    func testSwiftUIDisplaySizingRequestsHeightFromNovelTextLayoutMeasurement() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let sizeThatFitsBody = try XCTUnwrap(functionBody(named: "sizeThatFits", in: adapterSource))
        let measuredHeightBody = try XCTUnwrap(functionBody(named: "measuredHeight", in: adapterSource))

        XCTAssertTrue(sizeThatFitsBody.contains("NovelTextDisplayAdapter.measuredHeight"))
        XCTAssertTrue(measuredHeightBody.contains("NovelTextLayout.measuredTextHeight"))
        XCTAssertFalse(sizeThatFitsBody.contains("displayView.measuredHeight"))
    }

    func testNovelTextDisplayValueStaysPureAndDisplayMaterializationUsesPlatformAdapter() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readerModelsSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Models/ReaderModels.swift"),
            encoding: .utf8
        )
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let displayValueBody = try XCTUnwrap(typeBody(named: "NovelTextDisplayValue", in: readerModelsSource))
        let updateUIViewBody = try XCTUnwrap(functionBody(named: "updateUIView", in: adapterSource))
        let displayUIViewBody = try XCTUnwrap(typeBody(named: "NovelTextViewportDisplayUIView", in: adapterSource))

        XCTAssertFalse(displayValueBody.contains("NSAttributedString"))
        XCTAssertFalse(displayValueBody.contains("NSText"))
        XCTAssertFalse(displayValueBody.contains("UIView"))
        XCTAssertFalse(displayValueBody.contains("NSView"))
        XCTAssertTrue(updateUIViewBody.contains("NovelTextKit2PlatformAdapter.makeAttributedText"))
        XCTAssertFalse(displayUIViewBody.contains("func measuredHeight"))
        XCTAssertTrue(adapterSource.contains("NovelTextViewportDisplayUIView: UIView, NSTextViewportLayoutControllerDelegate"))
        XCTAssertTrue(displayUIViewBody.contains("textViewportLayoutController.layoutViewport()"))
    }

    func testSettingsPreviewAndReadingSessionUseSameAdapterBackedMaterialization() throws {
        let settings = ReaderAppearanceSettings(fontScale: 1.2, readingMode: .paged)
        let preview = NovelTextDisplayAdapter.materialization(
            surface: .settingsPreview,
            displayValue: NovelTextDisplayValue(
                text: "设置预览",
                chapterTitle: nil,
                settings: settings
            ),
            baseFontSize: 22,
            textColor: .settingsPreviewPrimaryText
        )
        let block = try XCTUnwrap(ReaderBlockNovelTextDisplayMaterializer.materialization(
            for: .text("正文块", chapterTitle: "第一章", settings: settings),
            settings: settings
        ))

        XCTAssertEqual(preview.backend, .novelTextViewport)
        XCTAssertEqual(block.backend, preview.backend)
        XCTAssertEqual(block.measurementBackend, preview.measurementBackend)
    }

    func testTwoPagePagedSpreadUsesViewportBackedReaderPageContent() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readerSupportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: readerSupportSource))
        let settings = ReaderAppearanceSettings(
            showsTwoPagesInLandscapeOnPad: true,
            readingMode: .paged
        )
        let block = try XCTUnwrap(ReaderBlockNovelTextDisplayMaterializer.materialization(
            for: .text(
                "双页横屏展示中的左右页都必须复用 viewport-backed page content。",
                chapterTitle: "第一章",
                settings: settings
            ),
            settings: settings
        ))

        XCTAssertTrue(spreadContentBody.contains("ReaderPageContent("))
        XCTAssertFalse(spreadContentBody.contains("Text(displayValue.text"))
        XCTAssertEqual(block.backend, .novelTextViewport)
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

    func testSettingsPreviewPassesDisplayValueIntoNativeTextKitAdapter() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settingsSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSettingsViews.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("displayValue: NovelTextDisplayValue"))
        XCTAssertFalse(settingsSource.contains("surface: .settingsPreview,\n                    text:"))
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

        let materialization = try XCTUnwrap(ReaderBlockNovelTextDisplayMaterializer.materialization(
            for: .text(
                "第一章\n正文需要覆盖字体、字号、行距、字距和段首缩进。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: true,
                settings: settings
            ),
            settings: settings
        ))

        XCTAssertEqual(materialization.style.fontFamily, .systemSerif)
        XCTAssertEqual(materialization.style.pointSize, 28.6, accuracy: 0.001)
        XCTAssertEqual(materialization.style.lineHeightScale, 1.8)
        XCTAssertEqual(materialization.style.characterSpacingScale, 0.16)
        XCTAssertTrue(materialization.style.indentsParagraphFirstLine)
        XCTAssertTrue(materialization.style.includesChapterTitle)
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

private func functionBody(named name: String, in source: String) -> String? {
    guard let nameRange = source.range(of: "func \(name)") ?? source.range(of: "static func \(name)") else {
        return nil
    }
    guard let bodyStart = source[nameRange.upperBound...].firstIndex(of: "{") else {
        return nil
    }

    var depth = 0
    var index = bodyStart
    while index < source.endIndex {
        if source[index] == "{" {
            depth += 1
        } else if source[index] == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[bodyStart...index])
            }
        }
        index = source.index(after: index)
    }
    return nil
}

private func typeBody(named name: String, in source: String) -> String? {
    guard let nameRange = source.range(of: "struct \(name)") ?? source.range(of: "final class \(name)") else {
        return nil
    }
    guard let bodyStart = source[nameRange.upperBound...].firstIndex(of: "{") else {
        return nil
    }

    var depth = 0
    var index = bodyStart
    while index < source.endIndex {
        if source[index] == "{" {
            depth += 1
        } else if source[index] == "}" {
            depth -= 1
            if depth == 0 {
                return String(source[bodyStart...index])
            }
        }
        index = source.index(after: index)
    }
    return nil
}
