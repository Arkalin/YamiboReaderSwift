import SwiftUI
import YamiboReaderCore

#if os(iOS)
import UIKit

private struct ReaderVerticalViewportDisplaySurface {
    let identity: NovelReaderSurfaceIdentity
    let surfaceIndex: Int
    let documentView: Int
    let chapterTitle: String?
    let presentationHeight: CGFloat?
    let blocks: [ReaderViewportDisplayBlock]
}

struct ReaderVerticalViewportScrollView: UIViewRepresentable {
    let surfaces: [NovelReaderSurface]
    let settings: ReaderAppearanceSettings
    let refererURL: URL
    let sessionState: SessionState
    let topInset: CGFloat
    let bottomInset: CGFloat
    let scrollRequest: ReaderVerticalScrollRequest?
    let displayReferenceProvider: @MainActor (NovelReaderSurfaceIdentity) -> NovelTextViewportDisplayReference?
    let isChromeVisible: Bool
    let onVisibleSurfaceIdentitiesChange: ([NovelReaderSurfaceIdentity]) -> Void
    let onScrollRequestHandled: (ReaderVerticalScrollRequest) -> Void
    let onScrollViewReady: (UIScrollView) -> Void
    let onSurfaceFramesChange: ([Int: ReaderVerticalSurfaceFrameValue]) -> Void
    let onTextViewportSampleChange: (NovelTextViewportSample?) -> Void
    let onViewportChange: () -> Void
    let onScrollSettled: () -> Void
    let onTap: () -> Void
    let onChromeVisibleImageTap: () -> Void
    let onImageTap: (URL, String?) -> Void

    private var contentIdentity: ReaderVerticalViewportContentIdentity {
        ReaderVerticalViewportContentIdentity(
            surfaces: surfaces,
            settings: settings
        )
    }

    private var verticalLineSpacing: CGFloat {
        Self.verticalLineSpacing(for: settings)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = verticalLineSpacing
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = .zero

        let collectionView = ReaderVerticalViewportCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(ReaderVerticalViewportCell.self, forCellWithReuseIdentifier: ReaderVerticalViewportCell.reuseIdentifier)
        let coordinator = context.coordinator
        collectionView.onLayoutSubviews = { [weak coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.publishLayout(from: collectionView)
        }
        context.coordinator.tapGesture.cancelsTouchesInView = false
        context.coordinator.tapGesture.delegate = context.coordinator
        collectionView.addGestureRecognizer(context.coordinator.tapGesture)
        onScrollViewReady(collectionView)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.callbackScheduler.performViewUpdate {
            context.coordinator.updateLineSpacing(in: collectionView)
            context.coordinator.reloadDataIfNeeded(in: collectionView, contentIdentity: contentIdentity)
            context.coordinator.handle(scrollRequest, in: collectionView)
        }
    }

    private static func verticalLineSpacing(for settings: ReaderAppearanceSettings) -> CGFloat {
        max(CGFloat(6 * settings.lineHeightScale), 0)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ReaderVerticalViewportScrollView
        let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
        private var contentIdentity: ReaderVerticalViewportContentIdentity?
        private var handledScrollRequest: ReaderVerticalScrollRequest?
        private var lastPublishedSurfaceFrames: [Int: ReaderVerticalSurfaceFrameValue]?
        private var lastPublishedVisibleSurfaceIdentities: [NovelReaderSurfaceIdentity]?
        private var lastPublishedTextViewportSample: NovelTextViewportSample?
        private var hasPublishedNilTextViewportSample = false
        private var isImmediateVisibleTextRedrawScheduled = false
        private var isDelayedVisibleTextRedrawScheduled = false
        lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))

        init(parent: ReaderVerticalViewportScrollView) {
            self.parent = parent
            super.init()
        }

        fileprivate func updateLineSpacing(in collectionView: UICollectionView) {
            guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
                return
            }
            let lineSpacing = parent.verticalLineSpacing
            guard layout.minimumLineSpacing != lineSpacing else { return }
            layout.minimumLineSpacing = lineSpacing
            layout.invalidateLayout()
        }

        fileprivate func reloadDataIfNeeded(
            in collectionView: UICollectionView,
            contentIdentity nextContentIdentity: ReaderVerticalViewportContentIdentity
        ) {
            let contentIdentityChanged = contentIdentity != nextContentIdentity
            let insetsChanged = updateInsets(in: collectionView)
            guard contentIdentityChanged else {
                if insetsChanged {
                    publishLayout(from: collectionView)
                }
                return
            }
            contentIdentity = nextContentIdentity
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.reloadData()
            resetPublishedViewportCache()
            if collectionView.bounds.width > 0, collectionView.bounds.height > 0 {
                collectionView.layoutIfNeeded()
                publishLayout(from: collectionView)
            }
            scheduleVisibleTextRedraw(in: collectionView, includeDelayedPass: true)
        }

        @discardableResult
        private func updateInsets(in collectionView: UICollectionView) -> Bool {
            let contentInset = UIEdgeInsets(
                top: parent.topInset,
                left: 0,
                bottom: parent.bottomInset,
                right: 0
            )
            guard collectionView.contentInset != contentInset else { return false }
            let previousVisibleOffsetY = collectionView.contentOffset.y + collectionView.adjustedContentInset.top
            collectionView.contentInset = contentInset
            collectionView.scrollIndicatorInsets = contentInset
            let nextOffsetY = previousVisibleOffsetY - collectionView.adjustedContentInset.top
            if collectionView.contentOffset.y != nextOffsetY {
                collectionView.setContentOffset(
                    CGPoint(x: collectionView.contentOffset.x, y: nextOffsetY),
                    animated: false
                )
            }
            return true
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            verticalSurfaceCount
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: ReaderVerticalViewportCell.reuseIdentifier,
                for: indexPath
            )
            guard let cell = cell as? ReaderVerticalViewportCell else {
                return cell
            }
            guard let displaySurface = verticalDisplaySurface(for: indexPath.item) else {
                return cell
            }
            let displayReference = parent.displayReferenceProvider(displaySurface.identity)
            cell.configure(
                page: displaySurface,
                displayReference: displayReference,
                textHeight: displaySurface.presentationHeight,
                settings: parent.settings,
                refererURL: parent.refererURL,
                sessionState: parent.sessionState,
                contentWidth: max(verticalItemWidth(in: collectionView) - parent.settings.horizontalPadding * 2, 1),
                topPadding: displaySurface.surfaceIndex == 0 ? 16 : 0,
                onImageTap: parent.onImageTap
            )
            if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                cell.refreshLayout(for: attributes.size)
            }
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard let cell = cell as? ReaderVerticalViewportCell else { return }
            if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
                cell.refreshLayout(for: attributes.size)
            } else {
                cell.refreshLayoutForCurrentBounds(forceRedraw: true)
            }
            scheduleVisibleTextRedraw(in: collectionView, includeDelayedPass: false)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            CGSize(
                width: verticalItemWidth(in: collectionView),
                height: verticalItemHeight(for: indexPath.item, in: collectionView)
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            publishFrames(from: scrollView)
            let onViewportChange = parent.onViewportChange
            callbackScheduler.publish {
                onViewportChange()
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            publishScrollSettled(from: scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            publishScrollSettled(from: scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            publishScrollSettled(from: scrollView)
        }

        func publishLayout(from collectionView: UICollectionView) {
            publishFrames(from: collectionView)
            let onViewportChange = parent.onViewportChange
            callbackScheduler.publish {
                onViewportChange()
            }
        }

        func handle(_ request: ReaderVerticalScrollRequest?, in collectionView: UICollectionView) {
            guard let request else {
                handledScrollRequest = nil
                return
            }
            guard request.surfaceIndex >= 0, request.surfaceIndex < verticalSurfaceCount else {
                handledScrollRequest = nil
                return
            }
            guard collectionView.bounds.width > 0,
                  collectionView.bounds.height > 0,
                  collectionView.contentSize.height > 0 else {
                handledScrollRequest = nil
                return
            }
            guard handledScrollRequest != request else { return }
            handledScrollRequest = request
            collectionView.scrollToItem(
                at: IndexPath(item: request.surfaceIndex, section: 0),
                at: .top,
                animated: false
            )
            let didRestoreTextAnchor = restoreTextAnchorIfPossible(for: request, in: collectionView)
            guard request.textAnchor == nil || didRestoreTextAnchor else {
                handledScrollRequest = nil
                return
            }
            let onScrollRequestHandled = parent.onScrollRequestHandled
            callbackScheduler.publish {
                onScrollRequestHandled(request)
            }
            scheduleVisibleTextRedraw(in: collectionView, includeDelayedPass: true)
            publishScrollSettled(from: collectionView)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            if let collectionView = recognizer.view as? UICollectionView {
                let location = recognizer.location(in: collectionView)
                if let imageView = collectionView.firstDescendant(
                    ofType: ReaderVerticalViewportImageView.self,
                    containing: location
                ) {
                    let imageLocation = collectionView.convert(location, to: imageView)
                    handleImageTap(imageView, at: imageLocation)
                    return
                }
            }
            let onTap = parent.onTap
            callbackScheduler.publish {
                onTap()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer.view?.isDescendant(ofType: ReaderVerticalViewportImageView.self) == true
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

        private func publishFrames(from scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            let frames = collectionView.indexPathsForVisibleItems.reduce(into: [Int: ReaderVerticalSurfaceFrameValue]()) { result, indexPath in
                guard let surface = verticalSurface(for: indexPath.item),
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                    return
                }
                let visibleFrame = attributes.frame.offsetBy(
                    dx: -collectionView.contentOffset.x,
                    dy: -collectionView.contentOffset.y
                )
                result[surface.presentationIndex] = ReaderVerticalSurfaceFrameValue(
                    documentView: surface.documentView,
                    frame: visibleFrame
                )
            }
            let onSurfaceFramesChange = parent.onSurfaceFramesChange
            if lastPublishedSurfaceFrames != frames {
                lastPublishedSurfaceFrames = frames
                callbackScheduler.publish {
                    onSurfaceFramesChange(frames)
                }
            }
            let visibleSurfaceIdentities = collectionView.indexPathsForVisibleItems
                .sorted { $0.item < $1.item }
                .compactMap { verticalSurface(for: $0.item)?.identity }
            let onVisibleSurfaceIdentitiesChange = parent.onVisibleSurfaceIdentitiesChange
            if lastPublishedVisibleSurfaceIdentities != visibleSurfaceIdentities {
                lastPublishedVisibleSurfaceIdentities = visibleSurfaceIdentities
                callbackScheduler.publish {
                    onVisibleSurfaceIdentitiesChange(visibleSurfaceIdentities)
                }
            }

            let referenceLineY = ReaderVerticalPositioning.viewportReadingAnchorLineY(in: scrollView.bounds)
            let textSample = collectionView.indexPathsForVisibleItems
                .compactMap { indexPath -> (distance: CGFloat, sample: NovelTextViewportSample)? in
                    guard let surface = verticalSurface(for: indexPath.item),
                          let cell = collectionView.cellForItem(at: indexPath) as? ReaderVerticalViewportCell,
                          let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                        return nil
                    }
                    let visibleFrame = attributes.frame.offsetBy(
                        dx: -collectionView.contentOffset.x,
                        dy: -collectionView.contentOffset.y
                    )
                    guard let sample = cell.textViewportSample(
                        referenceLineY: referenceLineY,
                        surfaceFrame: visibleFrame
                    ) else {
                        return nil
                    }
                    return (ReaderVerticalPositioning.pageDistance(from: referenceLineY, to: visibleFrame), sample)
                }
                .min { $0.distance < $1.distance }?.sample
            let onTextViewportSampleChange = parent.onTextViewportSampleChange
            if shouldPublishTextViewportSample(textSample) {
                lastPublishedTextViewportSample = textSample
                hasPublishedNilTextViewportSample = textSample == nil
                callbackScheduler.publish {
                    onTextViewportSampleChange(textSample)
                }
            }
        }

        private func scheduleVisibleTextRedraw(in collectionView: UICollectionView, includeDelayedPass: Bool) {
            if !isImmediateVisibleTextRedrawScheduled {
                isImmediateVisibleTextRedrawScheduled = true
                DispatchQueue.main.async { [weak self, weak collectionView] in
                    self?.isImmediateVisibleTextRedrawScheduled = false
                    self?.redrawVisibleText(in: collectionView)
                }
            }
            guard includeDelayedPass, !isDelayedVisibleTextRedrawScheduled else { return }
            isDelayedVisibleTextRedrawScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak collectionView] in
                self?.isDelayedVisibleTextRedrawScheduled = false
                self?.redrawVisibleText(in: collectionView)
            }
        }

        private func redrawVisibleText(in collectionView: UICollectionView?) {
            collectionView?.visibleCells.forEach { cell in
                guard let cell = cell as? ReaderVerticalViewportCell else { return }
                cell.refreshLayoutForCurrentBounds(forceRedraw: true)
            }
        }

        private func resetPublishedViewportCache() {
            lastPublishedSurfaceFrames = nil
            lastPublishedVisibleSurfaceIdentities = nil
            lastPublishedTextViewportSample = nil
            hasPublishedNilTextViewportSample = false
        }

        private func shouldPublishTextViewportSample(_ sample: NovelTextViewportSample?) -> Bool {
            guard let sample else {
                return !hasPublishedNilTextViewportSample || lastPublishedTextViewportSample != nil
            }
            return lastPublishedTextViewportSample != sample
        }

        private func publishScrollSettled(from scrollView: UIScrollView) {
            publishFrames(from: scrollView)
            let onScrollSettled = parent.onScrollSettled
            callbackScheduler.publish {
                onScrollSettled()
            }
        }

        private func verticalItemWidth(in collectionView: UICollectionView) -> CGFloat {
            max(
                collectionView.bounds.width
                    - collectionView.adjustedContentInset.left
                    - collectionView.adjustedContentInset.right,
                1
            )
        }

        private func verticalItemHeight(for item: Int, in collectionView: UICollectionView) -> CGFloat {
            guard let displaySurface = verticalDisplaySurface(for: item) else {
                return max(collectionView.bounds.height, 1)
            }
            let topPadding = displaySurface.surfaceIndex == 0 ? CGFloat(16) : 0
            if let presentationHeight = displaySurface.presentationHeight {
                return max(ceil(presentationHeight + topPadding), 1)
            }
            let blockHeights = displaySurface.blocks.map { block -> CGFloat in
                switch block {
                case .text:
                    return max(collectionView.bounds.height, 1)
                case .image:
                    return max(collectionView.bounds.height, 160)
                case .footer:
                    return 44
                }
            }
            let contentHeight = blockHeights.reduce(CGFloat.zero, +)
            let spacingHeight = CGFloat(max(displaySurface.blocks.count - 1, 0)) * 14
            return max(ceil(contentHeight + spacingHeight + topPadding), 1)
        }

        private var verticalSurfaceCount: Int {
            parent.surfaces.count
        }

        private func verticalSurface(for item: Int) -> NovelReaderSurface? {
            guard parent.surfaces.indices.contains(item) else { return nil }
            return parent.surfaces[item]
        }

        private func verticalDisplaySurface(for item: Int) -> ReaderVerticalViewportDisplaySurface? {
            guard let surface = verticalSurface(for: item) else { return nil }
            return ReaderVerticalViewportDisplaySurface(
                identity: surface.identity,
                surfaceIndex: surface.presentationIndex,
                documentView: surface.documentView,
                chapterTitle: surface.chapterTitle,
                presentationHeight: surface.presentationSize.height > 0 ? surface.presentationSize.height : nil,
                blocks: ReaderViewportSurfaceContent.viewportBlocks(
                    surface: surface
                )
            )
        }

        private func restoreTextAnchorIfPossible(
            for request: ReaderVerticalScrollRequest,
            in collectionView: UICollectionView
        ) -> Bool {
            guard let textAnchor = request.textAnchor,
                  request.surfaceIndex >= 0,
                  request.surfaceIndex < verticalSurfaceCount else {
                return request.textAnchor == nil
            }

            let targetIndexPath = IndexPath(item: request.surfaceIndex, section: 0)
            let visibleItems = collectionView.indexPathsForVisibleItems.map(\.item)
            let nearbyItems = ((request.surfaceIndex - 2)...(request.surfaceIndex + 2))
                .filter { $0 >= 0 && $0 < verticalSurfaceCount }
            var seenItems = Set<Int>()
            let candidateItems = ([request.surfaceIndex] + visibleItems + nearbyItems)
                .filter { seenItems.insert($0).inserted }
                .sorted { lhs, rhs in
                    abs(lhs - request.surfaceIndex) < abs(rhs - request.surfaceIndex)
                }

            for item in candidateItems {
                let indexPath = IndexPath(item: item, section: 0)
                guard let cell = collectionView.cellForItem(at: indexPath) as? ReaderVerticalViewportCell,
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
                    continue
                }
                let visibleFrame = attributes.frame.offsetBy(
                    dx: -collectionView.contentOffset.x,
                    dy: -collectionView.contentOffset.y
                )
                guard let anchorY = cell.textViewportAnchorY(
                    for: textAnchor,
                    surfaceFrame: visibleFrame
                ) else {
                    continue
                }
                applyTextAnchorRestore(
                    anchorY: anchorY,
                    request: request,
                    collectionView: collectionView,
                    restoredItem: item,
                    visibleFrame: visibleFrame
                )
                return true
            }

            guard collectionView.cellForItem(at: targetIndexPath) is ReaderVerticalViewportCell,
                  let targetAttributes = collectionView.layoutAttributesForItem(at: targetIndexPath) else {
                return false
            }
            let targetFrame = targetAttributes.frame.offsetBy(
                dx: -collectionView.contentOffset.x,
                dy: -collectionView.contentOffset.y
            )
            applyProgressFallbackRestore(
                request: request,
                collectionView: collectionView,
                visibleFrame: targetFrame
            )
            return true
        }

        private func applyTextAnchorRestore(
            anchorY: CGFloat,
            request: ReaderVerticalScrollRequest,
            collectionView: UICollectionView,
            restoredItem: Int,
            visibleFrame: CGRect
        ) {
            let referenceLineY = ReaderVerticalPositioning.viewportReadingAnchorLineY(in: collectionView.bounds)
            let desiredY = collectionView.contentOffset.y + anchorY - referenceLineY
            let minOffsetY = -collectionView.adjustedContentInset.top
            let maxOffsetY = max(
                minOffsetY,
                collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
            )
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: min(max(desiredY, minOffsetY), maxOffsetY)),
                animated: false
            )
        }

        private func applyProgressFallbackRestore(
            request: ReaderVerticalScrollRequest,
            collectionView: UICollectionView,
            visibleFrame: CGRect
        ) {
            let referenceLineY = ReaderVerticalPositioning.viewportReadingAnchorLineY(in: collectionView.bounds)
            let desiredY = collectionView.contentOffset.y
                + visibleFrame.minY
                + visibleFrame.height * min(max(request.intraSurfaceProgress, 0), 1)
                - referenceLineY
            let minOffsetY = -collectionView.adjustedContentInset.top
            let maxOffsetY = max(
                minOffsetY,
                collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
            )
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: min(max(desiredY, minOffsetY), maxOffsetY)),
                animated: false
            )
        }
    }
}

private final class ReaderVerticalViewportCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

private final class ReaderVerticalViewportCell: UICollectionViewCell {
    static let reuseIdentifier = "ReaderVerticalViewportScrollCell"

    private struct BlockView {
        let view: UIView
        let height: CGFloat
        let displayReference: NovelTextViewportDisplayReference?
    }

    private var blockViews: [BlockView] = []
    private var currentPage: ReaderVerticalViewportDisplaySurface?
    private var currentSettings = ReaderAppearanceSettings()
    private var currentRefererURL: URL?
    private var currentSessionState = SessionState()
    private var currentContentWidth: CGFloat = 0
    private var currentTopPadding: CGFloat = 0
    private var currentDisplayReference: NovelTextViewportDisplayReference?
    private var currentTextHeight: CGFloat?
    private var currentOnImageTap: (URL, String?) -> Void = { _, _ in }
    private var lastAppliedLayoutSize = CGSize.zero
    private var preferredLayoutSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViewHierarchy()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentPage = nil
        currentDisplayReference = nil
        currentTextHeight = nil
        currentOnImageTap = { _, _ in }
        lastAppliedLayoutSize = .zero
        preferredLayoutSize = .zero
        removeBlockSubviews()
    }

    override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        let previousSize = lastAppliedLayoutSize
        super.apply(layoutAttributes)
        let nextSize = effectiveLayoutSize(for: layoutAttributes.size)
        guard previousSize != nextSize else { return }
        lastAppliedLayoutSize = nextSize
        applyContentViewFrame(for: nextSize)
        refreshLayoutForCurrentBounds()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyContentViewFrame(for: effectiveLayoutSize(for: bounds.size))
        layoutBlockSubviews()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle,
              let currentPage,
              let currentRefererURL else {
            return
        }
        configure(
            page: currentPage,
            displayReference: currentDisplayReference,
            textHeight: currentTextHeight,
            settings: currentSettings,
            refererURL: currentRefererURL,
            sessionState: currentSessionState,
            contentWidth: currentContentWidth,
            topPadding: currentTopPadding,
            onImageTap: currentOnImageTap
        )
    }

    func configure(
        page: ReaderVerticalViewportDisplaySurface,
        displayReference: NovelTextViewportDisplayReference?,
        textHeight: CGFloat?,
        settings: ReaderAppearanceSettings,
        refererURL: URL,
        sessionState: SessionState,
        contentWidth: CGFloat,
        topPadding: CGFloat,
        onImageTap: @escaping (URL, String?) -> Void
    ) {
        currentPage = page
        currentDisplayReference = displayReference
        currentTextHeight = textHeight
        currentSettings = settings
        currentRefererURL = refererURL
        currentSessionState = sessionState
        currentContentWidth = contentWidth
        currentTopPadding = topPadding
        currentOnImageTap = onImageTap

        removeBlockSubviews()

        for (blockIndex, block) in page.blocks.enumerated() {
            let blockView = makeBlockView(
                for: block,
                blockIndex: blockIndex,
                page: page,
                contentWidth: contentWidth,
                refererURL: refererURL,
                sessionState: sessionState,
                displayReference: displayReference,
                textHeight: textHeight,
                onImageTap: onImageTap
            )
            blockViews.append(blockView)
            contentView.addSubview(blockView.view)
        }
        let blockHeight = blockViews.reduce(CGFloat.zero) { $0 + $1.height }
        let spacingHeight = CGFloat(max(blockViews.count - 1, 0)) * 14
        preferredLayoutSize = CGSize(
            width: max(contentWidth + settings.horizontalPadding * 2, bounds.width, 1),
            height: max(ceil(blockHeight + spacingHeight + topPadding), 1)
        )
        refreshLayout(for: preferredLayoutSize)
    }

    func textViewportSample(
        referenceLineY: CGFloat,
        surfaceFrame: CGRect
    ) -> NovelTextViewportSample? {
        let contentY = referenceLineY - surfaceFrame.minY
        let candidates = blockViews.compactMap { block -> (distance: CGFloat, sample: NovelTextViewportSample)? in
            guard let displayReference = block.displayReference else {
                return nil
            }
            let referencePoint = CGPoint(x: block.view.bounds.midX, y: contentY - block.view.frame.minY)
            guard let sample = displayReference.viewportSample(referencePoint: referencePoint) else {
                return nil
            }
            return (ReaderVerticalPositioning.pageDistance(from: contentY, to: block.view.frame), sample)
        }
        return candidates.min { $0.distance < $1.distance }?.sample
    }

    func textViewportAnchorY(
        for anchor: ReaderVerticalTextAnchor,
        surfaceFrame: CGRect
    ) -> CGFloat? {
        for block in blockViews {
            guard let displayReference = block.displayReference,
                  let referenceY = displayReference.referenceY(for: anchor.position) else {
                continue
            }
            return surfaceFrame.minY + block.view.frame.minY + referenceY
        }
        return nil
    }

    func setNeedsDisplayForTextBlocks() {
        for block in blockViews where block.displayReference != nil {
            block.view.setNeedsDisplay()
        }
    }

    func refreshLayoutForCurrentBounds(forceRedraw: Bool = false) {
        let didChangeLayout = layoutBlockSubviews()
        if forceRedraw || didChangeLayout {
            setNeedsDisplayForTextBlocks()
        }
    }

    func refreshLayout(for layoutSize: CGSize) {
        let nextSize = effectiveLayoutSize(for: layoutSize)
        lastAppliedLayoutSize = nextSize
        applyContentViewFrame(for: nextSize)
        refreshLayoutForCurrentBounds()
    }

    private func configureViewHierarchy() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        clipsToBounds = true
        contentView.clipsToBounds = true
    }

    private func makeBlockView(
        for block: ReaderViewportDisplayBlock,
        blockIndex: Int,
        page: ReaderVerticalViewportDisplaySurface,
        contentWidth: CGFloat,
        refererURL: URL,
        sessionState: SessionState,
        displayReference: NovelTextViewportDisplayReference?,
        textHeight: CGFloat?,
        onImageTap: @escaping (URL, String?) -> Void
    ) -> BlockView {
        switch block {
        case .text:
            return makeTextBlockView(
                contentWidth: contentWidth,
                displayReference: displayReference,
                textHeight: textHeight
            )
        case let .image(url):
            return makeImageBlockView(
                url: url,
                refererURL: refererURL,
                sessionState: sessionState,
                preferredHeight: textHeight,
                title: page.chapterTitle,
                onImageTap: onImageTap
            )
        case let .footer(text):
            return makeFooterBlockView(text)
        }
    }

    private func makeTextBlockView(
        contentWidth: CGFloat,
        displayReference: NovelTextViewportDisplayReference?,
        textHeight: CGFloat?
    ) -> BlockView {
        let surface = NovelTextViewportReferenceUIView()
        surface.displayReference = displayReference
        return BlockView(
            view: surface,
            height: max(textHeight ?? bounds.height, 1),
            displayReference: displayReference
        )
    }

    private func makeImageBlockView(
        url: URL,
        refererURL: URL,
        sessionState: SessionState,
        preferredHeight: CGFloat?,
        title: String?,
        onImageTap: @escaping (URL, String?) -> Void
    ) -> BlockView {
        let height = max(preferredHeight ?? bounds.height, 1)
        let imageView = ReaderVerticalViewportImageView()
        imageView.configure(url: url, refererURL: refererURL, sessionState: sessionState, title: title, onTap: onImageTap)
        return BlockView(view: imageView, height: height, displayReference: nil)
    }

    private func makeFooterBlockView(_ text: String) -> BlockView {
        let label = UILabel()
        label.text = text
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .caption1)
        label.numberOfLines = 0
        return BlockView(view: label, height: 44, displayReference: nil)
    }

    @discardableResult
    private func layoutBlockSubviews() -> Bool {
        let x = currentSettings.horizontalPadding
        let width = max(contentView.bounds.width - currentSettings.horizontalPadding * 2, currentContentWidth, 1)
        var y = currentTopPadding
        var didChangeLayout = false
        for blockView in blockViews {
            let height = max(ceil(blockView.height), 1)
            let frame = CGRect(x: x, y: y, width: width, height: height)
            if blockView.view.frame != frame {
                blockView.view.frame = frame
                didChangeLayout = true
            }
            y += height + 14
        }
        return didChangeLayout
    }

    private func effectiveLayoutSize(for layoutSize: CGSize) -> CGSize {
        guard preferredLayoutSize.width > 0, preferredLayoutSize.height > 0 else {
            return layoutSize
        }
        return CGSize(
            width: max(layoutSize.width, preferredLayoutSize.width, 1),
            height: preferredLayoutSize.height
        )
    }

    private func applyContentViewFrame(for layoutSize: CGSize) {
        guard layoutSize.width > 0, layoutSize.height > 0 else { return }
        let contentFrame = CGRect(origin: .zero, size: layoutSize)
        if contentView.frame != contentFrame {
            contentView.frame = contentFrame
        }
    }

    private func removeBlockSubviews() {
        for blockView in blockViews {
            blockView.view.removeFromSuperview()
        }
        blockViews.removeAll()
    }
}

final class ReaderVerticalViewportImageView: UIView {
    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let failureLabel = UILabel()
    private var task: Task<Void, Never>?
    private var url: URL?
    private var title: String?
    private var requestIdentity: RequestIdentity?

    private struct RequestIdentity: Equatable {
        let url: URL
        let refererURL: URL
        let userAgent: String
        let cookie: String
    }

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

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        guard let image = imageView.image else {
            return !activityIndicator.isHidden || !failureLabel.isHidden
        }
        return ReaderImageHitTesting.containsImagePoint(
            point,
            imageSize: image.size,
            containerSize: bounds.size
        )
    }

    func configure(
        url: URL,
        refererURL: URL,
        sessionState: SessionState,
        title: String?,
        onTap: @escaping (URL, String?) -> Void
    ) {
        let nextRequestIdentity = RequestIdentity(
            url: url,
            refererURL: refererURL,
            userAgent: sessionState.userAgent,
            cookie: sessionState.cookie
        )
        self.url = url
        self.title = title
        guard requestIdentity != nextRequestIdentity else { return }
        requestIdentity = nextRequestIdentity
        task?.cancel()
        imageView.image = nil
        failureLabel.isHidden = true
        activityIndicator.startAnimating()
        task = Task { [weak self] in
            var request = URLRequest(url: url)
            request.setValue(sessionState.userAgent, forHTTPHeaderField: "User-Agent")
            if !sessionState.cookie.isEmpty {
                request.setValue(sessionState.cookie, forHTTPHeaderField: "Cookie")
            }
            request.setValue(refererURL.absoluteString, forHTTPHeaderField: "Referer")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      200 ..< 300 ~= http.statusCode,
                      let image = UIImage(data: data) else {
                    await self?.showFailure()
                    return
                }
                await self?.show(image: image)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.showFailure()
            }
        }
    }

    private func configureViewHierarchy() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)

        failureLabel.text = L10n.string("image.load_failed")
        failureLabel.textColor = .secondaryLabel
        failureLabel.font = .preferredFont(forTextStyle: .caption1)
        failureLabel.textAlignment = .center
        failureLabel.isHidden = true
        failureLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(failureLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            failureLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            failureLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            failureLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            failureLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }

    func imageTapPayloadIfHit(at point: CGPoint) -> (url: URL, title: String?)? {
        guard let url,
              let image = imageView.image,
              ReaderImageHitTesting.containsImagePoint(
                  point,
                  imageSize: image.size,
                  containerSize: bounds.size
              ) else {
            return nil
        }
        return (url, title)
    }

    @MainActor
    private func show(image: UIImage) {
        activityIndicator.stopAnimating()
        failureLabel.isHidden = true
        imageView.image = image
    }

    @MainActor
    private func showFailure() {
        activityIndicator.stopAnimating()
        failureLabel.isHidden = false
        imageView.image = nil
    }
}

struct ReaderInlineViewportImage: UIViewRepresentable {
    let url: URL
    let refererURL: URL
    let sessionState: SessionState
    let title: String?
    let onTap: (URL, String?) -> Void

    func makeUIView(context: Context) -> ReaderVerticalViewportImageView {
        ReaderVerticalViewportImageView()
    }

    func updateUIView(_ uiView: ReaderVerticalViewportImageView, context: Context) {
        uiView.configure(
            url: url,
            refererURL: refererURL,
            sessionState: sessionState,
            title: title,
            onTap: onTap
        )
    }
}

extension UIView {
    func isDescendant<T: UIView>(ofType type: T.Type) -> Bool {
        if self is T {
            return true
        }
        return superview?.isDescendant(ofType: type) ?? false
    }

    func firstDescendant<T: UIView>(
        ofType type: T.Type,
        containing point: CGPoint,
        event: UIEvent? = nil
    ) -> T? {
        for subview in subviews.reversed() {
            let subviewPoint = convert(point, to: subview)
            if let typedSubview = subview as? T,
               typedSubview.point(inside: subviewPoint, with: event) {
                return typedSubview
            }
            if let match = subview.firstDescendant(
                ofType: type,
                containing: subviewPoint,
                event: event
            ) {
                return match
            }
        }
        return nil
    }
}

private struct ReaderVerticalViewportContentIdentity: Hashable {
    var surfaces: [NovelReaderSurface]
    var settings: ReaderAppearanceSettings
}
#endif
