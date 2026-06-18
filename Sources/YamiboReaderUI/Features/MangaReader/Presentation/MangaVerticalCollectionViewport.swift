import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

struct MangaVerticalCollectionViewport: UIViewRepresentable {
    let pages: [MangaReaderPageProjection]
    let currentPageIndex: Int?
    let viewportPlacement: MangaReaderViewportPlacement?
    let imagePipeline: MangaImagePipeline
    let onCurrentPageChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let collectionView = MangaVerticalCollectionView(
            frame: .zero,
            collectionViewLayout: Self.makeLayout()
        )
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = .black
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            MangaVerticalCollectionPageCell.self,
            forCellWithReuseIdentifier: MangaVerticalCollectionPageCell.reuseIdentifier
        )
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.applyInitialPlacementIfNeeded(in: collectionView)
            coordinator?.applyViewportPlacementIfNeeded(in: collectionView)
        }
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateContentIfNeeded(in: collectionView)
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(MangaVerticalCollectionPageCell.defaultEstimatedHeight)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 0
            return section
        }
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UIScrollViewDelegate {
        var parent: MangaVerticalCollectionViewport
        private var contentIdentity: [String] = []
        private var heightToWidthRatios: [String: CGFloat] = [:]
        private var pendingInitialPageIndex: Int?
        private var lastReportedGlobalIndex: Int?
        private var lastAppliedPlacementRevision: Int?

        init(parent: MangaVerticalCollectionViewport) {
            self.parent = parent
        }

        func updateContentIfNeeded(in collectionView: UICollectionView) {
            let nextIdentity = parent.pages.map(\.id)
            guard nextIdentity != contentIdentity else {
                applyInitialPlacementIfNeeded(in: collectionView)
                applyViewportPlacementIfNeeded(in: collectionView)
                return
            }

            contentIdentity = nextIdentity
            let validIDs = Set(nextIdentity)
            heightToWidthRatios = heightToWidthRatios.filter { validIDs.contains($0.key) }
            lastReportedGlobalIndex = nil

            if parent.pages.isEmpty {
                pendingInitialPageIndex = nil
                collectionView.alpha = 1
            } else {
                let requestedIndex = parent.viewportPlacement?.targetPageIndex ?? parent.currentPageIndex ?? 0
                pendingInitialPageIndex = min(max(requestedIndex, 0), parent.pages.count - 1)
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
            parent.pages.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: MangaVerticalCollectionPageCell.reuseIdentifier,
                for: indexPath
            )
            guard let cell = cell as? MangaVerticalCollectionPageCell,
                  parent.pages.indices.contains(indexPath.item) else {
                return cell
            }

            let page = parent.pages[indexPath.item]
            cell.configure(
                page: page,
                imagePipeline: parent.imagePipeline,
                knownHeightToWidthRatio: heightToWidthRatios[page.id],
                onHeightToWidthRatioChange: { [weak self, weak collectionView] ratio in
                    self?.heightToWidthRatios[page.id] = ratio
                    collectionView?.collectionViewLayout.invalidateLayout()
                    if let collectionView {
                        self?.publishCurrentPageIfNeeded(from: collectionView)
                    }
                }
            )
            return cell
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard pendingInitialPageIndex == nil,
                  let collectionView = scrollView as? UICollectionView else {
                return
            }
            publishCurrentPageIfNeeded(from: collectionView)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate,
                  let collectionView = scrollView as? UICollectionView else {
                return
            }
            publishCurrentPageIfNeeded(from: collectionView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            publishCurrentPageIfNeeded(from: collectionView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            publishCurrentPageIfNeeded(from: collectionView)
        }

        func applyInitialPlacementIfNeeded(in collectionView: UICollectionView) {
            guard let targetIndex = pendingInitialPageIndex else { return }
            guard parent.pages.indices.contains(targetIndex) else {
                pendingInitialPageIndex = nil
                collectionView.alpha = 1
                return
            }
            guard collectionView.bounds.width > 0, collectionView.bounds.height > 0 else {
                return
            }

            collectionView.scrollToItem(
                at: IndexPath(item: targetIndex, section: 0),
                at: .top,
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
            let targetIndex = min(max(placement.targetPageIndex, 0), max(parent.pages.count - 1, 0))
            guard parent.pages.indices.contains(targetIndex),
                  collectionView.bounds.width > 0,
                  collectionView.bounds.height > 0 else {
                return
            }

            collectionView.scrollToItem(
                at: IndexPath(item: targetIndex, section: 0),
                at: .top,
                animated: placement.animated
            )
            lastAppliedPlacementRevision = placement.revision
            publishCurrentPageIfNeeded(from: collectionView)
        }

        private func publishCurrentPageIfNeeded(from collectionView: UICollectionView) {
            guard let globalIndex = currentGlobalIndex(in: collectionView),
                  globalIndex != lastReportedGlobalIndex else {
                return
            }

            lastReportedGlobalIndex = globalIndex
            let onCurrentPageChange = parent.onCurrentPageChange
            DispatchQueue.main.async {
                onCurrentPageChange(globalIndex)
            }
        }

        private func currentGlobalIndex(in collectionView: UICollectionView) -> Int? {
            let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
            return collectionView.indexPathsForVisibleItems
                .compactMap { indexPath -> (index: Int, visibleArea: CGFloat, topDistance: CGFloat)? in
                    guard parent.pages.indices.contains(indexPath.item),
                          let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                        return nil
                    }
                    let intersection = visibleRect.intersection(attributes.frame)
                    guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
                        return nil
                    }
                    return (
                        index: indexPath.item,
                        visibleArea: intersection.width * intersection.height,
                        topDistance: abs(attributes.frame.minY - visibleRect.minY)
                    )
                }
                .max { lhs, rhs in
                    if lhs.visibleArea == rhs.visibleArea {
                        return lhs.topDistance > rhs.topDistance
                    }
                    return lhs.visibleArea < rhs.visibleArea
                }?.index
        }
    }
}

private final class MangaVerticalCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

private final class MangaVerticalCollectionPageCell: UICollectionViewCell {
    static let reuseIdentifier = "MangaVerticalCollectionPageCell"
    static let defaultWidthToHeightAspectRatio: CGFloat = 0.72
    static let defaultEstimatedHeight: CGFloat = 560

    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let failureLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let failureStack = UIStackView()
    private var task: Task<Void, Never>?
    private var page: MangaReaderPageProjection?
    private var imagePipeline: MangaImagePipeline?
    private var currentPageID: String?
    private var heightToWidthRatio = 1 / defaultWidthToHeightAspectRatio
    private var onHeightToWidthRatioChange: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        task?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        page = nil
        imagePipeline = nil
        currentPageID = nil
        onHeightToWidthRatioChange = nil
        heightToWidthRatio = 1 / Self.defaultWidthToHeightAspectRatio
        imageView.image = nil
        activityIndicator.stopAnimating()
        setFailureStackVisible(false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        activityIndicator.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)

        guard !failureStack.isHidden else {
            failureStack.frame = .zero
            return
        }

        let horizontalInset: CGFloat = contentView.bounds.width >= 32 ? 16 : 0
        let availableWidth = max(contentView.bounds.width - horizontalInset * 2, 0)
        let fittingSize = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        let stackSize = failureStack.systemLayoutSizeFitting(fittingSize)
        failureStack.frame = CGRect(
            x: contentView.bounds.midX - min(stackSize.width, availableWidth) / 2,
            y: contentView.bounds.midY - stackSize.height / 2,
            width: min(stackSize.width, availableWidth),
            height: stackSize.height
        )
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        let width = max(attributes.size.width, 1)
        attributes.size.height = max(ceil(width * heightToWidthRatio), 160)
        return attributes
    }

    func configure(
        page: MangaReaderPageProjection,
        imagePipeline: MangaImagePipeline,
        knownHeightToWidthRatio: CGFloat?,
        onHeightToWidthRatioChange: @escaping (CGFloat) -> Void
    ) {
        self.page = page
        self.imagePipeline = imagePipeline
        self.onHeightToWidthRatioChange = onHeightToWidthRatioChange
        if let knownHeightToWidthRatio {
            heightToWidthRatio = knownHeightToWidthRatio
        }

        let isSamePage = currentPageID == page.id
        currentPageID = page.id
        if isSamePage, imageView.image != nil {
            return
        }

        task?.cancel()
        if let cachedImage = imagePipeline.cachedImage(for: page) {
            show(image: cachedImage, pageID: page.id)
        } else {
            startLoad()
        }
    }

    private func configureViewHierarchy() {
        backgroundColor = .black
        contentView.backgroundColor = .black
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        contentView.addSubview(imageView)

        activityIndicator.color = .white
        contentView.addSubview(activityIndicator)

        failureLabel.text = L10n.string("image.load_failed")
        failureLabel.textColor = .secondaryLabel
        failureLabel.font = .preferredFont(forTextStyle: .caption1)
        failureLabel.textAlignment = .center
        failureLabel.numberOfLines = 0

        retryButton.setTitle(L10n.string("common.retry"), for: .normal)
        retryButton.addTarget(self, action: #selector(retryImageLoad), for: .touchUpInside)

        failureStack.axis = .vertical
        failureStack.alignment = .center
        failureStack.spacing = 8
        failureStack.addArrangedSubview(failureLabel)
        failureStack.addArrangedSubview(retryButton)
        contentView.addSubview(failureStack)
        setFailureStackVisible(false)
    }

    private func startLoad() {
        guard let page, let imagePipeline else { return }
        showLoading()
        task = Task { @MainActor [weak self] in
            do {
                let image = try await imagePipeline.image(for: page)
                guard !Task.isCancelled else { return }
                self?.show(image: image, pageID: page.id)
            } catch {
                guard !Task.isCancelled else { return }
                self?.showFailure(pageID: page.id)
            }
        }
    }

    @objc
    private func retryImageLoad() {
        task?.cancel()
        startLoad()
    }

    private func showLoading() {
        imageView.image = nil
        setFailureStackVisible(false)
        activityIndicator.startAnimating()
    }

    private func show(image: UIImage, pageID: String) {
        guard currentPageID == pageID else { return }
        activityIndicator.stopAnimating()
        setFailureStackVisible(false)
        imageView.image = image
        updateHeightToWidthRatio(for: image)
    }

    private func showFailure(pageID: String) {
        guard currentPageID == pageID else { return }
        activityIndicator.stopAnimating()
        imageView.image = nil
        setFailureStackVisible(true)
        setNeedsLayout()
    }

    private func setFailureStackVisible(_ isVisible: Bool) {
        failureLabel.isHidden = !isVisible
        retryButton.isHidden = !isVisible
        failureStack.isHidden = !isVisible
        failureStack.isUserInteractionEnabled = isVisible
        if !isVisible {
            failureStack.frame = .zero
        }
    }

    private func updateHeightToWidthRatio(for image: UIImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let nextRatio = image.size.height / image.size.width
        guard nextRatio.isFinite, nextRatio > 0 else { return }
        guard abs(nextRatio - heightToWidthRatio) > 0.001 else { return }
        heightToWidthRatio = nextRatio
        onHeightToWidthRatioChange?(nextRatio)
    }
}
#endif
