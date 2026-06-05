import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class NovelTextDisplayAdapterTests: XCTestCase {
    func testSinglePagePagedCellUsesOpaqueWorkflowDisplayReference() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let surfaceBody = try XCTUnwrap(typeBody(named: "NovelTextViewportReferenceUIView", in: adapterSource))

        XCTAssertTrue(singlePageBody.contains("displayReferenceProvider(indexPath.item)"))
        XCTAssertTrue(singlePageBody.contains("displayReference: displayReference"))
        XCTAssertTrue(adapterSource.contains("NativeNovelTextViewportReferenceView"))
        XCTAssertTrue(surfaceBody.contains("NovelTextViewportDisplayReference?"))
        XCTAssertFalse(surfaceBody.contains("NSTextContentStorage"))
        XCTAssertFalse(surfaceBody.contains("NSTextLayoutManager"))
        XCTAssertFalse(surfaceBody.contains("NSAttributedString"))
    }

    func testSwiftUIViewUpdateCallbackSchedulerDefersCallbacksDuringViewUpdate() {
        let scheduler = SwiftUIViewUpdateCallbackScheduler()
        var events: [String] = []

        scheduler.publish {
            events.append("immediate")
        }

        XCTAssertEqual(events, ["immediate"])

        let deferredCallback = expectation(description: "Deferred callback")
        scheduler.performViewUpdate {
            scheduler.publish {
                events.append("deferred")
                deferredCallback.fulfill()
            }
            XCTAssertEqual(events, ["immediate"])
        }

        XCTAssertEqual(events, ["immediate"])
        scheduler.publish {
            events.append("queued-after-update")
        }
        XCTAssertEqual(events, ["immediate"])
        wait(for: [deferredCallback], timeout: 1)
        XCTAssertEqual(events, ["immediate", "deferred", "queued-after-update"])
    }

    func testViewportPageContentDoesNotIndentContinuationSliceFromSameParagraph() throws {
        let firstParagraph = "第一段正文很长，需要横向分页后继续显示。"
        let secondParagraph = "第二段应该仍然作为新段落缩进。"
        let sourceText = firstParagraph + "\n\n" + secondParagraph
        let settings = ReaderAppearanceSettings(indentsParagraphFirstLine: true, readingMode: .paged)
        let context = viewportContext(text: sourceText, settings: settings)
        let continuationRange = ReaderRenderedTextRange(
            segmentIndex: 0,
            startOffset: 8,
            endOffset: firstParagraph.count
        )

        let displayValue = try NovelTextLayout.displayValue(
            viewportContext: context,
            viewportPage: viewportTestIndexPage(index: 1, range: continuationRange),
            settings: settings
        )

        XCTAssertFalse(displayValue.startsAtParagraphBoundary)
    }

    func testViewportPageContentIndentsSliceStartingAtRealParagraphBoundary() throws {
        let firstParagraph = "第一段正文很长，需要横向分页后继续显示。"
        let secondParagraph = "第二段应该仍然作为新段落缩进。"
        let sourceText = firstParagraph + "\n\n" + secondParagraph
        let settings = ReaderAppearanceSettings(indentsParagraphFirstLine: true, readingMode: .paged)
        let context = viewportContext(text: sourceText, settings: settings)
        let paragraphBoundaryOffset = firstParagraph.count + "\n\n".count
        let paragraphRange = ReaderRenderedTextRange(
            segmentIndex: 0,
            startOffset: paragraphBoundaryOffset,
            endOffset: sourceText.count
        )

        let displayValue = try NovelTextLayout.displayValue(
            viewportContext: context,
            viewportPage: viewportTestIndexPage(index: 2, range: paragraphRange),
            settings: settings
        )

        XCTAssertTrue(displayValue.startsAtParagraphBoundary)
    }

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
        let materialization = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(
                text: "正文文本块应该由 Novel Text Layout 绘制。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: false,
                settings: settings
            ),
            baseFontSize: 22,
            textColor: .primaryReaderText
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

        XCTAssertEqual(materialization.surface, .novelReadingSessionTextBlock)
        XCTAssertEqual(materialization.backend, previewMaterialization.backend)
        XCTAssertEqual(materialization.style.fontFamily, .rounded)
        XCTAssertEqual(materialization.style.lineHeightScale, 1.6)
        XCTAssertEqual(materialization.chapterTitle, "第一章")
        XCTAssertEqual(materialization.startsAtParagraphBoundary, false)
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
        let materialization = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(
                text: "已经排版的阅读会话文本块必须使用快照中的显示语义。",
                chapterTitle: "第一章",
                settings: snapshotSettings
            ),
            baseFontSize: 20,
            textColor: .primaryReaderText
        )

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
        let blockMaterialization = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(
                text: "纵向阅读正文块测高也不能回退到独立 text view fitting。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: true,
                settings: settings
            ),
            baseFontSize: 22,
            textColor: .primaryReaderText
        )

        XCTAssertEqual(previewMaterialization.measurementBackend, .novelTextLayoutMeasurement)
        XCTAssertEqual(blockMaterialization.measurementBackend, previewMaterialization.measurementBackend)
        XCTAssertEqual(blockMaterialization.surface, .novelReadingSessionTextBlock)
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
        XCTAssertTrue(measuredHeightBody.contains("NovelTextLayout.measuredDisplayHeight"))
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
        let makeUIViewBody = try XCTUnwrap(functionBody(named: "makeUIView", in: adapterSource))
        let updateUIViewBody = try XCTUnwrap(functionBody(named: "updateUIView", in: adapterSource))
        let displayUIViewBody = try XCTUnwrap(typeBody(named: "NovelTextViewportDisplayUIView", in: adapterSource))

        XCTAssertFalse(displayValueBody.contains("NSAttributedString"))
        XCTAssertFalse(displayValueBody.contains("NSText"))
        XCTAssertFalse(displayValueBody.contains("UIView"))
        XCTAssertFalse(displayValueBody.contains("NSView"))
        XCTAssertTrue(makeUIViewBody.contains("NovelTextLayout.makeDisplayView()"))
        XCTAssertFalse(makeUIViewBody.contains("NovelTextViewportDisplayUIView()"))
        XCTAssertTrue(updateUIViewBody.contains("NovelTextLayout.updateDisplayView"))
        XCTAssertFalse(updateUIViewBody.contains("NovelTextKit2PlatformAdapter.makeAttributedText"))
        XCTAssertFalse(displayUIViewBody.contains("func measuredHeight"))
        XCTAssertTrue(adapterSource.contains("NovelTextViewportDisplayUIView: UIView, @MainActor NSTextViewportLayoutControllerDelegate"))
        XCTAssertTrue(displayUIViewBody.contains("textViewportLayoutController.layoutViewport()"))
    }

    func testNovelTextViewportDisplayInvalidatesDrawingWhenBoundsChange() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let displayUIViewBody = try XCTUnwrap(typeBody(named: "NovelTextViewportDisplayUIView", in: adapterSource))
        let layoutSubviewsBody = try XCTUnwrap(functionBody(named: "layoutSubviews", in: adapterSource))
        let configureTextKit2Body = try XCTUnwrap(functionBody(named: "configureTextKit2", in: adapterSource))

        XCTAssertTrue(configureTextKit2Body.contains("contentMode = .redraw"))
        XCTAssertTrue(displayUIViewBody.contains("lastLaidOutBoundsSize"))
        XCTAssertTrue(layoutSubviewsBody.contains("updateTextContainerSizeForCurrentBounds()"))
        XCTAssertTrue(layoutSubviewsBody.contains("setNeedsDisplay()"))
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
        let block = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(text: "正文块", chapterTitle: "第一章", settings: settings),
            baseFontSize: 22,
            textColor: .primaryReaderText
        )

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
        let block = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(
                text: "双页横屏展示中的左右页都必须复用 viewport-backed page content。",
                chapterTitle: "第一章",
                settings: settings
            ),
            baseFontSize: 22,
            textColor: .primaryReaderText
        )

        XCTAssertTrue(spreadContentBody.contains("ReaderViewportPageContent("))
        XCTAssertFalse(spreadContentBody.contains("Text(displayValue.text"))
        XCTAssertEqual(block.backend, .novelTextViewport)
    }

    func testTwoPageSpreadInstallsOpaqueReferencesForLeftAndRightPages() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let spreadViewportBody = try XCTUnwrap(
            typeBody(named: "ReaderPagedSpreadCollectionViewport", in: supportSource)
        )
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: supportSource))

        XCTAssertTrue(spreadViewportBody.contains("displayReferenceProvider"))
        XCTAssertTrue(spreadContentBody.contains("displayReferenceProvider(pageIndex)"))
        XCTAssertTrue(spreadContentBody.contains("displayReference: displayReference"))
        XCTAssertFalse(spreadContentBody.contains("NovelTextViewportDisplayUIView()"))
        XCTAssertFalse(spreadContentBody.contains("NSTextContentStorage"))
        XCTAssertFalse(spreadContentBody.contains("NSTextLayoutManager"))
    }

    func testPagedCellsResolveViewportPageIdentityBeforeRenderingNormalText() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: supportSource))
        let viewportContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportPageContent", in: supportSource))

        for body in [singlePageBody, spreadContentBody] {
            XCTAssertTrue(body.contains("viewportIndex?.pages.first"))
            XCTAssertTrue(body.contains("ReaderViewportPageContent("))
            XCTAssertFalse(body.contains("page.blocks.compactMap(\\.novelTextDisplayValue)"))
            XCTAssertFalse(body.contains("page.novelTextDisplayValues.first"))
        }
        XCTAssertTrue(singlePageBody.contains("$0.pageIndex == indexPath.item"))
        XCTAssertTrue(spreadContentBody.contains("$0.pageIndex == pageIndex"))
        XCTAssertFalse(singlePageBody.contains("$0.documentView == page.documentView"))
        XCTAssertFalse(spreadContentBody.contains("$0.documentView == page.documentView"))
        XCTAssertTrue(viewportContentBody.contains("NovelTextLayout.displayValue("))
        XCTAssertTrue(viewportContentBody.contains("viewportBlocks("))
        XCTAssertFalse(viewportContentBody.contains("compatibilityBlocks"))
    }

    func testSinglePagePagedReadingUsesUIKitCollectionViewportInsteadOfSwiftUITabView() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let pagedContentBody = try XCTUnwrap(functionBody(named: "pagedContent", in: containerSource))
        let collectionViewportBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))

        XCTAssertTrue(pagedContentBody.contains("ReaderPagedCollectionViewport("))
        XCTAssertTrue(supportSource.contains("struct ReaderPagedCollectionViewport: UIViewRepresentable"))
        XCTAssertTrue(collectionViewportBody.contains("UICollectionView"))
        XCTAssertTrue(collectionViewportBody.contains("viewportContext"))
        XCTAssertTrue(collectionViewportBody.contains("viewportIndex"))
    }

    func testTwoPageSpreadReadingUsesUIKitCollectionViewportWithSharedViewportContext() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let pagedContentBody = try XCTUnwrap(functionBody(named: "pagedContent", in: containerSource))
        let spreadViewportBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: supportSource))

        XCTAssertTrue(pagedContentBody.contains("ReaderPagedSpreadCollectionViewport("))
        XCTAssertTrue(supportSource.contains("struct ReaderPagedSpreadCollectionViewport: UIViewRepresentable"))
        XCTAssertTrue(spreadViewportBody.contains("UICollectionView"))
        XCTAssertTrue(spreadViewportBody.contains("viewportContext"))
        XCTAssertTrue(spreadViewportBody.contains("viewportIndex"))
        XCTAssertTrue(spreadContentBody.contains("spread.leftPageIndex"))
        XCTAssertTrue(spreadContentBody.contains("spread.rightPageIndex"))
    }

    func testVerticalReadingUsesViewportBackedReaderPageContentInsteadOfSwiftUITextChunks() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalContentBody = try XCTUnwrap(functionBody(named: "verticalContent", in: containerSource))
        let scrollViewBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))
        let readerBlockBody = try XCTUnwrap(typeBody(named: "ReaderViewportBlockView", in: supportSource))
        let settings = ReaderAppearanceSettings(readingMode: .vertical)
        let block = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(
                text: "纵向阅读的可见正文必须由 Novel Text Viewport 绘制。",
                chapterTitle: "第一章",
                settings: settings
            ),
            baseFontSize: 22,
            textColor: .primaryReaderText
        )

        XCTAssertTrue(verticalContentBody.contains("ReaderVerticalViewportScrollView("))
        XCTAssertTrue(scrollViewBody.contains("verticalDisplayPage(for: indexPath.item)"))
        XCTAssertFalse(scrollViewBody.contains("ReaderViewportPageContent.viewportBackedPage("))
        XCTAssertTrue(readerBlockBody.contains("NativeNovelTextDisplayView("))
        XCTAssertFalse(readerBlockBody.contains("Text(displayValue.text"))
        XCTAssertEqual(block.backend, .novelTextViewport)
    }

    func testVerticalReadingUsesUIKitViewportScrollViewInsteadOfSwiftUILazyTextHost() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalContentBody = try XCTUnwrap(functionBody(named: "verticalContent", in: containerSource))
        let scrollViewBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))

        XCTAssertTrue(verticalContentBody.contains("ReaderVerticalViewportScrollView("))
        XCTAssertFalse(verticalContentBody.contains("LazyVStack"))
        XCTAssertTrue(supportSource.contains("struct ReaderVerticalViewportScrollView: UIViewRepresentable"))
        XCTAssertTrue(scrollViewBody.contains("UICollectionView"))
        XCTAssertTrue(scrollViewBody.contains("viewportContext"))
        XCTAssertTrue(scrollViewBody.contains("viewportIndex"))
    }

    func testVisibleSurfaceDiagnosticsSeparateIndexBuildFromViewportDrawing() throws {
        let context = NovelTextViewportContext(
            identity: NovelTextViewportIdentity(
                threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=152&mobile=2")!,
                documentView: 1,
                maxView: 1,
                fetchedAt: Date(timeIntervalSince1970: 0),
                contentSource: .fallbackUnfilteredPage,
                appearance: ReaderAppearanceSettings(),
                layout: ReaderContainerLayout(width: 320, height: 568)
            ),
            document: NovelTextViewportDocument(
                text: "visible viewport text",
                textRangesBySegment: [0: ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 21)],
                insertedSeparatorRanges: []
            ),
            externalBlocks: [],
            diagnostics: NovelTextViewportDiagnostics(indexBuildCount: 1)
        )
        let viewportPage = NovelTextViewportIndexPage(
            pageIndex: 0,
            documentView: 1,
            chapterOrdinal: 0,
            chapterTitle: "第一章",
            ranges: [ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: 21)],
            chapterCommentTarget: nil
        )

        let diagnostics = NovelTextViewportVisibleSurfaceDiagnostics(
            viewportContext: context,
            viewportPage: viewportPage
        )

        XCTAssertEqual(diagnostics.indexBuildCount, 1)
        XCTAssertEqual(diagnostics.visibleSurfaceLayoutPassCount, 1)
        XCTAssertEqual(diagnostics.perBlockTextKitDocumentCount, 0)
        XCTAssertEqual(diagnostics.compatibilityTextDisplayValueCount, 0)
        XCTAssertTrue(diagnostics.usesSharedViewportContext)
    }

    func testAllVisibleViewportModesRenderSharedContextThroughLazyCollectionCells() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: supportSource))
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))

        XCTAssertTrue(singlePageBody.contains("UICollectionViewDataSource"))
        XCTAssertTrue(singlePageBody.contains("cellForItemAt"))
        XCTAssertTrue(singlePageBody.contains("ReaderViewportPageContent"))
        XCTAssertTrue(singlePageBody.contains("parent.viewportContext"))
        XCTAssertTrue(singlePageBody.contains("parent.viewportIndex"))
        XCTAssertFalse(singlePageBody.contains("ForEach(parent.pages"))
        XCTAssertFalse(singlePageBody.contains("ReaderBlockNovelTextDisplayMaterializer"))
        XCTAssertFalse(singlePageBody.contains("NovelTextKit2Representable("))
        XCTAssertTrue(verticalBody.contains("UICollectionViewDataSource"))
        XCTAssertTrue(verticalBody.contains("cellForItemAt"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalViewportDisplayPage"))
        XCTAssertTrue(verticalBody.contains("parent.viewportContext"))
        XCTAssertTrue(verticalBody.contains("parent.viewportIndex"))
        XCTAssertFalse(verticalBody.contains("ForEach(parent.pages"))
        XCTAssertFalse(verticalBody.contains("ReaderBlockNovelTextDisplayMaterializer"))
        XCTAssertFalse(verticalBody.contains("NovelTextKit2Representable("))
        XCTAssertTrue(singlePageBody.contains("UIHostingConfiguration"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalViewportCell"))
        XCTAssertTrue(spreadBody.contains("UICollectionViewDataSource"))
        XCTAssertTrue(spreadBody.contains("cellForItemAt"))
        XCTAssertTrue(spreadBody.contains("UIHostingConfiguration"))
        XCTAssertTrue(spreadBody.contains("ReaderPagedSpreadContent"))
        XCTAssertTrue(spreadBody.contains("parent.viewportContext"))
        XCTAssertTrue(spreadBody.contains("parent.viewportIndex"))
        XCTAssertTrue(spreadContentBody.contains("ReaderViewportPageContent"))
        XCTAssertTrue(spreadContentBody.contains("viewportContext"))
        XCTAssertTrue(spreadContentBody.contains("viewportIndex"))
        XCTAssertFalse(spreadBody.contains("ForEach(parent.pages"))
        XCTAssertFalse(spreadBody.contains("ReaderBlockNovelTextDisplayMaterializer"))
        XCTAssertFalse(spreadBody.contains("NovelTextKit2Representable("))
    }

    func testPagedViewportCellsRenderFromViewportIndexPageIdentity() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: supportSource))

        XCTAssertTrue(singlePageBody.contains("$0.pageIndex == indexPath.item"))
        XCTAssertFalse(singlePageBody.contains("compatibilityBlocks"))
        XCTAssertFalse(singlePageBody.contains("let page = parent.pages[indexPath.item]"))
        XCTAssertFalse(singlePageBody.contains("viewportBackedPage("))
        XCTAssertTrue(spreadContentBody.contains("$0.pageIndex == pageIndex"))
        XCTAssertFalse(spreadContentBody.contains("compatibilityBlocks"))
        XCTAssertFalse(spreadContentBody.contains("let page = pages[pageIndex]"))
        XCTAssertFalse(spreadContentBody.contains("viewportBackedPage("))
    }

    func testPagedViewportsRetrySelectionScrollAfterInitialZeroWidthLayout() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadCollectionViewport", in: supportSource))

        XCTAssertTrue(supportSource.contains("final class ReaderPagedViewportCollectionView: UICollectionView"))
        XCTAssertTrue(supportSource.contains("override func layoutSubviews()"))
        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("onLayoutSubviews"))
            XCTAssertTrue(body.contains("reloadDataAndRequestSelectionScroll(in: collectionView, animated: false)"))
            XCTAssertTrue(body.contains("scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)"))
        }
    }

    func testPagedViewportsRetrySelectionScrollAfterReloadLayoutCompletes() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadCollectionViewport", in: supportSource))

        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("reloadDataAndRequestSelectionScroll(in: collectionView, animated: false)"))
            XCTAssertTrue(body.contains("collectionView.performBatchUpdates(nil)"))
            XCTAssertTrue(body.contains("self?.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)"))
        }
    }

    func testPagedViewportsKeepPendingSelectionUntilCollectionViewCanRepresentTargetOffset() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadCollectionViewport", in: supportSource))

        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("collectionView.window != nil"))
            XCTAssertTrue(body.contains("collectionView.contentSize.width >= targetContentOffsetX + collectionView.bounds.width"))
            XCTAssertTrue(body.contains("schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)"))
            XCTAssertTrue(body.contains("collectionView.setContentOffset"))
            XCTAssertFalse(body.contains("collectionView.scrollToItem"))
        }
    }

    func testVerticalViewportUsesExplicitFlowLayoutSizingForScrollableFullWidthCells() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))

        XCTAssertTrue(verticalBody.contains("layout.estimatedItemSize = .zero"))
        XCTAssertTrue(verticalBody.contains("sizeForItemAt indexPath"))
        XCTAssertTrue(verticalBody.contains("verticalItemWidth(in: collectionView)"))
        XCTAssertTrue(verticalBody.contains("verticalItemHeight(for: indexPath.item"))
        XCTAssertTrue(verticalBody.contains("verticalDisplayPage(for: item)"))
        XCTAssertFalse(verticalBody.contains("ReaderViewportPageContent.viewportBackedPage"))
        XCTAssertTrue(verticalBody.contains("viewportLayoutMetrics"))
        XCTAssertTrue(verticalBody.contains("pageHeight(for: displayPage.pageIndex)"))
        XCTAssertFalse(verticalBody.contains("textRuntimeStore.measuredHeight"))
        XCTAssertFalse(verticalBody.contains("NovelTextLayout.measuredTextHeight"))
        XCTAssertTrue(verticalBody.contains("topInset: CGFloat"))
        XCTAssertTrue(verticalBody.contains("bottomInset: CGFloat"))
        XCTAssertTrue(verticalBody.contains("collectionView.contentInset = contentInset"))
        XCTAssertTrue(verticalBody.contains("reloadDataIfNeeded(in: collectionView"))
        XCTAssertTrue(verticalBody.contains("handledScrollRequest != request"))
        XCTAssertTrue(verticalBody.contains("tapGesture.cancelsTouchesInView = false"))
        XCTAssertFalse(verticalBody.contains("collectionView.reloadData()\n            context.coordinator.handle"))
        XCTAssertFalse(verticalBody.contains("UICollectionViewFlowLayout.automaticSize"))
    }

    func testVerticalViewportCellsUseWorkflowOwnedDisplayReferences() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))
        let verticalCellBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportCell", in: supportSource))

        XCTAssertTrue(verticalBody.contains("displayReferenceProvider"))
        XCTAssertTrue(verticalBody.contains("visiblePageIdentities"))
        XCTAssertFalse(verticalBody.contains("NovelTextLayoutLiveSurfaceStore"))
        XCTAssertFalse(verticalBody.contains("removeAllTextSurfaces"))
        XCTAssertTrue(verticalCellBody.contains("NovelTextViewportDisplayReference?"))
        XCTAssertTrue(verticalCellBody.contains("NovelTextViewportReferenceUIView"))
        XCTAssertTrue(verticalCellBody.contains("displayReference.viewportSample"))
        XCTAssertTrue(verticalCellBody.contains("displayReference.referenceY"))
        XCTAssertFalse(verticalCellBody.contains("NovelTextLayoutLiveSurface"))
        XCTAssertFalse(verticalCellBody.contains("NovelTextLayoutLiveSurfaceIdentity("))
        XCTAssertFalse(verticalCellBody.contains("textRuntimeStore.textSurface("))
        XCTAssertFalse(verticalCellBody.contains("NovelTextViewportDisplayUIView()"))
        XCTAssertFalse(verticalCellBody.contains("NovelTextKit2PlatformAdapter.makeAttributedText"))
        XCTAssertFalse(verticalCellBody.contains("NovelTextLayout.measuredTextHeight"))
    }

    func testVerticalViewportCellsSampleAndRestoreThroughTextKitSurfaces() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))
        let verticalCellBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportCell", in: supportSource))
        let displayPageBody = try XCTUnwrap(functionBody(named: "verticalDisplayPage", in: verticalBody))
        let itemHeightBody = try XCTUnwrap(functionBody(named: "verticalItemHeight", in: verticalBody))
        let publishFramesBody = try XCTUnwrap(functionBody(named: "publishFrames", in: verticalBody))
        let restoreTextAnchorBody = try XCTUnwrap(functionBody(named: "restoreTextAnchorIfPossible", in: verticalBody))
        let sampleBody = try XCTUnwrap(functionBody(named: "textViewportSample", in: verticalCellBody))
        let anchorBody = try XCTUnwrap(functionBody(named: "textViewportAnchorY", in: verticalCellBody))
        let makeImageBlockBody = try XCTUnwrap(functionBody(named: "makeImageBlockView", in: verticalCellBody))

        XCTAssertTrue(displayPageBody.contains("viewportIndex?.pages.first"))
        XCTAssertTrue(displayPageBody.contains("ReaderViewportPageContent.viewportBlocks"))
        XCTAssertFalse(displayPageBody.contains("ReaderViewportPageContent.viewportBackedPage"))
        XCTAssertTrue(itemHeightBody.contains("verticalDisplayPage(for: item)"))
        XCTAssertTrue(itemHeightBody.contains("viewportLayoutMetrics?.pageHeight(for: displayPage.pageIndex)"))
        XCTAssertFalse(itemHeightBody.contains("textRuntimeStore.measuredHeight"))
        XCTAssertFalse(itemHeightBody.contains("NovelTextLayout.measuredTextHeight"))
        XCTAssertTrue(publishFramesBody.contains("cell.textViewportSample("))
        XCTAssertTrue(publishFramesBody.contains("ReaderVerticalPositioning.pageDistance"))
        XCTAssertTrue(restoreTextAnchorBody.contains("request.textAnchor"))
        XCTAssertTrue(restoreTextAnchorBody.contains("cell.textViewportAnchorY("))
        XCTAssertTrue(restoreTextAnchorBody.contains("ReaderVerticalPositioning.viewportReferenceLineY"))
        XCTAssertTrue(sampleBody.contains("displayReference.viewportSample("))
        XCTAssertTrue(sampleBody.contains("ReaderVerticalPositioning.pageDistance"))
        XCTAssertTrue(anchorBody.contains("displayReference.referenceY("))
        XCTAssertTrue(makeImageBlockBody.contains("displayReference: nil"))
        XCTAssertFalse(sampleBody.contains("intraPageProgress"))
        XCTAssertFalse(restoreTextAnchorBody.contains("request.intraPageProgress"))
    }

    func testVerticalViewportSizingSamplingAndRestoreUseNovelTextLayoutViewportAPIs() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))
        let pagedSpreadBody = try XCTUnwrap(typeBody(named: "ReaderPagedSpreadContent", in: supportSource))
        let mapperBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportTextOffsetMapper", in: supportSource))
        let itemHeightBody = try XCTUnwrap(functionBody(named: "verticalItemHeight", in: verticalBody))

        XCTAssertTrue(
            verticalBody.contains(
                "let viewportIndex: NovelTextViewportIndex?\n    let viewportLayoutMetrics: NovelTextViewportLayoutMetrics?"
            )
        )
        XCTAssertFalse(pagedSpreadBody.contains("viewportLayoutMetrics"))
        XCTAssertTrue(itemHeightBody.contains("viewportLayoutMetrics?.pageHeight(for: displayPage.pageIndex)"))
        XCTAssertTrue(mapperBody.contains("NovelTextLayout.viewportSample"))
        XCTAssertTrue(mapperBody.contains("NovelTextLayout.displayOffset"))
        XCTAssertFalse(mapperBody.contains("var runningOffset"))
        XCTAssertFalse(mapperBody.contains("range.startOffset +"))
    }

    func testVerticalTextViewportPositioningUsesTextKitLineFragmentsInsteadOfGeometryProgress() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let displayUIViewBody = try XCTUnwrap(typeBody(named: "NovelTextViewportDisplayUIView", in: adapterSource))
        let closestTextOffsetBody = try XCTUnwrap(functionBody(named: "closestTextOffset", in: displayUIViewBody))
        let referenceYBody = try XCTUnwrap(functionBody(named: "textFragmentReferenceY", in: displayUIViewBody))

        XCTAssertTrue(closestTextOffsetBody.contains("textLineFragment("))
        XCTAssertTrue(closestTextOffsetBody.contains("forVerticalOffset:"))
        XCTAssertTrue(closestTextOffsetBody.contains("characterIndex(for:"))
        XCTAssertTrue(referenceYBody.contains("location(documentStart, offsetBy: normalizedOffset)"))
        XCTAssertTrue(referenceYBody.contains("textLayoutFragment(for: location)"))
        XCTAssertTrue(referenceYBody.contains("textLineFragment(for: location"))
        XCTAssertTrue(displayUIViewBody.contains("private func closestLayoutFragment"))
        XCTAssertFalse(closestTextOffsetBody.contains("progress"))
        XCTAssertFalse(closestTextOffsetBody.contains("fragmentLength"))
        XCTAssertFalse(referenceYBody.contains("progress"))
        XCTAssertFalse(referenceYBody.contains("fragmentLength"))
        XCTAssertFalse(referenceYBody.contains("progress * frame.height"))
    }

    func testViewportPageContentRequestsNormalTextDisplayValueFromNovelTextLayout() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let viewportPageContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportPageContent", in: supportSource))

        XCTAssertTrue(viewportPageContentBody.contains("viewportBlocks("))
        XCTAssertFalse(viewportPageContentBody.contains("viewportBackedPage("))
        XCTAssertTrue(viewportPageContentBody.contains("NovelTextLayout.displayValue("))
        XCTAssertTrue(viewportPageContentBody.contains("viewportPage.ranges"))
        XCTAssertFalse(viewportPageContentBody.contains("compatibilityBlocks"))
        XCTAssertTrue(viewportPageContentBody.contains("visibleSurfaceDiagnostics("))
        XCTAssertTrue(viewportPageContentBody.contains("NovelTextViewportVisibleSurfaceDiagnostics"))
        XCTAssertFalse(viewportPageContentBody.contains("viewportContext.document.textRangesBySegment"))
        XCTAssertFalse(viewportPageContentBody.contains("viewportContext.document.text"))
        XCTAssertFalse(viewportPageContentBody.contains("page.novelTextDisplayValues.first"))
    }

    func testNovelReadingSessionPositioningUsesViewportIndexWithoutPageSegmentFallbacks() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sessionSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelReadingSession.swift"),
            encoding: .utf8
        )
        let applyPaginationBody = try XCTUnwrap(functionBody(named: "applyPagination", in: sessionSource))
        let textRangesBody = try XCTUnwrap(functionBody(named: "textRanges", in: sessionSource))
        let containsSegmentBody = try XCTUnwrap(functionBody(named: "contains(segmentIndex", in: sessionSource))
        let intraPageProgressBody = try XCTUnwrap(functionBody(named: "intraPageProgress", in: sessionSource))

        XCTAssertFalse(applyPaginationBody.contains("page.segmentIndex"))
        XCTAssertFalse(applyPaginationBody.contains("page.segmentStartOffset"))
        XCTAssertFalse(applyPaginationBody.contains("page.segmentEndOffset"))
        XCTAssertFalse(textRangesBody.contains("page.novelTextDisplayValues"))
        XCTAssertFalse(containsSegmentBody.contains("page.segmentIndex"))
        XCTAssertFalse(intraPageProgressBody.contains("page.segmentStartOffset"))
        XCTAssertFalse(intraPageProgressBody.contains("page.segmentEndOffset"))
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

        let materialization = NovelTextDisplayAdapter.materialization(
            surface: .novelReadingSessionTextBlock,
            displayValue: NovelTextDisplayValue(
                text: "第一章\n正文需要覆盖字体、字号、行距、字距和段首缩进。",
                chapterTitle: "第一章",
                startsAtParagraphBoundary: true,
                settings: settings
            ),
            baseFontSize: 22,
            textColor: .primaryReaderText
        )

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
                viewportPageLayout: { _, _, _ in [] }
            )
        ) { error in
            XCTAssertEqual(error as? NovelTextLayoutFailure, .unableToLayoutText)
        }
    }
}

private func viewportContext(
    text: String,
    settings: ReaderAppearanceSettings
) -> NovelTextViewportContext {
    NovelTextViewportContext(
        identity: NovelTextViewportIdentity(
            threadURL: URL(string: "https://bbs.yamibo.com/forum.php?mod=viewthread&tid=indent&mobile=2")!,
            documentView: 1,
            maxView: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            contentSource: .fallbackUnfilteredPage,
            appearance: settings,
            layout: ReaderContainerLayout(width: 320, height: 568)
        ),
        document: NovelTextViewportDocument(
            text: text,
            textRangesBySegment: [
                0: ReaderRenderedTextRange(segmentIndex: 0, startOffset: 0, endOffset: text.count)
            ],
            insertedSeparatorRanges: []
        ),
        externalBlocks: [],
        diagnostics: NovelTextViewportDiagnostics(indexBuildCount: 1)
    )
}

private func viewportTestIndexPage(index: Int, range: ReaderRenderedTextRange) -> NovelTextViewportIndexPage {
    NovelTextViewportIndexPage(
        pageIndex: index,
        documentView: 1,
        chapterOrdinal: 0,
        chapterTitle: "第一章",
        ranges: [range]
    )
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
