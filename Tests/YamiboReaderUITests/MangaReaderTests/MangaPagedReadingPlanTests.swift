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
}

private func makePagedPlanPages() throws -> [MangaReaderPageProjection] {
    try (0 ..< 3).map { index in
        MangaReaderPageProjection(
            tid: "700",
            ownerPostID: "post-700",
            chapterTitle: "Chapter 700",
            imageURL: try #require(URL(string: "https://img.example.com/700-\(index).png")),
            refererURL: try #require(URL(string: "https://bbs.yamibo.com/forum.php?tid=700")),
            globalIndex: index,
            localIndex: index,
            chapterPageCount: 3
        )
    }
}
