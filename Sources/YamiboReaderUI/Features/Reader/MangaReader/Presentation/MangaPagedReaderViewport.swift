import SwiftUI
import Combine
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaPagedReaderViewport: UIViewRepresentable {
    let plan: MangaPagedReadingPlan
    let viewportPlacement: MangaReaderViewportPlacement?
    let settings: MangaReaderSettings
    let imagePipeline: MangaImagePipeline
    let isChromeVisible: Bool
    let zoomEnabled: Bool
    let onCurrentPageChange: (Int) -> Void
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var pageEdgeFillColor: UIColor {
        settings.pageEdgeFillStyle.uiColor(for: colorScheme)
    }

    private var effectivePageScaleMode: MangaPageScaleMode {
        MangaPagedLayoutPolicy.effectivePageScaleMode(
            settings: settings,
            usesTwoPageSpread: plan.usesTwoPageSpread
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        let collectionView = MangaPagedReaderCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isPagingEnabled = true
        collectionView.alwaysBounceHorizontal = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.backgroundColor = pageEdgeFillColor
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(ReaderPagedPageTurnCell.self, forCellWithReuseIdentifier: Coordinator.reuseIdentifier)
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.realignViewportAfterBoundsChangeIfNeeded(in: collectionView)
            coordinator?.applyInitialPlacementIfNeeded(in: collectionView)
            coordinator?.applyViewportPlacementIfNeeded(in: collectionView)
        }
        context.coordinator.tapGesture.cancelsTouchesInView = false
        context.coordinator.tapGesture.delegate = context.coordinator
        context.coordinator.tapGesture.require(toFail: context.coordinator.doubleTapGesture)
        collectionView.addGestureRecognizer(context.coordinator.tapGesture)
        context.coordinator.doubleTapGesture.cancelsTouchesInView = false
        context.coordinator.doubleTapGesture.delegate = context.coordinator
        collectionView.addGestureRecognizer(context.coordinator.doubleTapGesture)
        context.coordinator.quickFadePanGesture.delegate = context.coordinator
        collectionView.addGestureRecognizer(context.coordinator.quickFadePanGesture)
        collectionView.shouldBeginPanGesture = { [weak coordinator, weak collectionView] recognizer in
            guard let coordinator,
                  let collectionView else {
                return true
            }
            return coordinator.collectionViewPanShouldBegin(recognizer, in: collectionView)
        }
        context.coordinator.updateGestureState(in: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        collectionView.backgroundColor = pageEdgeFillColor
        context.coordinator.updateGestureState(in: collectionView)
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.updateContentIfNeeded(in: collectionView)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        static let reuseIdentifier = "MangaPagedReaderPageCell"

        var parent: MangaPagedReaderViewport
        private let pagingDriver = ReaderPagedViewportPagingDriver()
        private var contentIdentity: MangaPagedReaderContentIdentity?
        private var surfaceInteractionIdentity: MangaPagedReaderSurfaceInteractionIdentity?
        private var pageSurfaceInteractions: [String: MangaPagedReaderPageSurfaceInteraction] = [:]
        private var spreadSurfaceInteractions: [String: MangaPagedReaderPageSurfaceInteraction] = [:]
        private var pageSurfaceInitialHorizontalAlignments: [String: MangaPagedImageSurfaceInitialHorizontalAlignment] = [:]
        private var pendingInitialSpreadIndex: Int?
        private var lastReportedGlobalIndex: Int?
        private var lastAppliedPlacementRevision: Int?
        private var lastLaidOutViewportSize: CGSize?
        lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        lazy var doubleTapGesture: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            return recognizer
        }()
        lazy var quickFadePanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleQuickFadePan(_:)))

        var callbackScheduler: SwiftUIViewUpdateCallbackScheduler {
            pagingDriver.callbackScheduler
        }

        private var pagingInputs: ReaderPagedViewportPagingInputs {
            pagingInputs(selectionSpreadIndex: parent.plan.currentSpreadIndex)
        }

        private func pagingInputs(selectionSpreadIndex: Int?) -> ReaderPagedViewportPagingInputs {
            let spreadIndex = parent.plan.clampedSpreadIndex(selectionSpreadIndex) ?? 0
            return ReaderPagedViewportPagingInputs(
                itemCount: parent.plan.spreads.count,
                selectionIndex: spreadIndex,
                pagedTurnStyle: parent.settings.pagedTurnStyle,
                horizontalNavigationDirection: parent.settings.pageTurnDirection.horizontalNavigationDirection,
                pagerIdentity: ReaderPagedPagerIdentity(
                    visibleView: spreadIndex + 1,
                    surfaceCount: parent.plan.pages.count,
                    spreadCount: parent.plan.spreads.count,
                    usesTwoPageSpread: parent.plan.usesTwoPageSpread,
                    layout: .zero
                ),
                scrollAnimationRequest: nil,
                canBoundaryPageTurn: { _ in false },
                onSelectionChange: { [weak self] spreadIndex in
                    self?.publishCurrentPageIfNeeded(spreadIndex: spreadIndex)
                },
                onBoundaryPageTurn: { _ in },
                onScrollAnimationRequestConsumed: { _ in },
                pageTurnRestingBackgroundColor: { [parent] _ in parent.pageEdgeFillColor },
                pageTurnBackgroundColor: { [parent] _, overlayAlpha in
                    ReaderPagedPageTurnBackground.dimmedPageColor(
                        baseColor: parent.pageEdgeFillColor,
                        overlayAlpha: overlayAlpha
                    )
                },
                itemIndexForSelectionIndex: { [weak self] spreadIndex in
                    self?.viewportIndex(forSpreadIndex: spreadIndex) ?? spreadIndex
                },
                selectionIndexForItemIndex: { [weak self] viewportIndex in
                    self?.spreadIndex(forViewportIndex: viewportIndex) ?? viewportIndex
                }
            )
        }

        init(parent: MangaPagedReaderViewport) {
            self.parent = parent
        }

        func updateContentIfNeeded(in collectionView: UICollectionView) {
            let nextIdentity = MangaPagedReaderContentIdentity(
                spreadIDs: parent.plan.spreads.map(\.id),
                pageScaleMode: parent.effectivePageScaleMode,
                pagedTurnStyle: parent.settings.pagedTurnStyle,
                pageTurnDirection: parent.settings.pageTurnDirection,
                pageEdgeFillStyle: parent.settings.pageEdgeFillStyle,
                colorScheme: parent.colorScheme
            )
            guard nextIdentity != contentIdentity else {
                applyInitialPlacementIfNeeded(in: collectionView)
                applyViewportPlacementIfNeeded(in: collectionView)
                updateVisiblePageSurfacesIfNeeded(in: collectionView)
                return
            }

            contentIdentity = nextIdentity
            surfaceInteractionIdentity = nil
            pageSurfaceInteractions = [:]
            spreadSurfaceInteractions = [:]
            pageSurfaceInitialHorizontalAlignments = [:]
            lastReportedGlobalIndex = nil
            if parent.plan.spreads.isEmpty {
                pendingInitialSpreadIndex = nil
                collectionView.alpha = 1
            } else {
                let targetPageIndex = parent.plan.clampedPageIndex(
                    parent.viewportPlacement?.targetPageIndex ?? parent.plan.currentPageIndex
                )
                pendingInitialSpreadIndex = targetPageIndex.flatMap(parent.plan.spreadIndex(forPageAt:))
                    ?? parent.plan.currentSpreadIndex
                collectionView.alpha = 0
            }

            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
            collectionView.setNeedsLayout()
            collectionView.layoutIfNeeded()
            applyInitialPlacementIfNeeded(in: collectionView)
            applyViewportPlacementIfNeeded(in: collectionView)
            updateVisiblePageSurfacesIfNeeded(in: collectionView)
        }

        func realignViewportAfterBoundsChangeIfNeeded(in collectionView: UICollectionView) {
            let currentViewportSize = collectionView.bounds.size
            defer {
                lastLaidOutViewportSize = currentViewportSize
            }

            guard pendingInitialSpreadIndex == nil,
                  let targetOffsetX = MangaPagedViewportResizePolicy.alignedContentOffsetX(
                      previousContentOffsetX: collectionView.contentOffset.x,
                      previousViewportSize: lastLaidOutViewportSize,
                      currentViewportSize: currentViewportSize,
                      itemCount: parent.plan.spreads.count
                  ) else {
                return
            }

            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.setContentOffset(
                CGPoint(x: targetOffsetX, y: collectionView.contentOffset.y),
                animated: false
            )
            publishCurrentPageIfNeeded(from: collectionView)
            updateGestureState(in: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.plan.spreads.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.reuseIdentifier,
                for: indexPath
            )
            let spreadIndex = spreadIndex(forViewportIndex: indexPath.item)
            guard let cell = cell as? ReaderPagedPageTurnCell,
                  parent.plan.spreads.indices.contains(spreadIndex) else {
                return cell
            }

            configureSpreadCell(cell, spreadIndex: spreadIndex, refreshInitialHorizontalAlignment: true)
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            let spreadIndex = spreadIndex(forViewportIndex: indexPath.item)
            configureSpreadCell(cell, spreadIndex: spreadIndex, refreshInitialHorizontalAlignment: true)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            collectionView.bounds.size
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pagingDriver.scrollViewWillBeginDragging(scrollView, inputs: pagingInputs)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            pagingDriver.scrollViewDidScroll(scrollView, inputs: pagingInputs)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            pagingDriver.scrollViewDidEndDecelerating(scrollView, inputs: pagingInputs)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            pagingDriver.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate, inputs: pagingInputs)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            pagingDriver.scrollViewDidEndScrollingAnimation(scrollView, inputs: pagingInputs)
        }

        func applyInitialPlacementIfNeeded(in collectionView: UICollectionView) {
            guard let targetIndex = pendingInitialSpreadIndex else { return }
            guard parent.plan.spreads.indices.contains(targetIndex) else {
                pendingInitialSpreadIndex = nil
                collectionView.alpha = 1
                return
            }
            guard collectionView.bounds.width > 0, collectionView.bounds.height > 0 else {
                return
            }
            let targetViewportIndex = viewportIndex(forSpreadIndex: targetIndex)

            collectionView.scrollToItem(
                at: IndexPath(item: targetViewportIndex, section: 0),
                at: .centeredHorizontally,
                animated: false
            )
            lastAppliedPlacementRevision = parent.viewportPlacement?.revision
            pendingInitialSpreadIndex = nil
            collectionView.alpha = 1
            publishCurrentPageIfNeeded(from: collectionView)
            updateGestureState(in: collectionView)
        }

        func applyViewportPlacementIfNeeded(in collectionView: UICollectionView) {
            guard pendingInitialSpreadIndex == nil,
                  let placement = parent.viewportPlacement,
                  placement.revision != lastAppliedPlacementRevision else {
                return
            }
            guard let targetIndex = parent.plan.clampedPageIndex(placement.targetPageIndex),
                  parent.plan.pages.indices.contains(targetIndex),
                  let targetSpreadIndex = parent.plan.spreadIndex(forPageAt: targetIndex),
                  collectionView.bounds.width > 0,
                  collectionView.bounds.height > 0 else {
                return
            }

            let targetViewportIndex = viewportIndex(forSpreadIndex: targetSpreadIndex)
            let placementInputs = pagingInputs(selectionSpreadIndex: targetSpreadIndex)
            lastAppliedPlacementRevision = placement.revision
            if placement.animated {
                let didRequestDriverScroll = pagingDriver.requestSelectionScroll(
                    in: collectionView,
                    animated: true,
                    inputs: placementInputs
                )
                if !didRequestDriverScroll {
                    collectionView.scrollToItem(
                        at: IndexPath(item: targetViewportIndex, section: 0),
                        at: .centeredHorizontally,
                        animated: true
                    )
                }
            } else {
                collectionView.scrollToItem(
                    at: IndexPath(item: targetViewportIndex, section: 0),
                    at: .centeredHorizontally,
                    animated: false
                )
                publishCurrentPageIfNeeded(spreadIndex: targetSpreadIndex)
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let collectionView = recognizer.view as? UICollectionView else {
                return
            }
            let zone = ReaderPagedTapZone.zone(
                for: recognizer.location(in: collectionView),
                in: collectionView.bounds
            )
            if parent.isChromeVisible {
                let onTap = parent.onTap
                callbackScheduler.publish {
                    onTap()
                }
                return
            }
            if consumeSurfaceEdgeTap(for: zone, in: collectionView) {
                return
            }
            let directionalZone = directionalTapZone(for: zone)
            if pagingDriver.animateAdjacentSelection(for: directionalZone, in: collectionView, inputs: pagingInputs) {
                return
            }
            guard directionalZone == .toggleChrome else {
                return
            }
            let onTap = parent.onTap
            callbackScheduler.publish {
                onTap()
            }
        }

        @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let collectionView = recognizer.view as? UICollectionView else {
                return
            }
            let location = recognizer.location(in: collectionView)
            guard MangaPagedCenterTapHitTesting.acceptsCenterTap(at: location, in: collectionView.bounds) else {
                return
            }

            if parent.isChromeVisible {
                let onTap = parent.onTap
                callbackScheduler.publish {
                    onTap()
                }
                return
            }

            guard parent.zoomEnabled else {
                return
            }
            if parent.plan.usesTwoPageSpread {
                requestSpreadZoomToggle(at: location, in: collectionView)
                return
            }

            guard let pageIndex = pageIndex(at: location, in: collectionView),
                  let page = parent.plan.page(at: pageIndex),
                  let surfaceInteraction = pageSurfaceInteractions[page.id] else {
                return
            }
            surfaceInteraction.requestZoomToggle(at: surfaceLocation(for: pageIndex, location: location, in: collectionView))
        }

        @objc private func handleQuickFadePan(_ recognizer: UIPanGestureRecognizer) {
            guard !parent.isChromeVisible else { return }
            pagingDriver.handleQuickFadePan(recognizer, inputs: pagingInputs)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard touch.view?.isDescendant(ofType: UIControl.self) != true else {
                return false
            }
            guard gestureRecognizer === doubleTapGesture,
                  let collectionView = gestureRecognizer.view as? UICollectionView else {
                return true
            }
            return MangaPagedCenterTapHitTesting.acceptsCenterTap(
                at: touch.location(in: collectionView),
                in: collectionView.bounds
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === quickFadePanGesture,
                  let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer else {
                return true
            }
            guard !parent.isChromeVisible,
                  let collectionView = panRecognizer.view as? UICollectionView,
                  pagingDriver.quickFadePanShouldBegin(panRecognizer, inputs: pagingInputs) else {
                return false
            }
            if shouldDeferPageTurnPanToSurfaceContent(panRecognizer, in: collectionView) {
                return false
            }
            return true
        }

        func collectionViewPanShouldBegin(
            _ panRecognizer: UIPanGestureRecognizer,
            in collectionView: UICollectionView
        ) -> Bool {
            guard !parent.isChromeVisible,
                  parent.settings.pagedTurnStyle != .quickFade else {
                return false
            }
            if shouldDeferPageTurnPanToSurfaceContent(panRecognizer, in: collectionView) {
                return false
            }
            return true
        }

        func updateGestureState(in collectionView: UICollectionView) {
            pagingDriver.updateGestureState(in: collectionView, inputs: pagingInputs)
            if parent.isChromeVisible {
                collectionView.panGestureRecognizer.isEnabled = false
            }
            quickFadePanGesture.isEnabled = !parent.isChromeVisible && parent.settings.pagedTurnStyle == .quickFade
        }

        private func shouldDeferPageTurnPanToSurfaceContent(
            _ recognizer: UIPanGestureRecognizer,
            in collectionView: UICollectionView
        ) -> Bool {
            let surfaceInteraction: MangaPagedReaderPageSurfaceInteraction?
            if parent.plan.usesTwoPageSpread {
                surfaceInteraction = currentSpreadSurfaceInteraction(in: collectionView)
            } else {
                surfaceInteraction = currentPageSurfaceInteraction(in: collectionView)
            }
            guard let surfaceInteraction else {
                return false
            }
            let velocity = recognizer.velocity(in: collectionView)
            let translation = recognizer.translation(in: collectionView)
            let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(
                horizontalVelocityX: velocity.x,
                horizontalTranslationX: translation.x
            )
            return MangaPagedSurfaceEdgeInteraction.shouldDeferPageTurnPanToSurfaceContent(
                zoomEnabled: parent.zoomEnabled,
                isZoomActive: surfaceInteraction.isZoomActive,
                hiddenEdges: surfaceInteraction.hiddenEdges,
                physicalEdge: physicalEdge
            )
        }

        private func updateVisiblePageSurfacesIfNeeded(in collectionView: UICollectionView) {
            let nextIdentity = MangaPagedReaderSurfaceInteractionIdentity(
                isChromeVisible: parent.isChromeVisible,
                zoomEnabled: parent.zoomEnabled
            )
            guard nextIdentity != surfaceInteractionIdentity else { return }
            surfaceInteractionIdentity = nextIdentity

            for case let cell as ReaderPagedPageTurnCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                let spreadIndex = spreadIndex(forViewportIndex: indexPath.item)
                configureSpreadCell(cell, spreadIndex: spreadIndex, refreshInitialHorizontalAlignment: false)
            }
        }

        private func configureSpreadCell(
            _ cell: UICollectionViewCell,
            spreadIndex: Int,
            refreshInitialHorizontalAlignment: Bool
        ) {
            guard let cell = cell as? ReaderPagedPageTurnCell,
                  parent.plan.spreads.indices.contains(spreadIndex) else {
                return
            }

            let spread = parent.plan.spreads[spreadIndex]
            cell.configure(
                spreadID: spread.id,
                usesTwoPageSpread: parent.plan.usesTwoPageSpread,
                leftPageSurface: pageSurface(
                    page: spread.leftPage,
                    pageIndex: spread.leftPageIndex,
                    refreshInitialHorizontalAlignment: refreshInitialHorizontalAlignment
                ),
                rightPageSurface: pageSurface(
                    page: spread.rightPage,
                    pageIndex: spread.rightPageIndex,
                    refreshInitialHorizontalAlignment: refreshInitialHorizontalAlignment
                ),
                imagePipeline: parent.imagePipeline,
                pageScaleMode: parent.effectivePageScaleMode,
                pageEdgeFillStyle: parent.settings.pageEdgeFillStyle,
                isChromeVisible: parent.isChromeVisible,
                zoomEnabled: parent.zoomEnabled,
                allowsUnzoomedSurfacePan: true,
                spreadSurfaceInteraction: spreadSurfaceInteraction(for: spread),
                colorScheme: parent.colorScheme
            )
            cell.resetPageTurnVisuals()
        }

        private func pageSurface(
            page: MangaReaderPageProjection?,
            pageIndex: Int?,
            refreshInitialHorizontalAlignment: Bool
        ) -> MangaPagedReaderSpreadPageSurface? {
            guard let page, let pageIndex else { return nil }
            return MangaPagedReaderSpreadPageSurface(
                page: page,
                surfaceIdentity: MangaPagedReaderPageAppearanceIdentity(pageID: page.id, appearanceGeneration: 0),
                initialHorizontalAlignment: initialHorizontalAlignment(
                    for: page,
                    pageIndex: pageIndex,
                    refresh: refreshInitialHorizontalAlignment
                ),
                surfaceInteraction: surfaceInteraction(for: page)
            )
        }

        private func initialHorizontalAlignment(
            for page: MangaReaderPageProjection,
            pageIndex: Int,
            refresh: Bool
        ) -> MangaPagedImageSurfaceInitialHorizontalAlignment {
            if !refresh, let alignment = pageSurfaceInitialHorizontalAlignments[page.id] {
                return alignment
            }

            let alignment = MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
                pageTurnDirection: parent.settings.pageTurnDirection,
                pageScaleMode: parent.effectivePageScaleMode,
                currentPageIndex: parent.plan.currentPageIndex,
                targetPageIndex: pageIndex
            )
            pageSurfaceInitialHorizontalAlignments[page.id] = alignment
            return alignment
        }

        private func surfaceInteraction(for page: MangaReaderPageProjection) -> MangaPagedReaderPageSurfaceInteraction {
            if let interaction = pageSurfaceInteractions[page.id] {
                return interaction
            }
            let interaction = MangaPagedReaderPageSurfaceInteraction()
            pageSurfaceInteractions[page.id] = interaction
            return interaction
        }

        private func spreadSurfaceInteraction(for spread: MangaPageSpread) -> MangaPagedReaderPageSurfaceInteraction {
            if let interaction = spreadSurfaceInteractions[spread.id] {
                return interaction
            }
            let interaction = MangaPagedReaderPageSurfaceInteraction()
            spreadSurfaceInteractions[spread.id] = interaction
            return interaction
        }

        private func consumeSurfaceEdgeTap(for zone: ReaderPagedTapZone, in collectionView: UICollectionView) -> Bool {
            guard let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(forTapZone: zone) else {
                return false
            }
            let surfaceInteraction: MangaPagedReaderPageSurfaceInteraction?
            if parent.plan.usesTwoPageSpread {
                surfaceInteraction = currentSpreadSurfaceInteraction(in: collectionView)
            } else if let pageIndex = pageIndex(forPhysicalEdge: physicalEdge, in: collectionView),
                      let page = parent.plan.page(at: pageIndex) {
                surfaceInteraction = pageSurfaceInteractions[page.id]
            } else {
                surfaceInteraction = nil
            }
            guard let surfaceInteraction,
                  MangaPagedSurfaceEdgeInteraction.shouldRevealHiddenContent(
                      on: physicalEdge,
                      hiddenEdges: surfaceInteraction.hiddenEdges
                  ) else {
                return false
            }
            return surfaceInteraction.consumeTap(onPhysicalEdge: physicalEdge)
        }

        private func requestSpreadZoomToggle(at location: CGPoint, in collectionView: UICollectionView) {
            guard let spreadIndex = currentSpreadIndex(in: collectionView),
                  let spread = parent.plan.spread(at: spreadIndex),
                  let surfaceInteraction = spreadSurfaceInteractions[spread.id] else {
                return
            }
            surfaceInteraction.requestZoomToggle(at: spreadLocation(for: spreadIndex, location: location, in: collectionView))
        }

        private func currentSpreadSurfaceInteraction(
            in collectionView: UICollectionView
        ) -> MangaPagedReaderPageSurfaceInteraction? {
            guard let spreadIndex = currentSpreadIndex(in: collectionView),
                  let spread = parent.plan.spread(at: spreadIndex) else {
                return nil
            }
            return spreadSurfaceInteractions[spread.id]
        }

        private func currentPageSurfaceInteraction(
            in collectionView: UICollectionView
        ) -> MangaPagedReaderPageSurfaceInteraction? {
            guard let pageIndex = currentPageIndex(in: collectionView),
                  let page = parent.plan.page(at: pageIndex) else {
                return nil
            }
            return pageSurfaceInteractions[page.id]
        }

        private func surfaceLocation(
            for pageIndex: Int,
            location: CGPoint,
            in collectionView: UICollectionView
        ) -> CGPoint {
            let spreadIndex = parent.plan.spreadIndex(forPageAt: pageIndex) ?? 0
            let indexPath = IndexPath(item: viewportIndex(forSpreadIndex: spreadIndex), section: 0)
            if let cell = collectionView.cellForItem(at: indexPath) {
                var cellLocation = collectionView.convert(location, to: cell.contentView)
                if parent.plan.usesTwoPageSpread,
                   let spread = parent.plan.spread(at: spreadIndex) {
                    let slotWidth = max(cell.contentView.bounds.width / 2, 1)
                    if spread.rightPageIndex == pageIndex {
                        cellLocation.x -= slotWidth
                    }
                    cellLocation.x = min(max(cellLocation.x, 0), slotWidth)
                }
                return cellLocation
            }
            return CGPoint(
                x: location.x - collectionView.bounds.minX,
                y: location.y - collectionView.bounds.minY
            )
        }

        private func spreadLocation(
            for spreadIndex: Int,
            location: CGPoint,
            in collectionView: UICollectionView
        ) -> CGPoint {
            let indexPath = IndexPath(item: viewportIndex(forSpreadIndex: spreadIndex), section: 0)
            if let cell = collectionView.cellForItem(at: indexPath) {
                let cellLocation = collectionView.convert(location, to: cell.contentView)
                return CGPoint(
                    x: min(max(cellLocation.x, 0), max(cell.contentView.bounds.width, 1)),
                    y: min(max(cellLocation.y, 0), max(cell.contentView.bounds.height, 1))
                )
            }
            return CGPoint(
                x: location.x - collectionView.bounds.minX,
                y: location.y - collectionView.bounds.minY
            )
        }

        private func directionalTapZone(for zone: ReaderPagedTapZone) -> ReaderPagedTapZone {
            guard parent.settings.pageTurnDirection == .rightToLeft else {
                return zone
            }
            switch zone {
            case .previous:
                return .next
            case .next:
                return .previous
            case .toggleChrome:
                return .toggleChrome
            }
        }

        private func publishCurrentPageIfNeeded(spreadIndex: Int) {
            guard let globalIndex = parent.plan.globalIndex(forSpreadAt: spreadIndex),
                  globalIndex != lastReportedGlobalIndex else {
                return
            }

            lastReportedGlobalIndex = globalIndex
            let onCurrentPageChange = parent.onCurrentPageChange
            callbackScheduler.publish {
                onCurrentPageChange(globalIndex)
            }
        }

        private func publishCurrentPageIfNeeded(from collectionView: UICollectionView) {
            guard let spreadIndex = currentSpreadIndex(in: collectionView),
                  parent.plan.spreads.indices.contains(spreadIndex) else {
                return
            }
            publishCurrentPageIfNeeded(spreadIndex: spreadIndex)
        }

        private func currentPageIndex(in collectionView: UICollectionView) -> Int? {
            currentSpreadIndex(in: collectionView).flatMap(parent.plan.pageIndex(forSpreadAt:))
        }

        private func currentSpreadIndex(in collectionView: UICollectionView) -> Int? {
            guard collectionView.bounds.width > 0 else {
                return parent.plan.currentSpreadIndex
            }
            let rawIndex = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
            return parent.plan.clampedSpreadIndex(spreadIndex(forViewportIndex: rawIndex))
        }

        private func pageIndex(at location: CGPoint, in collectionView: UICollectionView) -> Int? {
            guard let spreadIndex = currentSpreadIndex(in: collectionView),
                  let spread = parent.plan.spread(at: spreadIndex) else {
                return parent.plan.currentPageIndex
            }
            guard parent.plan.usesTwoPageSpread else {
                return spread.preferredPageIndex
            }
            return spread.pageIndexForHorizontalLocation(location.x, width: collectionView.bounds.width)
        }

        private func pageIndex(
            forPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge,
            in collectionView: UICollectionView
        ) -> Int? {
            guard let spreadIndex = currentSpreadIndex(in: collectionView),
                  let spread = parent.plan.spread(at: spreadIndex) else {
                return parent.plan.currentPageIndex
            }
            guard parent.plan.usesTwoPageSpread else {
                return spread.preferredPageIndex
            }
            switch edge {
            case .left:
                return spread.leftPageIndex
            case .right:
                return spread.rightPageIndex
            }
        }

        private func viewportIndex(forSpreadIndex spreadIndex: Int) -> Int {
            guard !parent.plan.spreads.isEmpty,
                  let clampedSpreadIndex = parent.plan.clampedSpreadIndex(spreadIndex) else {
                return 0
            }
            switch parent.settings.pageTurnDirection {
            case .leftToRight:
                return clampedSpreadIndex
            case .rightToLeft:
                return parent.plan.spreads.count - 1 - clampedSpreadIndex
            }
        }

        private func spreadIndex(forViewportIndex viewportIndex: Int) -> Int {
            guard !parent.plan.spreads.isEmpty else { return 0 }
            let clampedViewportIndex = min(max(viewportIndex, 0), parent.plan.spreads.count - 1)
            switch parent.settings.pageTurnDirection {
            case .leftToRight:
                return clampedViewportIndex
            case .rightToLeft:
                return parent.plan.spreads.count - 1 - clampedViewportIndex
            }
        }
    }
}

struct MangaPagedPageCurlReaderViewport: UIViewControllerRepresentable {
    let plan: MangaPagedReadingPlan
    let viewportPlacement: MangaReaderViewportPlacement?
    let settings: MangaReaderSettings
    let imagePipeline: MangaImagePipeline
    let isChromeVisible: Bool
    let zoomEnabled: Bool
    let onCurrentPageChange: (Int) -> Void
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var pageEdgeFillColor: UIColor {
        settings.pageEdgeFillStyle.uiColor(for: colorScheme)
    }

    private var effectivePageScaleMode: MangaPageScaleMode {
        MangaPagedLayoutPolicy.effectivePageScaleMode(
            settings: settings,
            usesTwoPageSpread: plan.usesTwoPageSpread
        )
    }

    private var sequence: MangaPagedPageCurlSequence {
        MangaPagedPageCurlSequence(plan: plan)
    }

    private var selectionIndex: Int {
        MangaPagedPageCurlSelectionResolver.currentSelectionIndex(plan: plan)
    }

    private var contentIdentity: MangaPagedReaderContentIdentity {
        MangaPagedReaderContentIdentity(
            spreadIDs: plan.spreads.map(\.id),
            pageScaleMode: effectivePageScaleMode,
            pagedTurnStyle: settings.pagedTurnStyle,
            pageTurnDirection: settings.pageTurnDirection,
            pageEdgeFillStyle: settings.pageEdgeFillStyle,
            colorScheme: colorScheme
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MangaPagedPageCurlContainerViewController {
        let spineLocation: UIPageViewController.SpineLocation = sequence.usesTwoPageSpread ? .mid : .min
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: spineLocation.rawValue]
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = pageEdgeFillColor
        pageViewController.view.isOpaque = true

        let containerViewController = MangaPagedPageCurlContainerViewController(pageViewController: pageViewController)
        let coordinator = context.coordinator
        containerViewController.onLayoutSubviews = { [weak coordinator, weak containerViewController] in
            guard let containerViewController else { return }
            coordinator?.pageCurlContainerDidLayout(containerViewController)
        }

        context.coordinator.configureContainerGestures(in: containerViewController)
        context.coordinator.configureGestures(in: pageViewController)
        _ = context.coordinator.configureSpine(in: pageViewController)
        context.coordinator.applyPageBackground(to: containerViewController)
        context.coordinator.setCurrentSelection(in: pageViewController, animated: false)
        context.coordinator.updatePageCurlSpreadZoomAvailability(in: containerViewController, animated: false)
        return containerViewController
    }

    func updateUIViewController(_ containerViewController: MangaPagedPageCurlContainerViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.update(
                containerViewController,
                contentIdentity: contentIdentity
            )
            context.coordinator.applyPageBackground(to: containerViewController)
            context.coordinator.updatePageCurlSpreadZoomAvailability(in: containerViewController, animated: true)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: MangaPagedPageCurlReaderViewport
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var selectionResolver = MangaPagedPageCurlSelectionResolver()
        private var contentIdentity: MangaPagedReaderContentIdentity?
        private var currentSelectionIndex: Int?
        private var lastReportedGlobalIndex: Int?
        private var pageSurfaceInteractions: [String: MangaPagedReaderPageSurfaceInteraction] = [:]
        private var pageCurlSurfaceInteractionIdentity: MangaPagedReaderSurfaceInteractionIdentity?
        private var pageCurlPageAppearanceGenerations: [String: Int] = [:]
        private var pageCurlSpreadHiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge> = []
        private var pageCurlSteadyScale: CGFloat = 1
        private var pageCurlGestureScale: CGFloat = 1
        private var pageCurlSteadyUserOffset: CGSize = .zero
        private var pageCurlGestureUserOffset: CGSize = .zero
        private var pageCurlPinchStartScale: CGFloat?
        private weak var activeContainerViewController: MangaPagedPageCurlContainerViewController?
        private weak var activePageViewController: UIPageViewController?
        private weak var pageCurlBackColorPageViewController: UIPageViewController?
        private var pageCurlBackColorDisplayLink: CADisplayLink?
        lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        lazy var doubleTapGesture: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            recognizer.numberOfTapsRequired = 2
            return recognizer
        }()
        lazy var spreadPinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleSpreadPinch(_:)))
        lazy var spreadPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleSpreadPan(_:)))

        private var pageCurlZoomScale: CGFloat {
            MangaPageZoomPolicy.clampedScale(pageCurlSteadyScale * pageCurlGestureScale)
        }

        init(parent: MangaPagedPageCurlReaderViewport) {
            self.parent = parent
        }

        deinit {
            MainActor.assumeIsolated {
                stopPageCurlBackColorRefresh()
            }
        }

        fileprivate func update(
            _ containerViewController: MangaPagedPageCurlContainerViewController,
            contentIdentity nextContentIdentity: MangaPagedReaderContentIdentity
        ) {
            let pageViewController = containerViewController.pageViewController
            activeContainerViewController = containerViewController
            activePageViewController = pageViewController
            let didChangeContentIdentity = contentIdentity != nextContentIdentity
            if didChangeContentIdentity {
                pageSurfaceInteractions = [:]
                pageCurlSurfaceInteractionIdentity = nil
                pageCurlPageAppearanceGenerations = [:]
                resetPageCurlSpreadZoom(in: containerViewController, animated: false)
            }
            contentIdentity = nextContentIdentity
            configureContainerGestures(in: containerViewController)
            configureGestures(in: pageViewController)
            let isAwaitingSinglePageSpine = !parent.sequence.usesTwoPageSpread &&
                pageViewController.mangaPageCurlSpineLocation == .mid
            _ = configureSpine(in: pageViewController)
            applyPageBackground(to: pageViewController)
            guard !isAwaitingSinglePageSpine else { return }

            let targetSelectionIndex = selectionResolver.selectionIndex(
                plan: parent.plan,
                viewportPlacement: parent.viewportPlacement
            )
            updateVisiblePageCurlPagesIfNeeded(in: pageViewController)
            guard didChangeContentIdentity || currentSelectionIndex != targetSelectionIndex else {
                return
            }
            setCurrentSelection(
                in: pageViewController,
                selectionIndex: targetSelectionIndex,
                animated: !didChangeContentIdentity && parent.viewportPlacement?.animated == true
            )
        }

        private func updateVisiblePageCurlPagesIfNeeded(in pageViewController: UIPageViewController) {
            let nextIdentity = MangaPagedReaderSurfaceInteractionIdentity(
                isChromeVisible: parent.isChromeVisible,
                zoomEnabled: parent.zoomEnabled
            )
            guard nextIdentity != pageCurlSurfaceInteractionIdentity else { return }
            pageCurlSurfaceInteractionIdentity = nextIdentity

            for case let controller as MangaPagedPageCurlHostingController in pageViewController.viewControllers ?? [] {
                controller.updateRootView(rootView(for: controller.leaf), pageBackgroundColor: parent.pageEdgeFillColor)
            }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let pageController = viewController as? MangaPagedPageCurlHostingController,
                  let leafIndex = parent.sequence.leafIndex(before: pageController.leaf.index) else {
                return nil
            }
            return controller(forLeafIndex: leafIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let pageController = viewController as? MangaPagedPageCurlHostingController,
                  let leafIndex = parent.sequence.leafIndex(after: pageController.leaf.index) else {
                return nil
            }
            return controller(forLeafIndex: leafIndex)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            willTransitionTo pendingViewControllers: [UIViewController]
        ) {
            startPageCurlBackColorRefresh(in: pageViewController)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            spineLocationFor orientation: UIInterfaceOrientation
        ) -> UIPageViewController.SpineLocation {
            let spineLocation = configureSpine(in: pageViewController)
            setCurrentSelection(in: pageViewController, animated: false)
            return spineLocation
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            stopPageCurlBackColorRefresh()
            guard completed else { return }
            preparePreviousPageCurlPagesForReuse(previousViewControllers)
            publishSelection(from: pageViewController)
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let containerViewController = activeContainerViewController,
                  let pageViewController = activePageViewController else {
                return
            }
            if parent.isChromeVisible {
                let onTap = parent.onTap
                callbackScheduler.publish {
                    onTap()
                }
                return
            }

            let zone = ReaderPagedTapZone.zone(
                for: recognizer.location(in: containerViewController.view),
                in: containerViewController.view.bounds
            )
            if consumePageCurlSpreadEdgeTap(for: zone, in: containerViewController) ||
                consumeSurfaceEdgeTap(for: zone, in: pageViewController) {
                return
            }
            switch directionalTapZone(for: zone) {
            case .previous:
                animateAdjacentSelection(delta: -1, in: pageViewController)
            case .next:
                animateAdjacentSelection(delta: 1, in: pageViewController)
            case .toggleChrome:
                let onTap = parent.onTap
                callbackScheduler.publish {
                    onTap()
                }
            }
        }

        @objc
        func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let containerViewController = activeContainerViewController else {
                return
            }
            let location = recognizer.location(in: containerViewController.view)
            guard MangaPagedCenterTapHitTesting.acceptsCenterTap(
                at: location,
                in: containerViewController.view.bounds
            ) else {
                return
            }

            if parent.isChromeVisible {
                let onTap = parent.onTap
                callbackScheduler.publish {
                    onTap()
                }
                return
            }

            guard parent.zoomEnabled else { return }
            if parent.sequence.usesTwoPageSpread {
                togglePageCurlSpreadZoom(at: location, in: containerViewController)
            } else {
                requestPageCurlPageZoomToggle(at: location, in: containerViewController)
            }
        }

        @objc
        func handleSpreadPinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let containerViewController = activeContainerViewController,
                  isPageCurlSpreadZoomInteractionEnabled(in: containerViewController) else {
                return
            }
            switch recognizer.state {
            case .began:
                pageCurlPinchStartScale = pageCurlSteadyScale
            case .changed:
                let startScale = pageCurlPinchStartScale ?? pageCurlSteadyScale
                let targetScale = MangaPageZoomPolicy.clampedScale(startScale * recognizer.scale)
                pageCurlGestureScale = targetScale / max(pageCurlSteadyScale, 0.001)
                clampPageCurlSteadyUserOffset(in: containerViewController, scale: targetScale)
                applyPageCurlSpreadZoomTransform(in: containerViewController, animated: false)
            case .ended, .cancelled, .failed:
                let startScale = pageCurlPinchStartScale ?? pageCurlSteadyScale
                let targetScale = MangaPageZoomPolicy.clampedScale(startScale * recognizer.scale)
                pageCurlPinchStartScale = nil
                pageCurlSteadyScale = targetScale
                pageCurlGestureScale = 1
                if MangaPageZoomPolicy.isActive(targetScale) {
                    clampPageCurlSteadyUserOffset(in: containerViewController)
                    applyPageCurlSpreadZoomTransform(in: containerViewController, animated: true)
                } else {
                    resetPageCurlSpreadZoom(in: containerViewController, animated: true)
                }
            default:
                break
            }
        }

        @objc
        func handleSpreadPan(_ recognizer: UIPanGestureRecognizer) {
            guard let containerViewController = activeContainerViewController,
                  isPageCurlSpreadPanEnabled(in: containerViewController) else {
                pageCurlGestureUserOffset = .zero
                return
            }
            let translation = recognizer.translation(in: containerViewController.view)
            switch recognizer.state {
            case .began, .changed:
                let layout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: pageCurlZoomScale)
                let proposed = CGSize(
                    width: pageCurlSteadyUserOffset.width + translation.x,
                    height: pageCurlSteadyUserOffset.height + translation.y
                )
                let clamped = layout.clampedUserOffset(proposed)
                pageCurlGestureUserOffset = CGSize(
                    width: clamped.width - pageCurlSteadyUserOffset.width,
                    height: clamped.height - pageCurlSteadyUserOffset.height
                )
                applyPageCurlSpreadZoomTransform(in: containerViewController, animated: false)
            case .ended, .cancelled, .failed:
                let layout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: pageCurlSteadyScale)
                let proposed = CGSize(
                    width: pageCurlSteadyUserOffset.width + translation.x,
                    height: pageCurlSteadyUserOffset.height + translation.y
                )
                pageCurlSteadyUserOffset = layout.clampedUserOffset(proposed)
                pageCurlGestureUserOffset = .zero
                applyPageCurlSpreadZoomTransform(in: containerViewController, animated: false)
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard touch.view?.isDescendant(ofType: UIControl.self) != true else {
                return false
            }
            guard gestureRecognizer === doubleTapGesture,
                  let containerViewController = activeContainerViewController else {
                return true
            }
            return MangaPagedCenterTapHitTesting.acceptsCenterTap(
                at: touch.location(in: containerViewController.view),
                in: containerViewController.view.bounds
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPanGestureRecognizer ||
                otherGestureRecognizer is UIPanGestureRecognizer ||
                gestureRecognizer is UIPinchGestureRecognizer ||
                otherGestureRecognizer is UIPinchGestureRecognizer
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === spreadPinchGesture {
                guard let containerViewController = activeContainerViewController else { return false }
                return isPageCurlSpreadZoomInteractionEnabled(in: containerViewController)
            }
            if gestureRecognizer === spreadPanGesture {
                guard let containerViewController = activeContainerViewController else {
                    return false
                }
                return isPageCurlSpreadPanEnabled(in: containerViewController)
            }
            guard let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
                  gestureRecognizer !== spreadPanGesture,
                  let pageViewController = activePageViewController,
                  pageViewController.gestureRecognizers.contains(where: { $0 === gestureRecognizer }) else {
                return true
            }
            guard !parent.isChromeVisible else {
                return false
            }
            if let containerViewController = activeContainerViewController,
               shouldDeferPageCurlPanToSpreadContent(panRecognizer, in: containerViewController) {
                return false
            }
            if shouldDeferPageCurlPanToSurfaceContent(panRecognizer, in: pageViewController) {
                return false
            }
            return true
        }

        func configureContainerGestures(in containerViewController: MangaPagedPageCurlContainerViewController) {
            activeContainerViewController = containerViewController
            if tapGesture.view !== containerViewController.view {
                tapGesture.cancelsTouchesInView = false
                tapGesture.delegate = self
                tapGesture.require(toFail: doubleTapGesture)
                containerViewController.view.addGestureRecognizer(tapGesture)
            }
            if doubleTapGesture.view !== containerViewController.view {
                doubleTapGesture.cancelsTouchesInView = false
                doubleTapGesture.delegate = self
                containerViewController.view.addGestureRecognizer(doubleTapGesture)
            }
            if spreadPinchGesture.view !== containerViewController.view {
                spreadPinchGesture.cancelsTouchesInView = false
                spreadPinchGesture.delegate = self
                containerViewController.view.addGestureRecognizer(spreadPinchGesture)
            }
            if spreadPanGesture.view !== containerViewController.view {
                spreadPanGesture.cancelsTouchesInView = false
                spreadPanGesture.delegate = self
                containerViewController.view.addGestureRecognizer(spreadPanGesture)
            }
            updatePageCurlContainerGestureState(in: containerViewController)
        }

        func configureSpine(in pageViewController: UIPageViewController) -> UIPageViewController.SpineLocation {
            let configuration = MangaPagedPageCurlSpineConfiguration.configuration(
                usesTwoPageSpread: parent.sequence.usesTwoPageSpread,
                currentSpineLocation: pageViewController.mangaPageCurlSpineLocation
            )
            if let doubleSided = configuration.doubleSidedUpdate {
                pageViewController.isDoubleSided = doubleSided
            }
            return configuration.uiPageViewControllerSpineLocation
        }

        func configureGestures(in pageViewController: UIPageViewController) {
            activePageViewController = pageViewController
            for recognizer in pageViewController.gestureRecognizers {
                if recognizer is UITapGestureRecognizer {
                    recognizer.isEnabled = false
                } else if recognizer is UIPanGestureRecognizer {
                    recognizer.delegate = self
                    recognizer.isEnabled = !parent.isChromeVisible
                }
            }
        }

        func pageCurlContainerDidLayout(_ containerViewController: MangaPagedPageCurlContainerViewController) {
            guard parent.sequence.usesTwoPageSpread else {
                resetPageCurlSpreadZoom(in: containerViewController, animated: false)
                return
            }
            clampPageCurlSteadyUserOffset(in: containerViewController)
            applyPageCurlSpreadZoomTransform(in: containerViewController, animated: false)
        }

        func updatePageCurlSpreadZoomAvailability(
            in containerViewController: MangaPagedPageCurlContainerViewController,
            animated: Bool
        ) {
            guard isPageCurlSpreadZoomInteractionEnabled(in: containerViewController) else {
                resetPageCurlSpreadZoom(in: containerViewController, animated: animated)
                return
            }
            clampPageCurlSteadyUserOffset(in: containerViewController)
            applyPageCurlSpreadZoomTransform(in: containerViewController, animated: false)
        }

        func setCurrentSelection(in pageViewController: UIPageViewController, animated: Bool) {
            let targetSelectionIndex = selectionResolver.selectionIndex(
                plan: parent.plan,
                viewportPlacement: parent.viewportPlacement
            )
            setCurrentSelection(
                in: pageViewController,
                selectionIndex: targetSelectionIndex,
                animated: animated
            )
        }

        func setCurrentSelection(
            in pageViewController: UIPageViewController,
            selectionIndex: Int,
            animated: Bool
        ) {
            setSelection(selectionIndex, in: pageViewController, animated: animated, publishOnCompletion: false)
        }

        private func animateAdjacentSelection(delta: Int, in pageViewController: UIPageViewController) {
            let currentSelectionIndex = currentSelectionIndex ?? parent.selectionIndex
            let targetSelectionIndex = currentSelectionIndex + delta
            guard targetSelectionIndex >= 0,
                  targetSelectionIndex < parent.sequence.pageCount else {
                return
            }
            setSelection(
                targetSelectionIndex,
                in: pageViewController,
                animated: true,
                publishOnCompletion: true
            )
        }

        private func setSelection(
            _ selectionIndex: Int,
            in pageViewController: UIPageViewController,
            animated: Bool,
            publishOnCompletion: Bool
        ) {
            let clampedSelectionIndex = min(max(selectionIndex, 0), max(parent.sequence.pageCount - 1, 0))
            let leafIndexes = parent.sequence.leafIndexes(forSelectionIndex: clampedSelectionIndex)
            let controllers = leafIndexes.compactMap(controller(forLeafIndex:))
            guard !controllers.isEmpty else {
                currentSelectionIndex = nil
                return
            }
            if parent.sequence.usesTwoPageSpread,
               clampedSelectionIndex != currentSelectionIndex,
               let activeContainerViewController {
                resetPageCurlSpreadZoom(in: activeContainerViewController, animated: false)
            }

            let direction = navigationDirection(to: clampedSelectionIndex)
            let outgoingViewControllers = pageViewController.viewControllers ?? []
            let shouldPrepareOutgoingPageCurlPages = !parent.sequence.usesTwoPageSpread &&
                clampedSelectionIndex != currentSelectionIndex
            pageViewController.setViewControllers(
                controllers,
                direction: direction,
                animated: animated
            ) { [weak self] completed in
                guard let self else { return }
                if animated {
                    self.stopPageCurlBackColorRefresh()
                }
                guard !animated || completed else { return }
                if animated, shouldPrepareOutgoingPageCurlPages {
                    self.preparePreviousPageCurlPagesForReuse(outgoingViewControllers)
                }
                self.currentSelectionIndex = clampedSelectionIndex
                if publishOnCompletion {
                    self.publishCurrentPageIfNeeded(selectionIndex: clampedSelectionIndex)
                }
            }
            if animated {
                startPageCurlBackColorRefresh(in: pageViewController)
            } else {
                if shouldPrepareOutgoingPageCurlPages {
                    preparePreviousPageCurlPagesForReuse(outgoingViewControllers)
                }
                currentSelectionIndex = clampedSelectionIndex
            }
        }

        private func navigationDirection(to selectionIndex: Int) -> UIPageViewController.NavigationDirection {
            guard let currentSelectionIndex,
                  let currentLeafIndex = parent.sequence.firstLeafIndex(forSelectionIndex: currentSelectionIndex),
                  let targetLeafIndex = parent.sequence.firstLeafIndex(forSelectionIndex: selectionIndex) else {
                return .forward
            }
            return targetLeafIndex >= currentLeafIndex ? .forward : .reverse
        }

        private func controller(forLeafIndex leafIndex: Int) -> UIViewController? {
            guard parent.sequence.leaves.indices.contains(leafIndex) else { return nil }
            let leaf = parent.sequence.leaves[leafIndex]
            return MangaPagedPageCurlHostingController(
                leaf: leaf,
                rootView: rootView(for: leaf),
                pageBackgroundColor: parent.pageEdgeFillColor
            )
        }

        private func rootView(for leaf: MangaPagedPageCurlLeaf) -> MangaPagedPageCurlLeafView {
            MangaPagedPageCurlLeafView(
                pageSurface: pageSurface(for: leaf),
                imagePipeline: parent.imagePipeline,
                pageScaleMode: parent.effectivePageScaleMode,
                pageEdgeFillStyle: parent.settings.pageEdgeFillStyle,
                isChromeVisible: parent.isChromeVisible,
                zoomEnabled: parent.zoomEnabled,
                isPageZoomEnabled: !parent.sequence.usesTwoPageSpread
            )
        }

        private func pageSurface(for leaf: MangaPagedPageCurlLeaf) -> MangaPagedReaderSpreadPageSurface? {
            guard let pageIndex = leaf.pageIndex,
                  let page = parent.plan.page(at: pageIndex) else {
                return nil
            }
            return MangaPagedReaderSpreadPageSurface(
                page: page,
                surfaceIdentity: pageCurlPageSurfaceIdentity(for: page),
                initialHorizontalAlignment: initialHorizontalAlignment(for: page, pageIndex: pageIndex),
                surfaceInteraction: surfaceInteraction(for: page)
            )
        }

        private func pageCurlPageSurfaceIdentity(
            for page: MangaReaderPageProjection
        ) -> MangaPagedReaderPageAppearanceIdentity {
            MangaPagedReaderPageAppearanceIdentity(
                pageID: page.id,
                appearanceGeneration: pageCurlPageAppearanceGenerations[page.id, default: 0]
            )
        }

        private func initialHorizontalAlignment(
            for page: MangaReaderPageProjection,
            pageIndex: Int
        ) -> MangaPagedImageSurfaceInitialHorizontalAlignment {
            MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
                pageTurnDirection: parent.settings.pageTurnDirection,
                pageScaleMode: parent.effectivePageScaleMode,
                currentPageIndex: parent.plan.currentPageIndex,
                targetPageIndex: pageIndex
            )
        }

        private func surfaceInteraction(for page: MangaReaderPageProjection) -> MangaPagedReaderPageSurfaceInteraction {
            if let interaction = pageSurfaceInteractions[page.id] {
                return interaction
            }
            let interaction = MangaPagedReaderPageSurfaceInteraction()
            pageSurfaceInteractions[page.id] = interaction
            return interaction
        }

        func applyPageBackground(to containerViewController: MangaPagedPageCurlContainerViewController) {
            let pageBackgroundColor = parent.pageEdgeFillColor
            containerViewController.view.backgroundColor = pageBackgroundColor
            containerViewController.view.isOpaque = true
            applyPageBackground(to: containerViewController.pageViewController)
        }

        func applyPageBackground(to pageViewController: UIPageViewController) {
            let pageBackgroundColor = parent.pageEdgeFillColor
            pageViewController.view.backgroundColor = pageBackgroundColor
            pageViewController.view.isOpaque = true
            for case let controller as MangaPagedPageCurlHostingController in pageViewController.viewControllers ?? [] {
                controller.applyPageBackground(pageBackgroundColor)
            }
            if !parent.sequence.usesTwoPageSpread {
                MangaPageCurlPrivateBackColor.apply(to: pageViewController.view, backColor: pageBackgroundColor)
            }
        }

        private func startPageCurlBackColorRefresh(in pageViewController: UIPageViewController) {
            guard !parent.sequence.usesTwoPageSpread else {
                applyPageBackground(to: pageViewController)
                return
            }

            pageCurlBackColorPageViewController = pageViewController
            applyPageBackground(to: pageViewController)
            guard pageCurlBackColorDisplayLink == nil else { return }

            let displayLink = CADisplayLink(
                target: self,
                selector: #selector(refreshPageCurlBackColor)
            )
            displayLink.add(to: .main, forMode: .common)
            pageCurlBackColorDisplayLink = displayLink
        }

        private func stopPageCurlBackColorRefresh() {
            pageCurlBackColorDisplayLink?.invalidate()
            pageCurlBackColorDisplayLink = nil
            if let pageCurlBackColorPageViewController {
                applyPageBackground(to: pageCurlBackColorPageViewController)
            }
            pageCurlBackColorPageViewController = nil
        }

        @objc
        private func refreshPageCurlBackColor() {
            guard let pageViewController = pageCurlBackColorPageViewController else {
                stopPageCurlBackColorRefresh()
                return
            }
            applyPageBackground(to: pageViewController)
        }

        private func publishSelection(from pageViewController: UIPageViewController) {
            let leafIndexes = pageViewController.viewControllers?
                .compactMap { ($0 as? MangaPagedPageCurlHostingController)?.leaf.index } ?? []
            guard let selectionIndex = parent.sequence.selectionIndex(forLeafIndexes: leafIndexes) else { return }
            if parent.sequence.usesTwoPageSpread,
               selectionIndex != currentSelectionIndex,
               let activeContainerViewController {
                resetPageCurlSpreadZoom(in: activeContainerViewController, animated: false)
            }
            currentSelectionIndex = selectionIndex
            guard selectionIndex != parent.selectionIndex else { return }
            publishCurrentPageIfNeeded(selectionIndex: selectionIndex)
        }

        private func preparePreviousPageCurlPagesForReuse(_ previousViewControllers: [UIViewController]) {
            guard !parent.sequence.usesTwoPageSpread else { return }
            for case let controller as MangaPagedPageCurlHostingController in previousViewControllers {
                guard let pageIndex = controller.leaf.pageIndex,
                      let page = parent.plan.page(at: pageIndex) else {
                    continue
                }
                pageCurlPageAppearanceGenerations[page.id, default: 0] += 1
                controller.updateRootView(rootView(for: controller.leaf), pageBackgroundColor: parent.pageEdgeFillColor)
            }
        }

        private func publishCurrentPageIfNeeded(selectionIndex: Int) {
            guard let globalIndex = parent.sequence.globalIndex(forSelectionIndex: selectionIndex),
                  globalIndex != lastReportedGlobalIndex else {
                return
            }

            lastReportedGlobalIndex = globalIndex
            let onCurrentPageChange = parent.onCurrentPageChange
            callbackScheduler.publish {
                onCurrentPageChange(globalIndex)
            }
        }

        private func consumePageCurlSpreadEdgeTap(
            for zone: ReaderPagedTapZone,
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) -> Bool {
            guard parent.sequence.usesTwoPageSpread,
                  let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(forTapZone: zone),
                  MangaPagedSurfaceEdgeInteraction.shouldRevealHiddenContent(
                      on: physicalEdge,
                      hiddenEdges: pageCurlSpreadHiddenEdges
                  ) else {
                return false
            }
            revealPageCurlSpreadHiddenContent(on: physicalEdge, in: containerViewController)
            return true
        }

        private func consumeSurfaceEdgeTap(for zone: ReaderPagedTapZone, in pageViewController: UIPageViewController) -> Bool {
            guard !parent.sequence.usesTwoPageSpread,
                  let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(forTapZone: zone),
                  let surfaceInteraction = pageCurlSurfaceInteraction(
                      onPhysicalEdge: physicalEdge,
                      in: pageViewController
                  ),
                  MangaPagedSurfaceEdgeInteraction.shouldRevealHiddenContent(
                      on: physicalEdge,
                      hiddenEdges: surfaceInteraction.hiddenEdges
                  ) else {
                return false
            }
            return surfaceInteraction.consumeTap(onPhysicalEdge: physicalEdge)
        }

        private func shouldDeferPageCurlPanToSpreadContent(
            _ recognizer: UIPanGestureRecognizer,
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) -> Bool {
            guard parent.sequence.usesTwoPageSpread else { return false }
            let velocity = recognizer.velocity(in: containerViewController.view)
            let translation = recognizer.translation(in: containerViewController.view)
            let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(
                horizontalVelocityX: velocity.x,
                horizontalTranslationX: translation.x
            )
            return MangaPagedSurfaceEdgeInteraction.shouldDeferPageTurnPanToSurfaceContent(
                zoomEnabled: parent.zoomEnabled,
                isZoomActive: MangaPageZoomPolicy.isActive(pageCurlZoomScale),
                hiddenEdges: pageCurlSpreadHiddenEdges,
                physicalEdge: physicalEdge
            )
        }

        private func shouldDeferPageCurlPanToSurfaceContent(
            _ recognizer: UIPanGestureRecognizer,
            in pageViewController: UIPageViewController
        ) -> Bool {
            guard !parent.sequence.usesTwoPageSpread,
                  let surfaceInteraction = currentPageCurlSurfaceInteraction(in: pageViewController) else {
                return false
            }
            let velocity = recognizer.velocity(in: pageViewController.view)
            let translation = recognizer.translation(in: pageViewController.view)
            let physicalEdge = MangaPagedSurfaceEdgeInteraction.physicalEdge(
                horizontalVelocityX: velocity.x,
                horizontalTranslationX: translation.x
            )
            return MangaPagedSurfaceEdgeInteraction.shouldDeferPageTurnPanToSurfaceContent(
                zoomEnabled: parent.zoomEnabled,
                isZoomActive: surfaceInteraction.isZoomActive,
                hiddenEdges: surfaceInteraction.hiddenEdges,
                physicalEdge: physicalEdge
            )
        }

        private func currentPageCurlSurfaceInteraction(
            in pageViewController: UIPageViewController
        ) -> MangaPagedReaderPageSurfaceInteraction? {
            let targetController = (pageViewController.viewControllers ?? [])
                .compactMap { $0 as? MangaPagedPageCurlHostingController }
                .sorted { $0.leaf.index < $1.leaf.index }
                .first
            guard let pageIndex = targetController?.leaf.pageIndex,
                  let page = parent.plan.page(at: pageIndex) else {
                return nil
            }
            return pageSurfaceInteractions[page.id]
        }

        private func pageCurlSurfaceInteraction(
            onPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge,
            in pageViewController: UIPageViewController
        ) -> MangaPagedReaderPageSurfaceInteraction? {
            let controllers = (pageViewController.viewControllers ?? [])
                .compactMap { $0 as? MangaPagedPageCurlHostingController }
                .sorted { $0.leaf.index < $1.leaf.index }
            let targetController: MangaPagedPageCurlHostingController?
            if parent.sequence.usesTwoPageSpread {
                targetController = switch edge {
                case .left:
                    controllers.first
                case .right:
                    controllers.last
                }
            } else {
                targetController = controllers.first
            }
            guard let pageIndex = targetController?.leaf.pageIndex,
                  let page = parent.plan.page(at: pageIndex) else {
                return nil
            }
            return pageSurfaceInteractions[page.id]
        }

        private func requestPageCurlPageZoomToggle(
            at location: CGPoint,
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            guard let targetController = (containerViewController.pageViewController.viewControllers ?? [])
                .compactMap({ $0 as? MangaPagedPageCurlHostingController })
                .first,
                  let pageIndex = targetController.leaf.pageIndex,
                  let page = parent.plan.page(at: pageIndex),
                  let surfaceInteraction = pageSurfaceInteractions[page.id] else {
                return
            }
            let targetLocation = containerViewController.view.convert(location, to: targetController.view)
            surfaceInteraction.requestZoomToggle(at: targetLocation)
        }

        private func togglePageCurlSpreadZoom(
            at location: CGPoint,
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            if MangaPageZoomPolicy.isZoomedForDoubleTapReset(pageCurlSteadyScale) {
                resetPageCurlSpreadZoom(in: containerViewController, animated: true)
            } else {
                zoomInPageCurlSpread(to: location, in: containerViewController)
            }
        }

        private func zoomInPageCurlSpread(
            to location: CGPoint,
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            let targetScale = MangaPageZoomPolicy.doubleTapTargetScale
            let targetLayout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: targetScale)
            pageCurlSteadyScale = targetScale
            pageCurlGestureScale = 1
            pageCurlSteadyUserOffset = targetLayout.userOffsetAnchoring(location)
            pageCurlGestureUserOffset = .zero
            applyPageCurlSpreadZoomTransform(in: containerViewController, animated: true)
        }

        private func revealPageCurlSpreadHiddenContent(
            on edge: MangaPagedImageSurfaceHorizontalEdge,
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            let layout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: pageCurlZoomScale)
            let userOffset = proposedPageCurlSpreadUserOffset(layout: layout)
            guard let targetUserOffset = layout.userOffsetRevealingContent(on: edge, fromUserOffset: userOffset) else {
                updatePageCurlSpreadHiddenEdges(in: containerViewController)
                return
            }
            pageCurlSteadyUserOffset = targetUserOffset
            pageCurlGestureUserOffset = .zero
            applyPageCurlSpreadZoomTransform(in: containerViewController, animated: true)
        }

        private func resetPageCurlSpreadZoom(
            in containerViewController: MangaPagedPageCurlContainerViewController,
            animated: Bool
        ) {
            pageCurlSteadyScale = 1
            pageCurlGestureScale = 1
            pageCurlSteadyUserOffset = .zero
            pageCurlGestureUserOffset = .zero
            pageCurlPinchStartScale = nil
            applyPageCurlSpreadZoomTransform(in: containerViewController, animated: animated)
        }

        private func clampPageCurlSteadyUserOffset(
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            clampPageCurlSteadyUserOffset(in: containerViewController, scale: pageCurlSteadyScale)
        }

        private func clampPageCurlSteadyUserOffset(
            in containerViewController: MangaPagedPageCurlContainerViewController,
            scale: CGFloat
        ) {
            let layout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: scale)
            pageCurlSteadyUserOffset = layout.clampedUserOffset(pageCurlSteadyUserOffset)
            pageCurlGestureUserOffset = .zero
        }

        private func applyPageCurlSpreadZoomTransform(
            in containerViewController: MangaPagedPageCurlContainerViewController,
            animated: Bool
        ) {
            let layout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: pageCurlZoomScale)
            let userOffset = proposedPageCurlSpreadUserOffset(layout: layout)
            let displayOffset = layout.displayOffset(forUserOffset: userOffset)
            let pageViewController = containerViewController.pageViewController
            let updates = {
                pageViewController.view.transform = CGAffineTransform(translationX: displayOffset.width, y: displayOffset.height).scaledBy(
                    x: self.pageCurlZoomScale,
                    y: self.pageCurlZoomScale
                )
            }
            if animated {
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: [.curveEaseOut, .allowUserInteraction],
                    animations: updates
                )
            } else {
                updates()
            }
            pageCurlSpreadHiddenEdges = hiddenPageCurlSpreadHorizontalEdges(layout: layout, userOffset: userOffset)
            updatePageCurlContainerGestureState(in: containerViewController)
        }

        private func updatePageCurlSpreadHiddenEdges(
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            let layout = pageCurlSpreadSurfaceLayout(in: containerViewController, scale: pageCurlZoomScale)
            let userOffset = proposedPageCurlSpreadUserOffset(layout: layout)
            pageCurlSpreadHiddenEdges = hiddenPageCurlSpreadHorizontalEdges(layout: layout, userOffset: userOffset)
        }

        private func updatePageCurlContainerGestureState(
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) {
            doubleTapGesture.isEnabled = true
            spreadPinchGesture.isEnabled = isPageCurlSpreadZoomInteractionEnabled(in: containerViewController)
            spreadPanGesture.isEnabled = isPageCurlSpreadPanEnabled(in: containerViewController)
        }

        private func isPageCurlSpreadZoomInteractionEnabled(
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) -> Bool {
            parent.sequence.usesTwoPageSpread &&
                parent.zoomEnabled &&
                !parent.isChromeVisible &&
                containerViewController.view.bounds.width > 0 &&
                containerViewController.view.bounds.height > 0
        }

        private func isPageCurlSpreadPanEnabled(
            in containerViewController: MangaPagedPageCurlContainerViewController
        ) -> Bool {
            isPageCurlSpreadZoomInteractionEnabled(in: containerViewController) &&
                MangaPageZoomPolicy.isActive(pageCurlZoomScale)
        }

        private func proposedPageCurlSpreadUserOffset(layout: MangaPagedSpreadSurfaceZoomLayout) -> CGSize {
            layout.clampedUserOffset(
                CGSize(
                    width: pageCurlSteadyUserOffset.width + pageCurlGestureUserOffset.width,
                    height: pageCurlSteadyUserOffset.height + pageCurlGestureUserOffset.height
                )
            )
        }

        private func hiddenPageCurlSpreadHorizontalEdges(
            layout: MangaPagedSpreadSurfaceZoomLayout,
            userOffset: CGSize
        ) -> Set<MangaPagedImageSurfaceHorizontalEdge> {
            Set(
                MangaPagedImageSurfaceHorizontalEdge.allCases.filter { edge in
                    layout.hasHiddenContent(on: edge, fromUserOffset: userOffset)
                }
            )
        }

        private func pageCurlSpreadSurfaceLayout(
            in containerViewController: MangaPagedPageCurlContainerViewController,
            scale: CGFloat
        ) -> MangaPagedSpreadSurfaceZoomLayout {
            MangaPagedSpreadSurfaceZoomLayout(
                containerSize: containerViewController.view.bounds.size,
                zoomScale: scale
            )
        }

        private func directionalTapZone(for zone: ReaderPagedTapZone) -> ReaderPagedTapZone {
            guard parent.settings.pageTurnDirection == .rightToLeft else {
                return zone
            }
            switch zone {
            case .previous:
                return .next
            case .next:
                return .previous
            case .toggleChrome:
                return .toggleChrome
            }
        }
    }
}

final class MangaPagedPageCurlContainerViewController: UIViewController {
    let pageViewController: UIPageViewController
    var onLayoutSubviews: (() -> Void)?

    init(pageViewController: UIPageViewController) {
        self.pageViewController = pageViewController
        super.init(nibName: nil, bundle: nil)
    }

    @MainActor @preconcurrency
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        pageViewController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayoutSubviews?()
    }
}

private final class MangaPagedPageCurlHostingController: UIHostingController<MangaPagedPageCurlLeafView> {
    let leaf: MangaPagedPageCurlLeaf

    init(
        leaf: MangaPagedPageCurlLeaf,
        rootView: MangaPagedPageCurlLeafView,
        pageBackgroundColor: UIColor
    ) {
        self.leaf = leaf
        super.init(rootView: rootView)
        applyPageBackground(pageBackgroundColor)
    }

    @MainActor @preconcurrency
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyPageBackground(_ pageBackgroundColor: UIColor) {
        view.backgroundColor = pageBackgroundColor
        view.isOpaque = true
    }

    func updateRootView(_ rootView: MangaPagedPageCurlLeafView, pageBackgroundColor: UIColor) {
        self.rootView = rootView
        applyPageBackground(pageBackgroundColor)
    }
}

@MainActor
private enum MangaPageCurlPrivateBackColor {
    private static let filtersKey = "filters"
    private static let backgroundFiltersKey = "backgroundFilters"
    private static let typeKey = "type"
    private static let pageCurlType = "pageCurl"
    private static let inputBackEnabledKey = "inputBackEnabled"
    private static let inputBackColor0Key = "inputBackColor0"
    private static let inputBackColor1Key = "inputBackColor1"

    static func apply(to rootView: UIView, backColor: UIColor) {
        let colorComponents = backColor.mangaPageCurlPrivateColorComponents
        apply(to: rootView.layer, colorComponents: colorComponents)
    }

    private static func apply(to layer: CALayer, colorComponents: [NSNumber]) {
        for filterKey in [filtersKey, backgroundFiltersKey] {
            guard let filters = layer.value(forKey: filterKey) as? [NSObject] else { continue }
            for filter in filters where isPageCurlFilter(filter) {
                filter.setValue(NSNumber(value: true), forKey: inputBackEnabledKey)
                filter.setValue(colorComponents, forKey: inputBackColor0Key)
                filter.setValue(colorComponents, forKey: inputBackColor1Key)
            }
        }

        layer.sublayers?.forEach { apply(to: $0, colorComponents: colorComponents) }
    }

    private static func isPageCurlFilter(_ filter: NSObject) -> Bool {
        if String(describing: filter) == pageCurlType {
            return true
        }
        return (filter.value(forKey: typeKey) as? String) == pageCurlType
    }
}

private extension UIColor {
    var mangaPageCurlPrivateColorComponents: [NSNumber] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha].map { NSNumber(value: Double($0)) }
    }
}

private extension UIPageViewController {
    var mangaPageCurlSpineLocation: MangaPagedPageCurlSpineLocation {
        spineLocation == .mid ? .mid : .min
    }
}

private extension MangaPagedPageCurlSpineConfiguration {
    var uiPageViewControllerSpineLocation: UIPageViewController.SpineLocation {
        switch spineLocation {
        case .min:
            .min
        case .mid:
            .mid
        }
    }
}

private struct MangaPagedPageCurlLeafView: View {
    let pageSurface: MangaPagedReaderSpreadPageSurface?
    let imagePipeline: MangaImagePipeline
    let pageScaleMode: MangaPageScaleMode
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isChromeVisible: Bool
    let zoomEnabled: Bool
    let isPageZoomEnabled: Bool

    var body: some View {
        MangaPagedReaderPageSlot(
            surface: pageSurface,
            imagePipeline: imagePipeline,
            pageScaleMode: pageScaleMode,
            pageEdgeFillStyle: pageEdgeFillStyle,
            isChromeVisible: isChromeVisible,
            zoomEnabled: zoomEnabled,
            allowsUnzoomedSurfacePan: true,
            isPageZoomEnabled: isPageZoomEnabled
        )
        .ignoresSafeArea(
            .container,
            edges: UIDevice.current.userInterfaceIdiom == .pad ? .vertical : .bottom
        )
    }
}

private struct MangaPagedReaderContentIdentity: Equatable {
    var spreadIDs: [String]
    var pageScaleMode: MangaPageScaleMode
    var pagedTurnStyle: ReaderPagedTurnStyle
    var pageTurnDirection: MangaPageTurnDirection
    var pageEdgeFillStyle: MangaPageEdgeFillStyle
    var colorScheme: ColorScheme
}

private struct MangaPagedReaderSurfaceInteractionIdentity: Equatable {
    var isChromeVisible: Bool
    var zoomEnabled: Bool
}

private struct MangaPagedReaderEdgeRevealRequest {
    let sequence: Int
    let edge: MangaPagedImageSurfaceHorizontalEdge?
}

private struct MangaPagedReaderZoomToggleRequest {
    let sequence: Int
    let location: CGPoint?
}

private final class MangaPagedReaderPageSurfaceInteraction {
    let edgeRevealRequests = PassthroughSubject<MangaPagedReaderEdgeRevealRequest, Never>()
    let zoomToggleRequests = PassthroughSubject<MangaPagedReaderZoomToggleRequest, Never>()

    private var requestSequence = 0
    private(set) var hiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge> = []
    private(set) var isZoomActive = false

    func updateHiddenEdges(_ hiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge>) {
        self.hiddenEdges = hiddenEdges
    }

    func updateZoomActive(_ isZoomActive: Bool) {
        self.isZoomActive = isZoomActive
    }

    func hasHiddenContent(onPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge) -> Bool {
        hiddenEdges.contains(edge)
    }

    func consumeTap(onPhysicalEdge edge: MangaPagedImageSurfaceHorizontalEdge) -> Bool {
        guard hiddenEdges.contains(edge) else { return false }
        requestSequence += 1
        edgeRevealRequests.send(MangaPagedReaderEdgeRevealRequest(sequence: requestSequence, edge: edge))
        return true
    }

    func requestZoomToggle(at location: CGPoint) {
        requestSequence += 1
        zoomToggleRequests.send(MangaPagedReaderZoomToggleRequest(sequence: requestSequence, location: location))
    }
}

private final class MangaPagedReaderCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?
    var shouldBeginPanGesture: ((UIPanGestureRecognizer) -> Bool)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard super.gestureRecognizerShouldBegin(gestureRecognizer) else {
            return false
        }
        guard gestureRecognizer === panGestureRecognizer,
              let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
              let shouldBeginPanGesture else {
            return true
        }
        return shouldBeginPanGesture(panRecognizer)
    }
}

private extension ReaderPagedPageTurnCell {
    func configure(
        spreadID: String,
        usesTwoPageSpread: Bool,
        leftPageSurface: MangaPagedReaderSpreadPageSurface?,
        rightPageSurface: MangaPagedReaderSpreadPageSurface?,
        imagePipeline: MangaImagePipeline,
        pageScaleMode: MangaPageScaleMode,
        pageEdgeFillStyle: MangaPageEdgeFillStyle,
        isChromeVisible: Bool,
        zoomEnabled: Bool,
        allowsUnzoomedSurfacePan: Bool,
        spreadSurfaceInteraction: MangaPagedReaderPageSurfaceInteraction,
        colorScheme: ColorScheme
    ) {
        let pageEdgeFillColor = pageEdgeFillStyle.uiColor(for: colorScheme)
        backgroundColor = pageEdgeFillColor
        contentView.backgroundColor = pageEdgeFillColor
        contentConfiguration = UIHostingConfiguration {
            MangaPagedReaderSpreadSurface(
                spreadID: spreadID,
                usesTwoPageSpread: usesTwoPageSpread,
                leftPageSurface: leftPageSurface,
                rightPageSurface: rightPageSurface,
                imagePipeline: imagePipeline,
                pageScaleMode: pageScaleMode,
                pageEdgeFillStyle: pageEdgeFillStyle,
                isChromeVisible: isChromeVisible,
                zoomEnabled: zoomEnabled,
                allowsUnzoomedSurfacePan: allowsUnzoomedSurfacePan,
                spreadSurfaceInteraction: spreadSurfaceInteraction
            )
            .ignoresSafeArea(
                .container,
                edges: UIDevice.current.userInterfaceIdiom == .pad ? .vertical : .bottom
            )
        }
        .margins(.all, 0)
    }
}

private struct MangaPagedReaderSpreadPageSurface {
    let page: MangaReaderPageProjection
    let surfaceIdentity: MangaPagedReaderPageAppearanceIdentity
    let initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment
    let surfaceInteraction: MangaPagedReaderPageSurfaceInteraction
}

private struct MangaPagedReaderPageAppearanceIdentity: Hashable {
    let pageID: String
    let appearanceGeneration: Int
}

private struct MangaPagedReaderSpreadSurface: View {
    let spreadID: String
    let usesTwoPageSpread: Bool
    let leftPageSurface: MangaPagedReaderSpreadPageSurface?
    let rightPageSurface: MangaPagedReaderSpreadPageSurface?
    let imagePipeline: MangaImagePipeline
    let pageScaleMode: MangaPageScaleMode
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isChromeVisible: Bool
    let zoomEnabled: Bool
    let allowsUnzoomedSurfacePan: Bool
    let spreadSurfaceInteraction: MangaPagedReaderPageSurfaceInteraction

    var body: some View {
        ZStack {
            pageEdgeFillStyle.color(for: colorScheme)

            if usesTwoPageSpread {
                MangaPagedReaderZoomableSpreadSurface(
                    spreadID: spreadID,
                    leftPageSurface: leftPageSurface,
                    rightPageSurface: rightPageSurface,
                    imagePipeline: imagePipeline,
                    pageScaleMode: pageScaleMode,
                    pageEdgeFillStyle: pageEdgeFillStyle,
                    isChromeVisible: isChromeVisible,
                    isZoomInteractionEnabled: !isChromeVisible && zoomEnabled,
                    spreadSurfaceInteraction: spreadSurfaceInteraction
                )
            } else {
                MangaPagedReaderPageSlot(
                    surface: leftPageSurface ?? rightPageSurface,
                    imagePipeline: imagePipeline,
                    pageScaleMode: pageScaleMode,
                    pageEdgeFillStyle: pageEdgeFillStyle,
                    isChromeVisible: isChromeVisible,
                    zoomEnabled: zoomEnabled,
                    allowsUnzoomedSurfacePan: allowsUnzoomedSurfacePan,
                    isPageZoomEnabled: true
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @Environment(\.colorScheme) private var colorScheme
}

private struct MangaPagedReaderPageSlot: View {
    let surface: MangaPagedReaderSpreadPageSurface?
    let imagePipeline: MangaImagePipeline
    let pageScaleMode: MangaPageScaleMode
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isChromeVisible: Bool
    let zoomEnabled: Bool
    let allowsUnzoomedSurfacePan: Bool
    let isPageZoomEnabled: Bool

    var body: some View {
        ZStack {
            pageEdgeFillStyle.color(for: colorScheme)
            if let surface {
                MangaPagedReaderPageSurface(
                    page: surface.page,
                    surfaceIdentity: surface.surfaceIdentity,
                    imagePipeline: imagePipeline,
                    pageScaleMode: pageScaleMode,
                    initialHorizontalAlignment: surface.initialHorizontalAlignment,
                    pageEdgeFillStyle: pageEdgeFillStyle,
                    isChromeVisible: isChromeVisible,
                    zoomEnabled: zoomEnabled && isPageZoomEnabled,
                    allowsUnzoomedSurfacePan: allowsUnzoomedSurfacePan && isPageZoomEnabled,
                    surfaceInteraction: surface.surfaceInteraction
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @Environment(\.colorScheme) private var colorScheme
}

private struct MangaPagedReaderZoomableSpreadSurface: View {
    let spreadID: String
    let leftPageSurface: MangaPagedReaderSpreadPageSurface?
    let rightPageSurface: MangaPagedReaderSpreadPageSurface?
    let imagePipeline: MangaImagePipeline
    let pageScaleMode: MangaPageScaleMode
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isChromeVisible: Bool
    let isZoomInteractionEnabled: Bool
    let spreadSurfaceInteraction: MangaPagedReaderPageSurfaceInteraction

    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyUserOffset: CGSize = .zero
    @State private var gestureUserOffset: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let layout = spreadSurfaceLayout(containerSize: containerSize, scale: zoomScale)
            let userOffset = proposedUserOffset(layout: layout)
            let displayOffset = layout.displayOffset(forUserOffset: userOffset)
            let hiddenEdges = hiddenHorizontalEdges(layout: layout, userOffset: userOffset)
            let isSurfaceZoomActive = isZoomInteractionEnabled && MangaPageZoomPolicy.isActive(zoomScale)

            ZStack {
                pageEdgeFillStyle.color(for: colorScheme)
                HStack(spacing: 0) {
                    MangaPagedReaderPageSlot(
                        surface: leftPageSurface,
                        imagePipeline: imagePipeline,
                        pageScaleMode: pageScaleMode,
                        pageEdgeFillStyle: pageEdgeFillStyle,
                        isChromeVisible: isChromeVisible,
                        zoomEnabled: false,
                        allowsUnzoomedSurfacePan: false,
                        isPageZoomEnabled: false
                    )
                    MangaPagedReaderPageSlot(
                        surface: rightPageSurface,
                        imagePipeline: imagePipeline,
                        pageScaleMode: pageScaleMode,
                        pageEdgeFillStyle: pageEdgeFillStyle,
                        isChromeVisible: isChromeVisible,
                        zoomEnabled: false,
                        allowsUnzoomedSurfacePan: false,
                        isPageZoomEnabled: false
                    )
                }
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(zoomScale)
                .offset(displayOffset)
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(magnifyGesture(containerSize: containerSize))
            .simultaneousGesture(
                dragGesture(containerSize: containerSize),
                including: surfaceDragGestureMask
            )
            .onChange(of: isZoomInteractionEnabled) { _, isEnabled in
                guard !isEnabled else { return }
                resetZoomState(animated: true)
            }
            .onChange(of: spreadID) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: containerSize) { _, newValue in
                clampSteadyUserOffset(containerSize: newValue)
            }
            .onChange(of: hiddenEdges, initial: true) { _, newValue in
                spreadSurfaceInteraction.updateHiddenEdges(newValue)
            }
            .onChange(of: isSurfaceZoomActive, initial: true) { _, newValue in
                spreadSurfaceInteraction.updateZoomActive(newValue)
            }
            .onReceive(spreadSurfaceInteraction.edgeRevealRequests) { request in
                guard let edge = request.edge else { return }
                revealHiddenContent(on: edge, containerSize: containerSize)
            }
            .onReceive(spreadSurfaceInteraction.zoomToggleRequests) { request in
                guard isZoomInteractionEnabled,
                      let location = request.location else {
                    return
                }
                toggleZoom(at: location, containerSize: containerSize)
            }
            .onDisappear {
                spreadSurfaceInteraction.updateHiddenEdges([])
                spreadSurfaceInteraction.updateZoomActive(false)
            }
        }
    }

    private var zoomScale: CGFloat {
        clampedScale(steadyScale * gestureScale)
    }

    private var surfaceDragGestureMask: GestureMask {
        surfaceDragGestureEnabled ? .gesture : .subviews
    }

    private var surfaceDragGestureEnabled: Bool {
        isZoomInteractionEnabled && MangaPageZoomPolicy.isActive(zoomScale)
    }

    private func magnifyGesture(containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isZoomInteractionEnabled else { return }
                let nextScale = clampedScale(steadyScale * value.magnification)
                gestureScale = nextScale / max(steadyScale, 0.001)
                let layout = spreadSurfaceLayout(containerSize: containerSize, scale: nextScale)
                steadyUserOffset = layout.clampedUserOffset(steadyUserOffset)
            }
            .onEnded { value in
                guard isZoomInteractionEnabled else { return }
                let nextScale = clampedScale(steadyScale * value.magnification)
                steadyScale = nextScale
                gestureScale = 1
                if nextScale <= 1.01 {
                    resetZoomState(animated: true)
                } else {
                    let layout = spreadSurfaceLayout(containerSize: containerSize, scale: nextScale)
                    steadyUserOffset = layout.clampedUserOffset(steadyUserOffset)
                }
            }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard surfaceDragGestureEnabled else { return }
                let layout = spreadSurfaceLayout(containerSize: containerSize, scale: zoomScale)
                let proposed = CGSize(
                    width: steadyUserOffset.width + value.translation.width,
                    height: steadyUserOffset.height + value.translation.height
                )
                let clamped = layout.clampedUserOffset(proposed)
                gestureUserOffset = CGSize(
                    width: clamped.width - steadyUserOffset.width,
                    height: clamped.height - steadyUserOffset.height
                )
            }
            .onEnded { value in
                guard surfaceDragGestureEnabled else {
                    gestureUserOffset = .zero
                    return
                }
                let layout = spreadSurfaceLayout(containerSize: containerSize, scale: steadyScale)
                let proposed = CGSize(
                    width: steadyUserOffset.width + value.translation.width,
                    height: steadyUserOffset.height + value.translation.height
                )
                steadyUserOffset = layout.clampedUserOffset(proposed)
                gestureUserOffset = .zero
            }
    }

    private func toggleZoom(at location: CGPoint, containerSize: CGSize) {
        if MangaPageZoomPolicy.isZoomedForDoubleTapReset(steadyScale) {
            resetZoomState(animated: true)
        } else {
            zoomIn(to: location, containerSize: containerSize)
        }
    }

    private func zoomIn(to location: CGPoint, containerSize: CGSize) {
        let targetScale = MangaPageZoomPolicy.doubleTapTargetScale
        let targetLayout = spreadSurfaceLayout(containerSize: containerSize, scale: targetScale)

        withAnimation(.easeOut(duration: 0.2)) {
            steadyScale = targetScale
            gestureScale = 1
            steadyUserOffset = targetLayout.userOffsetAnchoring(location)
            gestureUserOffset = .zero
        }
    }

    private func revealHiddenContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        containerSize: CGSize
    ) {
        let layout = spreadSurfaceLayout(containerSize: containerSize, scale: zoomScale)
        let userOffset = proposedUserOffset(layout: layout)
        guard let targetUserOffset = layout.userOffsetRevealingContent(on: edge, fromUserOffset: userOffset) else {
            spreadSurfaceInteraction.updateHiddenEdges(hiddenHorizontalEdges(layout: layout, userOffset: userOffset))
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            steadyUserOffset = targetUserOffset
            gestureUserOffset = .zero
        }
    }

    private func resetZoomState(animated: Bool) {
        let updates = {
            steadyScale = 1
            gestureScale = 1
            steadyUserOffset = .zero
            gestureUserOffset = .zero
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2), updates)
        } else {
            updates()
        }
    }

    private func clampSteadyUserOffset(containerSize: CGSize) {
        let layout = spreadSurfaceLayout(containerSize: containerSize, scale: steadyScale)
        steadyUserOffset = layout.clampedUserOffset(steadyUserOffset)
        gestureUserOffset = .zero
    }

    private func proposedUserOffset(layout: MangaPagedSpreadSurfaceZoomLayout) -> CGSize {
        layout.clampedUserOffset(
            CGSize(
                width: steadyUserOffset.width + gestureUserOffset.width,
                height: steadyUserOffset.height + gestureUserOffset.height
            )
        )
    }

    private func hiddenHorizontalEdges(
        layout: MangaPagedSpreadSurfaceZoomLayout,
        userOffset: CGSize
    ) -> Set<MangaPagedImageSurfaceHorizontalEdge> {
        Set(
            MangaPagedImageSurfaceHorizontalEdge.allCases.filter { edge in
                layout.hasHiddenContent(on: edge, fromUserOffset: userOffset)
            }
        )
    }

    private func spreadSurfaceLayout(containerSize: CGSize, scale: CGFloat) -> MangaPagedSpreadSurfaceZoomLayout {
        MangaPagedSpreadSurfaceZoomLayout(
            containerSize: containerSize,
            zoomScale: scale
        )
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        MangaPageZoomPolicy.clampedScale(scale)
    }
}

private struct MangaPagedReaderPageSurface: View {
    let page: MangaReaderPageProjection
    let surfaceIdentity: MangaPagedReaderPageAppearanceIdentity
    let imagePipeline: MangaImagePipeline
    let pageScaleMode: MangaPageScaleMode
    let initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isChromeVisible: Bool
    let zoomEnabled: Bool
    let allowsUnzoomedSurfacePan: Bool
    let surfaceInteraction: MangaPagedReaderPageSurfaceInteraction

    @State private var loadedImage: UIImage?
    @State private var loadedPageID: String?
    @State private var loadingPageID: String?
    @State private var failedPageID: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            pageEdgeFillStyle.color(for: colorScheme)

            if let image = displayedImage {
                MangaPagedReaderScaledImage(
                    image: image,
                    pageID: page.id,
                    pageScaleMode: pageScaleMode,
                    initialHorizontalAlignment: initialHorizontalAlignment,
                    pageEdgeFillStyle: pageEdgeFillStyle,
                    isZoomInteractionEnabled: !isChromeVisible && zoomEnabled,
                    allowsUnzoomedSurfacePan: allowsUnzoomedSurfacePan,
                    surfaceInteraction: surfaceInteraction
                )
                .id(surfaceIdentity)
            } else if loadingPageID == page.id {
                ProgressView()
                    .tint(pageEdgeFillStyle.progressTint(for: colorScheme))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: failedPageID == page.id ? "exclamationmark.triangle" : "photo")
                        .font(.title2.weight(.semibold))
                    Text(failedPageID == page.id ? L10n.string("image.load_failed") : L10n.string("manga.loading"))
                        .font(.caption)
                }
                .foregroundStyle(pageEdgeFillStyle.placeholderForeground(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: page.id) { @MainActor in
            await loadImage()
        }
    }

    private var displayedImage: UIImage? {
        if let cachedImage = imagePipeline.cachedImage(for: page) {
            return cachedImage
        }
        guard loadedPageID == page.id else { return nil }
        return loadedImage
    }

    @MainActor
    private func loadImage() async {
        if let cachedImage = imagePipeline.cachedImage(for: page) {
            loadedImage = cachedImage
            loadedPageID = page.id
            loadingPageID = nil
            failedPageID = nil
            return
        }

        loadingPageID = page.id
        failedPageID = nil

        do {
            let image = try await imagePipeline.image(for: page)
            guard !Task.isCancelled else { return }
            loadedImage = image
            loadedPageID = page.id
            loadingPageID = nil
            failedPageID = nil
        } catch {
            guard !Task.isCancelled else { return }
            if loadedPageID != page.id {
                loadedImage = nil
            }
            loadingPageID = nil
            failedPageID = page.id
        }
    }
}

private struct MangaPagedReaderScaledImage: View {
    let image: UIImage
    let pageID: String
    let pageScaleMode: MangaPageScaleMode
    let initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isZoomInteractionEnabled: Bool
    let allowsUnzoomedSurfacePan: Bool
    let surfaceInteraction: MangaPagedReaderPageSurfaceInteraction

    @State private var steadyScale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var steadyUserOffset: CGSize = .zero
    @State private var gestureUserOffset: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let layout = imageSurfaceLayout(containerSize: containerSize, scale: zoomScale)
            let userOffset = proposedUserOffset(layout: layout)
            let displayOffset = layout.displayOffset(forUserOffset: userOffset)
            let hiddenEdges = hiddenHorizontalEdges(layout: layout, userOffset: userOffset)
            let isSurfaceZoomActive = isZoomInteractionEnabled && MangaPageZoomPolicy.isActive(zoomScale)

            ZStack {
                pageEdgeFillStyle.color(for: colorScheme)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                    .offset(displayOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(magnifyGesture(containerSize: containerSize))
            .simultaneousGesture(
                dragGesture(containerSize: containerSize),
                including: surfaceDragGestureMask
            )
            .onChange(of: isZoomInteractionEnabled) { _, isEnabled in
                guard !isEnabled else { return }
                endSurfaceInteraction(animated: true)
            }
            .onChange(of: pageID) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: pageScaleMode) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: initialHorizontalAlignment) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: containerSize) { _, newValue in
                clampSteadyUserOffset(containerSize: newValue)
            }
            .onChange(of: hiddenEdges, initial: true) { _, newValue in
                surfaceInteraction.updateHiddenEdges(newValue)
            }
            .onChange(of: isSurfaceZoomActive, initial: true) { _, newValue in
                surfaceInteraction.updateZoomActive(newValue)
            }
            .onReceive(surfaceInteraction.edgeRevealRequests) { request in
                guard let edge = request.edge else { return }
                revealHiddenContent(on: edge, containerSize: containerSize)
            }
            .onReceive(surfaceInteraction.zoomToggleRequests) { request in
                guard isZoomInteractionEnabled,
                      let location = request.location else {
                    return
                }
                toggleZoom(at: location, containerSize: containerSize)
            }
            .onDisappear {
                surfaceInteraction.updateHiddenEdges([])
                surfaceInteraction.updateZoomActive(false)
            }
        }
    }

    private var zoomScale: CGFloat {
        clampedScale(steadyScale * gestureScale)
    }

    private var surfaceDragGestureMask: GestureMask {
        surfaceDragGestureEnabled ? .gesture : .subviews
    }

    private var surfaceDragGestureEnabled: Bool {
        isZoomInteractionEnabled && (allowsUnzoomedSurfacePan || MangaPageZoomPolicy.isActive(zoomScale))
    }

    private func magnifyGesture(containerSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isZoomInteractionEnabled else { return }
                let nextScale = clampedScale(steadyScale * value.magnification)
                gestureScale = nextScale / max(steadyScale, 0.001)
                let layout = imageSurfaceLayout(containerSize: containerSize, scale: nextScale)
                steadyUserOffset = layout.clampedUserOffset(steadyUserOffset)
            }
            .onEnded { value in
                guard isZoomInteractionEnabled else { return }
                let nextScale = clampedScale(steadyScale * value.magnification)
                steadyScale = nextScale
                gestureScale = 1
                if nextScale <= 1.01 {
                    resetZoomState(animated: true)
                } else {
                    let layout = imageSurfaceLayout(containerSize: containerSize, scale: nextScale)
                    steadyUserOffset = layout.clampedUserOffset(steadyUserOffset)
                }
            }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(
            minimumDistance: MangaPagedSurfaceDragIntent.minimumUnzoomedHorizontalTranslation,
            coordinateSpace: .local
        )
            .onChanged { value in
                guard surfaceDragGestureEnabled,
                      let translation = surfaceDragTranslation(value.translation) else {
                    return
                }
                let layout = imageSurfaceLayout(containerSize: containerSize, scale: zoomScale)
                let proposed = CGSize(
                    width: steadyUserOffset.width + translation.width,
                    height: steadyUserOffset.height + translation.height
                )
                let clamped = layout.clampedUserOffset(proposed)
                gestureUserOffset = CGSize(
                    width: clamped.width - steadyUserOffset.width,
                    height: clamped.height - steadyUserOffset.height
                )
            }
            .onEnded { value in
                guard surfaceDragGestureEnabled,
                      let translation = surfaceDragTranslation(value.translation) else {
                    gestureUserOffset = .zero
                    return
                }
                let layout = imageSurfaceLayout(containerSize: containerSize, scale: steadyScale)
                let proposed = CGSize(
                    width: steadyUserOffset.width + translation.width,
                    height: steadyUserOffset.height + translation.height
                )
                steadyUserOffset = layout.clampedUserOffset(proposed)
                gestureUserOffset = .zero
            }
    }

    private func surfaceDragTranslation(_ translation: CGSize) -> CGSize? {
        if MangaPageZoomPolicy.isActive(zoomScale) {
            return translation
        }
        guard allowsUnzoomedSurfacePan else { return nil }
        return MangaPagedSurfaceDragIntent.unzoomedHorizontalTranslation(translation)
    }

    private func toggleZoom(at location: CGPoint, containerSize: CGSize) {
        if MangaPageZoomPolicy.isZoomedForDoubleTapReset(steadyScale) {
            resetZoomState(animated: true)
        } else {
            zoomIn(to: location, containerSize: containerSize)
        }
    }

    private func zoomIn(to location: CGPoint, containerSize: CGSize) {
        let targetScale = MangaPageZoomPolicy.doubleTapTargetScale
        let targetLayout = imageSurfaceLayout(containerSize: containerSize, scale: targetScale)
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let targetLocation = CGRect(origin: .zero, size: containerSize).contains(location)
            ? location
            : center
        let proposedDisplayOffset = CGSize(
            width: -(targetLocation.x - center.x) * targetScale,
            height: -(targetLocation.y - center.y) * targetScale
        )
        let proposedUserOffset = CGSize(
            width: proposedDisplayOffset.width - targetLayout.restingOffset.width,
            height: proposedDisplayOffset.height - targetLayout.restingOffset.height
        )

        withAnimation(.easeOut(duration: 0.2)) {
            steadyScale = targetScale
            gestureScale = 1
            steadyUserOffset = targetLayout.clampedUserOffset(proposedUserOffset)
            gestureUserOffset = .zero
        }
    }

    private func revealHiddenContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        containerSize: CGSize
    ) {
        let layout = imageSurfaceLayout(containerSize: containerSize, scale: zoomScale)
        let userOffset = proposedUserOffset(layout: layout)
        guard let targetUserOffset = layout.userOffsetRevealingContent(on: edge, fromUserOffset: userOffset) else {
            surfaceInteraction.updateHiddenEdges(hiddenHorizontalEdges(layout: layout, userOffset: userOffset))
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            steadyUserOffset = targetUserOffset
            gestureUserOffset = .zero
        }
    }

    private func resetZoomState(animated: Bool) {
        let updates = {
            steadyScale = 1
            gestureScale = 1
            steadyUserOffset = .zero
            gestureUserOffset = .zero
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2), updates)
        } else {
            updates()
        }
    }

    private func endSurfaceInteraction(animated: Bool) {
        guard MangaPagedSurfaceDragIntent.shouldResetOffsetWhenInteractionDisables(zoomScale: zoomScale) else {
            gestureScale = 1
            gestureUserOffset = .zero
            return
        }
        resetZoomState(animated: animated)
    }

    private func clampSteadyUserOffset(containerSize: CGSize) {
        let layout = imageSurfaceLayout(containerSize: containerSize, scale: steadyScale)
        steadyUserOffset = layout.clampedUserOffset(steadyUserOffset)
        gestureUserOffset = .zero
    }

    private func proposedUserOffset(layout: MangaPagedImageSurfaceLayout) -> CGSize {
        layout.clampedUserOffset(
            CGSize(
                width: steadyUserOffset.width + gestureUserOffset.width,
                height: steadyUserOffset.height + gestureUserOffset.height
            )
        )
    }

    private func hiddenHorizontalEdges(
        layout: MangaPagedImageSurfaceLayout,
        userOffset: CGSize
    ) -> Set<MangaPagedImageSurfaceHorizontalEdge> {
        Set(
            MangaPagedImageSurfaceHorizontalEdge.allCases.filter { edge in
                layout.hasHiddenContent(on: edge, fromUserOffset: userOffset)
            }
        )
    }

    private func imageSurfaceLayout(containerSize: CGSize, scale: CGFloat) -> MangaPagedImageSurfaceLayout {
        MangaPagedImageSurfaceLayout(
            imageSize: image.size,
            containerSize: containerSize,
            pageScaleMode: pageScaleMode,
            initialHorizontalAlignment: initialHorizontalAlignment,
            zoomScale: scale
        )
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        MangaPageZoomPolicy.clampedScale(scale)
    }
}

private extension MangaPageEdgeFillStyle {
    func color(for colorScheme: ColorScheme) -> Color {
        Color(uiColor: uiColor(for: colorScheme))
    }

    func uiColor(for colorScheme: ColorScheme) -> UIColor {
        switch self {
        case .white:
            .white
        case .black:
            .black
        case .system:
            colorScheme == .dark ? .black : .white
        }
    }

    func progressTint(for colorScheme: ColorScheme) -> Color {
        usesLightFill(for: colorScheme) ? .black : .white
    }

    func placeholderForeground(for colorScheme: ColorScheme) -> Color {
        usesLightFill(for: colorScheme) ? Color.black.opacity(0.62) : Color.white.opacity(0.68)
    }

    private func usesLightFill(for colorScheme: ColorScheme) -> Bool {
        switch self {
        case .white:
            true
        case .black:
            false
        case .system:
            colorScheme != .dark
        }
    }
}

private extension MangaPageTurnDirection {
    var horizontalNavigationDirection: ReaderPagedHorizontalNavigationDirection {
        switch self {
        case .rightToLeft:
            .rightSwipeAdvances
        case .leftToRight:
            .leftSwipeAdvances
        }
    }
}
#endif
