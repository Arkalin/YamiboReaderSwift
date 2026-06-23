import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaPagedReaderViewport: UIViewRepresentable {
    let plan: MangaPagedReadingPlan
    let viewportPlacement: MangaReaderViewportPlacement?
    let settings: MangaReaderSettings
    let imagePipeline: MangaImagePipeline
    let onCurrentPageChange: (Int) -> Void
    let onTap: () -> Void

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
        collectionView.backgroundColor = .black
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            MangaPagedReaderPageCell.self,
            forCellWithReuseIdentifier: MangaPagedReaderPageCell.reuseIdentifier
        )
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.applyInitialPlacementIfNeeded(in: collectionView)
            coordinator?.applyViewportPlacementIfNeeded(in: collectionView)
        }
        context.coordinator.tapGesture.cancelsTouchesInView = false
        context.coordinator.tapGesture.delegate = context.coordinator
        collectionView.addGestureRecognizer(context.coordinator.tapGesture)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.updateContentIfNeeded(in: collectionView)
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: MangaPagedReaderViewport
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var contentIdentity: MangaPagedReaderContentIdentity?
        private var pendingInitialPageIndex: Int?
        private var lastReportedGlobalIndex: Int?
        private var lastAppliedPlacementRevision: Int?
        lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

        init(parent: MangaPagedReaderViewport) {
            self.parent = parent
        }

        func updateContentIfNeeded(in collectionView: UICollectionView) {
            let nextIdentity = MangaPagedReaderContentIdentity(
                pageIDs: parent.plan.pages.map(\.id),
                pageScaleMode: parent.settings.pageScaleMode,
                pageTurnDirection: parent.settings.pageTurnDirection
            )
            guard nextIdentity != contentIdentity else {
                applyInitialPlacementIfNeeded(in: collectionView)
                applyViewportPlacementIfNeeded(in: collectionView)
                return
            }

            contentIdentity = nextIdentity
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
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.plan.pages.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: MangaPagedReaderPageCell.reuseIdentifier,
                for: indexPath
            )
            guard let cell = cell as? MangaPagedReaderPageCell,
                  parent.plan.pages.indices.contains(indexPath.item) else {
                return cell
            }

            cell.configure(
                page: parent.plan.pages[indexPath.item],
                imagePipeline: parent.imagePipeline,
                pageScaleMode: parent.settings.pageScaleMode,
                pageTurnDirection: parent.settings.pageTurnDirection
            )
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
            guard let collectionView = scrollView as? UICollectionView else { return }
            publishCurrentPageIfNeeded(from: collectionView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate,
                  let collectionView = scrollView as? UICollectionView else {
                return
            }
            publishCurrentPageIfNeeded(from: collectionView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            publishCurrentPageIfNeeded(from: collectionView)
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

            collectionView.scrollToItem(
                at: IndexPath(item: targetIndex, section: 0),
                at: .centeredHorizontally,
                animated: false
            )
            lastAppliedPlacementRevision = parent.viewportPlacement?.revision
            pendingInitialPageIndex = nil
            collectionView.alpha = 1
            publishCurrentPageIfNeeded(from: collectionView)
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

            collectionView.scrollToItem(
                at: IndexPath(item: targetIndex, section: 0),
                at: .centeredHorizontally,
                animated: placement.animated
            )
            lastAppliedPlacementRevision = placement.revision
            if !placement.animated {
                publishCurrentPageIfNeeded(from: collectionView)
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
            guard let delta = pageDelta(for: zone) else {
                let onTap = parent.onTap
                callbackScheduler.publish {
                    onTap()
                }
                return
            }
            guard let currentIndex = currentPageIndex(in: collectionView),
                  let targetIndex = parent.plan.clampedPageIndex(currentIndex + delta),
                  targetIndex != currentIndex else {
                return
            }
            collectionView.scrollToItem(
                at: IndexPath(item: targetIndex, section: 0),
                at: .centeredHorizontally,
                animated: true
            )
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

        private func pageDelta(for zone: ReaderPagedTapZone) -> Int? {
            switch (zone, parent.settings.pageTurnDirection) {
            case (.toggleChrome, _):
                nil
            case (.previous, .rightToLeft), (.next, .leftToRight):
                1
            case (.next, .rightToLeft), (.previous, .leftToRight):
                -1
            }
        }

        private func publishCurrentPageIfNeeded(from collectionView: UICollectionView) {
            guard let pageIndex = currentPageIndex(in: collectionView),
                  let globalIndex = parent.plan.globalIndex(forPageAt: pageIndex),
                  globalIndex != lastReportedGlobalIndex else {
                return
            }

            lastReportedGlobalIndex = globalIndex
            let onCurrentPageChange = parent.onCurrentPageChange
            callbackScheduler.publish {
                onCurrentPageChange(globalIndex)
            }
        }

        private func currentPageIndex(in collectionView: UICollectionView) -> Int? {
            guard collectionView.bounds.width > 0 else {
                return parent.plan.currentPageIndex
            }
            let rawIndex = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
            return parent.plan.clampedPageIndex(rawIndex)
        }
    }
}

private struct MangaPagedReaderContentIdentity: Equatable {
    var pageIDs: [String]
    var pageScaleMode: MangaPageScaleMode
    var pageTurnDirection: MangaPageTurnDirection
}

private final class MangaPagedReaderCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

private final class MangaPagedReaderPageCell: UICollectionViewCell {
    static let reuseIdentifier = "MangaPagedReaderPageCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        contentView.backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
    }

    func configure(
        page: MangaReaderPageProjection,
        imagePipeline: MangaImagePipeline,
        pageScaleMode: MangaPageScaleMode,
        pageTurnDirection: MangaPageTurnDirection
    ) {
        contentConfiguration = UIHostingConfiguration {
            MangaPagedReaderPageSurface(
                page: page,
                imagePipeline: imagePipeline,
                pageScaleMode: pageScaleMode,
                pageTurnDirection: pageTurnDirection
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

    @State private var loadedImage: UIImage?
    @State private var loadedPageID: String?
    @State private var loadingPageID: String?
    @State private var failedPageID: String?

    var body: some View {
        ZStack {
            Color.black

            if let image = displayedImage {
                MangaPagedReaderScaledImage(
                    image: image,
                    pageScaleMode: pageScaleMode,
                    pageTurnDirection: pageTurnDirection
                )
            } else if loadingPageID == page.id {
                ProgressView()
                    .tint(.white)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: failedPageID == page.id ? "exclamationmark.triangle" : "photo")
                        .font(.title2.weight(.semibold))
                    Text(failedPageID == page.id ? L10n.string("image.load_failed") : L10n.string("manga.loading"))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
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
    let pageScaleMode: MangaPageScaleMode
    let pageTurnDirection: MangaPageTurnDirection

    var body: some View {
        GeometryReader { proxy in
            let scaledSize = scaledImageSize(
                imageSize: image.size,
                containerSize: proxy.size,
                pageScaleMode: pageScaleMode
            )

            ZStack(alignment: imageAlignment) {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .frame(width: scaledSize.width, height: scaledSize.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var imageAlignment: Alignment {
        guard pageScaleMode == .fitHeight else { return .center }
        return pageTurnDirection == .rightToLeft ? .trailing : .leading
    }

    private func scaledImageSize(
        imageSize: CGSize,
        containerSize: CGSize,
        pageScaleMode: MangaPageScaleMode
    ) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }
        let scale = switch pageScaleMode {
        case .fitWidth:
            containerSize.width / imageSize.width
        case .fitHeight:
            containerSize.height / imageSize.height
        }
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
#endif
