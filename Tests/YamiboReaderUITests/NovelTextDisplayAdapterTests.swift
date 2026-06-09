import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class NovelTextDisplayAdapterTests: XCTestCase {
    func testMigrationGateRejectsUIOwnedTextKitGraphsAndDisplayValueFallbacks() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let sessionSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelReadingSession.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(adapterSource.contains("NovelTextLayoutLiveSurfaceStore"))
        XCTAssertFalse(adapterSource.contains("NovelTextLayoutLiveSurface"))
        XCTAssertFalse(adapterSource.contains("NovelTextViewportDisplayUIView"))
        XCTAssertFalse(adapterSource.contains("NativeNovelTextDisplayView"))
        XCTAssertFalse(adapterSource.contains("NovelTextDisplayValue"))
        XCTAssertFalse(adapterSource.contains("NovelTextDisplayAdapter"))
        XCTAssertFalse(adapterSource.contains("NSTextContentStorage"))
        XCTAssertFalse(adapterSource.contains("NSTextLayoutManager"))
        XCTAssertFalse(supportSource.contains("NovelTextLayout.displayValue("))
        XCTAssertFalse(supportSource.contains("NovelTextDisplayValue"))
        XCTAssertFalse(supportSource.contains("NativeNovelTextDisplayView"))
        XCTAssertFalse(sessionSource.contains("import UIKit"))
        XCTAssertFalse(sessionSource.contains("import AppKit"))
        XCTAssertTrue(sessionSource.contains("package struct NovelReadingSession: Sendable"))
    }

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

        XCTAssertTrue(singlePageBody.contains("displayReferenceProvider($0.identity)"))
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

    func testViewportSurfaceContentDoesNotMaterializeDisplayValuesForParagraphIndent() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let viewportContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportSurfaceContent", in: supportSource))

        XCTAssertFalse(viewportContentBody.contains("NovelTextLayout.displayValue("))
        XCTAssertFalse(viewportContentBody.contains("NovelTextDisplayValue"))
    }

    func testSettingsPreviewUsesAttributedPreviewSurfaceWithoutUILayoutMeasurement() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settingsSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSettingsViews.swift"),
            encoding: .utf8
        )
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let previewBody = try XCTUnwrap(typeBody(named: "ReaderBooksPreviewMaskedContent", in: settingsSource))

        XCTAssertTrue(previewBody.contains("NativeNovelTextSettingsPreviewView("))
        XCTAssertTrue(previewBody.contains("NovelTextSettingsPreviewSurface("))
        XCTAssertTrue(previewBody.contains("settings: settings"))
        XCTAssertTrue(adapterSource.contains("NovelTextSettingsPreviewSurface"))
        XCTAssertFalse(previewBody.contains("sizeThatFits"))
        XCTAssertFalse(previewBody.contains("measuredHeight"))
    }

    func testReferenceSurfaceOwnsNoTextKitGraphAndDisplayValueIsRemoved() throws {
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
        let referenceSurfaceBody = try XCTUnwrap(
            typeBody(named: "NovelTextViewportReferenceUIView", in: adapterSource)
        )

        XCTAssertFalse(readerModelsSource.contains("NovelTextDisplayValue"))
        XCTAssertTrue(referenceSurfaceBody.contains("NovelTextViewportDisplayReference?"))
        XCTAssertTrue(referenceSurfaceBody.contains("displayReference.draw("))
        XCTAssertFalse(referenceSurfaceBody.contains("NSTextContentStorage"))
        XCTAssertFalse(referenceSurfaceBody.contains("NSTextLayoutManager"))
        XCTAssertFalse(referenceSurfaceBody.contains("NSAttributedString"))
    }

    func testNovelTextViewportReferenceInvalidatesDrawingWhenReferenceChanges() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let referenceSurfaceBody = try XCTUnwrap(
            typeBody(named: "NovelTextViewportReferenceUIView", in: adapterSource)
        )

        XCTAssertTrue(referenceSurfaceBody.contains("guard oldValue !== displayReference"))
        XCTAssertTrue(referenceSurfaceBody.contains("setNeedsDisplay()"))
        XCTAssertTrue(referenceSurfaceBody.contains("context.clear(self.bounds)"))
        XCTAssertTrue(referenceSurfaceBody.contains("clearsContextBeforeDrawing = true"))
        XCTAssertTrue(referenceSurfaceBody.contains("contentMode = .redraw"))
        XCTAssertTrue(referenceSurfaceBody.contains("override func layoutSubviews()"))
        XCTAssertTrue(referenceSurfaceBody.contains("override func didMoveToWindow()"))
    }

    func testTwoPagePagedSpreadUsesViewportBackedReaderPageContent() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readerSupportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: readerSupportSource))

        XCTAssertTrue(spreadContentBody.contains("ReaderViewportSurfaceContent("))
        XCTAssertTrue(spreadContentBody.contains("displayReference: surface.flatMap"))
        XCTAssertFalse(spreadContentBody.contains("Text(displayValue.text"))
        XCTAssertFalse(spreadContentBody.contains("NovelTextDisplayValue"))
    }

    func testTwoPageSpreadInstallsOpaqueReferencesForLeftAndRightPages() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let spreadViewportBody = try XCTUnwrap(
            typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource)
        )
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: supportSource))

        XCTAssertTrue(spreadViewportBody.contains("displayReferenceProvider"))
        XCTAssertTrue(spreadContentBody.contains("displayReferenceProvider($0.identity)"))
        XCTAssertTrue(spreadContentBody.contains("displayReference: surface.flatMap"))
        XCTAssertFalse(spreadContentBody.contains("NovelTextViewportDisplayUIView()"))
        XCTAssertFalse(spreadContentBody.contains("NSTextContentStorage"))
        XCTAssertFalse(spreadContentBody.contains("NSTextLayoutManager"))
    }

    func testReaderLifecycleClosesWorkflowAndForwardsMemoryWarnings() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let modelSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(containerSource.contains("UIApplication.didReceiveMemoryWarningNotification"))
        XCTAssertTrue(containerSource.contains("model.handleMemoryPressure()"))
        XCTAssertTrue(containerSource.contains("await model.saveProgress()"))
        XCTAssertTrue(containerSource.contains("model.close()"))
        XCTAssertTrue(modelSource.contains("readingWorkflow?.handleMemoryPressure()"))
        XCTAssertTrue(modelSource.contains("readingWorkflow?.close()"))
    }

    func testReaderCommentsOpenOriginalPostUsesParentDismissFlow() throws {
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

        XCTAssertTrue(containerSource.contains("let resumeContext = await model.saveProgress()"))
        XCTAssertTrue(containerSource.contains("appModel.dismissReader(openThreadInForum: url, suspendedContext: resumeContext)"))
        XCTAssertTrue(supportSource.contains("let onOpenOriginalPost: (URL) -> Void"))
        XCTAssertTrue(supportSource.contains("onOpenOriginalPost(url)"))
        XCTAssertFalse(supportSource.contains("appModel.dismissReader(openThreadInForum: url)"))
    }

    func testPagedCellsResolveViewportSurfaceIdentityBeforeRenderingNormalText() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: supportSource))
        let viewportContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportSurfaceContent", in: supportSource))

        XCTAssertTrue(singlePageBody.contains("parent.surfaces[indexPath.item]"))
        XCTAssertTrue(spreadContentBody.contains("surfaces.first"))
        for body in [singlePageBody, spreadContentBody] {
            XCTAssertTrue(body.contains("ReaderViewportSurfaceContent("))
            XCTAssertFalse(body.contains("page.blocks.compactMap(\\.novelTextDisplayValue)"))
            XCTAssertFalse(body.contains("page.novelTextDisplayValues.first"))
            XCTAssertFalse(body.contains("identity.ordinal =="))
        }
        XCTAssertTrue(spreadContentBody.contains("$0.presentationIndex == surfaceIndex"))
        XCTAssertFalse(singlePageBody.contains("$0.documentView == page.documentView"))
        XCTAssertFalse(spreadContentBody.contains("$0.documentView == page.documentView"))
        XCTAssertTrue(viewportContentBody.contains("viewportBlocks("))
        XCTAssertTrue(viewportContentBody.contains("displayReference: displayReference"))
        XCTAssertTrue(viewportContentBody.contains("fallbackSurfaceIndex"))
        XCTAssertFalse(supportSource.contains("fallbackPageIndex"))
        XCTAssertFalse(viewportContentBody.contains("NovelTextLayout.displayValue("))
        XCTAssertFalse(viewportContentBody.contains("NovelTextDisplayValue"))
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
        XCTAssertTrue(collectionViewportBody.contains("surfaces"))
        XCTAssertFalse(collectionViewportBody.contains("viewportContext"))
        XCTAssertFalse(collectionViewportBody.contains("viewportIndex"))
    }

    func testPagedViewportUsesChromeInsetsBecauseHostingCellAlreadyAppliesSafeArea() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let pagedContentBody = try XCTUnwrap(functionBody(named: "pagedContent", in: containerSource))

        XCTAssertTrue(pagedContentBody.contains("topInset: layout.chromeInsets.top"))
        XCTAssertTrue(pagedContentBody.contains("bottomInset: layout.chromeInsets.bottom"))
    }

    func testTwoPageSpreadReadingUsesUIKitCollectionViewportWithCommittedSurfaces() throws {
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
        let spreadViewportBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: supportSource))

        XCTAssertTrue(pagedContentBody.contains("ReaderPresentationSpreadCollectionViewport("))
        XCTAssertTrue(supportSource.contains("struct ReaderPresentationSpreadCollectionViewport: UIViewRepresentable"))
        XCTAssertTrue(spreadViewportBody.contains("UICollectionView"))
        XCTAssertTrue(spreadViewportBody.contains("surfaces"))
        XCTAssertFalse(spreadViewportBody.contains("viewportContext"))
        XCTAssertFalse(spreadViewportBody.contains("viewportIndex"))
        XCTAssertTrue(spreadContentBody.contains("spread.leftSurfaceIndex"))
        XCTAssertTrue(spreadContentBody.contains("spread.rightSurfaceIndex"))
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
        XCTAssertTrue(verticalContentBody.contains("ReaderVerticalViewportScrollView("))
        XCTAssertTrue(scrollViewBody.contains("verticalDisplaySurface(for: indexPath.item)"))
        XCTAssertFalse(scrollViewBody.contains("ReaderViewportSurfaceContent.viewportBackedPage("))
        XCTAssertTrue(readerBlockBody.contains("NativeNovelTextViewportReferenceView("))
        XCTAssertTrue(readerBlockBody.contains("displayReference"))
        XCTAssertFalse(readerBlockBody.contains("NativeNovelTextDisplayView("))
        XCTAssertFalse(readerBlockBody.contains("NovelTextDisplayValue"))
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
        XCTAssertTrue(scrollViewBody.contains("surfaces: [NovelReaderSurface]"))
        XCTAssertTrue(scrollViewBody.contains("displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity)"))
        XCTAssertFalse(scrollViewBody.contains("viewportContext"))
        XCTAssertFalse(scrollViewBody.contains("viewportIndex"))
    }

    func testAllVisibleViewportModesRenderSharedContextThroughLazyCollectionCells() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: supportSource))
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))

        XCTAssertTrue(singlePageBody.contains("UICollectionViewDataSource"))
        XCTAssertTrue(singlePageBody.contains("cellForItemAt"))
        XCTAssertTrue(singlePageBody.contains("ReaderViewportSurfaceContent"))
        XCTAssertTrue(singlePageBody.contains("parent.surfaces"))
        XCTAssertFalse(singlePageBody.contains("parent.viewportContext"))
        XCTAssertFalse(singlePageBody.contains("parent.viewportIndex"))
        XCTAssertFalse(singlePageBody.contains("ForEach(parent.pages"))
        XCTAssertFalse(singlePageBody.contains("ReaderBlockNovelTextDisplayMaterializer"))
        XCTAssertFalse(singlePageBody.contains("NovelTextKit2Representable("))
        XCTAssertTrue(verticalBody.contains("UICollectionViewDataSource"))
        XCTAssertTrue(verticalBody.contains("cellForItemAt"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalViewportDisplaySurface"))
        XCTAssertTrue(verticalBody.contains("parent.surfaces"))
        XCTAssertFalse(verticalBody.contains("parent.viewportContext"))
        XCTAssertFalse(verticalBody.contains("parent.viewportIndex"))
        XCTAssertFalse(verticalBody.contains("ForEach(parent.pages"))
        XCTAssertFalse(verticalBody.contains("ReaderBlockNovelTextDisplayMaterializer"))
        XCTAssertFalse(verticalBody.contains("NovelTextKit2Representable("))
        XCTAssertTrue(singlePageBody.contains("UIHostingConfiguration"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalViewportCell"))
        XCTAssertTrue(spreadBody.contains("UICollectionViewDataSource"))
        XCTAssertTrue(spreadBody.contains("cellForItemAt"))
        XCTAssertTrue(spreadBody.contains("UIHostingConfiguration"))
        XCTAssertTrue(spreadBody.contains("ReaderPresentationSpreadContent"))
        XCTAssertTrue(spreadBody.contains("parent.surfaces"))
        XCTAssertFalse(spreadBody.contains("parent.viewportContext"))
        XCTAssertFalse(spreadBody.contains("parent.viewportIndex"))
        XCTAssertTrue(spreadContentBody.contains("ReaderViewportSurfaceContent"))
        XCTAssertTrue(spreadContentBody.contains("surfaces"))
        XCTAssertFalse(spreadContentBody.contains("viewportContext"))
        XCTAssertFalse(spreadContentBody.contains("viewportIndex"))
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
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: supportSource))

        XCTAssertTrue(singlePageBody.contains("parent.surfaces[indexPath.item]"))
        XCTAssertFalse(singlePageBody.contains("identity.ordinal =="))
        XCTAssertFalse(singlePageBody.contains("compatibilityBlocks"))
        XCTAssertFalse(singlePageBody.contains("let page = parent.pages[indexPath.item]"))
        XCTAssertFalse(singlePageBody.contains("viewportBackedPage("))
        XCTAssertTrue(spreadContentBody.contains("$0.presentationIndex == surfaceIndex"))
        XCTAssertFalse(spreadContentBody.contains("identity.ordinal =="))
        XCTAssertFalse(spreadContentBody.contains("compatibilityBlocks"))
        XCTAssertFalse(spreadContentBody.contains("let page = pages[surfaceIndex]"))
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
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))

        XCTAssertTrue(supportSource.contains("final class ReaderPagedViewportCollectionView: UICollectionView"))
        XCTAssertTrue(supportSource.contains("override func layoutSubviews()"))
        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("onLayoutSubviews"))
            XCTAssertTrue(body.contains("reloadDataAndRequestSelectionScroll(in: collectionView, animated: false)"))
            XCTAssertTrue(body.contains("scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)"))
        }
    }

    func testVerticalViewportPublishesVisibleSurfacesAfterLayoutSubviews() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))

        XCTAssertTrue(supportSource.contains("private final class ReaderVerticalViewportCollectionView: UICollectionView"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalViewportCollectionView(frame: .zero, collectionViewLayout: layout)"))
        XCTAssertTrue(verticalBody.contains("collectionView.onLayoutSubviews"))
        XCTAssertTrue(verticalBody.contains("coordinator?.publishLayout(from: collectionView)"))
        XCTAssertTrue(verticalBody.contains("func publishLayout(from collectionView: UICollectionView)"))
        XCTAssertFalse(verticalBody.contains("scrollViewDidLayoutSubviews"))
    }

    func testVerticalViewportRefreshesCellsAfterFinalFlowLayoutSizing() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))
        let coordinatorBody = try XCTUnwrap(typeBody(named: "Coordinator", in: verticalBody))
        let cellBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportCell", in: supportSource))
        let reloadBody = try XCTUnwrap(functionBody(named: "reloadDataIfNeeded", in: coordinatorBody))
        let applyBody = try XCTUnwrap(functionBody(named: "apply", in: cellBody))
        let refreshBody = try XCTUnwrap(functionBody(named: "refreshLayoutForCurrentBounds", in: cellBody))
        let refreshForSizeBody = try XCTUnwrap(functionBody(named: "refreshLayout(for layoutSize: CGSize)", in: cellBody))
        let effectiveSizeBody = try XCTUnwrap(functionBody(named: "effectiveLayoutSize", in: cellBody))
        let applyContentFrameBody = try XCTUnwrap(functionBody(named: "applyContentViewFrame", in: cellBody))

        XCTAssertTrue(reloadBody.contains("collectionView.layoutIfNeeded()"))
        XCTAssertTrue(reloadBody.contains("publishLayout(from: collectionView)"))
        XCTAssertTrue(coordinatorBody.contains("willDisplay cell"))
        XCTAssertTrue(coordinatorBody.contains("layoutAttributesForItem(at: indexPath)"))
        XCTAssertTrue(coordinatorBody.contains("refreshLayout(for: attributes.size)"))
        XCTAssertTrue(coordinatorBody.contains("refreshLayoutForCurrentBounds(forceRedraw: true)"))
        XCTAssertTrue(cellBody.contains("private var lastAppliedLayoutSize = CGSize.zero"))
        XCTAssertTrue(cellBody.contains("private var preferredLayoutSize = CGSize.zero"))
        XCTAssertTrue(applyBody.contains("layoutAttributes.size"))
        XCTAssertTrue(applyBody.contains("effectiveLayoutSize(for: layoutAttributes.size)"))
        XCTAssertTrue(applyBody.contains("applyContentViewFrame(for: nextSize)"))
        XCTAssertTrue(applyBody.contains("refreshLayoutForCurrentBounds()"))
        XCTAssertTrue(refreshBody.contains("layoutBlockSubviews()"))
        XCTAssertTrue(refreshBody.contains("setNeedsDisplayForTextBlocks()"))
        XCTAssertTrue(refreshForSizeBody.contains("effectiveLayoutSize(for: layoutSize)"))
        XCTAssertTrue(refreshForSizeBody.contains("applyContentViewFrame(for: nextSize)"))
        XCTAssertTrue(effectiveSizeBody.contains("preferredLayoutSize.height"))
        XCTAssertFalse(applyContentFrameBody.contains("bounds.size = layoutSize"))
        XCTAssertTrue(applyContentFrameBody.contains("contentView.frame = contentFrame"))
    }

    func testPagedViewportsRetrySelectionScrollAfterReloadLayoutCompletes() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))

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
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))

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
        XCTAssertTrue(verticalBody.contains("verticalDisplaySurface(for: item)"))
        XCTAssertFalse(verticalBody.contains("ReaderViewportSurfaceContent.viewportBackedPage"))
        XCTAssertTrue(verticalBody.contains("presentationHeight"))
        XCTAssertTrue(verticalBody.contains("displaySurface.presentationHeight"))
        XCTAssertFalse(verticalBody.contains("viewportLayoutMetrics"))
        XCTAssertFalse(verticalBody.contains("surfaceHeight(for: displaySurface.surfaceOrdinal)"))
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
        XCTAssertTrue(verticalBody.contains("verticalSurface(for:"))
        XCTAssertTrue(verticalBody.contains("visibleSurfaceIdentities"))
        XCTAssertTrue(verticalBody.contains("onVisibleSurfaceIdentitiesChange"))
        XCTAssertFalse(verticalBody.contains("onVisiblePageIdentitiesChange"))
        XCTAssertFalse(verticalBody.contains("surfaceIdentityByPageIndex"))
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
        let displaySurfaceBody = try XCTUnwrap(functionBody(named: "verticalDisplaySurface", in: verticalBody))
        let itemHeightBody = try XCTUnwrap(functionBody(named: "verticalItemHeight", in: verticalBody))
        let publishFramesBody = try XCTUnwrap(functionBody(named: "publishFrames", in: verticalBody))
        let redrawBody = try XCTUnwrap(functionBody(named: "scheduleVisibleTextRedraw", in: verticalBody))
        let redrawVisibleTextBody = try XCTUnwrap(functionBody(named: "redrawVisibleText", in: verticalBody))
        let restoreTextAnchorBody = try XCTUnwrap(functionBody(named: "restoreTextAnchorIfPossible", in: verticalBody))
        let sampleBody = try XCTUnwrap(functionBody(named: "textViewportSample", in: verticalCellBody))
        let anchorBody = try XCTUnwrap(functionBody(named: "textViewportAnchorY", in: verticalCellBody))
        let setNeedsDisplayBody = try XCTUnwrap(functionBody(named: "setNeedsDisplayForTextBlocks", in: verticalCellBody))
        let makeImageBlockBody = try XCTUnwrap(functionBody(named: "makeImageBlockView", in: verticalCellBody))

        XCTAssertTrue(displaySurfaceBody.contains("verticalSurface(for: item)"))
        XCTAssertTrue(displaySurfaceBody.contains("ReaderViewportSurfaceContent.viewportBlocks"))
        XCTAssertFalse(displaySurfaceBody.contains("ReaderViewportSurfaceContent.viewportBackedPage"))
        XCTAssertTrue(itemHeightBody.contains("verticalDisplaySurface(for: item)"))
        XCTAssertTrue(itemHeightBody.contains("displaySurface.presentationHeight"))
        XCTAssertFalse(itemHeightBody.contains("viewportLayoutMetrics"))
        XCTAssertFalse(itemHeightBody.contains("textRuntimeStore.measuredHeight"))
        XCTAssertFalse(itemHeightBody.contains("NovelTextLayout.measuredTextHeight"))
        XCTAssertTrue(publishFramesBody.contains("cell.textViewportSample("))
        XCTAssertTrue(publishFramesBody.contains("ReaderVerticalPositioning.pageDistance"))
        XCTAssertFalse(publishFramesBody.contains("scheduleVisibleTextRedraw"))
        XCTAssertTrue(verticalBody.contains("scheduleVisibleTextRedraw(in: collectionView, includeDelayedPass: false)"))
        XCTAssertTrue(verticalBody.contains("scheduleVisibleTextRedraw(in: collectionView, includeDelayedPass: true)"))
        XCTAssertTrue(redrawBody.contains("DispatchQueue.main.async"))
        XCTAssertTrue(redrawVisibleTextBody.contains("refreshLayoutForCurrentBounds(forceRedraw: true)"))
        XCTAssertTrue(restoreTextAnchorBody.contains("request.textAnchor"))
        XCTAssertTrue(restoreTextAnchorBody.contains("cell.textViewportAnchorY("))
        XCTAssertTrue(restoreTextAnchorBody.contains("applyTextAnchorRestore"))
        XCTAssertTrue(restoreTextAnchorBody.contains("applyProgressFallbackRestore"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalPositioning.viewportReadingAnchorLineY"))
        XCTAssertTrue(sampleBody.contains("displayReference.viewportSample("))
        XCTAssertTrue(sampleBody.contains("ReaderVerticalPositioning.pageDistance"))
        XCTAssertTrue(anchorBody.contains("displayReference.referenceY("))
        XCTAssertTrue(setNeedsDisplayBody.contains("block.displayReference != nil"))
        XCTAssertTrue(setNeedsDisplayBody.contains("block.view.setNeedsDisplay()"))
        XCTAssertTrue(verticalCellBody.contains("contentView.clipsToBounds = true"))
        XCTAssertTrue(makeImageBlockBody.contains("displayReference: nil"))
        XCTAssertFalse(sampleBody.contains("intraSurfaceProgress"))
        XCTAssertFalse(restoreTextAnchorBody.contains("request.intraSurfaceProgress"))
    }

    func testVerticalViewportSizingSamplingAndRestoreUseWorkflowReferences() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))
        let pagedSpreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: supportSource))
        let itemHeightBody = try XCTUnwrap(functionBody(named: "verticalItemHeight", in: verticalBody))

        XCTAssertTrue(verticalBody.contains("let surfaces: [NovelReaderSurface]"))
        XCTAssertFalse(pagedSpreadBody.contains("viewportLayoutMetrics"))
        XCTAssertTrue(itemHeightBody.contains("displaySurface.presentationHeight"))
        XCTAssertTrue(verticalBody.contains("displayReferenceProvider"))
        XCTAssertFalse(verticalBody.contains("viewportIndex"))
        XCTAssertFalse(verticalBody.contains("viewportLayoutMetrics"))
        XCTAssertFalse(supportSource.contains("ReaderVerticalViewportTextOffsetMapper"))
        XCTAssertFalse(supportSource.contains("NovelTextLayout.viewportSample"))
        XCTAssertFalse(supportSource.contains("NovelTextLayout.displayOffset"))
    }

    func testVerticalTextViewportPositioningLivesInCoreRuntime() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runtimeSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelTextViewportRuntime.swift"),
            encoding: .utf8
        )
        let runtimeBody = try XCTUnwrap(
            typeBody(named: "NovelTextViewportRuntimeOwner", in: runtimeSource)
        )

        XCTAssertTrue(runtimeBody.contains("textLineFragment("))
        XCTAssertTrue(runtimeBody.contains("forVerticalOffset:"))
        XCTAssertTrue(runtimeBody.contains("characterIndex(for:"))
        XCTAssertTrue(runtimeBody.contains("textLayoutFragment(for: location)"))
        XCTAssertTrue(runtimeBody.contains("private func closestLayoutFragment"))
        XCTAssertFalse(runtimeBody.contains("progress * frame.height"))
        XCTAssertFalse(runtimeBody.contains("textRangesBySegment"))
        XCTAssertFalse(runtimeBody.contains("semantics(forSegmentIndex"))
        XCTAssertFalse(runtimeBody.contains("resolvedSegmentIndex"))
        XCTAssertTrue(runtimeBody.contains("containingDocumentOffset:"))
        XCTAssertTrue(runtimeBody.contains("nearestTextSample("))
    }

    func testViewportSurfaceContentUsesReferenceMarkerWithoutRebuildingDisplayValue() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let viewportSurfaceContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportSurfaceContent", in: supportSource))

        XCTAssertTrue(viewportSurfaceContentBody.contains("viewportBlocks("))
        XCTAssertFalse(viewportSurfaceContentBody.contains("viewportBackedPage("))
        XCTAssertTrue(viewportSurfaceContentBody.contains("displayReference: displayReference"))
        XCTAssertFalse(viewportSurfaceContentBody.contains("NovelTextLayout.displayValue("))
        XCTAssertFalse(viewportSurfaceContentBody.contains("NovelTextDisplayValue"))
        XCTAssertTrue(viewportSurfaceContentBody.contains("surface.kind == .text"))
        XCTAssertFalse(viewportSurfaceContentBody.contains("viewportSurface"))
        XCTAssertFalse(viewportSurfaceContentBody.contains("compatibilityBlocks"))
        XCTAssertFalse(viewportSurfaceContentBody.contains("viewportContext.document.textRangesBySegment"))
        XCTAssertFalse(viewportSurfaceContentBody.contains("viewportContext.document.text"))
        XCTAssertFalse(viewportSurfaceContentBody.contains("page.novelTextDisplayValues.first"))
    }

    func testPagedExternalBlockSurfaceContentCentersImageBlocks() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let supportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )
        let viewportSurfaceContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportSurfaceContent", in: supportSource))

        XCTAssertTrue(viewportSurfaceContentBody.contains("if centersExternalBlockInPagedMode"))
        XCTAssertTrue(viewportSurfaceContentBody.contains("settings.readingMode == .paged && surface?.kind == .externalBlock"))
        XCTAssertTrue(viewportSurfaceContentBody.contains("centeredViewportBlocks"))
        XCTAssertTrue(viewportSurfaceContentBody.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)"))
        XCTAssertTrue(viewportSurfaceContentBody.contains("stackedViewportBlocks"))
        XCTAssertTrue(viewportSurfaceContentBody.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
    }

    func testNovelReadingSessionPositioningUsesViewportIndexWithoutPageSegmentFallbacks() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sessionSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderCore/Support/NovelReadingSession.swift"),
            encoding: .utf8
        )
        let committedLayoutBody = try XCTUnwrap(functionBody(named: "applyCommittedLayoutResult", in: sessionSource))

        XCTAssertTrue(sessionSource.contains("consumeCommittedLayoutResult("))
        XCTAssertFalse(sessionSource.contains("func applySettings("))
        XCTAssertFalse(sessionSource.contains("func updateLayout("))
        XCTAssertFalse(sessionSource.contains("func updatePagedPresentationEnvironment("))
        XCTAssertFalse(sessionSource.contains("private let pagination"))
        XCTAssertFalse(committedLayoutBody.contains("page.segmentIndex"))
        XCTAssertFalse(committedLayoutBody.contains("page.segmentStartOffset"))
        XCTAssertFalse(committedLayoutBody.contains("page.segmentEndOffset"))
        XCTAssertNil(functionBody(named: "textRanges", in: sessionSource))
        XCTAssertNil(functionBody(named: "contains(segmentIndex", in: sessionSource))
        XCTAssertNil(functionBody(named: "intraSurfaceProgress", in: sessionSource))
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

    func testNovelReadingSessionBlockPassesOpaqueDisplayReference() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let readerSupportSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSupportViews.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(readerSupportSource.contains("displayReference: displayReference"))
        XCTAssertTrue(readerSupportSource.contains("NativeNovelTextViewportReferenceView("))
        XCTAssertFalse(readerSupportSource.contains("NativeNovelTextDisplayView("))
        XCTAssertFalse(readerSupportSource.contains("NovelTextLayout.displayValue("))
    }

    func testSettingsPreviewUsesLightweightSurfaceInsteadOfReaderRuntimeAdapter() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settingsSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Views/ReaderSettingsViews.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(settingsSource.contains("NativeNovelTextSettingsPreviewView("))
        XCTAssertTrue(settingsSource.contains("NovelTextSettingsPreviewSurface("))
        XCTAssertFalse(settingsSource.contains("NativeNovelTextDisplayView("))
        XCTAssertFalse(settingsSource.contains("NovelTextDisplayValue"))
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
            try NovelTextLayout.layout(
                document: document,
                settings: ReaderAppearanceSettings(readingMode: .paged),
                layout: ReaderContainerLayout(width: 320, height: 568),
                viewportSurfaceLayout: { _, _, _ in [] }
            )
        ) { error in
            XCTAssertEqual(error as? NovelTextLayoutFailure, .textKitIndexing)
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

private func viewportTestIndexPage(index: Int, range: ReaderRenderedTextRange) -> NovelTextViewportIndexSurface {
    NovelTextViewportIndexSurface(
        surfaceOrdinal: index,
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
