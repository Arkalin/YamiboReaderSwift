import CoreGraphics
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@Suite("MangaReaderTests: Paged Image Surface Layout")
struct MangaPagedImageSurfaceLayoutTests {
    @Test func fitWidthKeepsFixedPageSurfaceWithVerticalBlankSpace() {
        let layout = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 800, height: 600),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitWidth,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )

        #expect(layout.fittedImageSize == CGSize(width: 400, height: 300))
        #expect(layout.contentSize == CGSize(width: 400, height: 300))
        #expect(layout.displayOffset(forUserOffset: .zero) == .zero)
        #expect(layout.clampedUserOffset(CGSize(width: 80, height: 80)) == .zero)
    }

    @Test func fitHeightInitialOverflowAlignmentFollowsPageTurnDirection() {
        let leftToRight = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )
        let rightToLeft = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .rightToLeft,
            zoomScale: 1
        )

        #expect(leftToRight.fittedImageSize == CGSize(width: 1200, height: 800))
        #expect(leftToRight.displayOffset(forUserOffset: .zero) == CGSize(width: 400, height: 0))
        #expect(rightToLeft.displayOffset(forUserOffset: .zero) == CGSize(width: -400, height: 0))
    }

    @Test func fitHeightHorizontalOverflowPanIsBoundedFromInitialAlignment() {
        let layout = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )

        #expect(layout.clampedUserOffset(CGSize(width: 100, height: 0)) == .zero)
        #expect(layout.clampedUserOffset(CGSize(width: -1_000, height: 0)) == CGSize(width: -800, height: 0))
        #expect(layout.displayOffset(forUserOffset: CGSize(width: -800, height: 0)) == CGSize(width: -400, height: 0))
    }

    @Test func fitHeightReportsHiddenPhysicalEdgesFromInitialAlignment() {
        let leftToRight = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )
        let rightToLeft = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .rightToLeft,
            zoomScale: 1
        )

        #expect(!leftToRight.hasHiddenContent(on: .left, fromUserOffset: .zero))
        #expect(leftToRight.hasHiddenContent(on: .right, fromUserOffset: .zero))
        #expect(leftToRight.userOffsetRevealingContent(on: .right, fromUserOffset: .zero) == CGSize(width: -800, height: 0))
        #expect(leftToRight.userOffsetRevealingContent(on: .left, fromUserOffset: .zero) == nil)

        #expect(rightToLeft.hasHiddenContent(on: .left, fromUserOffset: .zero))
        #expect(!rightToLeft.hasHiddenContent(on: .right, fromUserOffset: .zero))
        #expect(rightToLeft.userOffsetRevealingContent(on: .left, fromUserOffset: .zero) == CGSize(width: 800, height: 0))
        #expect(rightToLeft.userOffsetRevealingContent(on: .right, fromUserOffset: .zero) == nil)
    }

    @Test func fitHeightCenteredOverflowCanRevealEitherPhysicalEdge() {
        let layout = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )
        let centeredUserOffset = CGSize(width: -400, height: 0)

        #expect(layout.displayOffset(forUserOffset: centeredUserOffset) == .zero)
        #expect(layout.hasHiddenContent(on: .left, fromUserOffset: centeredUserOffset))
        #expect(layout.hasHiddenContent(on: .right, fromUserOffset: centeredUserOffset))
        #expect(layout.userOffsetRevealingContent(on: .left, fromUserOffset: centeredUserOffset) == .zero)
        #expect(layout.userOffsetRevealingContent(on: .right, fromUserOffset: centeredUserOffset) == CGSize(width: -800, height: 0))
    }

    @Test func nonOverflowingAndFitWidthSurfacesDoNotRevealPhysicalEdges() {
        let fitHeightWithoutOverflow = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 400, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )
        let fitWidth = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitWidth,
            pageTurnDirection: .leftToRight,
            zoomScale: 1
        )

        for edge in MangaPagedImageSurfaceHorizontalEdge.allCases {
            #expect(!fitHeightWithoutOverflow.hasHiddenContent(on: edge, fromUserOffset: .zero))
            #expect(fitHeightWithoutOverflow.userOffsetRevealingContent(on: edge, fromUserOffset: .zero) == nil)
            #expect(!fitWidth.hasHiddenContent(on: edge, fromUserOffset: .zero))
            #expect(fitWidth.userOffsetRevealingContent(on: edge, fromUserOffset: .zero) == nil)
        }
    }

    @Test func zoomedSurfacePanIsBoundedToScaledContent() {
        let layout = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 800, height: 1_200),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitWidth,
            pageTurnDirection: .leftToRight,
            zoomScale: 2
        )

        #expect(layout.contentSize == CGSize(width: 800, height: 1_200))
        #expect(layout.clampedUserOffset(CGSize(width: 600, height: -900)) == CGSize(width: 200, height: -200))
    }
}
