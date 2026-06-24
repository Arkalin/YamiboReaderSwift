import Foundation
import Testing
@testable import YamiboReaderCore
@testable import YamiboReaderUI

@Suite("MangaReaderTests: Paged Reading Plan")
struct MangaPagedReadingPlanTests {
    @Test func planKeepsSinglePageIdentityForCurrentPageLookup() throws {
        let pages = try makePagedPlanPages()
        let plan = MangaPagedReadingPlan(pages: pages, currentPageIndex: 1)

        #expect(plan.pages.map(\.id) == ["700#0", "700#1", "700#2"])
        #expect(plan.currentPage?.id == "700#1")
        #expect(plan.globalIndex(forPageAt: 1) == 1)
        #expect(plan.globalIndex(forPageAt: 9) == nil)
    }

    @Test func planClampsInitialCurrentPageWithoutCreatingSpreadState() throws {
        let pages = try makePagedPlanPages()
        let leadingPlan = MangaPagedReadingPlan(pages: pages, currentPageIndex: -5)
        let trailingPlan = MangaPagedReadingPlan(pages: pages, currentPageIndex: 99)

        #expect(leadingPlan.currentPageIndex == 0)
        #expect(leadingPlan.currentPage?.localIndex == 0)
        #expect(trailingPlan.currentPageIndex == 2)
        #expect(trailingPlan.currentPage?.localIndex == 2)
        #expect(trailingPlan.pages.map(\.localIndex) == [0, 1, 2])
    }

    @Test func planBuildsTwoPageSpreadsWithoutReplacingPageLevelCurrentPage() throws {
        let pages = try makePagedPlanPages(pageCountsByTID: [("700", 3), ("701", 2)])
        let plan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 1,
            pageTurnDirection: .leftToRight,
            usesTwoPageSpread: true
        )

        #expect(plan.spreads.count == 3)
        #expect(plan.currentPage?.id == "700#1")
        #expect(plan.currentSpreadIndex == 0)
        #expect(plan.globalIndex(forSpreadAt: 0) == 1)

        #expect(plan.spreads[0].leftPage?.id == "700#0")
        #expect(plan.spreads[0].rightPage?.id == "700#1")
        #expect(plan.spreads[0].preferredPage.id == "700#1")

        #expect(plan.spreads[1].leftPage?.id == "700#2")
        #expect(plan.spreads[1].rightPage == nil)
        #expect(plan.spreads[1].pageIndexes == [2])
        #expect(plan.spreads[1].pageIndexForHorizontalLocation(25, width: 100) == 2)
        #expect(plan.spreads[1].pageIndexForHorizontalLocation(75, width: 100) == nil)

        #expect(plan.spreads[2].leftPage?.id == "701#0")
        #expect(plan.spreads[2].rightPage?.id == "701#1")
        #expect(plan.spreads[2].pageIndexes == [3, 4])
    }

    @Test func planOrdersTwoPageSpreadsByPageTurnDirection() throws {
        let pages = try makePagedPlanPages(pageCountsByTID: [("700", 2)])
        let ltrPlan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 0,
            pageTurnDirection: .leftToRight,
            usesTwoPageSpread: true
        )
        let rtlPlan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 0,
            pageTurnDirection: .rightToLeft,
            usesTwoPageSpread: true
        )

        #expect(ltrPlan.spreads[0].leftPage?.id == "700#0")
        #expect(ltrPlan.spreads[0].rightPage?.id == "700#1")
        #expect(rtlPlan.spreads[0].leftPage?.id == "700#1")
        #expect(rtlPlan.spreads[0].rightPage?.id == "700#0")
    }

    @Test func planDisplaysLogicalChapterPageRangeForTwoPageSpread() throws {
        let pages = try makePagedPlanPages(pageCountsByTID: [("700", 4)])
        let plan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 1,
            pageTurnDirection: .rightToLeft,
            usesTwoPageSpread: true
        )

        #expect(plan.currentChapterPageLabel == "1-2")
        #expect(plan.chapterPageLabel(forSpreadAt: 0) == "1-2")
        #expect(plan.chapterPageLabel(forSpreadAt: 1) == "3-4")
    }

    @Test func planPlacesRightToLeftOddTailOnRightWithoutFakeLeftPage() throws {
        let pages = try makePagedPlanPages(pageCountsByTID: [("700", 3)])
        let plan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 2,
            pageTurnDirection: .rightToLeft,
            usesTwoPageSpread: true
        )

        #expect(plan.spreads[1].leftPage == nil)
        #expect(plan.spreads[1].rightPage?.id == "700#2")
        #expect(plan.spreads[1].pageIndexes == [2])
        #expect(plan.spreads[1].pageIndexForHorizontalLocation(25, width: 100) == nil)
        #expect(plan.spreads[1].pageIndexForHorizontalLocation(75, width: 100) == 2)
        #expect(plan.currentChapterPageLabel == "3")
    }

    @Test func pageCurlSequenceMapsSinglePagesThroughPhysicalBookOrder() throws {
        let pages = try makePagedPlanPages(pageCountsByTID: [("700", 3)])
        let ltrPlan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 0,
            pageTurnDirection: .leftToRight,
            usesTwoPageSpread: false
        )
        let rtlPlan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 0,
            pageTurnDirection: .rightToLeft,
            usesTwoPageSpread: false
        )

        let ltrSequence = MangaPagedPageCurlSequence(plan: ltrPlan)
        let rtlSequence = MangaPagedPageCurlSequence(plan: rtlPlan)

        #expect(ltrSequence.pageCount == 3)
        #expect(ltrSequence.leaves.map(\.pageIndex) == [0, 1, 2])
        #expect(ltrSequence.leafIndexes(forSelectionIndex: 1) == [1])
        #expect(ltrSequence.selectionIndex(forLeafIndexes: [2]) == 2)
        #expect(ltrSequence.globalIndex(forSelectionIndex: 2) == 2)
        #expect(ltrSequence.leafIndex(after: 1) == 2)

        #expect(rtlSequence.pageCount == 3)
        #expect(rtlSequence.leaves.map(\.pageIndex) == [2, 1, 0])
        #expect(rtlSequence.leafIndexes(forSelectionIndex: 0) == [2])
        #expect(rtlSequence.selectionIndex(forLeafIndexes: [0]) == 2)
        #expect(rtlSequence.globalIndex(forSelectionIndex: 2) == 2)
        #expect(rtlSequence.leafIndex(before: 2) == 1)
    }

    @Test func pageCurlSequenceMapsTwoPageBlankLeavesWithoutCreatingPagePositions() throws {
        let pages = try makePagedPlanPages(pageCountsByTID: [("700", 3), ("701", 2)])
        let ltrPlan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 2,
            pageTurnDirection: .leftToRight,
            usesTwoPageSpread: true
        )
        let rtlPlan = MangaPagedReadingPlan(
            pages: pages,
            currentPageIndex: 2,
            pageTurnDirection: .rightToLeft,
            usesTwoPageSpread: true
        )

        let ltrSequence = MangaPagedPageCurlSequence(plan: ltrPlan)
        let rtlSequence = MangaPagedPageCurlSequence(plan: rtlPlan)

        #expect(ltrSequence.pageCount == 3)
        #expect(ltrSequence.leafIndexes(forSelectionIndex: 1) == [2, 3])
        #expect(ltrSequence.leaves.map(\.pageIndex) == [0, 1, 2, nil, 3, 4])
        #expect(ltrSequence.selectionIndex(forLeafIndexes: [3]) == 1)
        #expect(ltrSequence.pageIndex(forSelectionIndex: 1) == 2)
        #expect(ltrSequence.globalIndex(forSelectionIndex: 1) == 2)

        #expect(rtlSequence.pageCount == 3)
        #expect(rtlSequence.leafIndexes(forSelectionIndex: 1) == [2, 3])
        #expect(rtlSequence.leaves.map(\.pageIndex) == [4, 3, nil, 2, 1, 0])
        #expect(rtlSequence.selectionIndex(forLeafIndexes: [2]) == 1)
        #expect(rtlSequence.pageIndex(forSelectionIndex: 1) == 2)
        #expect(rtlSequence.globalIndex(forSelectionIndex: 1) == 2)
        #expect(rtlSequence.leaves[2].pageIndex == nil)
    }

    @Test func pageCurlSequenceProvidesBlankPresentationLeavesForEmptyPlans() {
        let singlePageSequence = MangaPagedPageCurlSequence(
            plan: MangaPagedReadingPlan(
                pages: [],
                currentPageIndex: nil,
                pageTurnDirection: .leftToRight,
                usesTwoPageSpread: false
            )
        )
        let spreadSequence = MangaPagedPageCurlSequence(
            plan: MangaPagedReadingPlan(
                pages: [],
                currentPageIndex: nil,
                pageTurnDirection: .rightToLeft,
                usesTwoPageSpread: true
            )
        )

        #expect(singlePageSequence.pageCount == 1)
        #expect(singlePageSequence.leafIndexes(forSelectionIndex: 0) == [0])
        #expect(singlePageSequence.leaves.map(\.pageIndex) == [nil])
        #expect(singlePageSequence.pageIndex(forSelectionIndex: 0) == nil)
        #expect(singlePageSequence.globalIndex(forSelectionIndex: 0) == nil)

        #expect(spreadSequence.pageCount == 1)
        #expect(spreadSequence.leafIndexes(forSelectionIndex: 0) == [0, 1])
        #expect(spreadSequence.leaves.map(\.pageIndex) == [nil, nil])
        #expect(spreadSequence.pageIndex(forSelectionIndex: 0) == nil)
        #expect(spreadSequence.globalIndex(forSelectionIndex: 0) == nil)
    }
}

private func makePagedPlanPages() throws -> [MangaReaderPageProjection] {
    try makePagedPlanPages(pageCountsByTID: [("700", 3)])
}

private func makePagedPlanPages(pageCountsByTID: [(String, Int)]) throws -> [MangaReaderPageProjection] {
    var globalIndex = 0
    var pages: [MangaReaderPageProjection] = []
    for (tid, pageCount) in pageCountsByTID {
        for localIndex in 0 ..< pageCount {
            pages.append(
                MangaReaderPageProjection(
                    tid: tid,
                    ownerPostID: "post-\(tid)",
                    chapterTitle: "Chapter \(tid)",
                    imageURL: try #require(URL(string: "https://img.example.com/\(tid)-\(localIndex).png")),
                    refererURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=\(tid)")),
                    globalIndex: globalIndex,
                    localIndex: localIndex,
                    chapterPageCount: pageCount
                )
            )
            globalIndex += 1
        }
    }
    return pages
}
