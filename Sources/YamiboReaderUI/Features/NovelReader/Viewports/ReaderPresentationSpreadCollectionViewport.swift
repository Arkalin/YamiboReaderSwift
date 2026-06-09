import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct ReaderPresentationSpreadCollectionViewport: UIViewRepresentable {
    let spreads: [NovelReaderPresentationSpread]
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    let topInset: CGFloat
    let bottomInset: CGFloat
    let selectionIndex: Int
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let isChromeVisible: Bool
    let onSelectionChange: (Int) -> Void
    let onPageTapZone: (ReaderPagedTapZone) -> Void
    let onChromeVisibleImageTap: () -> Void
    let onImageTap: (URL, String?) -> Void

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
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: Coordinator.reuseIdentifier)
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
            context.coordinator.reloadDataAndRequestSelectionScroll(in: collectionView, animated: false)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        static let reuseIdentifier = "ReaderPresentationSpreadCollectionViewportCell"

        var parent: ReaderPresentationSpreadCollectionViewport
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var pendingSelectionIndex: Int?
        private var isReloadingDataForSelectionScroll = false
        private var isPendingSelectionScrollRetryScheduled = false

        init(parent: ReaderPresentationSpreadCollectionViewport) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.spreads.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.reuseIdentifier,
                for: indexPath
            )
            let spread = parent.spreads[indexPath.item]
            cell.backgroundColor = .clear
            cell.contentConfiguration = UIHostingConfiguration {
                ReaderPresentationSpreadContent(
                    spread: spread,
                    surfaces: parent.surfaces,
                    settings: parent.settings,
                    refererURL: parent.refererURL,
                    sessionState: parent.sessionState,
                    topInset: parent.topInset,
                    bottomInset: parent.bottomInset,
                    displayReferenceProvider: parent.displayReferenceProvider,
                    onImageTap: parent.onImageTap
                )
            }
            .margins(.all, 0)
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            collectionView.bounds.size
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateSelection(from: scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            updateSelection(from: scrollView)
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

        func requestSelectionScroll(in collectionView: UICollectionView, animated: Bool) {
            pendingSelectionIndex = parent.selectionIndex
            scrollToPendingSelectionIfPossible(in: collectionView, animated: animated)
        }

        func scrollToPendingSelectionIfPossible(in collectionView: UICollectionView, animated: Bool) {
            guard let pendingSelectionIndex,
                  !isReloadingDataForSelectionScroll,
                  !parent.spreads.isEmpty,
                  collectionView.bounds.width > 0,
                  collectionView.window != nil else {
                return
            }
            let item = min(max(pendingSelectionIndex, 0), max(parent.spreads.count - 1, 0))
            guard collectionView.numberOfSections > 0,
                  collectionView.numberOfItems(inSection: 0) > item else {
                schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)
                return
            }

            collectionView.layoutIfNeeded()
            let targetContentOffsetX = CGFloat(item) * collectionView.bounds.width
            guard collectionView.contentSize.width >= targetContentOffsetX + collectionView.bounds.width else {
                schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)
                return
            }

            collectionView.setContentOffset(
                CGPoint(x: targetContentOffsetX, y: collectionView.contentOffset.y),
                animated: animated
            )
            if animated || abs(collectionView.contentOffset.x - targetContentOffsetX) <= 1 {
                self.pendingSelectionIndex = nil
            } else {
                schedulePendingSelectionScrollRetry(in: collectionView, animated: animated)
            }
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
            let clampedItem = min(max(item, 0), max(parent.spreads.count - 1, 0))
            guard clampedItem != parent.selectionIndex else { return }
            let onSelectionChange = parent.onSelectionChange
            callbackScheduler.publish {
                onSelectionChange(clampedItem)
            }
        }
    }
}
#endif
