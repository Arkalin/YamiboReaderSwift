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
        usesTwoPageSpread: Bool
    ) {
        self.usesTwoPageSpread = usesTwoPageSpread
        if usesTwoPageSpread {
            var nextLeaves: [ReaderPagedPageCurlLeaf] = []
            for spread in spreads {
                nextLeaves.append(
                    ReaderPagedPageCurlLeaf(
                        index: nextLeaves.count,
                        kind: .surface(spread.leftSurfaceIndex),
                        selectionIndex: spread.index
                    )
                )
                nextLeaves.append(
                    ReaderPagedPageCurlLeaf(
                        index: nextLeaves.count,
                        kind: spread.rightSurfaceIndex.map(ReaderPagedPageCurlLeaf.Kind.surface) ?? .blank,
                        selectionIndex: spread.index
                    )
                )
            }
            leaves = nextLeaves.isEmpty ? Self.emptySpreadLeaves : nextLeaves
        } else {
            let nextLeaves = surfaces.indices.map { index in
                ReaderPagedPageCurlLeaf(
                    index: index,
                    kind: .surface(index),
                    selectionIndex: index
                )
            }
            leaves = nextLeaves.isEmpty ? [Self.emptySingleLeaf] : nextLeaves
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
        if usesTwoPageSpread {
            let clampedSelection = min(max(selectionIndex, 0), max(pageCount - 1, 0))
            let startIndex = clampedSelection * 2
            return [startIndex, startIndex + 1].filter { leaves.indices.contains($0) }
        }
        let clampedSelection = min(max(selectionIndex, 0), max(leaves.count - 1, 0))
        return [clampedSelection]
    }

    func selectionIndex(forLeafIndexes leafIndexes: [Int]) -> Int? {
        leafIndexes
            .compactMap { leaves.indices.contains($0) ? leaves[$0].selectionIndex : nil }
            .min()
    }
}

#if os(iOS)
import UIKit

struct ReaderPagedPageCurlViewport: UIViewControllerRepresentable {
    let spreads: [NovelReaderPresentationSpread]
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    let topInset: CGFloat
    let bottomInset: CGFloat
    let selectionIndex: Int
    let usesTwoPageSpread: Bool
    let pagerIdentity: ReaderPagedPagerIdentity
    let scrollAnimationRequest: ReaderPagedScrollAnimationRequest?
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let isChromeVisible: Bool
    let onSelectionChange: (Int) -> Void
    let onPageTapZone: (ReaderPagedTapZone) -> Void
    let onScrollAnimationRequestConsumed: (ReaderPagedScrollAnimationRequest) -> Void
    let onChromeVisibleImageTap: () -> Void
    let onImageTap: (URL, String?) -> Void

    private var sequence: ReaderPagedPageCurlSequence {
        ReaderPagedPageCurlSequence(
            surfaces: surfaces,
            spreads: spreads,
            usesTwoPageSpread: usesTwoPageSpread
        )
    }

    private var contentIdentity: ReaderPagedSpreadViewportContentIdentity {
        ReaderPagedSpreadViewportContentIdentity(
            spreads: spreads,
            content: ReaderPagedViewportContentIdentity(
                surfaces: surfaces,
                settings: settings,
                refererURL: refererURL,
                sessionState: sessionState,
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
        pageViewController.view.backgroundColor = .clear

        let tapRecognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        pageViewController.view.addGestureRecognizer(tapRecognizer)

        context.coordinator.configureGestures(in: pageViewController)
        context.coordinator.configureSpine(in: pageViewController)
        context.coordinator.setCurrentSelection(in: pageViewController, animated: false)
        return pageViewController
    }

    func updateUIViewController(_ pageViewController: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.update(
                pageViewController,
                contentIdentity: contentIdentity
            )
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: ReaderPagedPageCurlViewport
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var contentIdentity: ReaderPagedSpreadViewportContentIdentity?
        private var consumedScrollAnimationRequestID: UUID?
        private var currentSelectionIndex: Int?

        init(parent: ReaderPagedPageCurlViewport) {
            self.parent = parent
        }

        func update(
            _ pageViewController: UIPageViewController,
            contentIdentity nextContentIdentity: ReaderPagedSpreadViewportContentIdentity
        ) {
            let didChangeContentIdentity = contentIdentity != nextContentIdentity
            contentIdentity = nextContentIdentity
            configureGestures(in: pageViewController)
            configureSpine(in: pageViewController)

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
            if let imageView = containerView.firstDescendant(
                ofType: ReaderVerticalViewportImageView.self,
                containing: location
            ) {
                let imageLocation = containerView.convert(location, to: imageView)
                handleImageTap(imageView, at: imageLocation)
                return
            }

            let zone = ReaderPagedTapZone.zone(for: location, in: containerView.bounds)
            let onPageTapZone = parent.onPageTapZone
            callbackScheduler.publish {
                onPageTapZone(zone)
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view?.isDescendant(ofType: ReaderVerticalViewportImageView.self) == true
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
                guard let currentSelectionIndex else { return .forward }
                return parent.selectionIndex >= currentSelectionIndex ? .forward : .reverse
            }()

            pageViewController.setViewControllers(
                controllers,
                direction: direction,
                animated: animated
            ) { [weak self] completed in
                guard let self else { return }
                if !animated || completed {
                    self.currentSelectionIndex = self.parent.selectionIndex
                }
                completion?()
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
                    sessionState: parent.sessionState,
                    topInset: parent.topInset,
                    bottomInset: parent.bottomInset,
                    displayReferenceProvider: parent.displayReferenceProvider,
                    onImageTap: parent.onImageTap
                )
            )
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

    init(leaf: ReaderPagedPageCurlLeaf, rootView: ReaderPagedPageCurlLeafView) {
        self.leaf = leaf
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }

    @MainActor @preconcurrency
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct ReaderPagedPageCurlLeafView: View {
    let leaf: ReaderPagedPageCurlLeaf
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    let topInset: CGFloat
    let bottomInset: CGFloat
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let onImageTap: (URL, String?) -> Void

    var body: some View {
        ReaderPagedPageSurfaceContainer(settings: settings) {
            if let surfaceIndex = leaf.surfaceIndex {
                let surface = surfaces.indices.contains(surfaceIndex) ? surfaces[surfaceIndex] : nil
                ReaderViewportSurfaceContent(
                    surface: surface,
                    displayReference: surface.flatMap { displayReferenceProvider($0.identity) },
                    fallbackDocumentView: surface?.documentView,
                    fallbackSurfaceIndex: surfaceIndex,
                    settings: settings,
                    refererURL: refererURL,
                    sessionState: sessionState,
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
