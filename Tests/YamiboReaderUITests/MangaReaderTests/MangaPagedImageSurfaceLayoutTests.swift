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
