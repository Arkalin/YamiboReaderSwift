import SwiftUI
import YamiboReaderCore

struct ReaderPagedPageTurnVisualMetrics: Equatable {
    var roundedPageIndex: Int
    var maskedPageIndex: Int
    var overlayAlpha: CGFloat
    var cornerRadius: CGFloat

    var isActive: Bool {
        overlayAlpha > 0
    }
}

enum ReaderPagedPageTurnPresentation {
    static let maxOverlayAlpha: CGFloat = 0.22
    static let fallbackPageCornerRadius: CGFloat = 56
    private static let completionThreshold: CGFloat = 0.001

    static func metrics(
        contentOffsetX: CGFloat,
        pageWidth: CGFloat,
        pageCount: Int,
        restingPageIndex: Int,
        maxOverlayAlpha: CGFloat = Self.maxOverlayAlpha,
        cornerRadius: CGFloat = Self.fallbackPageCornerRadius
    ) -> ReaderPagedPageTurnVisualMetrics? {
        guard pageWidth > 0, pageCount > 1 else { return nil }

        let progress = contentOffsetX / pageWidth
        let clampedRestingIndex = min(max(restingPageIndex, 0), max(pageCount - 1, 0))
        let delta = progress - CGFloat(clampedRestingIndex)
        guard abs(delta) > completionThreshold else { return nil }

        let targetIndex = delta > 0 ? clampedRestingIndex + 1 : clampedRestingIndex - 1
        guard targetIndex >= 0, targetIndex < pageCount else { return nil }

        let turnProgress = min(max(abs(delta), 0), 1)
        guard turnProgress < 1 - completionThreshold else { return nil }

        return ReaderPagedPageTurnVisualMetrics(
            roundedPageIndex: clampedRestingIndex,
            maskedPageIndex: targetIndex,
            overlayAlpha: maxOverlayAlpha * (1 - turnProgress),
            cornerRadius: cornerRadius
        )
    }
}

#if os(iOS)
import UIKit

struct ReaderPagedPageSurfaceContainer<Content: View>: View {
    let settings: ReaderAppearanceSettings
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(readerThemeColor(for: settings.backgroundStyle, colorScheme: colorScheme))
    }
}

enum ReaderPagedPageTurnBackground {
    static func dimmedPageColor(
        settings: ReaderAppearanceSettings,
        traitCollection: UITraitCollection,
        overlayAlpha: CGFloat
    ) -> UIColor {
        let base = pageColor(
            for: settings.backgroundStyle,
            isDarkMode: traitCollection.userInterfaceStyle == .dark
        )
        return blend(base: base, overlay: .black, alpha: min(max(overlayAlpha, 0), 1))
    }

    private static func pageColor(for style: ReaderBackgroundStyle, isDarkMode: Bool) -> UIColor {
        if isDarkMode {
            switch style {
            case .system:
                return UIColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1)
            case .paper:
                return UIColor(red: 0.21, green: 0.19, blue: 0.16, alpha: 1)
            case .mint:
                return UIColor(red: 0.14, green: 0.18, blue: 0.16, alpha: 1)
            case .sakura:
                return UIColor(red: 0.19, green: 0.16, blue: 0.18, alpha: 1)
            }
        }

        switch style {
        case .system:
            return UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
        case .paper:
            return UIColor(red: 0.945, green: 0.882, blue: 0.769, alpha: 1)
        case .mint:
            return UIColor(red: 0.92, green: 0.97, blue: 0.93, alpha: 1)
        case .sakura:
            return UIColor(red: 0.97, green: 0.92, blue: 0.93, alpha: 1)
        }
    }

    private static func blend(base: UIColor, overlay: UIColor, alpha: CGFloat) -> UIColor {
        var baseRed: CGFloat = 0
        var baseGreen: CGFloat = 0
        var baseBlue: CGFloat = 0
        var baseAlpha: CGFloat = 0
        var overlayRed: CGFloat = 0
        var overlayGreen: CGFloat = 0
        var overlayBlue: CGFloat = 0
        var overlayAlpha: CGFloat = 0

        base.getRed(&baseRed, green: &baseGreen, blue: &baseBlue, alpha: &baseAlpha)
        overlay.getRed(&overlayRed, green: &overlayGreen, blue: &overlayBlue, alpha: &overlayAlpha)

        return UIColor(
            red: baseRed * (1 - alpha) + overlayRed * alpha,
            green: baseGreen * (1 - alpha) + overlayGreen * alpha,
            blue: baseBlue * (1 - alpha) + overlayBlue * alpha,
            alpha: baseAlpha
        )
    }
}

enum ReaderPagedPageTurnCornerRadius {
    static let fallbackRadius = ReaderPagedPageTurnPresentation.fallbackPageCornerRadius
    private static let displayCornerRadiusSelectorName = ["_display", "Corner", "Radius"].joined()

    static func radius(for screen: UIScreen?) -> CGFloat {
        guard let screen else { return fallbackRadius }
        let selector = NSSelectorFromString(displayCornerRadiusSelectorName)
        guard screen.responds(to: selector),
              let value = screen.value(forKey: displayCornerRadiusSelectorName) as? NSNumber else {
            return fallbackRadius
        }
        let radius = CGFloat(truncating: value)
        return radius > 0 ? radius : fallbackRadius
    }
}

final class ReaderPagedViewportCollectionView: UICollectionView {
    var onLayoutSubviews: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutSubviews?()
    }
}

final class ReaderPagedPageTurnCell: UICollectionViewCell {
    private let pageTurnOverlayView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configurePageTurnOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePageTurnOverlay()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetPageTurnVisuals()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensurePageTurnOverlay()
        pageTurnOverlayView.frame = bounds
        bringSubviewToFront(pageTurnOverlayView)
    }

    func applyPageTurnVisuals(overlayAlpha: CGFloat, cornerRadius: CGFloat) {
        ensurePageTurnOverlay()
        pageTurnOverlayView.alpha = min(max(overlayAlpha, 0), 1)
        layer.cornerRadius = max(cornerRadius, 0)
        layer.cornerCurve = .continuous
        layer.masksToBounds = cornerRadius > 0
        bringSubviewToFront(pageTurnOverlayView)
    }

    func resetPageTurnVisuals() {
        ensurePageTurnOverlay()
        pageTurnOverlayView.alpha = 0
        layer.cornerRadius = 0
        layer.masksToBounds = false
    }

    private func configurePageTurnOverlay() {
        pageTurnOverlayView.backgroundColor = .black
        pageTurnOverlayView.alpha = 0
        pageTurnOverlayView.isUserInteractionEnabled = false
        pageTurnOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        ensurePageTurnOverlay()
    }

    private func ensurePageTurnOverlay() {
        guard pageTurnOverlayView.superview !== self else { return }
        pageTurnOverlayView.removeFromSuperview()
        addSubview(pageTurnOverlayView)
    }
}

struct ReaderPagedViewportContentIdentity: Equatable {
    var surfaces: [NovelReaderSurface]
    var settings: ReaderAppearanceSettings
    var refererURL: URL
    var sessionState: ReaderPagedViewportSessionIdentity
    var topInset: CGFloat
    var bottomInset: CGFloat

    init(
        surfaces: [NovelReaderSurface],
        settings: ReaderAppearanceSettings,
        refererURL: URL,
        sessionState: SessionState,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) {
        self.surfaces = surfaces
        self.settings = settings
        self.refererURL = refererURL
        self.sessionState = ReaderPagedViewportSessionIdentity(sessionState)
        self.topInset = topInset
        self.bottomInset = bottomInset
    }
}

struct ReaderPagedSpreadViewportContentIdentity: Equatable {
    var spreads: [NovelReaderPresentationSpread]
    var content: ReaderPagedViewportContentIdentity
}

struct ReaderPagedScrollAnimationRequest: Equatable {
    let id: UUID
    let pagerIdentity: ReaderPagedPagerIdentity
    let selectionIndex: Int

    init(
        id: UUID = UUID(),
        pagerIdentity: ReaderPagedPagerIdentity,
        selectionIndex: Int
    ) {
        self.id = id
        self.pagerIdentity = pagerIdentity
        self.selectionIndex = max(0, selectionIndex)
    }
}

struct ReaderPagedViewportSessionIdentity: Equatable {
    var userAgent: String
    var cookie: String

    init(_ sessionState: SessionState) {
        userAgent = sessionState.userAgent
        cookie = sessionState.cookie
    }
}

struct ReaderPagedViewportPagingInputs: @unchecked Sendable {
    var itemCount: Int
    var selectionIndex: Int
    var settings: ReaderAppearanceSettings
    var pagerIdentity: ReaderPagedPagerIdentity
    var scrollAnimationRequest: ReaderPagedScrollAnimationRequest?
    var onSelectionChange: (Int) -> Void
    var onScrollAnimationRequestConsumed: (ReaderPagedScrollAnimationRequest) -> Void
}

@MainActor
final class ReaderPagedViewportPagingDriver {
    private static let quickFadeDuration: TimeInterval = 0.18
    private static let quickFadeMinimumTranslation: CGFloat = 48
    private static let quickFadeTranslationWidthFactor: CGFloat = 0.18
    private static let quickFadeVelocityThreshold: CGFloat = 450

    let callbackScheduler = SwiftUIViewUpdateCallbackScheduler()
    private var pendingSelectionIndex: Int?
    private var isReloadingDataForSelectionScroll = false
    private var isPendingSelectionScrollRetryScheduled = false
    private var consumedScrollAnimationRequestID: UUID?
    private var pageTurnRestingIndex: Int?
    private var isPerformingQuickFadeTransition = false

    func updateContentAndRequestSelectionScroll(
        in collectionView: UICollectionView,
        didChangeContentIdentity: Bool,
        inputs: ReaderPagedViewportPagingInputs
    ) {
        let animationRequest = matchingScrollAnimationRequest(inputs: inputs)
        guard didChangeContentIdentity else {
            if let animationRequest {
                _ = requestSelectionScroll(
                    in: collectionView,
                    animated: true,
                    inputs: inputs
                ) { [weak self] in
                    self?.consumeScrollAnimationRequest(animationRequest, inputs: inputs)
                }
            } else {
                _ = requestSelectionScroll(in: collectionView, animated: false, inputs: inputs)
            }
            return
        }
        if let animationRequest {
            consumeScrollAnimationRequest(animationRequest, inputs: inputs)
        }
        collectionView.collectionViewLayout.invalidateLayout()
        reloadDataAndRequestSelectionScroll(in: collectionView, animated: false, inputs: inputs)
    }

    func reloadDataAndRequestSelectionScroll(
        in collectionView: UICollectionView,
        animated: Bool,
        inputs: ReaderPagedViewportPagingInputs
    ) {
        pendingSelectionIndex = inputs.selectionIndex
        isReloadingDataForSelectionScroll = true
        collectionView.reloadData()
        collectionView.performBatchUpdates(nil) { [weak self, weak collectionView] _ in
            guard let collectionView else { return }
            self?.isReloadingDataForSelectionScroll = false
            self?.requestSelectionScroll(in: collectionView, animated: animated, inputs: inputs)
            self?.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: inputs)
        }
    }

    @discardableResult
    func requestSelectionScroll(
        in collectionView: UICollectionView,
        animated: Bool,
        inputs: ReaderPagedViewportPagingInputs,
        onTransitionCompletion: (() -> Void)? = nil
    ) -> Bool {
        pendingSelectionIndex = inputs.selectionIndex
        return scrollToPendingSelectionIfPossible(
            in: collectionView,
            animated: animated,
            inputs: inputs,
            onTransitionCompletion: onTransitionCompletion
        )
    }

    @discardableResult
    func scrollToPendingSelectionIfPossible(
        in collectionView: UICollectionView,
        animated: Bool,
        inputs: ReaderPagedViewportPagingInputs,
        onTransitionCompletion: (() -> Void)? = nil
    ) -> Bool {
        guard let pendingSelectionIndex,
              !isReloadingDataForSelectionScroll,
              inputs.itemCount > 0,
              collectionView.bounds.width > 0,
              collectionView.window != nil else {
            return false
        }
        let item = min(max(pendingSelectionIndex, 0), max(inputs.itemCount - 1, 0))
        guard collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) > item else {
            schedulePendingSelectionScrollRetry(in: collectionView, animated: animated, inputs: inputs)
            return false
        }

        collectionView.layoutIfNeeded()
        let targetContentOffsetX = CGFloat(item) * collectionView.bounds.width
        guard collectionView.contentSize.width >= targetContentOffsetX + collectionView.bounds.width else {
            schedulePendingSelectionScrollRetry(in: collectionView, animated: animated, inputs: inputs)
            return false
        }

        return performSelectionTransition(
            to: item,
            targetContentOffsetX: targetContentOffsetX,
            in: collectionView,
            animated: animated,
            inputs: inputs,
            onTransitionCompletion: onTransitionCompletion
        )
    }

    func animateAdjacentSelection(
        for zone: ReaderPagedTapZone,
        in collectionView: UICollectionView,
        inputs: ReaderPagedViewportPagingInputs
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

        guard inputs.itemCount > 0,
              collectionView.bounds.width > 0,
              collectionView.window != nil else {
            return false
        }
        let targetItem = inputs.selectionIndex + delta
        guard targetItem >= 0, targetItem < inputs.itemCount else {
            return false
        }
        pendingSelectionIndex = targetItem
        return scrollToPendingSelectionIfPossible(in: collectionView, animated: true, inputs: inputs)
    }

    func updateGestureState(in collectionView: UICollectionView, inputs: ReaderPagedViewportPagingInputs) {
        collectionView.panGestureRecognizer.isEnabled = inputs.settings.pagedTurnStyle != .quickFade
        if inputs.settings.pagedTurnStyle == .quickFade {
            resetPageTurnVisuals(in: collectionView)
        }
    }

    func quickFadePanShouldBegin(_ recognizer: UIPanGestureRecognizer, inputs: ReaderPagedViewportPagingInputs) -> Bool {
        guard inputs.settings.pagedTurnStyle == .quickFade,
              inputs.itemCount > 1,
              let view = recognizer.view else {
            return false
        }
        let velocity = recognizer.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    func handleQuickFadePan(_ recognizer: UIPanGestureRecognizer, inputs: ReaderPagedViewportPagingInputs) {
        guard inputs.settings.pagedTurnStyle == .quickFade,
              let collectionView = recognizer.view as? UICollectionView else {
            return
        }

        switch recognizer.state {
        case .ended:
            guard let delta = quickFadePanDelta(for: recognizer, in: collectionView) else { return }
            let targetItem = inputs.selectionIndex + delta
            guard targetItem >= 0, targetItem < inputs.itemCount else { return }
            pendingSelectionIndex = targetItem
            _ = scrollToPendingSelectionIfPossible(in: collectionView, animated: true, inputs: inputs)
        case .cancelled, .failed:
            resetPageTurnVisuals(in: collectionView)
        default:
            break
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView, inputs: ReaderPagedViewportPagingInputs) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        guard inputs.settings.pagedTurnStyle != .quickFade else {
            resetPageTurnVisuals(in: collectionView)
            return
        }
        beginPageTurnVisuals(in: collectionView, inputs: inputs)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView, inputs: ReaderPagedViewportPagingInputs) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        guard inputs.settings.pagedTurnStyle != .quickFade else {
            resetPageTurnVisuals(in: collectionView)
            return
        }
        applyPageTurnVisuals(in: collectionView, inputs: inputs)
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool,
        inputs: ReaderPagedViewportPagingInputs
    ) {
        guard let collectionView = scrollView as? UICollectionView else { return }
        if !decelerate {
            updateSelection(from: scrollView, inputs: inputs)
            endPageTurnVisuals(in: collectionView)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView, inputs: ReaderPagedViewportPagingInputs) {
        updateSelection(from: scrollView, inputs: inputs)
        guard let collectionView = scrollView as? UICollectionView else { return }
        endPageTurnVisuals(in: collectionView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView, inputs: ReaderPagedViewportPagingInputs) {
        updateSelection(from: scrollView, inputs: inputs)
        guard let collectionView = scrollView as? UICollectionView else { return }
        endPageTurnVisuals(in: collectionView)
    }

    private func schedulePendingSelectionScrollRetry(
        in collectionView: UICollectionView,
        animated: Bool,
        inputs: ReaderPagedViewportPagingInputs
    ) {
        guard !isPendingSelectionScrollRetryScheduled else { return }
        isPendingSelectionScrollRetryScheduled = true
        DispatchQueue.main.async { [weak self, weak collectionView] in
            guard let self else { return }
            self.isPendingSelectionScrollRetryScheduled = false
            guard let collectionView else { return }
            self.scrollToPendingSelectionIfPossible(in: collectionView, animated: animated, inputs: inputs)
        }
    }

    private func updateSelection(from scrollView: UIScrollView, inputs: ReaderPagedViewportPagingInputs) {
        guard scrollView.bounds.width > 0 else { return }
        let item = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        let clampedItem = min(max(item, 0), max(inputs.itemCount - 1, 0))
        publishSelectionIfNeeded(clampedItem, inputs: inputs)
    }

    private func publishSelectionIfNeeded(_ selectionIndex: Int, inputs: ReaderPagedViewportPagingInputs) {
        let clampedItem = min(max(selectionIndex, 0), max(inputs.itemCount - 1, 0))
        guard clampedItem != inputs.selectionIndex else { return }
        let onSelectionChange = inputs.onSelectionChange
        callbackScheduler.publish {
            onSelectionChange(clampedItem)
        }
    }

    @discardableResult
    private func performSelectionTransition(
        to item: Int,
        targetContentOffsetX: CGFloat,
        in collectionView: UICollectionView,
        animated: Bool,
        inputs: ReaderPagedViewportPagingInputs,
        onTransitionCompletion: (() -> Void)? = nil
    ) -> Bool {
        guard !animated || inputs.settings.pagedTurnStyle != .quickFade || !isPerformingQuickFadeTransition else {
            return false
        }

        let targetOffset = CGPoint(x: targetContentOffsetX, y: collectionView.contentOffset.y)
        guard animated else {
            resetPageTurnVisuals(in: collectionView)
            collectionView.setContentOffset(targetOffset, animated: false)
            collectionView.layoutIfNeeded()
            pendingSelectionIndex = nil
            publishSelectionIfNeeded(item, inputs: inputs)
            onTransitionCompletion?()
            return true
        }

        switch inputs.settings.pagedTurnStyle {
        case .slide:
            beginPageTurnVisuals(in: collectionView, inputs: inputs)
            collectionView.setContentOffset(targetOffset, animated: true)
            applyPageTurnVisuals(in: collectionView, inputs: inputs)
            pendingSelectionIndex = nil
            onTransitionCompletion?()
        case .quickFade:
            isPerformingQuickFadeTransition = true
            resetPageTurnVisuals(in: collectionView)
            guard let quickFadeSnapshot = collectionView.snapshotView(afterScreenUpdates: false) else {
                collectionView.setContentOffset(targetOffset, animated: false)
                collectionView.layoutIfNeeded()
                isPerformingQuickFadeTransition = false
                pendingSelectionIndex = nil
                publishSelectionIfNeeded(item, inputs: inputs)
                onTransitionCompletion?()
                return true
            }

            quickFadeSnapshot.isUserInteractionEnabled = false
            if let snapshotContainer = collectionView.superview {
                quickFadeSnapshot.frame = collectionView.convert(collectionView.bounds, to: snapshotContainer)
                snapshotContainer.addSubview(quickFadeSnapshot)
            } else {
                quickFadeSnapshot.frame = CGRect(origin: targetOffset, size: collectionView.bounds.size)
                collectionView.addSubview(quickFadeSnapshot)
            }
            collectionView.setContentOffset(targetOffset, animated: false)
            collectionView.layoutIfNeeded()
            UIView.animate(
                withDuration: Self.quickFadeDuration,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                quickFadeSnapshot.alpha = 0
            } completion: { [weak self] _ in
                quickFadeSnapshot.removeFromSuperview()
                guard let self else { return }
                self.isPerformingQuickFadeTransition = false
                self.pendingSelectionIndex = nil
                self.publishSelectionIfNeeded(item, inputs: inputs)
                onTransitionCompletion?()
            }
        }
        return true
    }

    private func quickFadePanDelta(for recognizer: UIPanGestureRecognizer, in collectionView: UICollectionView) -> Int? {
        let translation = recognizer.translation(in: collectionView)
        let velocity = recognizer.velocity(in: collectionView)
        if abs(velocity.x) >= Self.quickFadeVelocityThreshold, abs(velocity.x) > abs(velocity.y) {
            return velocity.x < 0 ? 1 : -1
        }

        let translationThreshold = max(
            Self.quickFadeMinimumTranslation,
            collectionView.bounds.width * Self.quickFadeTranslationWidthFactor
        )
        guard abs(translation.x) >= translationThreshold, abs(translation.x) > abs(translation.y) else {
            return nil
        }
        return translation.x < 0 ? 1 : -1
    }

    private func beginPageTurnVisuals(in collectionView: UICollectionView, inputs: ReaderPagedViewportPagingInputs) {
        guard collectionView.bounds.width > 0 else { return }
        let currentIndex = Int((collectionView.contentOffset.x / collectionView.bounds.width).rounded())
        pageTurnRestingIndex = min(max(currentIndex, 0), max(inputs.itemCount - 1, 0))
    }

    private func applyPageTurnVisuals(in collectionView: UICollectionView, inputs: ReaderPagedViewportPagingInputs) {
        guard let metrics = ReaderPagedPageTurnPresentation.metrics(
            contentOffsetX: collectionView.contentOffset.x,
            pageWidth: collectionView.bounds.width,
            pageCount: inputs.itemCount,
            restingPageIndex: pageTurnRestingIndex ?? inputs.selectionIndex,
            cornerRadius: ReaderPagedPageTurnCornerRadius.radius(for: collectionView.window?.screen)
        ) else {
            resetPageTurnVisuals(in: collectionView)
            return
        }
        collectionView.backgroundColor = ReaderPagedPageTurnBackground.dimmedPageColor(
            settings: inputs.settings,
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

    private func matchingScrollAnimationRequest(
        inputs: ReaderPagedViewportPagingInputs
    ) -> ReaderPagedScrollAnimationRequest? {
        guard let request = inputs.scrollAnimationRequest,
              request.id != consumedScrollAnimationRequestID,
              request.pagerIdentity == inputs.pagerIdentity,
              request.selectionIndex == inputs.selectionIndex else {
            return nil
        }
        return request
    }

    private func consumeScrollAnimationRequest(
        _ request: ReaderPagedScrollAnimationRequest,
        inputs: ReaderPagedViewportPagingInputs
    ) {
        consumedScrollAnimationRequestID = request.id
        let onScrollAnimationRequestConsumed = inputs.onScrollAnimationRequestConsumed
        callbackScheduler.publish {
            onScrollAnimationRequestConsumed(request)
        }
    }
}
#endif
