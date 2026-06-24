import CoreGraphics
import YamiboReaderCore

enum MangaPagedImageSurfaceHorizontalEdge: CaseIterable, Hashable {
    case left
    case right
}

struct MangaPagedImageSurfaceLayout: Equatable {
    private static let edgeVisibilityTolerance: CGFloat = 0.5

    let imageSize: CGSize
    let containerSize: CGSize
    let pageScaleMode: MangaPageScaleMode
    let pageTurnDirection: MangaPageTurnDirection
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
            width: pageTurnDirection == .rightToLeft ? -horizontalOverflow : horizontalOverflow,
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

private extension CGFloat {
    func clamped(lower: CGFloat, upper: CGFloat) -> CGFloat {
        Swift.min(upper, Swift.max(lower, self))
    }
}
