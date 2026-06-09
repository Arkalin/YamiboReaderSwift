import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderPagedCollectionViewport: UIViewRepresentable {
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    let topInset: CGFloat
    let bottomInset: CGFloat
    let selectionIndex: Int
    let pagerIdentity: ReaderPagedPagerIdentity
    let scrollAnimationRequest: ReaderPagedScrollAnimationRequest?
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let isChromeVisible: Bool
    let onSelectionChange: (Int) -> Void
    let onPageTapZone: (ReaderPagedTapZone) -> Void
    let onScrollAnimationRequestConsumed: (ReaderPagedScrollAnimationRequest) -> Void
    let onChromeVisibleImageTap: () -> Void
    let onImageTap: (URL, String?) -> Void

    private var contentIdentity: ReaderPagedViewportContentIdentity {
        ReaderPagedViewportContentIdentity(
            surfaces: surfaces,
            settings: settings,
            refererURL: refererURL,
            sessionState: sessionState,
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
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.scrollToPendingSelectionIfPossible(in: collectionView, animated: false)
        }
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
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
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var contentIdentity: ReaderPagedViewportContentIdentity?
        private var pendingSelectionIndex: Int?
        private var isReloadingDataForSelectionScroll = false
        private var isPendingSelectionScrollRetryScheduled = false
        private var consumedScrollAnimationRequestID: UUID?
        private var pageTurnRestingIndex: Int?

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
                        sessionState: parent.sessionState,
                        onImageTap: parent.onImageTap
                    )
                    .padding(.horizontal, parent.settings.horizontalPadding)
                    .padding(.top, parent.topInset)
                    .padding(.bottom, parent.bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
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
            guard let collectionView = scrollView as? UICollectionView else { return }
            beginPageTurnVisuals(in: collectionView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            applyPageTurnVisuals(in: collectionView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            if !decelerate {
                updateSelection(from: scrollView)
                endPageTurnVisuals(in: collectionView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateSelection(from: scrollView)
            guard let collectionView = scrollView as? UICollectionView else { return }
            endPageTurnVisuals(in: collectionView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateSelection(from: scrollView)
            guard let collectionView = scrollView as? UICollectionView else { return }
            endPageTurnVisuals(in: collectionView)
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
               animateAdjacentSelection(for: zone, in: collectionView) {
                return
            }
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
            let animationRequest = matchingScrollAnimationRequest()
            guard contentIdentity != nextContentIdentity else {
                if requestSelectionScroll(in: collectionView, animated: animationRequest != nil),
                   let animationRequest {
                    consumeScrollAnimationRequest(animationRequest)
                }
                return
            }
            if let animationRequest {
                consumeScrollAnimationRequest(animationRequest)
            }
            contentIdentity = nextContentIdentity
            collectionView.collectionViewLayout.invalidateLayout()
            reloadDataAndRequestSelectionScroll(in: collectionView, animated: false)
        }

        func reloadDataAndRequestSelectionScroll(in collectionView: UICollectionView, animated: Bool) {
            pendingSelectionIndex = parent.selectionIndex
            isReloadingDataForSelectionScroll = true
            collectionView.reloadData()
            collectionView.performBatchUpdates(nil) { [weak self, weak collectionView] _ in
                guard let collectionView else { return }
                self?.isReloadingDataForSelectionScroll = false
                self?.requestSelectionScroll(in: collectionView, animated: animated)
                self?.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)
            }
        }

        @discardableResult
        func requestSelectionScroll(in collectionView: UICollectionView, animated: Bool) -> Bool {
            pendingSelectionIndex = parent.selectionIndex
            return scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)
        }

        @discardableResult
        func scrollToPendingSelectionIfPossible(in collectionView: UICollectionView, animated: Bool) -> Bool {
            guard let pendingSelectionIndex,
                  !isReloadingDataForSelectionScroll,
                  !parent.surfaces.isEmpty,
                  collectionView.bounds.width > 0,
                  collectionView.window != nil else {
                return false
            }
            let item = min(max(pendingSelectionIndex, 0), max(parent.surfaces.count - 1, 0))
            guard collectionView.numberOfSections > 0,
                  collectionView.numberOfItems(inSection: 0) > item else {
                schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)
                return false
            }

            collectionView.layoutIfNeeded()
            let targetContentOffsetX = CGFloat(item) * collectionView.bounds.width
            guard collectionView.contentSize.width >= targetContentOffsetX + collectionView.bounds.width else {
                schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)
                return false
            }

            if animated {
                beginPageTurnVisuals(in: collectionView)
            }
            collectionView.setContentOffset(
                CGPoint(x: targetContentOffsetX, y: collectionView.contentOffset.y),
                animated: animated
            )
            if animated {
                applyPageTurnVisuals(in: collectionView)
            }
            if animated || abs(collectionView.contentOffset.x - targetContentOffsetX) <= 1 {
                self.pendingSelectionIndex = nil
            } else {
                schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)
            }
            return true
        }

        private func animateAdjacentSelection(
            for zone: ReaderPagedTapZone,
            in collectionView: UICollectionView
        ) -> Bool {
            let delta: Int
            switch zone {
            case .previous:
                delta = -1
            case .next:
                delta = 1
            case .toggleChrome:
                return false
            }

            guard !parent.surfaces.isEmpty,
                  collectionView.bounds.width > 0,
                  collectionView.window != nil else {
                return false
            }
            let targetItem = parent.selectionIndex + delta
            guard targetItem >= 0, targetItem < parent.surfaces.count else {
                return false
            }
            pendingSelectionIndex = targetItem
            return scrollToPendingSelectionIfPossible(in: collectionView, animated: true)
        }

        private func schedulePendingSelectionScrollRetry(in collectionView: UICollectionView, animated: Bool) {
            guard !isPendingSelectionScrollRetryScheduled else { return }
            isPendingSelectionScrollRetryScheduled = true
            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self else { return }
                self.isPendingSelectionScrollRetryScheduled = false
                guard let collectionView else { return }
                self.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)
            }
        }

        private func updateSelection(from scrollView: UIScrollView) {
            guard scrollView.bounds.width > 0 else { return }
            let item = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
            let clampedItem = min(max(item, 0), max(parent.surfaces.count - 1, 0))
            guard clampedItem != parent.selectionIndex else { return }
            let onSelectionChange = parent.onSelectionChange
            callbackScheduler.publish {
                onSelectionChange(clampedItem)
            }
        }

        private func beginPageTurnVisuals(in collectionView: UICollectionView) {
            guard collectionView.bounds.width > 0 else { return }
            let currentIndex = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
            pageTurnRestingIndex = min(max(currentIndex, 0), max(parent.surfaces.count - 1, 0))
        }

        private func applyPageTurnVisuals(in collectionView: UICollectionView) {
            guard let metrics = ReaderPagedPageTurnPresentation.metrics(
                contentOffsetX: collectionView.contentOffset.x,
                pageWidth: collectionView.bounds.width,
                pageCount: parent.surfaces.count,
                restingPageIndex: pageTurnRestingIndex ?? parent.selectionIndex,
                cornerRadius: ReaderPagedPageTurnCornerRadius.radius(for: collectionView.window?.screen)
            ) else {
                resetPageTurnVisuals(in: collectionView)
                return
            }
            collectionView.backgroundColor = ReaderPagedPageTurnBackground.dimmedPageColor(
                settings: parent.settings,
                traitCollection: collectionView.traitCollection,
                overlayAlpha: metrics.overlayAlpha
            )

            for case let cell as ReaderPagedPageTurnCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else {
                    cell.resetPageTurnVisuals()
                    continue
                }
                if indexPath.item == metrics.maskedPageIndex {
                    cell.applyPageTurnVisuals(
                        overlayAlpha: metrics.overlayAlpha,
                        cornerRadius: 0
                    )
                } else if indexPath.item == metrics.roundedPageIndex {
                    cell.applyPageTurnVisuals(
                        overlayAlpha: 0,
                        cornerRadius: metrics.cornerRadius
                    )
                } else {
                    cell.resetPageTurnVisuals()
                }
            }
        }

        private func endPageTurnVisuals(in collectionView: UICollectionView) {
            pageTurnRestingIndex = nil
            resetPageTurnVisuals(in: collectionView)
        }

        private func resetPageTurnVisuals(in collectionView: UICollectionView) {
            collectionView.backgroundColor = .clear
            for case let cell as ReaderPagedPageTurnCell in collectionView.visibleCells {
                cell.resetPageTurnVisuals()
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
#endif
