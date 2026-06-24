import CoreGraphics
import YamiboReaderCore

enum MangaPageZoomPolicy {
    static let minimumScale: CGFloat = 1
    static let doubleTapScale: CGFloat = 2
    static let maximumScale: CGFloat = 4
    static let resetThreshold: CGFloat = 1.05
    static let activeThreshold: CGFloat = 1.01

    static var doubleTapTargetScale: CGFloat {
        min(maximumScale, doubleTapScale)
    }

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(maximumScale, max(minimumScale, scale))
    }

    static func isZoomedForDoubleTapReset(_ scale: CGFloat) -> Bool {
        scale > resetThreshold
    }

    static func isActive(_ scale: CGFloat) -> Bool {
        scale > activeThreshold
    }
}

enum MangaPagedCenterTapHitTesting {
    static func acceptsCenterTap(at point: CGPoint, in bounds: CGRect) -> Bool {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(point) else {
            return false
        }
        return ReaderPagedTapZone.zone(for: point, in: bounds) == .toggleChrome
    }
}

enum MangaPagedSurfaceDragIntent {
    static let minimumUnzoomedHorizontalTranslation: CGFloat = 12

    static func unzoomedHorizontalTranslation(_ translation: CGSize) -> CGSize? {
        let absoluteWidth = abs(translation.width)
        guard absoluteWidth >= minimumUnzoomedHorizontalTranslation,
              absoluteWidth > abs(translation.height) else {
            return nil
        }
        return CGSize(width: translation.width, height: 0)
    }

    static func shouldResetOffsetWhenInteractionDisables(zoomScale: CGFloat) -> Bool {
        MangaPageZoomPolicy.isActive(zoomScale)
    }
}

enum MangaPagedSurfaceEdgeInteraction {
    static func physicalEdge(forTapZone zone: ReaderPagedTapZone) -> MangaPagedImageSurfaceHorizontalEdge? {
        switch zone {
        case .previous:
            .left
        case .next:
            .right
        case .toggleChrome:
            nil
        }
    }

    static func physicalEdge(
        horizontalVelocityX: CGFloat,
        horizontalTranslationX: CGFloat
    ) -> MangaPagedImageSurfaceHorizontalEdge? {
        if horizontalVelocityX != 0 {
            return horizontalVelocityX < 0 ? .right : .left
        }

        guard horizontalTranslationX != 0 else { return nil }
        return horizontalTranslationX < 0 ? .right : .left
    }

    static func shouldRevealHiddenContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        hiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge>
    ) -> Bool {
        hiddenEdges.contains(edge)
    }

    static func shouldDeferPageTurnPanToSurfaceContent(
        zoomEnabled: Bool,
        hiddenEdges: Set<MangaPagedImageSurfaceHorizontalEdge>,
        physicalEdge: MangaPagedImageSurfaceHorizontalEdge
    ) -> Bool {
        zoomEnabled && shouldRevealHiddenContent(on: physicalEdge, hiddenEdges: hiddenEdges)
    }
}

enum MangaPagedImageSurfaceHorizontalEdge: CaseIterable, Hashable {
    case left
    case right
}

enum MangaPagedImageSurfaceInitialHorizontalAlignment: Hashable, Sendable {
    case left
    case right

    init(pageTurnDirection: MangaPageTurnDirection) {
        switch pageTurnDirection {
        case .leftToRight:
            self = .left
        case .rightToLeft:
            self = .right
        }
    }

    static func enteringPage(
        pageTurnDirection: MangaPageTurnDirection,
        pageScaleMode: MangaPageScaleMode,
        currentPageIndex: Int?,
        targetPageIndex: Int
    ) -> Self {
        let defaultAlignment = Self(pageTurnDirection: pageTurnDirection)
        guard pageScaleMode == .fitHeight,
              let currentPageIndex,
              abs(targetPageIndex - currentPageIndex) == 1 else {
            return defaultAlignment
        }
        return targetPageIndex < currentPageIndex ? defaultAlignment.opposite : defaultAlignment
    }

    private var opposite: Self {
        switch self {
        case .left:
            .right
        case .right:
            .left
        }
    }
}

struct MangaPagedImageSurfaceLayout: Equatable {
    private static let edgeVisibilityTolerance: CGFloat = 0.5

    let imageSize: CGSize
    let containerSize: CGSize
    let pageScaleMode: MangaPageScaleMode
    let initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment
    let zoomScale: CGFloat

    var fittedImageSize: CGSize {
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

    var contentSize: CGSize {
        let fittedSize = fittedImageSize
        let scale = max(1, zoomScale)
        return CGSize(width: fittedSize.width * scale, height: fittedSize.height * scale)
    }

    var restingOffset: CGSize {
        guard pageScaleMode == .fitHeight else { return .zero }
        let horizontalOverflow = overflowBounds.width
        guard horizontalOverflow > 0 else { return .zero }

        return CGSize(
            width: initialHorizontalAlignment == .right ? -horizontalOverflow : horizontalOverflow,
            height: 0
        )
    }

    func clampedUserOffset(_ proposed: CGSize) -> CGSize {
        let bounds = overflowBounds
        let restingOffset = restingOffset
        return CGSize(
            width: proposed.width.clamped(
                lower: -bounds.width - restingOffset.width,
                upper: bounds.width - restingOffset.width
            ),
            height: proposed.height.clamped(lower: -bounds.height, upper: bounds.height)
        )
    }

    func displayOffset(forUserOffset userOffset: CGSize) -> CGSize {
        let clampedUserOffset = clampedUserOffset(userOffset)
        let restingOffset = restingOffset
        return CGSize(
            width: restingOffset.width + clampedUserOffset.width,
            height: restingOffset.height + clampedUserOffset.height
        )
    }

    func hasHiddenContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        fromUserOffset userOffset: CGSize
    ) -> Bool {
        guard pageScaleMode == .fitHeight else { return false }
        let horizontalOverflow = overflowBounds.width
        guard horizontalOverflow > Self.edgeVisibilityTolerance else { return false }

        let displayOffsetX = displayOffset(forUserOffset: userOffset).width
        switch edge {
        case .left:
            return displayOffsetX < horizontalOverflow - Self.edgeVisibilityTolerance
        case .right:
            return displayOffsetX > -horizontalOverflow + Self.edgeVisibilityTolerance
        }
    }

    func userOffsetRevealingContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        fromUserOffset userOffset: CGSize
    ) -> CGSize? {
        guard hasHiddenContent(on: edge, fromUserOffset: userOffset) else { return nil }
        let horizontalOverflow = overflowBounds.width
        let targetDisplayOffsetX = switch edge {
        case .left:
            horizontalOverflow
        case .right:
            -horizontalOverflow
        }
        return clampedUserOffset(
            CGSize(
                width: targetDisplayOffsetX - restingOffset.width,
                height: userOffset.height
            )
        )
    }

    private var overflowBounds: CGSize {
        CGSize(
            width: max(0, (contentSize.width - containerSize.width) / 2),
            height: max(0, (contentSize.height - containerSize.height) / 2)
        )
    }
}

struct MangaPagedSpreadSurfaceZoomLayout: Equatable {
    private static let edgeVisibilityTolerance: CGFloat = 0.5

    let containerSize: CGSize
    let zoomScale: CGFloat

    var contentSize: CGSize {
        let scale = max(1, zoomScale)
        return CGSize(width: containerSize.width * scale, height: containerSize.height * scale)
    }

    func clampedUserOffset(_ proposed: CGSize) -> CGSize {
        let bounds = overflowBounds
        return CGSize(
            width: proposed.width.clamped(lower: -bounds.width, upper: bounds.width),
            height: proposed.height.clamped(lower: -bounds.height, upper: bounds.height)
        )
    }

    func displayOffset(forUserOffset userOffset: CGSize) -> CGSize {
        clampedUserOffset(userOffset)
    }

    func userOffsetAnchoring(_ location: CGPoint) -> CGSize {
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let targetLocation = CGRect(origin: .zero, size: containerSize).contains(location)
            ? location
            : center
        let scale = max(1, zoomScale)
        return clampedUserOffset(
            CGSize(
                width: -(targetLocation.x - center.x) * scale,
                height: -(targetLocation.y - center.y) * scale
            )
        )
    }

    func hasHiddenContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        fromUserOffset userOffset: CGSize
    ) -> Bool {
        let horizontalOverflow = overflowBounds.width
        guard horizontalOverflow > Self.edgeVisibilityTolerance else { return false }

        let displayOffsetX = displayOffset(forUserOffset: userOffset).width
        switch edge {
        case .left:
            return displayOffsetX < horizontalOverflow - Self.edgeVisibilityTolerance
        case .right:
            return displayOffsetX > -horizontalOverflow + Self.edgeVisibilityTolerance
        }
    }

    func userOffsetRevealingContent(
        on edge: MangaPagedImageSurfaceHorizontalEdge,
        fromUserOffset userOffset: CGSize
    ) -> CGSize? {
        guard hasHiddenContent(on: edge, fromUserOffset: userOffset) else { return nil }
        let horizontalOverflow = overflowBounds.width
        let targetDisplayOffsetX = switch edge {
        case .left:
            horizontalOverflow
        case .right:
            -horizontalOverflow
        }
        return clampedUserOffset(CGSize(width: targetDisplayOffsetX, height: userOffset.height))
    }

    private var overflowBounds: CGSize {
        CGSize(
            width: max(0, (contentSize.width - containerSize.width) / 2),
            height: max(0, (contentSize.height - containerSize.height) / 2)
        )
    }
}

private extension CGFloat {
    func clamped(lower: CGFloat, upper: CGFloat) -> CGFloat {
        Swift.min(upper, Swift.max(lower, self))
    }
}
