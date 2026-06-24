import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

#if os(iOS)
import UIKit
#endif

@Suite("MangaReaderTests: Presentation Infrastructure")
struct MangaReaderPresentationInfrastructureTests {
    @Test func verticalViewportUsesUIKitCompositionalLayout() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")

        #expect(source.contains("struct MangaVerticalCollectionViewport: UIViewRepresentable"))
        #expect(source.contains("UICollectionView"))
        #expect(source.contains("UICollectionViewCompositionalLayout"))
        #expect(!source.contains("LazyVStack"))
    }

    @Test func verticalViewportIgnoresScrollViewSafeAreaInsets() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")

        #expect(source.contains("collectionView.contentInsetAdjustmentBehavior = .never"))
    }

    @Test func verticalViewportSupportsFullStreamDoubleTapAndPinchZoom() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")
        let viewSource = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        #expect(viewSource.contains("MangaVerticalCollectionViewport("))
        #expect(viewSource.contains("isChromeVisible: isChromeVisible"))
        #expect(viewSource.contains("zoomEnabled: settings.zoomEnabled"))
        #expect(source.contains("let isChromeVisible: Bool"))
        #expect(source.contains("let zoomEnabled: Bool"))
        #expect(source.contains("lazy var doubleTapGesture: UITapGestureRecognizer"))
        #expect(source.contains("recognizer.numberOfTapsRequired = 2"))
        #expect(source.contains("tapGesture.require(toFail: context.coordinator.doubleTapGesture)"))
        #expect(source.contains("@objc private func handleDoubleTap"))
        #expect(source.contains("lazy var pinchGesture = UIPinchGestureRecognizer"))
        #expect(source.contains("@objc private func handlePinch"))
        #expect(source.contains("if parent.isChromeVisible"))
        #expect(source.contains("guard parent.zoomEnabled"))
        #expect(source.contains("private(set) var verticalZoomScale = MangaPageZoomPolicy.minimumScale"))
        #expect(source.contains("MangaVerticalCollectionZoomLayout.itemWidth"))
        #expect(source.contains("MangaVerticalCollectionZoomLayout.estimatedItemHeight"))
        #expect(source.contains("MangaVerticalCollectionZoomLayout.doubleTapTargetScale"))
        #expect(source.contains("MangaVerticalCollectionZoomLayout.anchoredContentOffset"))
        #expect(source.contains("setVerticalZoomScale("))
        #expect(!source.contains("private static let doubleTapZoomScale"))
        #expect(!source.contains("private static let maximumZoomScale"))
        #expect(!source.contains("cell.toggleZoom(at: location)"))
        #expect(!source.contains("private let zoomScrollView = UIScrollView()"))
        #expect(!source.contains("zoomScrollView.maximumZoomScale"))
        #expect(!source.contains("activeZoomCell"))
        #expect(!source.contains("collectionView.isScrollEnabled = false"))
        #expect(!source.contains("MangaPagedCenterTapHitTesting.acceptsCenterTap"))
    }

    @Test func readerLoadedStateDoesNotUseDiagnosticScrollList() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        #expect(source.contains("MangaVerticalCollectionViewport("))
        #expect(source.contains("MangaPagedReaderViewport("))
        #expect(source.contains("switch settings.readingMode"))
        #expect(source.contains("case .vertical:"))
        #expect(source.contains("case .paged:"))
        #expect(!source.contains("ScrollView"))
        #expect(!source.contains("LazyVStack"))
        #expect(!source.contains("MangaReaderRouteDetails"))
        #expect(!source.contains("chapterURL:"))
        #expect(!source.contains("originalThreadURL:"))
    }

    @Test func nonIOSRootTabViewDoesNotPresentMangaHost() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/AppEntry/RootTabView.swift")
        let nonIOSBranch = try #require(source.range(of: "#else\n        content"))
        let branchTail = String(source[nonIOSBranch.lowerBound...])
        let branchEnd = try #require(branchTail.range(of: "#endif"))
        let branch = String(branchTail[..<branchEnd.lowerBound])

        #expect(!branch.contains("MangaPresentationHostView"))
        #expect(!branch.contains("activeMangaRoute != nil"))
    }

    @Test func webFallbackViewIsIOSOnly() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/WebFallback/MangaWebFallbackView.swift")

        #expect(source.contains("#if os(iOS)\npublic struct MangaWebFallbackView"))
    }

    @Test func imagePipelineSourceCachesSuccessesAndDeduplicatesInFlightLoads() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaImagePipeline.swift")

        #expect(source.contains("NSCache<NSString, UIImage>"))
        #expect(source.contains("inFlightContinuations"))
        #expect(source.contains("UIImage(data: data)"))
        #expect(source.contains("MangaImagePipelineError.invalidImageData"))
    }

    @Test func progressImagePreviewUsesPipelineCacheAndLocalizedPageFallback() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")

        #expect(source.contains("struct MangaReaderProgressImagePreview"))
        #expect(source.contains("MangaReaderProgressPreviewImageArea("))
        #expect(source.contains("MangaReaderProgressPreviewPageLabel("))
        #expect(source.contains("imagePipeline?.cachedImage(for: page)"))
        #expect(source.contains("try await imagePipeline.image(for: page)"))
        #expect(source.contains("catch {"))
        #expect(source.contains("failedPageID = page.id"))
        #expect(source.contains("L10n.string(\"reader.page_number_spaced\", preview.pageNumber)"))
        #expect(source.contains("static let previewSize = CGSize(width: 184, height: 228)"))
        #expect(source.contains("showsPreview: false"))
        #expect(source.contains(".overlay {"))
        #expect(source.contains("let centerProgressPreview = progressChromePresentation.showsVerticalScrubber"))
        #expect(source.contains(": horizontalScrubState.preview"))
        #expect(source.contains("if let preview = centerProgressPreview"))
    }

    @Test func hiddenFailureStackIsNotMeasuredDuringLayout() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaVerticalCollectionViewport.swift")
        let guardRange = try #require(source.range(of: "guard !failureStack.isHidden else"))
        let fittingRange = try #require(source.range(of: "failureStack.systemLayoutSizeFitting(fittingSize)"))
        let hiddenGuardBody = String(source[guardRange.lowerBound..<fittingRange.lowerBound])

        #expect(hiddenGuardBody.contains("failureStack.frame = .zero"))
        #expect(hiddenGuardBody.contains("return"))
        #expect(guardRange.lowerBound < fittingRange.lowerBound)
    }

    @Test func pagedViewportPublishesPageLevelGlobalIndexFromPlan() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("struct MangaPagedReaderViewport: UIViewRepresentable"))
        #expect(source.contains("let plan: MangaPagedReadingPlan"))
        #expect(source.contains("let isChromeVisible: Bool"))
        #expect(source.contains("parent.plan.globalIndex(forSpreadAt: spreadIndex)"))
        #expect(source.contains("parent.plan.spreads.count"))
        #expect(source.contains("MangaPagedReaderSpreadSurface("))
        #expect(source.contains("onCurrentPageChange(globalIndex)"))
        #expect(source.contains("func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)"))
        #expect(!source.contains("NovelReaderSurface"))
    }

    @Test func pageCurlPagedViewportUsesUIPageViewControllerBookSpine() throws {
        let viewSource = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(viewSource.contains("if settings.pagedTurnStyle == .pageCurl"))
        #expect(viewSource.contains("MangaPagedPageCurlReaderViewport("))
        #expect(source.contains("struct MangaPagedPageCurlReaderViewport: UIViewControllerRepresentable"))
        #expect(source.contains("UIPageViewController(\n            transitionStyle: .pageCurl"))
        #expect(source.contains("options: [.spineLocation: spineLocation.rawValue]"))
        #expect(viewSource.contains(".id(plan.usesTwoPageSpread)"))
        #expect(source.contains("MangaPagedPageCurlSpineConfiguration.configuration("))
        #expect(source.contains("currentSpineLocation: pageViewController.mangaPageCurlSpineLocation"))
        #expect(source.contains("if let doubleSided = configuration.doubleSidedUpdate"))
        #expect(source.contains("pageViewController.isDoubleSided = doubleSided"))
        #expect(source.contains("let isAwaitingSinglePageSpine = !parent.sequence.usesTwoPageSpread"))
        #expect(source.contains("guard !isAwaitingSinglePageSpine else { return }"))
        #expect(source.contains("return spineLocation"))
        #expect(source.contains("MangaPagedPageCurlSequence(plan: plan)"))
        #expect(source.contains("publishCurrentPageIfNeeded(selectionIndex: selectionIndex)"))
        #expect(source.contains("parent.sequence.globalIndex(forSelectionIndex: selectionIndex)"))
        #expect(source.contains("private enum MangaPageCurlPrivateBackColor"))
    }

    @Test func pageCurlViewportConsumesHiddenPhysicalSurfaceEdgesBeforePageTurn() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let pageCurlRange = try #require(source.range(of: "struct MangaPagedPageCurlReaderViewport"))
        let pageCurlSource = String(source[pageCurlRange.lowerBound..<source.endIndex])
        let tapRange = try #require(pageCurlSource.range(of: "func handleTap(_ recognizer: UITapGestureRecognizer)"))
        let gestureRange = try #require(pageCurlSource.range(of: "func gestureRecognizer("))
        let tapSource = String(pageCurlSource[tapRange.lowerBound..<gestureRange.lowerBound])
        let consumeRange = try #require(tapSource.range(of: "if consumePageCurlSpreadEdgeTap(for: zone, in: containerViewController)"))
        let directionalRange = try #require(tapSource.range(of: "switch directionalTapZone(for: zone)"))

        #expect(consumeRange.lowerBound < directionalRange.lowerBound)
        #expect(tapSource.contains("consumeSurfaceEdgeTap(for: zone, in: pageViewController)"))
        #expect(pageCurlSource.contains("func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool"))
        #expect(pageCurlSource.contains("func gestureRecognizer(\n            _ gestureRecognizer: UIGestureRecognizer,\n            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer\n        ) -> Bool"))
        #expect(pageCurlSource.contains("shouldDeferPageCurlPanToSurfaceContent(panRecognizer, in: pageViewController)"))
        #expect(pageCurlSource.contains("shouldDeferPageCurlPanToSpreadContent(panRecognizer, in: containerViewController)"))
        #expect(pageCurlSource.contains("private func shouldDeferPageCurlPanToSurfaceContent"))
        #expect(pageCurlSource.contains("private func shouldDeferPageCurlPanToSpreadContent"))
        #expect(pageCurlSource.contains("consumePageCurlSpreadEdgeTap(for: zone, in: containerViewController)"))
        #expect(pageCurlSource.contains("private func consumePageCurlSpreadEdgeTap"))
        #expect(pageCurlSource.contains("revealPageCurlSpreadHiddenContent"))
        #expect(pageCurlSource.contains("guard !parent.sequence.usesTwoPageSpread,\n                  let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(forTapZone: zone)"))
        #expect(pageCurlSource.contains("guard !parent.sequence.usesTwoPageSpread else { return false }"))
        #expect(pageCurlSource.contains("pageCurlSurfaceInteraction("))
        #expect(pageCurlSource.contains("onPhysicalEdge: physicalEdge"))
        #expect(pageCurlSource.contains("surfaceInteraction.consumeTap(onPhysicalEdge: physicalEdge)"))
        #expect(pageCurlSource.contains("allowsUnzoomedSurfacePan: true"))
        #expect(!pageCurlSource.contains("pageSurfaceInitialHorizontalAlignments"))
    }

    @Test func pageCurlViewportSupportsDoubleTapSpreadZoomInTwoPageMode() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let pageCurlRange = try #require(source.range(of: "struct MangaPagedPageCurlReaderViewport"))
        let pageCurlSource = String(source[pageCurlRange.lowerBound..<source.endIndex])

        #expect(source.contains("func makeUIViewController(context: Context) -> MangaPagedPageCurlContainerViewController"))
        #expect(source.contains("private final class MangaPagedPageCurlContainerViewController: UIViewController"))
        #expect(source.contains("let pageViewController: UIPageViewController"))
        #expect(pageCurlSource.contains("lazy var doubleTapGesture: UITapGestureRecognizer"))
        #expect(pageCurlSource.contains("recognizer.numberOfTapsRequired = 2"))
        #expect(pageCurlSource.contains("tapGesture.require(toFail: doubleTapGesture)"))
        #expect(pageCurlSource.contains("lazy var spreadPinchGesture = UIPinchGestureRecognizer"))
        #expect(pageCurlSource.contains("lazy var spreadPanGesture = UIPanGestureRecognizer"))
        #expect(pageCurlSource.contains("@objc\n        func handleDoubleTap"))
        #expect(pageCurlSource.contains("MangaPagedCenterTapHitTesting.acceptsCenterTap"))
        #expect(pageCurlSource.contains("togglePageCurlSpreadZoom(at: location, in: containerViewController)"))
        #expect(pageCurlSource.contains("requestPageCurlPageZoomToggle(at: location, in: containerViewController)"))
        #expect(pageCurlSource.contains("MangaPagedSpreadSurfaceZoomLayout("))
        #expect(pageCurlSource.contains("MangaPageZoomPolicy.doubleTapTargetScale"))
        #expect(pageCurlSource.contains("pageViewController.view.transform = CGAffineTransform(translationX: displayOffset.width, y: displayOffset.height).scaledBy("))
        #expect(pageCurlSource.contains("isPageZoomEnabled: !parent.sequence.usesTwoPageSpread"))
        #expect(pageCurlSource.contains("surfaceInteraction.requestZoomToggle"))
        #expect(!pageCurlSource.contains("SpatialTapGesture(count: 2"))
        #expect(!pageCurlSource.contains("private static let doubleTapZoomScale"))
        #expect(!pageCurlSource.contains("private static let maximumZoomScale"))
    }

    @Test func readerLoadedContentGatesTwoPageSpreadsToIPadLandscapeSetting() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaReaderView.swift")
        let policySource = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedLayoutPolicy.swift")

        #expect(source.contains("GeometryReader { proxy in"))
        #expect(source.contains("pageTurnDirection: settings.pageTurnDirection"))
        #expect(source.contains("let usesTwoPageSpread = MangaPagedLayoutPolicy.usesTwoPageSpread("))
        #expect(source.contains("isPadDevice: UIDevice.current.userInterfaceIdiom == .pad"))
        #expect(source.contains("availableSize: proxy.size"))
        #expect(source.contains("usesTwoPageSpread: usesTwoPageSpread"))
        #expect(policySource.contains("settings.readingMode == .paged"))
        #expect(policySource.contains("settings.showsTwoPagesInLandscapeOnPad"))
        #expect(policySource.contains("isPadDevice"))
        #expect(policySource.contains("availableSize.width > availableSize.height"))
    }

    @Test func pagedViewportAppliesConfiguredPageEdgeFillStyle() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("pageEdgeFillStyle: parent.settings.pageEdgeFillStyle"))
        #expect(source.contains("pageEdgeFillStyle: MangaPageEdgeFillStyle"))
        #expect(source.contains("var pageEdgeFillStyle: MangaPageEdgeFillStyle"))
        #expect(source.contains("collectionView.backgroundColor = pageEdgeFillColor"))
        #expect(source.contains("backgroundColor = pageEdgeFillColor"))
        #expect(source.contains("contentView.backgroundColor = pageEdgeFillColor"))
        #expect(source.contains("pageEdgeFillStyle.color(for: colorScheme)"))
        #expect(source.contains("pageEdgeFillStyle.progressTint(for: colorScheme)"))
        #expect(source.contains("pageEdgeFillStyle.placeholderForeground(for: colorScheme)"))
    }

    @Test func pagedViewportLetsIPadFitHeightPagesIgnoreVerticalSafeArea() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let layoutSource = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedImageSurfaceLayout.swift")

        #expect(source.contains("collectionView.contentInsetAdjustmentBehavior = .never"))
        #expect(source.contains("edges: UIDevice.current.userInterfaceIdiom == .pad ? .vertical : .bottom"))
        #expect(layoutSource.contains("case .fitHeight:\n            containerSize.height / imageSize.height"))
    }

    @Test func pagedViewportUsesEffectivePageScaleModeForRenderedSurfaces() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("private var effectivePageScaleMode: MangaPageScaleMode"))
        #expect(source.contains("MangaPagedLayoutPolicy.effectivePageScaleMode("))
        #expect(source.contains("usesTwoPageSpread: plan.usesTwoPageSpread"))
        #expect(source.contains("pageScaleMode: parent.effectivePageScaleMode"))
        #expect(!source.contains("pageScaleMode: parent.settings.pageScaleMode"))
    }

    @Test func pagedViewportRealignsVisibleSpreadWhenCollectionBoundsChange() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let layoutCallbackRange = try #require(source.range(of: "collectionView.onLayoutSubviews ="))
        let contentUpdateRange = try #require(source.range(of: "func updateContentIfNeeded"))
        let layoutCallbackSource = String(source[layoutCallbackRange.lowerBound..<contentUpdateRange.lowerBound])

        #expect(source.contains("private var lastLaidOutViewportSize: CGSize?"))
        #expect(source.contains("func realignViewportAfterBoundsChangeIfNeeded(in collectionView: UICollectionView)"))
        #expect(layoutCallbackSource.contains("realignViewportAfterBoundsChangeIfNeeded(in: collectionView)"))
        #expect(source.contains("MangaPagedViewportResizePolicy.alignedContentOffsetX("))
        #expect(source.contains("collectionView.collectionViewLayout.invalidateLayout()"))
    }

    @Test func settingsSheetShowsPageEdgeFillAfterPageScaleMode() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Settings/MangaReaderSettingsSheet.swift")
        let scaleRange = try #require(source.range(of: "MangaReaderPageScaleModeMenuRow("))
        let edgeFillRange = try #require(source.range(of: "MangaReaderPageEdgeFillMenuRow("))

        #expect(scaleRange.lowerBound < edgeFillRange.lowerBound)
        #expect(source.contains("let usesTwoPageSpread = MangaPagedLayoutPolicy.usesTwoPageSpread("))
        #expect(source.contains("availableSize: proxy.size"))
        #expect(source.contains("if !usesTwoPageSpread"))
        #expect(source.contains("scaleMode: effectivePageScaleMode"))
        #expect(source.contains("L10n.string(\"manga.page_edge_fill\")"))
        #expect(source.contains("ForEach(MangaPageEdgeFillStyle.allCases, id: \\.self)"))
        #expect(source.contains("edgeFillStyle: settings.pageEdgeFillStyle"))
        #expect(source.contains("edgeFillBackground"))
        #expect(source.contains("scaleMode == .fitWidth ? edgeFillBackground : palette.previewPageBackground"))
        #expect(source.contains("verticalArtworkInset"))
        #expect(source.contains("artworkHeight + verticalArtworkInset * 2"))
        #expect(source.contains("pageBackground: palette.previewPageBackground"))
        #expect(source.contains(".background(pageBackground)"))
    }

    @Test func pagedViewportHidesVisibleChromeBeforeTapZonePageTurn() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let chromeGateRange = try #require(source.range(of: "if parent.isChromeVisible {"))
        let pageTurnRange = try #require(source.range(of: "pagingDriver.animateAdjacentSelection"))
        let chromeGateBody = String(source[chromeGateRange.lowerBound..<pageTurnRange.lowerBound])

        #expect(chromeGateRange.lowerBound < pageTurnRange.lowerBound)
        #expect(chromeGateBody.contains("let onTap = parent.onTap"))
        #expect(chromeGateBody.contains("onTap()"))
        #expect(chromeGateBody.contains("return"))
    }

    @Test func pagedViewportConsumesPhysicalSurfaceEdgeTapBeforeDirectionalPageTurn() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let chromeGateRange = try #require(source.range(of: "if parent.isChromeVisible {"))
        let edgeTapRange = try #require(source.range(of: "if consumeSurfaceEdgeTap(for: zone, in: collectionView)"))
        let directionalZoneRange = try #require(source.range(of: "let directionalZone = directionalTapZone(for: zone)"))
        let pageTurnRange = try #require(source.range(of: "pagingDriver.animateAdjacentSelection"))

        #expect(chromeGateRange.lowerBound < edgeTapRange.lowerBound)
        #expect(edgeTapRange.lowerBound < directionalZoneRange.lowerBound)
        #expect(directionalZoneRange.lowerBound < pageTurnRange.lowerBound)

        let consumeRange = try #require(source.range(of: "private func consumeSurfaceEdgeTap"))
        let requestZoomRange = try #require(source.range(of: "private func requestSpreadZoomToggle"))
        let consumeSource = String(source[consumeRange.lowerBound..<requestZoomRange.lowerBound])

        #expect(consumeSource.contains("MangaPagedSurfaceEdgeInteraction.physicalEdge(forTapZone: zone)"))
        #expect(consumeSource.contains("MangaPagedSurfaceEdgeInteraction.shouldRevealHiddenContent("))
        #expect(consumeSource.contains("surfaceInteraction.consumeTap(onPhysicalEdge: physicalEdge)"))
        #expect(!consumeSource.contains("directionalTapZone"))
        #expect(!source.contains("private func physicalHorizontalEdge"))
    }

    @Test func pagedViewportConfiguresInitialHorizontalAlignmentWhenCellsBecomeVisible() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("func collectionView(\n            _ collectionView: UICollectionView,\n            willDisplay cell: UICollectionViewCell,"))
        #expect(source.contains("private var pageSurfaceInitialHorizontalAlignments: [String: MangaPagedImageSurfaceInitialHorizontalAlignment] = [:]"))
        #expect(source.contains("pageSurfaceInitialHorizontalAlignments = [:]"))
        #expect(source.contains("refreshInitialHorizontalAlignment: true"))
        #expect(source.contains("refreshInitialHorizontalAlignment: false"))
        #expect(source.contains("initialHorizontalAlignment(\n                    for: page,\n                    pageIndex: pageIndex,\n                    refresh: refreshInitialHorizontalAlignment\n                )"))
        #expect(source.contains("private func initialHorizontalAlignment("))
        #expect(source.contains("MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage("))
        #expect(source.contains("currentPageIndex: parent.plan.currentPageIndex"))
        #expect(source.contains("targetPageIndex: pageIndex"))
        #expect(source.contains("let initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment"))
        #expect(source.contains(".onChange(of: initialHorizontalAlignment)"))
    }

    @Test func pagedViewportQuickFadePanDefersToPhysicalHiddenSurfaceEdges() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let shouldBeginRange = try #require(source.range(of: "func gestureRecognizerShouldBegin"))
        let updateGestureRange = try #require(source.range(of: "func updateGestureState"))
        let shouldBeginSource = String(source[shouldBeginRange.lowerBound..<updateGestureRange.lowerBound])

        #expect(shouldBeginSource.contains("pagingDriver.quickFadePanShouldBegin(panRecognizer, inputs: pagingInputs)"))
        #expect(shouldBeginSource.contains("shouldDeferPageTurnPanToSurfaceContent(panRecognizer, in: collectionView)"))
        #expect(shouldBeginSource.contains("return false"))

        let deferRange = try #require(source.range(of: "private func shouldDeferPageTurnPanToSurfaceContent"))
        let updateVisibleRange = try #require(source.range(of: "private func updateVisiblePageSurfacesIfNeeded"))
        let interactionRange = try #require(source.range(of: "private final class MangaPagedReaderPageSurfaceInteraction"))
        let collectionViewRange = try #require(source.range(of: "private final class MangaPagedReaderCollectionView"))
        let deferSource = String(source[deferRange.lowerBound..<updateVisibleRange.lowerBound])
        let interactionSource = String(source[interactionRange.lowerBound..<collectionViewRange.lowerBound])

        #expect(deferSource.contains("parent.zoomEnabled"))
        #expect(deferSource.contains("parent.plan.usesTwoPageSpread"))
        #expect(deferSource.contains("currentSpreadSurfaceInteraction(in: collectionView)"))
        #expect(deferSource.contains("currentPageSurfaceInteraction(in: collectionView)"))
        #expect(deferSource.contains("MangaPagedSurfaceEdgeInteraction.physicalEdge("))
        #expect(deferSource.contains("MangaPagedSurfaceEdgeInteraction.shouldDeferPageTurnPanToSurfaceContent("))
        #expect(deferSource.contains("hiddenEdges: surfaceInteraction.hiddenEdges"))
        #expect(!deferSource.contains("directionalTapZone"))

        #expect(!source.contains("private func physicalHiddenContentEdge"))

        #expect(interactionSource.contains("func hasHiddenContent(onPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge) -> Bool"))
        #expect(interactionSource.contains("hiddenEdges.contains(edge)"))
    }

    @Test func pagedViewportDefersSlidePanToUnzoomedSurfaceWhenHiddenContentRemains() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("collectionView.shouldBeginPanGesture = { [weak coordinator, weak collectionView] recognizer in"))
        #expect(source.contains("func collectionViewPanShouldBegin"))
        #expect(source.contains("shouldDeferPageTurnPanToSurfaceContent(panRecognizer, in: collectionView)"))
        #expect(source.contains("allowsUnzoomedSurfacePan: true"))
        #expect(!source.contains("allowsUnzoomedSurfacePan: parent.settings.pagedTurnStyle == .quickFade"))
        #expect(source.contains("allowsUnzoomedSurfacePan: allowsUnzoomedSurfacePan"))
        #expect(!source.contains(".simultaneousGesture(dragGesture(containerSize: containerSize))"))

        let scaledImageRange = try #require(source.range(of: "private struct MangaPagedReaderScaledImage"))
        let toggleRange = try #require(source.range(
            of: "private func toggleZoom",
            range: scaledImageRange.lowerBound ..< source.endIndex
        ))
        let scaledImageSource = String(source[scaledImageRange.lowerBound..<toggleRange.lowerBound])

        #expect(scaledImageSource.contains("let allowsUnzoomedSurfacePan: Bool"))
        #expect(scaledImageSource.contains("private var surfaceDragGestureMask: GestureMask"))
        #expect(scaledImageSource.contains("surfaceDragGestureEnabled ? .gesture : .subviews"))
        #expect(scaledImageSource.contains("allowsUnzoomedSurfacePan || MangaPageZoomPolicy.isActive(zoomScale)"))
        #expect(scaledImageSource.contains("including: surfaceDragGestureMask"))
        #expect(scaledImageSource.contains("endSurfaceInteraction(animated: true)"))
        #expect(scaledImageSource.contains("DragGesture(\n            minimumDistance: MangaPagedSurfaceDragIntent.minimumUnzoomedHorizontalTranslation,\n            coordinateSpace: .local\n        )"))
        #expect(scaledImageSource.contains("surfaceDragTranslation(value.translation)"))
        #expect(scaledImageSource.contains("MangaPagedSurfaceDragIntent.unzoomedHorizontalTranslation(translation)"))
        #expect(scaledImageSource.contains("guard surfaceDragGestureEnabled,\n                      let translation = surfaceDragTranslation(value.translation) else {\n                    return\n                }"))
        #expect(scaledImageSource.contains(
            "guard surfaceDragGestureEnabled,\n" +
            "                      let translation = surfaceDragTranslation(value.translation) else {\n" +
            "                    gestureUserOffset = .zero\n" +
            "                    return\n" +
            "                }"
        ))
    }

    @Test func pagedViewportUsesSharedSlideAndQuickFadePagingContracts() throws {
        let sharedSource = try sourceFile("Sources/YamiboReaderUI/Features/Reader/Shared/Paging/ReaderPagedPageTurnSupport.swift")
        let mangaSource = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(sharedSource.contains("struct ReaderPagedBoundaryPageTurn"))
        #expect(sharedSource.contains("enum ReaderPagedQuickFadeTransition"))
        #expect(sharedSource.contains("static let duration: TimeInterval = 0.18"))
        #expect(sharedSource.contains("final class ReaderPagedViewportPagingDriver"))
        #expect(sharedSource.contains("ReaderPagedPageTurnPresentation.metrics"))
        #expect(sharedSource.contains("var itemIndexForSelectionIndex: (Int) -> Int = { $0 }"))
        #expect(sharedSource.contains("var selectionIndexForItemIndex: (Int) -> Int = { $0 }"))

        #expect(mangaSource.contains("private let pagingDriver = ReaderPagedViewportPagingDriver()"))
        #expect(mangaSource.contains("collectionView.register(ReaderPagedPageTurnCell.self"))
        #expect(mangaSource.contains("handleQuickFadePan"))
        #expect(mangaSource.contains("pagingDriver.updateGestureState(in: collectionView, inputs: pagingInputs)"))
        #expect(mangaSource.contains("pagingDriver.animateAdjacentSelection("))
        #expect(mangaSource.contains("for: directionalZone"))
        #expect(mangaSource.contains("pagedTurnStyle: parent.settings.pagedTurnStyle"))
        #expect(mangaSource.contains("pageTurnBackgroundColor: { [parent] _, overlayAlpha in"))
        #expect(mangaSource.contains("horizontalNavigationDirection: parent.settings.pageTurnDirection.horizontalNavigationDirection"))
        #expect(mangaSource.contains("itemIndexForSelectionIndex: { [weak self] spreadIndex in"))
        #expect(mangaSource.contains("selectionIndexForItemIndex: { [weak self] viewportIndex in"))
        #expect(mangaSource.contains("leftPageSurface: pageSurface("))
        #expect(mangaSource.contains("rightPageSurface: pageSurface("))
        #expect(mangaSource.contains("surfaceInteraction: surfaceInteraction(for: page)"))
        #expect(mangaSource.contains("spreadSurfaceInteraction: spreadSurfaceInteraction(for: spread)"))
        #expect(mangaSource.contains("pagingInputs(selectionSpreadIndex: targetSpreadIndex)"))
        #expect(mangaSource.contains("IndexPath(item: targetViewportIndex, section: 0)"))
        #expect(mangaSource.contains("private func viewportIndex(forSpreadIndex spreadIndex: Int) -> Int"))
        #expect(mangaSource.contains("private func spreadIndex(forViewportIndex viewportIndex: Int) -> Int"))
        #expect(mangaSource.contains("case .rightToLeft:\n                return parent.plan.spreads.count - 1 - clampedSpreadIndex"))
        #expect(mangaSource.contains("case .rightToLeft:\n                return parent.plan.spreads.count - 1 - clampedViewportIndex"))
        #expect(mangaSource.contains("case .rightToLeft:\n            .rightSwipeAdvances"))
        #expect(mangaSource.contains("case .leftToRight:\n            .leftSwipeAdvances"))
        #expect(sharedSource.contains("ReaderPagedBoundaryPageTurn.directionalDelta"))
    }

    @Test func pagedViewportGatesZoomAndSurfacePanBehindHiddenChrome() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")

        #expect(source.contains("let zoomEnabled: Bool"))
        #expect(source.contains("zoomEnabled: parent.zoomEnabled"))
        #expect(source.contains("lazy var doubleTapGesture: UITapGestureRecognizer"))
        #expect(source.contains("recognizer.numberOfTapsRequired = 2"))
        #expect(source.contains("tapGesture.require(toFail: context.coordinator.doubleTapGesture)"))
        #expect(source.contains("@objc private func handleDoubleTap"))
        #expect(source.contains("MangaPagedCenterTapHitTesting.acceptsCenterTap"))
        #expect(source.contains("private var spreadSurfaceInteractions: [String: MangaPagedReaderPageSurfaceInteraction] = [:]"))
        #expect(source.contains("if parent.plan.usesTwoPageSpread {\n                requestSpreadZoomToggle"))
        #expect(source.contains("private func requestSpreadZoomToggle"))
        #expect(source.contains("spreadSurfaceInteractions[spread.id]"))
        #expect(source.contains("MangaPagedReaderZoomableSpreadSurface("))
        #expect(source.contains("isPageZoomEnabled: false"))
        #expect(source.contains("surfaceInteraction.requestZoomToggle"))
        #expect(source.contains("@Published private(set) var zoomToggleRequest"))
        #expect(source.contains("func requestZoomToggle(at location: CGPoint)"))
        #expect(source.contains(".onReceive(surfaceInteraction.$zoomToggleRequest)"))
        #expect(source.contains(".onReceive(spreadSurfaceInteraction.$zoomToggleRequest)"))
        #expect(source.contains("isZoomInteractionEnabled: !isChromeVisible && zoomEnabled"))
        #expect(source.contains("MangaPagedSpreadSurfaceZoomLayout("))
        #expect(source.contains("MangaPageZoomPolicy.doubleTapTargetScale"))
        #expect(source.contains("MangaPageZoomPolicy.clampedScale(scale)"))
        #expect(!source.contains("private static let doubleTapZoomScale"))
        #expect(!source.contains("private static let maximumZoomScale"))
        #expect(source.contains("MagnifyGesture()"))
        #expect(source.contains("DragGesture()"))
        #expect(source.contains("guard isZoomInteractionEnabled else { return }"))
        #expect(source.contains(".onChange(of: isZoomInteractionEnabled)"))
        #expect(source.contains("resetZoomState(animated: true)"))
        #expect(!source.contains("SpatialTapGesture(count: 2"))
    }

    @Test func pagedViewportKeepsZoomStateSeparateFromReadingPositionUpdates() throws {
        let source = try sourceFile("Sources/YamiboReaderUI/Features/Reader/MangaReader/Presentation/MangaPagedReaderViewport.swift")
        let spreadRange = try #require(source.range(of: "private struct MangaPagedReaderZoomableSpreadSurface"))
        let surfaceRange = try #require(source.range(of: "private struct MangaPagedReaderPageSurface"))
        let edgeFillRange = try #require(source.range(of: "private extension MangaPageEdgeFillStyle"))
        let spreadSource = String(source[spreadRange.lowerBound..<surfaceRange.lowerBound])
        let surfaceSource = String(source[surfaceRange.lowerBound..<edgeFillRange.lowerBound])

        #expect(spreadSource.contains("@State private var steadyScale: CGFloat = 1"))
        #expect(spreadSource.contains("@State private var steadyUserOffset: CGSize = .zero"))
        #expect(spreadSource.contains("MangaPagedSpreadSurfaceZoomLayout("))
        #expect(!spreadSource.contains("onCurrentPageChange"))
        #expect(!spreadSource.contains("publishCurrentPageIfNeeded"))
        #expect(surfaceSource.contains("@State private var steadyScale: CGFloat = 1"))
        #expect(surfaceSource.contains("@State private var steadyUserOffset: CGSize = .zero"))
        #expect(surfaceSource.contains("MangaPagedImageSurfaceLayout("))
        #expect(!surfaceSource.contains("onCurrentPageChange"))
        #expect(!surfaceSource.contains("publishCurrentPageIfNeeded"))
    }

    #if os(iOS)
    @MainActor
    @Test func imagePipelineDeduplicatesConcurrentLoads() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [.success(Self.pngData)], delayNanoseconds: 50_000_000)
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        async let first = pipeline.image(for: page)
        async let second = pipeline.image(for: page)
        let images = try await [first, second]

        #expect(images.count == 2)
        #expect(images.allSatisfy { $0.size.width > 0 && $0.size.height > 0 })
        #expect(await loader.callCount == 1)
    }

    @MainActor
    @Test func imagePipelineCachesDecodedImages() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [.success(Self.pngData)])
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        let first = try await pipeline.image(for: page)
        let second = try await pipeline.image(for: page)

        #expect(first === second)
        #expect(await loader.callCount == 1)
    }

    @MainActor
    @Test func imagePipelineDoesNotCacheInvalidImageData() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [
            .success(Data([0, 1, 2])),
            .success(Self.pngData)
        ])
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        await #expect(throws: MangaImagePipelineError.invalidImageData) {
            _ = try await pipeline.image(for: page)
        }
        let image = try await pipeline.image(for: page)

        #expect(image.size.width > 0)
        #expect(await loader.callCount == 2)
    }

    @MainActor
    @Test func imagePipelineDoesNotCacheLoaderFailures() async throws {
        let loader = RecordingMangaPipelineDataLoader(outputs: [
            .failure(MangaPipelineTestError.loaderFailure),
            .success(Self.pngData)
        ])
        let pipeline = MangaImagePipeline(dataLoader: loader)
        let page = try makePipelinePage()

        await #expect(throws: MangaPipelineTestError.loaderFailure) {
            _ = try await pipeline.image(for: page)
        }
        #expect(pipeline.cachedImage(for: page) == nil)
        let image = try await pipeline.image(for: page)

        #expect(image.size.width > 0)
        #expect(await loader.callCount == 2)
    }

    private static let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
    #endif
}

private func sourceFile(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return try String(contentsOf: url, encoding: .utf8)
}

#if os(iOS)
private enum MangaPipelineTestError: Error, Equatable {
    case loaderFailure
}

private actor RecordingMangaPipelineDataLoader: MangaImageDataLoading {
    private var outputs: [Result<Data, Error>]
    private let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(outputs: [Result<Data, Error>], delayNanoseconds: UInt64 = 0) {
        self.outputs = outputs
        self.delayNanoseconds = delayNanoseconds
    }

    func imageData(for url: URL, refererURL: URL?) async throws -> Data {
        callCount += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let output = outputs.isEmpty ? .success(Data()) : outputs.removeFirst()
        return try output.get()
    }
}

private func makePipelinePage() throws -> MangaReaderPageProjection {
    MangaReaderPageProjection(
        tid: "700",
        ownerPostID: "post-700",
        chapterTitle: "Chapter 700",
        imageURL: try #require(URL(string: "https://img.example.com/700-0.png")),
        refererURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=700")),
        globalIndex: 0,
        localIndex: 0,
        chapterPageCount: 1
    )
}
#endif
