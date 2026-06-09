import CoreGraphics
import XCTest
@testable import YamiboReaderCore
@testable import YamiboReaderUI

final class NovelTextDisplayAdapterTests: XCTestCase {
    func testInlineImageHitTestingUsesAspectFitFrameOnly() {
        let container = CGSize(width: 300, height: 500)
        let image = CGSize(width: 300, height: 200)
        let imageFrame = ReaderImageHitTesting.aspectFitImageFrame(
            imageSize: image,
            containerSize: container
        )

        XCTAssertEqual(imageFrame, CGRect(x: 0, y: 150, width: 300, height: 200))
        XCTAssertTrue(ReaderImageHitTesting.containsImagePoint(CGPoint(x: 150, y: 240), imageSize: image, containerSize: container))
        XCTAssertFalse(ReaderImageHitTesting.containsImagePoint(CGPoint(x: 150, y: 420), imageSize: image, containerSize: container))
    }

    func testPagedTapZoneKeepsBlankAreaNavigationAvailable() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)

        XCTAssertEqual(ReaderPagedTapZone.zone(for: CGPoint(x: 40, y: 720), in: bounds), .previous)
        XCTAssertEqual(ReaderPagedTapZone.zone(for: CGPoint(x: 190, y: 720), in: bounds), .toggleChrome)
        XCTAssertEqual(ReaderPagedTapZone.zone(for: CGPoint(x: 340, y: 720), in: bounds), .next)
    }

    func testPagedPageTurnVisualMetricsFadeOverlayAsPageApproachesRest() {
        let start = ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 201,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 2
        )
        let halfway = ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 250,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 2
        )
        let completed = ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 300,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 2
        )

        XCTAssertEqual(start?.overlayAlpha ?? 0, ReaderPagedPageTurnPresentation.maxOverlayAlpha * 0.99, accuracy: 0.001)
        XCTAssertEqual(halfway?.overlayAlpha ?? 0, ReaderPagedPageTurnPresentation.maxOverlayAlpha * 0.5, accuracy: 0.001)
        XCTAssertNil(completed)
    }

    func testPagedPageTurnVisualMetricsIdentifyNextAndPreviousPages() throws {
        let next = try XCTUnwrap(ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 250,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 2
        ))
        let previous = try XCTUnwrap(ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 150,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 2
        ))

        XCTAssertEqual(next.roundedPageIndex, 2)
        XCTAssertEqual(next.maskedPageIndex, 3)
        XCTAssertEqual(next.cornerRadius, ReaderPagedPageTurnPresentation.fallbackPageCornerRadius)
        XCTAssertTrue(next.isActive)
        XCTAssertEqual(previous.roundedPageIndex, 2)
        XCTAssertEqual(previous.maskedPageIndex, 1)
        XCTAssertTrue(previous.isActive)
    }

    func testPagedPageTurnVisualMetricsStayInactiveAtRestAndBoundaries() {
        XCTAssertNil(ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 200,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 2
        ))
        XCTAssertNil(ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: -20,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 0
        ))
        XCTAssertNil(ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: 420,
            pageWidth: 100,
            pageCount: 5,
            restingPageIndex: 4
        ))
    }

    func testImageTapRoutesHitImageBeforePageTapHandling() throws {
        let supportSource = try readerSupportSources()

        XCTAssertTrue(supportSource.contains("firstDescendant(\n                ofType: ReaderVerticalViewportImageView.self"))
        XCTAssertTrue(supportSource.contains("handleImageTap(imageView, at: imageLocation)"))
        XCTAssertTrue(supportSource.contains("func imageTapPayloadIfHit(at point: CGPoint) -> (url: URL, title: String?)?"))
        XCTAssertTrue(supportSource.contains("if parent.isChromeVisible"))
        XCTAssertTrue(supportSource.contains("onChromeVisibleImageTap()"))
        XCTAssertTrue(supportSource.contains("onImageTap(payload.url, payload.title)"))
        XCTAssertFalse(supportSource.contains("shouldBeRequiredToFailBy otherGestureRecognizer"))
        XCTAssertFalse(supportSource.contains("hitTest(location, with: nil)?.isDescendant(of: ReaderVerticalViewportImageView.self)"))
        XCTAssertFalse(supportSource.contains("private var onTap: ((URL, String?) -> Void)?"))
    }

    func testPagedViewportsInstallAppleBooksStylePageTurnVisuals() throws {
        let supportSource = try readerSupportSources()
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let pagingDriverBody = try XCTUnwrap(typeBody(named: "ReaderPagedViewportPagingDriver", in: supportSource))

        XCTAssertTrue(supportSource.contains("struct ReaderPagedPageTurnVisualMetrics: Equatable"))
        XCTAssertTrue(supportSource.contains("enum ReaderPagedPageTurnPresentation"))
        XCTAssertTrue(supportSource.contains("struct ReaderPagedPageSurfaceContainer<Content: View>: View"))
        XCTAssertTrue(supportSource.contains("final class ReaderPagedPageTurnCell: UICollectionViewCell"))
        XCTAssertTrue(supportSource.contains("final class ReaderPagedViewportPagingDriver"))
        XCTAssertTrue(supportSource.contains("enum ReaderPagedPageTurnBackground"))
        XCTAssertTrue(supportSource.contains("enum ReaderPagedPageTurnCornerRadius"))
        XCTAssertTrue(supportSource.contains("[\"_display\", \"Corner\", \"Radius\"].joined()"))
        XCTAssertTrue(supportSource.contains("screen.value(forKey: displayCornerRadiusSelectorName)"))
        XCTAssertTrue(supportSource.contains("static func dimmedPageColor"))
        XCTAssertTrue(supportSource.contains("static let maxOverlayAlpha: CGFloat = 0.22"))
        XCTAssertTrue(supportSource.contains("static let fallbackPageCornerRadius: CGFloat = 56"))
        XCTAssertTrue(supportSource.contains("layer.cornerCurve = .continuous"))
        XCTAssertTrue(supportSource.contains("addSubview(pageTurnOverlayView)"))
        XCTAssertTrue(supportSource.contains(".background(readerThemeColor(for: settings.backgroundStyle, colorScheme: colorScheme))"))

        XCTAssertTrue(pagingDriverBody.contains("beginPageTurnVisuals(in: collectionView, inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("applyPageTurnVisuals(in: collectionView, inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("endPageTurnVisuals(in: collectionView)"))
        XCTAssertTrue(pagingDriverBody.contains("ReaderPagedPageTurnPresentation.metrics"))
        XCTAssertTrue(pagingDriverBody.contains("cornerRadius: ReaderPagedPageTurnCornerRadius.radius(for: collectionView.window?.screen)"))
        XCTAssertTrue(pagingDriverBody.contains("collectionView.backgroundColor = ReaderPagedPageTurnBackground.dimmedPageColor"))
        XCTAssertTrue(pagingDriverBody.contains("collectionView.backgroundColor = .clear"))

        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("ReaderPagedPageTurnCell.self"))
            XCTAssertTrue(body.contains("as! ReaderPagedPageTurnCell"))
            XCTAssertTrue(body.contains("ReaderPagedPageSurfaceContainer(settings: parent.settings)"))
            XCTAssertTrue(body.contains("scrollViewWillBeginDragging"))
            XCTAssertTrue(body.contains("scrollViewDidScroll"))
            XCTAssertTrue(body.contains("scrollViewDidEndDragging"))
            XCTAssertTrue(body.contains("private let pagingDriver = ReaderPagedViewportPagingDriver()"))
            XCTAssertTrue(body.contains("pagingDriver.scrollViewWillBeginDragging(scrollView, inputs: pagingInputs)"))
            XCTAssertTrue(body.contains("pagingDriver.scrollViewDidScroll(scrollView, inputs: pagingInputs)"))
            XCTAssertTrue(body.contains("pagingDriver.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate, inputs: pagingInputs)"))
            XCTAssertTrue(body.contains("cell.resetPageTurnVisuals()"))
            XCTAssertTrue(body.contains("UIHostingConfiguration"))
        }
    }

    func testImageBrowserSwipeDownDismissRequiresMinimumZoomAndDownwardIntent() {
        XCTAssertTrue(ReaderImageBrowserDismissGesture.canBegin(
            translation: CGPoint(x: 12, y: 80),
            zoomScale: 1,
            minimumZoomScale: 1
        ))
        XCTAssertTrue(ReaderImageBrowserDismissGesture.shouldDismiss(
            translation: CGPoint(x: 12, y: 120),
            velocity: CGPoint(x: 0, y: 700),
            zoomScale: 1,
            minimumZoomScale: 1
        ))
        XCTAssertFalse(ReaderImageBrowserDismissGesture.shouldDismiss(
            translation: CGPoint(x: 12, y: 120),
            velocity: CGPoint(x: 0, y: 900),
            zoomScale: 1.2,
            minimumZoomScale: 1
        ))
        XCTAssertFalse(ReaderImageBrowserDismissGesture.canBegin(
            translation: CGPoint(x: 120, y: 80),
            zoomScale: 1,
            minimumZoomScale: 1
        ))
        XCTAssertFalse(ReaderImageBrowserDismissGesture.shouldDismiss(
            translation: CGPoint(x: 12, y: 70),
            velocity: CGPoint(x: 0, y: 300),
            zoomScale: 1,
            minimumZoomScale: 1
        ))
    }

    func testImageBrowserSwipeDownDismissVisualProgressIsClamped() {
        XCTAssertEqual(ReaderImageBrowserDismissGesture.progress(for: -40), 0)
        XCTAssertEqual(ReaderImageBrowserDismissGesture.progress(for: 75), 0.5)
        XCTAssertEqual(ReaderImageBrowserDismissGesture.progress(for: 300), 1)
        XCTAssertEqual(ReaderImageBrowserDismissGesture.imageScale(for: 1), 0.92, accuracy: 0.001)
        XCTAssertEqual(ReaderImageBrowserDismissGesture.backgroundOpacity(for: 1), 0, accuracy: 0.001)
    }

    func testImageBrowserUsesSwiftUIGestureAPIInsteadOfUIKitZoomView() throws {
        let supportSource = try readerSupportSources()
        let zoomableImageBody = try XCTUnwrap(typeBody(named: "ReaderZoomableImageView", in: supportSource))

        XCTAssertTrue(supportSource.contains("private struct ReaderZoomableImageView: View"))
        XCTAssertTrue(zoomableImageBody.contains("SpatialTapGesture(count: 2"))
        XCTAssertTrue(zoomableImageBody.contains("MagnifyGesture()"))
        XCTAssertTrue(zoomableImageBody.contains("DragGesture()"))
        XCTAssertFalse(supportSource.contains("ReaderZoomableImageView: UIViewRepresentable"))
        XCTAssertFalse(supportSource.contains("ReaderZoomableImageUIView"))
        XCTAssertFalse(zoomableImageBody.contains("UIScrollView"))
        XCTAssertFalse(zoomableImageBody.contains("UITapGestureRecognizer"))
        XCTAssertFalse(zoomableImageBody.contains("UIPanGestureRecognizer"))
    }

    func testMigrationGateRejectsUIOwnedTextKitGraphsAndDisplayValueFallbacks() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/PlatformAdapters/NovelTextDisplayAdapter.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
        let adapterSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/PlatformAdapters/NovelTextDisplayAdapter.swift"),
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
        let supportSource = try readerSupportSources()
        let viewportContentBody = try XCTUnwrap(typeBody(named: "ReaderViewportSurfaceContent", in: supportSource))

        XCTAssertFalse(viewportContentBody.contains("NovelTextLayout.displayValue("))
        XCTAssertFalse(viewportContentBody.contains("NovelTextDisplayValue"))
    }

    func testSettingsPreviewUsesAttributedPreviewSurfaceWithoutUILayoutMeasurement() throws {
        let settingsSource = try readerSettingsSources()
        let adapterSource = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/PlatformAdapters/NovelTextDisplayAdapter.swift"),
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/PlatformAdapters/NovelTextDisplayAdapter.swift"),
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/PlatformAdapters/NovelTextDisplayAdapter.swift"),
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
        let readerSupportSource = try readerSupportSources()
        let spreadContentBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadContent", in: readerSupportSource))

        XCTAssertTrue(spreadContentBody.contains("ReaderViewportSurfaceContent("))
        XCTAssertTrue(spreadContentBody.contains("displayReference: surface.flatMap"))
        XCTAssertFalse(spreadContentBody.contains("Text(displayValue.text"))
        XCTAssertFalse(spreadContentBody.contains("NovelTextDisplayValue"))
    }

    func testTwoPageSpreadInstallsOpaqueReferencesForLeftAndRightPages() throws {
        let supportSource = try readerSupportSources()
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
        let containerSource = try [
            "Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift",
            "Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerPresentationModifiers.swift",
        ]
        .map { path in
            try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
        }
        .joined(separator: "\n")
        let modelSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerModel.swift"),
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()

        XCTAssertTrue(containerSource.contains("let resumeContext = await model.saveProgress()"))
        XCTAssertTrue(containerSource.contains("appModel.dismissReader(openThreadInForum: url, suspendedContext: resumeContext)"))
        XCTAssertTrue(supportSource.contains("let onOpenOriginalPost: (URL) -> Void"))
        XCTAssertTrue(supportSource.contains("onOpenOriginalPost(url)"))
        XCTAssertFalse(supportSource.contains("appModel.dismissReader(openThreadInForum: url)"))
    }

    func testPagedCellsResolveViewportSurfaceIdentityBeforeRenderingNormalText() throws {
        let supportSource = try readerSupportSources()
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()
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
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let pagingDriverBody = try XCTUnwrap(typeBody(named: "ReaderPagedViewportPagingDriver", in: supportSource))

        XCTAssertTrue(supportSource.contains("final class ReaderPagedViewportCollectionView: UICollectionView"))
        XCTAssertTrue(supportSource.contains("override func layoutSubviews()"))
        XCTAssertTrue(pagingDriverBody.contains("func scrollToPendingSelectionIfPossible("))
        XCTAssertTrue(pagingDriverBody.contains("scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: inputs)"))
        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("onLayoutSubviews"))
            XCTAssertTrue(body.contains("updateContentAndRequestSelectionScroll("))
            XCTAssertTrue(body.contains("pagingDriver.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: pagingInputs)"))
        }
    }

    func testPagedViewportsReloadOnlyWhenContentIdentityChanges() throws {
        let supportSource = try readerSupportSources()
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let pagingDriverBody = try XCTUnwrap(typeBody(named: "ReaderPagedViewportPagingDriver", in: supportSource))

        XCTAssertTrue(supportSource.contains("struct ReaderPagedViewportContentIdentity: Equatable"))
        XCTAssertTrue(supportSource.contains("struct ReaderPagedSpreadViewportContentIdentity: Equatable"))
        XCTAssertTrue(supportSource.contains("struct ReaderPagedScrollAnimationRequest: Equatable"))
        XCTAssertTrue(supportSource.contains("struct ReaderPagedViewportPagingInputs"))
        XCTAssertTrue(supportSource.contains("var surfaces: [NovelReaderSurface]"))
        XCTAssertTrue(supportSource.contains("var spreads: [NovelReaderPresentationSpread]"))
        XCTAssertTrue(supportSource.contains("var settings: ReaderAppearanceSettings"))
        XCTAssertTrue(supportSource.contains("var refererURL: URL"))
        XCTAssertTrue(supportSource.contains("var sessionState: ReaderPagedViewportSessionIdentity"))
        XCTAssertTrue(supportSource.contains("var topInset: CGFloat"))
        XCTAssertTrue(supportSource.contains("var bottomInset: CGFloat"))
        XCTAssertTrue(supportSource.contains("var userAgent: String"))
        XCTAssertTrue(supportSource.contains("var cookie: String"))

        XCTAssertTrue(pagingDriverBody.contains("let animationRequest = matchingScrollAnimationRequest(inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("guard didChangeContentIdentity else"))
        XCTAssertTrue(pagingDriverBody.contains("requestSelectionScroll(in: collectionView, animated: animationRequest != nil, inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("consumeScrollAnimationRequest(animationRequest, inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("collectionView.collectionViewLayout.invalidateLayout()"))
        XCTAssertTrue(pagingDriverBody.contains("reloadDataAndRequestSelectionScroll(in: collectionView, animated: false, inputs: inputs)"))

        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("private var contentIdentity:"))
            XCTAssertTrue(body.contains("func updateContentAndRequestSelectionScroll("))
            XCTAssertTrue(body.contains("let didChangeContentIdentity = contentIdentity != nextContentIdentity"))
            XCTAssertTrue(body.contains("pagingDriver.updateContentAndRequestSelectionScroll("))
        }
    }

    func testPagedViewportsConsumeMatchingRelativePageAnimationRequests() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let containerSource = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderContainerView.swift"),
            encoding: .utf8
        )
        let supportSource = try readerSupportSources()
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let pagingDriverBody = try XCTUnwrap(typeBody(named: "ReaderPagedViewportPagingDriver", in: supportSource))
        let makeRequestBody = try XCTUnwrap(functionBody(named: "makePagedScrollAnimationRequest", in: containerSource))

        XCTAssertTrue(containerSource.contains("@State private var pagedScrollAnimationRequest: ReaderPagedScrollAnimationRequest?"))
        XCTAssertTrue(containerSource.contains("private func goRelativePage(_ delta: Int, pagerIdentity: ReaderPagedPagerIdentity?) async"))
        XCTAssertTrue(containerSource.contains("makePagedScrollAnimationRequest(delta: delta, pagerIdentity: $0)"))
        XCTAssertTrue(containerSource.contains("await model.jumpRelativeSurface(delta)"))
        XCTAssertTrue(makeRequestBody.contains("model.pagedViewportSelectionIndex + delta"))
        XCTAssertTrue(makeRequestBody.contains("model.presentationSpreads.count"))
        XCTAssertTrue(makeRequestBody.contains("model.readerSurfaces.count"))
        XCTAssertTrue(containerSource.contains("clearPagedScrollAnimationRequest"))

        XCTAssertTrue(pagingDriverBody.contains("let targetItem = inputs.selectionIndex + delta"))
        XCTAssertTrue(pagingDriverBody.contains("private var consumedScrollAnimationRequestID: UUID?"))
        XCTAssertTrue(pagingDriverBody.contains("private func matchingScrollAnimationRequest("))
        XCTAssertTrue(pagingDriverBody.contains("request.pagerIdentity == inputs.pagerIdentity"))
        XCTAssertTrue(pagingDriverBody.contains("request.selectionIndex == inputs.selectionIndex"))
        XCTAssertTrue(pagingDriverBody.contains("request.id != consumedScrollAnimationRequestID"))
        XCTAssertTrue(pagingDriverBody.contains("setContentOffset"))
        XCTAssertTrue(pagingDriverBody.contains("animated: animated"))

        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("let pagerIdentity: ReaderPagedPagerIdentity"))
            XCTAssertTrue(body.contains("let scrollAnimationRequest: ReaderPagedScrollAnimationRequest?"))
            XCTAssertTrue(body.contains("let onScrollAnimationRequestConsumed: (ReaderPagedScrollAnimationRequest) -> Void"))
            XCTAssertTrue(body.contains("pagingDriver.animateAdjacentSelection(for: zone, in: collectionView, inputs: pagingInputs)"))
            XCTAssertTrue(body.contains("scrollAnimationRequest: parent.scrollAnimationRequest"))
            XCTAssertTrue(body.contains("onScrollAnimationRequestConsumed: parent.onScrollAnimationRequestConsumed"))
        }
    }

    func testVerticalViewportPublishesVisibleSurfacesAfterLayoutSubviews() throws {
        let supportSource = try readerSupportSources()
        let verticalBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportScrollView", in: supportSource))

        XCTAssertTrue(supportSource.contains("private final class ReaderVerticalViewportCollectionView: UICollectionView"))
        XCTAssertTrue(verticalBody.contains("ReaderVerticalViewportCollectionView(frame: .zero, collectionViewLayout: layout)"))
        XCTAssertTrue(verticalBody.contains("collectionView.onLayoutSubviews"))
        XCTAssertTrue(verticalBody.contains("coordinator?.publishLayout(from: collectionView)"))
        XCTAssertTrue(verticalBody.contains("func publishLayout(from collectionView: UICollectionView)"))
        XCTAssertFalse(verticalBody.contains("scrollViewDidLayoutSubviews"))
    }

    func testVerticalViewportRefreshesCellsAfterFinalFlowLayoutSizing() throws {
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let pagingDriverBody = try XCTUnwrap(typeBody(named: "ReaderPagedViewportPagingDriver", in: supportSource))

        XCTAssertTrue(pagingDriverBody.contains("reloadDataAndRequestSelectionScroll(in: collectionView, animated: false, inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("collectionView.performBatchUpdates(nil)"))
        XCTAssertTrue(pagingDriverBody.contains("self?.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: inputs)"))
        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("pagingDriver.reloadDataAndRequestSelectionScroll(in: collectionView, animated: animated, inputs: pagingInputs)"))
        }
    }

    func testReaderInlineImagesUseSharedMemoryCache() throws {
        let supportSource = try readerSupportSources()
        let loaderBody = try XCTUnwrap(typeBody(named: "ReaderImageLoader", in: supportSource))
        let imageViewBody = try XCTUnwrap(typeBody(named: "ReaderVerticalViewportImageView", in: supportSource))
        let cacheBody = try XCTUnwrap(typeBody(named: "ReaderInlineImageMemoryCache", in: supportSource))
        let storageBody = try XCTUnwrap(typeBody(named: "ReaderInlineImageMemoryCacheStorage", in: supportSource))
        let requestIdentityBody = try XCTUnwrap(typeBody(named: "ReaderInlineImageRequestIdentity", in: supportSource))

        XCTAssertTrue(supportSource.contains("private final class ReaderInlineImageMemoryCacheStorage: @unchecked Sendable"))
        XCTAssertTrue(storageBody.contains("NSCache<NSString, UIImage>"))
        XCTAssertTrue(cacheBody.contains("defaultMemoryLimitBytes = 80 * 1024 * 1024"))
        XCTAssertTrue(storageBody.contains("cache.totalCostLimit = memoryLimitBytes"))
        XCTAssertTrue(cacheBody.contains("static func image(for requestIdentity: ReaderInlineImageRequestIdentity) -> UIImage?"))
        XCTAssertTrue(cacheBody.contains("static func store(_ image: UIImage, for requestIdentity: ReaderInlineImageRequestIdentity)"))

        XCTAssertTrue(requestIdentityBody.contains("let url: URL"))
        XCTAssertTrue(requestIdentityBody.contains("let refererURL: URL"))
        XCTAssertTrue(requestIdentityBody.contains("let userAgent: String"))
        XCTAssertTrue(requestIdentityBody.contains("let cookie: String"))
        XCTAssertTrue(requestIdentityBody.contains("url.absoluteString"))
        XCTAssertTrue(requestIdentityBody.contains("refererURL.absoluteString"))
        XCTAssertTrue(requestIdentityBody.contains("request.setValue(userAgent, forHTTPHeaderField: \"User-Agent\")"))
        XCTAssertTrue(requestIdentityBody.contains("request.setValue(cookie, forHTTPHeaderField: \"Cookie\")"))
        XCTAssertTrue(requestIdentityBody.contains("request.setValue(refererURL.absoluteString, forHTTPHeaderField: \"Referer\")"))

        XCTAssertTrue(loaderBody.contains("ReaderInlineImageMemoryCache.image(for: requestIdentity)"))
        XCTAssertTrue(loaderBody.contains("ReaderInlineImageMemoryCache.store(image, for: requestIdentity)"))
        XCTAssertTrue(imageViewBody.contains("ReaderInlineImageMemoryCache.image(for: nextRequestIdentity)"))
        XCTAssertTrue(imageViewBody.contains("ReaderInlineImageMemoryCache.store(image, for: nextRequestIdentity)"))
    }

    func testPagedViewportsKeepPendingSelectionUntilCollectionViewCanRepresentTargetOffset() throws {
        let supportSource = try readerSupportSources()
        let singlePageBody = try XCTUnwrap(typeBody(named: "ReaderPagedCollectionViewport", in: supportSource))
        let spreadBody = try XCTUnwrap(typeBody(named: "ReaderPresentationSpreadCollectionViewport", in: supportSource))
        let pagingDriverBody = try XCTUnwrap(typeBody(named: "ReaderPagedViewportPagingDriver", in: supportSource))

        XCTAssertTrue(pagingDriverBody.contains("collectionView.window != nil"))
        XCTAssertTrue(pagingDriverBody.contains("collectionView.contentSize.width >= targetContentOffsetX + collectionView.bounds.width"))
        XCTAssertTrue(pagingDriverBody.contains("schedulePendingSelectionScrollRetry(in: collectionView, animated: animated, inputs: inputs)"))
        XCTAssertTrue(pagingDriverBody.contains("collectionView.setContentOffset"))
        XCTAssertFalse(pagingDriverBody.contains("collectionView.scrollToItem"))
        for body in [singlePageBody, spreadBody] {
            XCTAssertTrue(body.contains("pagingDriver.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: pagingInputs)"))
        }
    }

    func testVerticalViewportUsesExplicitFlowLayoutSizingForScrollableFullWidthCells() throws {
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let supportSource = try readerSupportSources()
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
        let readerSupportSource = try readerSupportSources()
        let settingsSource = try readerSettingsSources()
        let productionDisplaySources = readerSupportSource + "\n" + settingsSource

        XCTAssertFalse(productionDisplaySources.contains("ReaderRichTextView"))
        XCTAssertFalse(productionDisplaySources.contains("UITextView"))
    }

    func testNovelReadingSessionBlockPassesOpaqueDisplayReference() throws {
        let readerSupportSource = try readerSupportSources()

        XCTAssertTrue(readerSupportSource.contains("displayReference: displayReference"))
        XCTAssertTrue(readerSupportSource.contains("NativeNovelTextViewportReferenceView("))
        XCTAssertFalse(readerSupportSource.contains("NativeNovelTextDisplayView("))
        XCTAssertFalse(readerSupportSource.contains("NovelTextLayout.displayValue("))
    }

    func testSettingsPreviewUsesLightweightSurfaceInsteadOfReaderRuntimeAdapter() throws {
        let settingsSource = try readerSettingsSources()

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

private func readerSupportSources() throws -> String {
    try joinedSourceFiles([
        "Sources/YamiboReaderUI/Features/NovelReader/Container/ReaderSupportViews.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Chrome/ReaderProgressPresentation.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Chrome/ReaderChromeProgressSnapshot.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Chrome/ReaderTopChrome.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Chrome/ReaderBottomChrome.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Chrome/ReaderChromeControls.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Viewports/ReaderViewportContentViews.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Viewports/ReaderPagedViewport.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Viewports/ReaderPagedCollectionViewport.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Viewports/ReaderPresentationSpreadCollectionViewport.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Viewports/ReaderPagedTapZones.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Viewports/ReaderVerticalViewport.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Sheets/ReaderImageBrowserView.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Chrome/ReaderProgressCapsules.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Sheets/ReaderChapterCatalogSheets.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Sheets/ReaderChapterCommentsSheets.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Sheets/ReaderWebJumpSheet.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Cache/ReaderCacheViews.swift",
    ])
}

private func readerSettingsSources() throws -> String {
    try joinedSourceFiles([
        "Sources/YamiboReaderUI/Features/NovelReader/Settings/ReaderSettingsViews.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Settings/ReaderSettingsHeroViews.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Settings/ReaderSettingsPalette.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Settings/ReaderSettingsSections.swift",
        "Sources/YamiboReaderUI/Features/NovelReader/Settings/ReaderSettingsControls.swift",
    ])
}

private func joinedSourceFiles(_ relativePaths: [String]) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return try relativePaths
        .map { path in
            try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
        }
        .joined(separator: "\n")
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
