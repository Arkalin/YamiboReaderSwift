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
