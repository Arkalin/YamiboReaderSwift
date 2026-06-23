import SwiftUI
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
        collectionView.backgroundColor = pageEdgeFillColor
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(ReaderPagedPageTurnCell.self, forCellWithReuseIdentifier: Coordinator.reuseIdentifier)
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.applyInitialPlacementIfNeeded(in: collectionView)
            coordinator?.applyViewportPlacementIfNeeded(in: collectionView)
        }
        context.coordinator.tapGesture.cancelsTouchesInView = false
        context.coordinator.tapGesture.delegate = context.coordinator
        collectionView.addGestureRecognizer(context.coordinator.tapGesture)
        context.coordinator.quickFadePanGesture.delegate = context.coordinator
        collectionView.addGestureRecognizer(context.coordinator.quickFadePanGesture)
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
        private var pendingInitialPageIndex: Int?
        private var lastReportedGlobalIndex: Int?
        private var lastAppliedPlacementRevision: Int?
        lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        lazy var quickFadePanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleQuickFadePan(_:)))

        var callbackScheduler: SwiftUIViewUpdateCallbackScheduler {
            pagingDriver.callbackScheduler
        }

        private var pagingInputs: ReaderPagedViewportPagingInputs {
            pagingInputs(selectionPageIndex: parent.plan.currentPageIndex)
        }

        private func pagingInputs(selectionPageIndex: Int?) -> ReaderPagedViewportPagingInputs {
            let pageIndex = parent.plan.clampedPageIndex(selectionPageIndex) ?? 0
            return ReaderPagedViewportPagingInputs(
                itemCount: parent.plan.pages.count,
                selectionIndex: pageIndex,
                pagedTurnStyle: parent.settings.pagedTurnStyle,
                horizontalNavigationDirection: parent.settings.pageTurnDirection.horizontalNavigationDirection,
                pagerIdentity: ReaderPagedPagerIdentity(
                    visibleView: pageIndex + 1,
                    surfaceCount: parent.plan.pages.count,
                    spreadCount: parent.plan.pages.count,
                    usesTwoPageSpread: false,
                    layout: .zero
                ),
                scrollAnimationRequest: nil,
                canBoundaryPageTurn: { _ in false },
                onSelectionChange: { [weak self] pageIndex in
                    self?.publishCurrentPageIfNeeded(pageIndex: pageIndex)
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
                itemIndexForSelectionIndex: { [weak self] pageIndex in
                    self?.viewportIndex(forPageIndex: pageIndex) ?? pageIndex
                },
                selectionIndexForItemIndex: { [weak self] viewportIndex in
                    self?.pageIndex(forViewportIndex: viewportIndex) ?? viewportIndex
                }
            )
        }

        init(parent: MangaPagedReaderViewport) {
            self.parent = parent
        }

        func updateContentIfNeeded(in collectionView: UICollectionView) {
            let nextIdentity = MangaPagedReaderContentIdentity(
                pageIDs: parent.plan.pages.map(\.id),
                pageScaleMode: parent.settings.pageScaleMode,
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
            lastReportedGlobalIndex = nil
            if parent.plan.pages.isEmpty {
                pendingInitialPageIndex = nil
                collectionView.alpha = 1
            } else {
                pendingInitialPageIndex = parent.plan.clampedPageIndex(
                    parent.viewportPlacement?.targetPageIndex ?? parent.plan.currentPageIndex
                )
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

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.plan.pages.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.reuseIdentifier,
                for: indexPath
            )
            let pageIndex = pageIndex(forViewportIndex: indexPath.item)
            guard let cell = cell as? ReaderPagedPageTurnCell,
                  parent.plan.pages.indices.contains(pageIndex) else {
                return cell
            }

            cell.configure(
                page: parent.plan.pages[pageIndex],
                imagePipeline: parent.imagePipeline,
                pageScaleMode: parent.settings.pageScaleMode,
                pageTurnDirection: parent.settings.pageTurnDirection,
                pageEdgeFillStyle: parent.settings.pageEdgeFillStyle,
                isChromeVisible: parent.isChromeVisible,
                zoomEnabled: parent.zoomEnabled,
                colorScheme: parent.colorScheme
            )
            cell.resetPageTurnVisuals()
            return cell
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
            guard let targetIndex = pendingInitialPageIndex else { return }
            guard parent.plan.pages.indices.contains(targetIndex) else {
                pendingInitialPageIndex = nil
                collectionView.alpha = 1
                return
            }
            guard collectionView.bounds.width > 0, collectionView.bounds.height > 0 else {
                return
            }
            let targetViewportIndex = viewportIndex(forPageIndex: targetIndex)

            collectionView.scrollToItem(
                at: IndexPath(item: targetViewportIndex, section: 0),
                at: .centeredHorizontally,
                animated: false
            )
            lastAppliedPlacementRevision = parent.viewportPlacement?.revision
            pendingInitialPageIndex = nil
            collectionView.alpha = 1
            publishCurrentPageIfNeeded(from: collectionView)
            updateGestureState(in: collectionView)
        }

        func applyViewportPlacementIfNeeded(in collectionView: UICollectionView) {
            guard pendingInitialPageIndex == nil,
                  let placement = parent.viewportPlacement,
                  placement.revision != lastAppliedPlacementRevision else {
                return
            }
            guard let targetIndex = parent.plan.clampedPageIndex(placement.targetPageIndex),
                  parent.plan.pages.indices.contains(targetIndex),
                  collectionView.bounds.width > 0,
                  collectionView.bounds.height > 0 else {
                return
            }

            let targetViewportIndex = viewportIndex(forPageIndex: targetIndex)
            let placementInputs = pagingInputs(selectionPageIndex: targetIndex)
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
                publishCurrentPageIfNeeded(pageIndex: targetIndex)
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

        @objc private func handleQuickFadePan(_ recognizer: UIPanGestureRecognizer) {
            guard !parent.isChromeVisible else { return }
            pagingDriver.handleQuickFadePan(recognizer, inputs: pagingInputs)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touch.view?.isDescendant(ofType: UIControl.self) != true
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
            return !parent.isChromeVisible &&
                pagingDriver.quickFadePanShouldBegin(panRecognizer, inputs: pagingInputs)
        }

        func updateGestureState(in collectionView: UICollectionView) {
            pagingDriver.updateGestureState(in: collectionView, inputs: pagingInputs)
            if parent.isChromeVisible {
                collectionView.panGestureRecognizer.isEnabled = false
            }
            quickFadePanGesture.isEnabled = !parent.isChromeVisible && parent.settings.pagedTurnStyle == .quickFade
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
                let pageIndex = pageIndex(forViewportIndex: indexPath.item)
                guard parent.plan.pages.indices.contains(pageIndex) else { continue }

                cell.configure(
                    page: parent.plan.pages[pageIndex],
                    imagePipeline: parent.imagePipeline,
                    pageScaleMode: parent.settings.pageScaleMode,
                    pageTurnDirection: parent.settings.pageTurnDirection,
                    pageEdgeFillStyle: parent.settings.pageEdgeFillStyle,
                    isChromeVisible: parent.isChromeVisible,
                    zoomEnabled: parent.zoomEnabled,
                    colorScheme: parent.colorScheme
                )
                cell.resetPageTurnVisuals()
            }
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

        private func publishCurrentPageIfNeeded(pageIndex: Int) {
            guard let globalIndex = parent.plan.globalIndex(forPageAt: pageIndex),
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
            guard let pageIndex = currentPageIndex(in: collectionView),
                  parent.plan.pages.indices.contains(pageIndex) else {
                return
            }
            publishCurrentPageIfNeeded(pageIndex: pageIndex)
        }

        private func currentPageIndex(in collectionView: UICollectionView) -> Int? {
            guard collectionView.bounds.width > 0 else {
                return parent.plan.currentPageIndex
            }
            let rawIndex = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
            return parent.plan.clampedPageIndex(pageIndex(forViewportIndex: rawIndex))
        }

        private func viewportIndex(forPageIndex pageIndex: Int) -> Int {
            guard !parent.plan.pages.isEmpty,
                  let clampedPageIndex = parent.plan.clampedPageIndex(pageIndex) else {
                return 0
            }
            switch parent.settings.pageTurnDirection {
            case .leftToRight:
                return clampedPageIndex
            case .rightToLeft:
                return parent.plan.pages.count - 1 - clampedPageIndex
            }
        }

        private func pageIndex(forViewportIndex viewportIndex: Int) -> Int {
            guard !parent.plan.pages.isEmpty else { return 0 }
            let clampedViewportIndex = min(max(viewportIndex, 0), parent.plan.pages.count - 1)
            switch parent.settings.pageTurnDirection {
            case .leftToRight:
                return clampedViewportIndex
            case .rightToLeft:
                return parent.plan.pages.count - 1 - clampedViewportIndex
            }
        }
    }
}

private struct MangaPagedReaderContentIdentity: Equatable {
    var pageIDs: [String]
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

private final class MangaPagedReaderCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

private extension ReaderPagedPageTurnCell {
    func configure(
        page: MangaReaderPageProjection,
        imagePipeline: MangaImagePipeline,
        pageScaleMode: MangaPageScaleMode,
        pageTurnDirection: MangaPageTurnDirection,
        pageEdgeFillStyle: MangaPageEdgeFillStyle,
        isChromeVisible: Bool,
        zoomEnabled: Bool,
        colorScheme: ColorScheme
    ) {
        let pageEdgeFillColor = pageEdgeFillStyle.uiColor(for: colorScheme)
        backgroundColor = pageEdgeFillColor
        contentView.backgroundColor = pageEdgeFillColor
        contentConfiguration = UIHostingConfiguration {
            MangaPagedReaderPageSurface(
                page: page,
                imagePipeline: imagePipeline,
                pageScaleMode: pageScaleMode,
                pageTurnDirection: pageTurnDirection,
                pageEdgeFillStyle: pageEdgeFillStyle,
                isChromeVisible: isChromeVisible,
                zoomEnabled: zoomEnabled
            )
        }
        .margins(.all, 0)
    }
}

private struct MangaPagedReaderPageSurface: View {
    let page: MangaReaderPageProjection
    let imagePipeline: MangaImagePipeline
    let pageScaleMode: MangaPageScaleMode
    let pageTurnDirection: MangaPageTurnDirection
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isChromeVisible: Bool
    let zoomEnabled: Bool

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
                    pageTurnDirection: pageTurnDirection,
                    pageEdgeFillStyle: pageEdgeFillStyle,
                    isZoomInteractionEnabled: !isChromeVisible && zoomEnabled
                )
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
    private static let maximumZoomScale: CGFloat = 4
    private static let doubleTapZoomScale: CGFloat = 2

    let image: UIImage
    let pageID: String
    let pageScaleMode: MangaPageScaleMode
    let pageTurnDirection: MangaPageTurnDirection
    let pageEdgeFillStyle: MangaPageEdgeFillStyle
    let isZoomInteractionEnabled: Bool

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
            .simultaneousGesture(doubleTapGesture(containerSize: containerSize))
            .simultaneousGesture(magnifyGesture(containerSize: containerSize))
            .simultaneousGesture(dragGesture(containerSize: containerSize))
            .onChange(of: isZoomInteractionEnabled) { _, isEnabled in
                guard !isEnabled else { return }
                resetZoomState(animated: true)
            }
            .onChange(of: pageID) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: pageScaleMode) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: pageTurnDirection) { _, _ in
                resetZoomState(animated: false)
            }
            .onChange(of: containerSize) { _, newValue in
                clampSteadyUserOffset(containerSize: newValue)
            }
        }
    }

    private var zoomScale: CGFloat {
        clampedScale(steadyScale * gestureScale)
    }

    private func doubleTapGesture(containerSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded { value in
                guard isZoomInteractionEnabled else { return }
                if steadyScale > 1.05 {
                    resetZoomState(animated: true)
                } else {
                    zoomIn(to: value.location, containerSize: containerSize)
                }
            }
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
        DragGesture()
            .onChanged { value in
                guard isZoomInteractionEnabled else { return }
                let layout = imageSurfaceLayout(containerSize: containerSize, scale: zoomScale)
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
                guard isZoomInteractionEnabled else { return }
                let layout = imageSurfaceLayout(containerSize: containerSize, scale: steadyScale)
                let proposed = CGSize(
                    width: steadyUserOffset.width + value.translation.width,
                    height: steadyUserOffset.height + value.translation.height
                )
                steadyUserOffset = layout.clampedUserOffset(proposed)
                gestureUserOffset = .zero
            }
    }

    private func zoomIn(to location: CGPoint, containerSize: CGSize) {
        let targetScale = min(Self.maximumZoomScale, Self.doubleTapZoomScale)
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

    private func imageSurfaceLayout(containerSize: CGSize, scale: CGFloat) -> MangaPagedImageSurfaceLayout {
        MangaPagedImageSurfaceLayout(
            imageSize: image.size,
            containerSize: containerSize,
            pageScaleMode: pageScaleMode,
            pageTurnDirection: pageTurnDirection,
            zoomScale: scale
        )
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(Self.maximumZoomScale, max(1, scale))
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
