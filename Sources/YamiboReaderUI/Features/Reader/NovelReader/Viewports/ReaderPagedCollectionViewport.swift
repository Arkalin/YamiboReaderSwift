import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderPagedCollectionViewport: UIViewRepresentable {
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let imageDataLoader: any NovelInlineImageDataLoading
    let imageCacheNamespace: NovelInlineImageCacheNamespace
    let topInset: CGFloat
    let bottomInset: CGFloat
    let selectionIndex: Int
    let pagerIdentity: ReaderPagedPagerIdentity
    let scrollAnimationRequest: ReaderPagedScrollAnimationRequest?
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let isChromeVisible: Bool
    let canBoundaryPageTurn: (Int) -> Bool
    let onSelectionChange: (Int) -> Void
    let onBoundaryPageTurn: (Int) -> Void
    let onPageTapZone: (ReaderPagedTapZone) -> Void
    let onScrollAnimationRequestConsumed: (ReaderPagedScrollAnimationRequest) -> Void
    let onChromeVisibleImageTap: () -> Void
    let onImageTap: (URL, String?) -> Void

    private var contentIdentity: ReaderPagedViewportContentIdentity {
        ReaderPagedViewportContentIdentity(
            surfaces: surfaces,
            settings: settings,
            refererURL: refererURL,
            imageCacheNamespace: imageCacheNamespace,
            topInset: topInset,
            bottomInset: bottomInset
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

        let collectionView = ReaderPagedViewportCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(ReaderPagedPageTurnCell.self, forCellWithReuseIdentifier: Coordinator.reuseIdentifier)
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        collectionView.addGestureRecognizer(tapRecognizer)
        let quickFadePanRecognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleQuickFadePan(_:))
        )
        quickFadePanRecognizer.delegate = context.coordinator
        collectionView.addGestureRecognizer(quickFadePanRecognizer)
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.scrollToPendingSelectionIfPossible(in: collectionView, animated: false)
        }
        context.coordinator.updateGestureState(in: collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateGestureState(in: collectionView)
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.updateContentAndRequestSelectionScroll(
                in: collectionView,
                contentIdentity: contentIdentity
            )
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        static let reuseIdentifier = "ReaderPagedCollectionViewportCell"

        var parent: ReaderPagedCollectionViewport
        private let pagingDriver = ReaderPagedViewportPagingDriver()
        private var contentIdentity: ReaderPagedViewportContentIdentity?

        var callbackScheduler: SwiftUIViewUpdateCallbackScheduler {
            pagingDriver.callbackScheduler
        }

        private var pagingInputs: ReaderPagedViewportPagingInputs {
            ReaderPagedViewportPagingInputs(
                itemCount: parent.surfaces.count,
                selectionIndex: parent.selectionIndex,
                pagedTurnStyle: parent.settings.pagedTurnStyle,
                horizontalNavigationDirection: .leftSwipeAdvances,
                pagerIdentity: parent.pagerIdentity,
                scrollAnimationRequest: parent.scrollAnimationRequest,
                canBoundaryPageTurn: parent.canBoundaryPageTurn,
                onSelectionChange: parent.onSelectionChange,
                onBoundaryPageTurn: parent.onBoundaryPageTurn,
                onScrollAnimationRequestConsumed: parent.onScrollAnimationRequestConsumed,
                pageTurnRestingBackgroundColor: { _ in .clear },
                pageTurnBackgroundColor: { [parent] traitCollection, overlayAlpha in
                    ReaderPagedPageTurnBackground.dimmedPageColor(
                        baseColor: readerThemeUIColor(
                            for: parent.settings.backgroundStyle,
                            traitCollection: traitCollection
                        ),
                        overlayAlpha: overlayAlpha
                    )
                }
            )
        }

        init(parent: ReaderPagedCollectionViewport) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.surfaces.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.reuseIdentifier,
                for: indexPath
            ) as! ReaderPagedPageTurnCell
            let surface = parent.surfaces.indices.contains(indexPath.item)
                ? parent.surfaces[indexPath.item]
                : nil
            let displayReference = surface.flatMap { parent.displayReferenceProvider($0.identity) }
            cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                ReaderPagedPageSurfaceContainer(settings: parent.settings) {
                    ReaderViewportSurfaceContent(
                        surface: surface,
                        displayReference: displayReference,
                        fallbackDocumentView: surface?.documentView,
                        fallbackSurfaceIndex: indexPath.item,
                        settings: parent.settings,
                        refererURL: parent.refererURL,
                        imageDataLoader: parent.imageDataLoader,
                        imageCacheNamespace: parent.imageCacheNamespace,
                        onImageTap: parent.onImageTap
                    )
                    .padding(.horizontal, parent.settings.horizontalPadding)
                    .padding(.top, parent.topInset)
                    .padding(.bottom, parent.bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .modifier(ReaderPagedHostingTopSafeAreaModifier())
            }
            .margins(.all, 0)
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

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            pagingDriver.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate, inputs: pagingInputs)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            pagingDriver.scrollViewDidEndDecelerating(scrollView, inputs: pagingInputs)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            pagingDriver.scrollViewDidEndScrollingAnimation(scrollView, inputs: pagingInputs)
        }

        @objc
        func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let collectionView = recognizer.view as? UICollectionView else {
                return
            }
            let location = recognizer.location(in: collectionView)
            if let imageView = collectionView.firstDescendant(
                ofType: ReaderVerticalViewportImageView.self,
                containing: location
            ) {
                let imageLocation = collectionView.convert(location, to: imageView)
                handleImageTap(imageView, at: imageLocation)
                return
            }
            let zone = ReaderPagedTapZone.zone(for: location, in: collectionView.bounds)
            if !parent.isChromeVisible,
               pagingDriver.animateAdjacentSelection(for: zone, in: collectionView, inputs: pagingInputs) {
                return
            }
            let onPageTapZone = parent.onPageTapZone
            callbackScheduler.publish {
                onPageTapZone(zone)
            }
        }

        @objc
        func handleQuickFadePan(_ recognizer: UIPanGestureRecognizer) {
            pagingDriver.handleQuickFadePan(recognizer, inputs: pagingInputs)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view?.isDescendant(ofType: ReaderVerticalViewportImageView.self) == true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            return pagingDriver.quickFadePanShouldBegin(panRecognizer, inputs: pagingInputs)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            true
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

        func updateContentAndRequestSelectionScroll(
            in collectionView: UICollectionView,
            contentIdentity nextContentIdentity: ReaderPagedViewportContentIdentity
        ) {
            let didChangeContentIdentity = contentIdentity != nextContentIdentity
            contentIdentity = nextContentIdentity
            pagingDriver.updateContentAndRequestSelectionScroll(
                in: collectionView,
                didChangeContentIdentity: didChangeContentIdentity,
                inputs: pagingInputs
            )
        }

        func reloadDataAndRequestSelectionScroll(in collectionView: UICollectionView, animated: Bool) {
            pagingDriver.reloadDataAndRequestSelectionScroll(in: collectionView, animated: animated, inputs: pagingInputs)
        }

        @discardableResult
        func requestSelectionScroll(in collectionView: UICollectionView, animated: Bool) -> Bool {
            pagingDriver.requestSelectionScroll(in: collectionView, animated: animated, inputs: pagingInputs)
        }

        @discardableResult
        func scrollToPendingSelectionIfPossible(in collectionView: UICollectionView, animated: Bool) -> Bool {
            pagingDriver.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: pagingInputs)
        }

        func updateGestureState(in collectionView: UICollectionView) {
            pagingDriver.updateGestureState(in: collectionView, inputs: pagingInputs)
        }
    }
}
#endif
