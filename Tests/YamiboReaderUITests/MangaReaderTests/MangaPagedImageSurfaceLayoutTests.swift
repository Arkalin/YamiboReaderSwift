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
            initialHorizontalAlignment: .left,
            zoomScale: 1
        )

        #expect(layout.fittedImageSize == CGSize(width: 400, height: 300))
        #expect(layout.contentSize == CGSize(width: 400, height: 300))
        #expect(layout.displayOffset(forUserOffset: .zero) == .zero)
        #expect(layout.clampedUserOffset(CGSize(width: 80, height: 80)) == .zero)
    }

    @Test func fitHeightInitialOverflowAlignmentFollowsInputEdge() {
        let left = Self.layout(initialHorizontalAlignment: .left)
        let right = Self.layout(initialHorizontalAlignment: .right)

        #expect(left.fittedImageSize == CGSize(width: 1200, height: 800))
        #expect(left.displayOffset(forUserOffset: .zero) == CGSize(width: 400, height: 0))
        #expect(right.displayOffset(forUserOffset: .zero) == CGSize(width: -400, height: 0))
    }

    @Test func fitHeightAdjacentEntryAlignmentShowsOppositeEdgeWhenReturningLeftToRight() {
        let forward = MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
            pageTurnDirection: .leftToRight,
            pageScaleMode: .fitHeight,
            currentPageIndex: 0,
            targetPageIndex: 1
        )
        let backward = MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
            pageTurnDirection: .leftToRight,
            pageScaleMode: .fitHeight,
            currentPageIndex: 1,
            targetPageIndex: 0
        )

        #expect(forward == .left)
        #expect(backward == .right)
        #expect(Self.layout(initialHorizontalAlignment: forward).displayOffset(forUserOffset: .zero) == CGSize(width: 400, height: 0))
        #expect(Self.layout(initialHorizontalAlignment: backward).displayOffset(forUserOffset: .zero) == CGSize(width: -400, height: 0))
    }

    @Test func fitHeightAdjacentEntryAlignmentShowsOppositeEdgeWhenReturningRightToLeft() {
        let forward = MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
            pageTurnDirection: .rightToLeft,
            pageScaleMode: .fitHeight,
            currentPageIndex: 0,
            targetPageIndex: 1
        )
        let backward = MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
            pageTurnDirection: .rightToLeft,
            pageScaleMode: .fitHeight,
            currentPageIndex: 1,
            targetPageIndex: 0
        )

        #expect(forward == .right)
        #expect(backward == .left)
        #expect(Self.layout(initialHorizontalAlignment: forward).displayOffset(forUserOffset: .zero) == CGSize(width: -400, height: 0))
        #expect(Self.layout(initialHorizontalAlignment: backward).displayOffset(forUserOffset: .zero) == CGSize(width: 400, height: 0))
    }

    @Test func initialEntryAlignmentUsesDefaultForNonAdjacentInitialAndFitWidthEntries() {
        #expect(
            MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
                pageTurnDirection: .leftToRight,
                pageScaleMode: .fitHeight,
                currentPageIndex: 4,
                targetPageIndex: 1
            ) == .left
        )
        #expect(
            MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
                pageTurnDirection: .leftToRight,
                pageScaleMode: .fitHeight,
                currentPageIndex: nil,
                targetPageIndex: 1
            ) == .left
        )
        #expect(
            MangaPagedImageSurfaceInitialHorizontalAlignment.enteringPage(
                pageTurnDirection: .leftToRight,
                pageScaleMode: .fitWidth,
                currentPageIndex: 1,
                targetPageIndex: 0
            ) == .left
        )
    }

    @Test func fitHeightHorizontalOverflowPanIsBoundedFromInitialAlignment() {
        let layout = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            initialHorizontalAlignment: .left,
            zoomScale: 1
        )

        #expect(layout.clampedUserOffset(CGSize(width: 100, height: 0)) == .zero)
        #expect(layout.clampedUserOffset(CGSize(width: -1_000, height: 0)) == CGSize(width: -800, height: 0))
        #expect(layout.displayOffset(forUserOffset: CGSize(width: -800, height: 0)) == CGSize(width: -400, height: 0))
    }

    @Test func fitHeightReportsHiddenPhysicalEdgesFromInitialAlignment() {
        let leftToRight = Self.layout(initialHorizontalAlignment: .left)
        let rightToLeft = Self.layout(initialHorizontalAlignment: .right)

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
            initialHorizontalAlignment: .left,
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
            initialHorizontalAlignment: .left,
            zoomScale: 1
        )
        let fitWidth = MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitWidth,
            initialHorizontalAlignment: .right,
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
            initialHorizontalAlignment: .left,
            zoomScale: 2
        )

        #expect(layout.contentSize == CGSize(width: 800, height: 1_200))
        #expect(layout.clampedUserOffset(CGSize(width: 600, height: -900)) == CGSize(width: 200, height: -200))
    }

    private static func layout(
        initialHorizontalAlignment: MangaPagedImageSurfaceInitialHorizontalAlignment
    ) -> MangaPagedImageSurfaceLayout {
        MangaPagedImageSurfaceLayout(
            imageSize: CGSize(width: 1200, height: 800),
            containerSize: CGSize(width: 400, height: 800),
            pageScaleMode: .fitHeight,
            initialHorizontalAlignment: initialHorizontalAlignment,
            zoomScale: 1
        )
    }
}
