import SwiftUI
import YamiboReaderCore

struct ReaderPagedPageCurlLeaf: Hashable {
    enum Kind: Hashable {
        case surface(Int)
        case blank
    }

    var index: Int
    var kind: Kind
    var selectionIndex: Int

    var surfaceIndex: Int? {
        guard case let .surface(surfaceIndex) = kind else { return nil }
        return surfaceIndex
    }
}

struct ReaderPagedPageCurlSequence: Equatable {
    var leaves: [ReaderPagedPageCurlLeaf]
    var usesTwoPageSpread: Bool

    init(
        surfaces: [NovelReaderSurface],
        spreads: [NovelReaderPresentationSpread],
        usesTwoPageSpread: Bool,
        pageTurnDirection: ReaderPageTurnDirection = .leftToRight
    ) {
        self.usesTwoPageSpread = usesTwoPageSpread
        if usesTwoPageSpread {
            let leafGroups = spreads.map { spread in
                [
                    ReaderPagedPageCurlLeaf(
                        index: 0,
                        kind: .surface(spread.leftSurfaceIndex),
                        selectionIndex: spread.index
                    ),
                    ReaderPagedPageCurlLeaf(
                        index: 0,
                        kind: spread.rightSurfaceIndex.map(ReaderPagedPageCurlLeaf.Kind.surface) ?? .blank,
                        selectionIndex: spread.index
                    ),
                ]
            }
            let orderedLeaves = Self.physicalBookOrder(
                leafGroups: leafGroups,
                pageTurnDirection: pageTurnDirection
            )
            leaves = orderedLeaves.isEmpty ? Self.emptySpreadLeaves : Self.indexedLeaves(from: orderedLeaves)
        } else {
            let leafGroups = surfaces.indices.map { index in
                [
                    ReaderPagedPageCurlLeaf(
                        index: 0,
                        kind: .surface(index),
                        selectionIndex: index
                    ),
                ]
            }
            let orderedLeaves = Self.physicalBookOrder(
                leafGroups: leafGroups,
                pageTurnDirection: pageTurnDirection
            )
            leaves = orderedLeaves.isEmpty ? [Self.emptySingleLeaf] : Self.indexedLeaves(from: orderedLeaves)
        }
    }

    private static var emptySingleLeaf: ReaderPagedPageCurlLeaf {
        ReaderPagedPageCurlLeaf(index: 0, kind: .blank, selectionIndex: 0)
    }

    private static var emptySpreadLeaves: [ReaderPagedPageCurlLeaf] {
        [
            ReaderPagedPageCurlLeaf(index: 0, kind: .blank, selectionIndex: 0),
            ReaderPagedPageCurlLeaf(index: 1, kind: .blank, selectionIndex: 0)
        ]
    }

    var pageCount: Int {
        usesTwoPageSpread ? leaves.count / 2 : leaves.count
    }

    func leafIndexes(forSelectionIndex selectionIndex: Int) -> [Int] {
        guard !leaves.isEmpty else { return [] }
        let clampedSelection = min(max(selectionIndex, 0), max(pageCount - 1, 0))
        let indexes = leaves
            .filter { $0.selectionIndex == clampedSelection }
            .map(\.index)
        if indexes.isEmpty {
            return usesTwoPageSpread ? [0, 1].filter { leaves.indices.contains($0) } : [0]
        }
        return indexes
    }

    func selectionIndex(forLeafIndexes leafIndexes: [Int]) -> Int? {
        leafIndexes
            .compactMap { leaves.indices.contains($0) ? leaves[$0].selectionIndex : nil }
            .min()
    }

    func firstLeafIndex(forSelectionIndex selectionIndex: Int) -> Int? {
        leafIndexes(forSelectionIndex: selectionIndex).first
    }

    private static func physicalBookOrder(
        leafGroups: [[ReaderPagedPageCurlLeaf]],
        pageTurnDirection: ReaderPageTurnDirection
    ) -> [ReaderPagedPageCurlLeaf] {
        switch pageTurnDirection {
        case .leftToRight:
            leafGroups.flatMap { $0 }
        case .rightToLeft:
            leafGroups.reversed().flatMap { $0 }
        }
    }

    private static func indexedLeaves(from leaves: [ReaderPagedPageCurlLeaf]) -> [ReaderPagedPageCurlLeaf] {
        leaves.enumerated().map { index, leaf in
            ReaderPagedPageCurlLeaf(
                index: index,
                kind: leaf.kind,
                selectionIndex: leaf.selectionIndex
            )
        }
    }
}

#if os(iOS)
import UIKit

struct ReaderPagedPageCurlViewport: UIViewControllerRepresentable {
    let spreads: [NovelReaderPresentationSpread]
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
    let topInset: CGFloat
    let bottomInset: CGFloat
    let selectionIndex: Int
    let usesTwoPageSpread: Bool
    let pagerIdentity: ReaderPagedPagerIdentity
    let scrollAnimationRequest: ReaderPagedScrollAnimationRequest?
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let isChromeVisible: Bool
    let canBoundaryPageTurn: (Int) -> Bool
    let onSelectionChange: (Int) -> Void
    let onBoundaryPageTurn: (Int) -> Void
    let onPageTapZone: (ReaderPagedTapZone) -> Void
    let onScrollAnimationRequestConsumed: (ReaderPagedScrollAnimationRequest) -> Void
    let onChromeVisibleImageTap: () -> Void
    let onImageTap: (URL, String?) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var pageBackgroundColor: UIColor {
        readerThemeUIColor(for: settings.backgroundStyle, colorScheme: colorScheme)
    }

    private var sequence: ReaderPagedPageCurlSequence {
        ReaderPagedPageCurlSequence(
            surfaces: surfaces,
            spreads: spreads,
            usesTwoPageSpread: usesTwoPageSpread,
            pageTurnDirection: settings.pageTurnDirection
        )
    }

    private var contentIdentity: ReaderPagedSpreadViewportContentIdentity {
        ReaderPagedSpreadViewportContentIdentity(
            spreads: spreads,
            content: ReaderPagedViewportContentIdentity(
                surfaces: surfaces,
                settings: settings,
                refererURL: refererURL,
                imageCacheNamespace: imageCacheNamespace,
                topInset: topInset,
                bottomInset: bottomInset
            )
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let spineLocation: UIPageViewController.SpineLocation = sequence.usesTwoPageSpread ? .mid : .min
        let pageViewController = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: spineLocation.rawValue]
        )
        pageViewController.dataSource = context.coordinator
        pageViewController.delegate = context.coordinator
        pageViewController.view.backgroundColor = pageBackgroundColor
        pageViewController.view.isOpaque = true

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        pageViewController.view.addGestureRecognizer(tapRecognizer)

        let boundaryPageTurnPanRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleBoundaryPageTurnPan(_:))
        )
        boundaryPageTurnPanRecognizer.delegate = context.coordinator
        pageViewController.view.addGestureRecognizer(boundaryPageTurnPanRecognizer)
        context.coordinator.boundaryPageTurnPanRecognizer = boundaryPageTurnPanRecognizer

        context.coordinator.applyPageBackground(to: pageViewController)
        context.coordinator.configureGestures(in: pageViewController)
        context.coordinator.configureSpine(in: pageViewController)
        context.coordinator.setCurrentSelection(in: pageViewController, animated: false)
        selectionController?.configure(mode: .paged)
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        selectionController?.configure(mode: .paged)
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.update(
                pageViewController,
                contentIdentity: contentIdentity
            )
            context.coordinator.applyPageBackground(to: pageViewController)
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: ReaderPagedPageCurlViewport
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var contentIdentity: ReaderPagedSpreadViewportContentIdentity?
        private var consumedScrollAnimationRequestID: UUID?
        private var currentSelectionIndex: Int?
        private weak var pageCurlBackColorPageViewController: UIPageViewController?
        weak var boundaryPageTurnPanRecognizer: UIPanGestureRecognizer?
        private var pageCurlBackColorDisplayLink: CADisplayLink?

        init(parent: ReaderPagedPageCurlViewport) {
            self.parent = parent
        }

        deinit {
            MainActor.assumeIsolated {
                stopPageCurlBackColorRefresh()
            }
        }

        func update(
            _ pageViewController: UIPageViewController,
            contentIdentity nextContentIdentity: ReaderPagedSpreadViewportContentIdentity
        ) {
            let didChangeContentIdentity = contentIdentity != nextContentIdentity
            contentIdentity = nextContentIdentity
            configureGestures(in: pageViewController)
            configureSpine(in: pageViewController)
            applyPageBackground(to: pageViewController)

            if let animationRequest = matchingScrollAnimationRequest() {
                setCurrentSelection(in: pageViewController, animated: true) { [weak self] in
                    self?.consumeScrollAnimationRequest(animationRequest)
                }
                return
            }

            if didChangeContentIdentity || currentSelectionIndex != parent.selectionIndex {
                setCurrentSelection(in: pageViewController, animated: false)
            }
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let pageController = viewController as? ReaderPagedPageCurlHostingController else {
                return nil
            }
            return controller(forLeafIndex: pageController.leaf.index - 1)
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let pageController = viewController as? ReaderPagedPageCurlHostingController else {
                return nil
            }
            return controller(forLeafIndex: pageController.leaf.index + 1)
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
            configureSpine(in: pageViewController)
            setCurrentSelection(in: pageViewController, animated: false)
            return parent.sequence.usesTwoPageSpread ? .mid : .min
        }

        func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            stopPageCurlBackColorRefresh()
            guard completed else { return }
            publishSelection(from: pageViewController)
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let containerView = recognizer.view else {
                return
            }
            let location = recognizer.location(in: containerView)
            if parent.selectionController?.hasSelection == true {
                parent.selectionController?.clearSelection()
                return
            }
            if let imageView = containerView.firstDescendant(
                ofType: ReaderVerticalViewportImageView.self,
                containing: location
            ) {
                let imageLocation = containerView.convert(location, to: imageView)
                handleImageTap(imageView, at: imageLocation)
                return
            }

            let zone = ReaderPagedTapZone.zone(for: location, in: containerView.bounds)
            let directionalZone = parent.settings.pageTurnDirection.directionalTapZone(for: zone)
            let onPageTapZone = parent.onPageTapZone
            callbackScheduler.publish {
                onPageTapZone(directionalZone)
            }
        }

        @objc
        func handleBoundaryPageTurnPan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended,
                  !parent.isChromeVisible,
                  let view = recognizer.view else {
                return
            }
            guard let delta = ReaderPagedBoundaryPageTurn.boundaryDelta(
                selectionIndex: parent.selectionIndex,
                itemCount: parent.sequence.pageCount,
                translation: recognizer.translation(in: view),
                velocity: recognizer.velocity(in: view),
                viewportWidth: view.bounds.width,
                horizontalNavigationDirection: parent.settings.pageTurnDirection.horizontalNavigationDirection,
                canBoundaryPageTurn: parent.canBoundaryPageTurn
            ) else {
                return
            }
            let onBoundaryPageTurn = parent.onBoundaryPageTurn
            callbackScheduler.publish {
                onBoundaryPageTurn(delta)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if gestureRecognizer === boundaryPageTurnPanRecognizer ||
                otherGestureRecognizer === boundaryPageTurnPanRecognizer {
                return true
            }
            return otherGestureRecognizer.view?.isDescendant(ofType: ReaderVerticalViewportImageView.self) == true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === boundaryPageTurnPanRecognizer,
                  let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
                  !parent.isChromeVisible,
                  let view = panRecognizer.view else {
                return true
            }
            let velocity = panRecognizer.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            let physicalDelta = velocity.x < 0 ? 1 : -1
            let delta = ReaderPagedBoundaryPageTurn.directionalDelta(
                physicalDelta,
                direction: parent.settings.pageTurnDirection.horizontalNavigationDirection
            )
            let targetItem = parent.selectionIndex + delta
            guard targetItem < 0 || targetItem >= parent.sequence.pageCount else { return true }
            return parent.canBoundaryPageTurn(delta)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            true
        }

        func configureSpine(in pageViewController: UIPageViewController) {
            pageViewController.isDoubleSided = parent.sequence.usesTwoPageSpread
        }

        func configureGestures(in pageViewController: UIPageViewController) {
            for recognizer in pageViewController.gestureRecognizers {
                if recognizer is UITapGestureRecognizer {
                    recognizer.isEnabled = false
                } else if recognizer is UIPanGestureRecognizer {
                    recognizer.isEnabled = !parent.isChromeVisible
                }
            }
            boundaryPageTurnPanRecognizer?.isEnabled = !parent.isChromeVisible
        }

        func setCurrentSelection(
            in pageViewController: UIPageViewController,
            animated: Bool,
            completion: (() -> Void)? = nil
        ) {
            let leafIndexes = parent.sequence.leafIndexes(forSelectionIndex: parent.selectionIndex)
            let controllers = leafIndexes.compactMap(controller(forLeafIndex:))
            guard !controllers.isEmpty else {
                currentSelectionIndex = nil
                completion?()
                return
            }

            let direction: UIPageViewController.NavigationDirection = {
                guard let currentSelectionIndex,
                      let currentLeafIndex = parent.sequence.firstLeafIndex(forSelectionIndex: currentSelectionIndex),
                      let targetLeafIndex = parent.sequence.firstLeafIndex(forSelectionIndex: parent.selectionIndex) else {
                    return .forward
                }
                return targetLeafIndex >= currentLeafIndex ? .forward : .reverse
            }()

            pageViewController.setViewControllers(
                controllers,
                direction: direction,
                animated: animated
            ) { [weak self] completed in
                guard let self else { return }
                if animated {
                    self.stopPageCurlBackColorRefresh()
                }
                if !animated || completed {
                    self.currentSelectionIndex = self.parent.selectionIndex
                }
                completion?()
            }
            if animated {
                startPageCurlBackColorRefresh(in: pageViewController)
            }
            if !animated {
                currentSelectionIndex = parent.selectionIndex
            }
        }

        private func controller(forLeafIndex leafIndex: Int) -> UIViewController? {
            guard parent.sequence.leaves.indices.contains(leafIndex) else { return nil }
            let leaf = parent.sequence.leaves[leafIndex]
            return ReaderPagedPageCurlHostingController(
                leaf: leaf,
                rootView: ReaderPagedPageCurlLeafView(
                    leaf: leaf,
                    surfaces: parent.surfaces,
                    settings: parent.settings,
                    refererURL: parent.refererURL,
                    imageDataLoader: parent.imageDataLoader,
                    imageCacheNamespace: parent.imageCacheNamespace,
                    topInset: parent.topInset,
                    bottomInset: parent.bottomInset,
                    displayReferenceProvider: parent.displayReferenceProvider,
                    selectionController: parent.selectionController,
                    onImageTap: parent.onImageTap
                ),
                pageBackgroundColor: parent.pageBackgroundColor
            )
        }

        func applyPageBackground(to pageViewController: UIPageViewController) {
            let pageBackgroundColor = parent.pageBackgroundColor
            pageViewController.view.backgroundColor = pageBackgroundColor
            pageViewController.view.isOpaque = true
            for case let controller as ReaderPagedPageCurlHostingController in pageViewController.viewControllers ?? [] {
                controller.applyPageBackground(pageBackgroundColor)
            }
            if !parent.sequence.usesTwoPageSpread {
                ReaderPageCurlPrivateBackColor.apply(to: pageViewController.view, backColor: pageBackgroundColor)
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
                .compactMap { ($0 as? ReaderPagedPageCurlHostingController)?.leaf.index } ?? []
            guard let selectionIndex = parent.sequence.selectionIndex(forLeafIndexes: leafIndexes) else { return }
            currentSelectionIndex = selectionIndex
            guard selectionIndex != parent.selectionIndex else { return }
            let onSelectionChange = parent.onSelectionChange
            callbackScheduler.publish {
                onSelectionChange(selectionIndex)
            }
        }

        private func handleImageTap(_ imageView: ReaderVerticalViewportImageView, at location: CGPoint) {
            if parent.isChromeVisible {
                let onChromeVisibleImageTap = parent.onChromeVisibleImageTap
                callbackScheduler.publish {
                    onChromeVisibleImageTap()
                }
                return
            }

            guard let payload = imageView.imageTapPayloadIfHit(at: location) else { return }
            let onImageTap = parent.onImageTap
            callbackScheduler.publish {
                onImageTap(payload.url, payload.title)
            }
        }

        private func matchingScrollAnimationRequest() -> ReaderPagedScrollAnimationRequest? {
            guard let request = parent.scrollAnimationRequest,
                  request.id != consumedScrollAnimationRequestID,
                  request.pagerIdentity == parent.pagerIdentity,
                  request.selectionIndex == parent.selectionIndex else {
                return nil
            }
            return request
        }

        private func consumeScrollAnimationRequest(_ request: ReaderPagedScrollAnimationRequest) {
            consumedScrollAnimationRequestID = request.id
            let onScrollAnimationRequestConsumed = parent.onScrollAnimationRequestConsumed
            callbackScheduler.publish {
                onScrollAnimationRequestConsumed(request)
            }
        }
    }
}

private final class ReaderPagedPageCurlHostingController: UIHostingController<ReaderPagedPageCurlLeafView> {
    let leaf: ReaderPagedPageCurlLeaf

    init(
        leaf: ReaderPagedPageCurlLeaf,
        rootView: ReaderPagedPageCurlLeafView,
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
}

@MainActor
private enum ReaderPageCurlPrivateBackColor {
    private static let filtersKey = "filters"
    private static let backgroundFiltersKey = "backgroundFilters"
    private static let typeKey = "type"
    private static let pageCurlType = "pageCurl"
    private static let inputBackEnabledKey = "inputBackEnabled"
    private static let inputBackColor0Key = "inputBackColor0"
    private static let inputBackColor1Key = "inputBackColor1"

    static func apply(to rootView: UIView, backColor: UIColor) {
        let colorComponents = backColor.readerPageCurlPrivateColorComponents
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
    var readerPageCurlPrivateColorComponents: [NSNumber] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha].map { NSNumber(value: Double($0)) }
    }
}

private struct ReaderPagedPageCurlLeafView: View {
    let leaf: ReaderPagedPageCurlLeaf
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
    let topInset: CGFloat
    let bottomInset: CGFloat
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let selectionController: NovelTextSelectionController?
    let onImageTap: (URL, String?) -> Void

    var body: some View {
        ReaderPagedPageSurfaceContainer(settings: settings) {
            if let surfaceIndex = leaf.surfaceIndex {
                let surface = surfaces.indices.contains(surfaceIndex) ? surfaces[surfaceIndex] : nil
                ReaderViewportSurfaceContent(
                    surface: surface,
                    displayReference: surface.flatMap { displayReferenceProvider($0.identity) },
                    selectionController: selectionController,
                    fallbackDocumentView: surface?.documentView,
                    fallbackSurfaceIndex: surfaceIndex,
                    settings: settings,
                    refererURL: refererURL,
                    imageDataLoader: imageDataLoader,
                    imageCacheNamespace: imageCacheNamespace,
                    onImageTap: onImageTap
                )
                .padding(.horizontal, settings.horizontalPadding)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .modifier(ReaderPagedHostingTopSafeAreaModifier())
    }
}
#endif
