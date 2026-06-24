import Foundation
import YamiboReaderCore

struct MangaPageSpread: Hashable, Sendable {
    let index: Int
    let pageIndexes: [Int]
    let leftPageIndex: Int?
    let rightPageIndex: Int?
    let leftPage: MangaReaderPageProjection?
    let rightPage: MangaReaderPageProjection?
    let preferredPageIndex: Int
    let preferredPage: MangaReaderPageProjection

    var id: String {
        [
            String(index),
            leftPage?.id ?? "_",
            rightPage?.id ?? "_",
        ].joined(separator: "|")
    }

    func containsPage(at pageIndex: Int) -> Bool {
        pageIndexes.contains(pageIndex)
    }

    func pageIndexForHorizontalLocation(_ x: CGFloat, width: CGFloat) -> Int? {
        guard leftPageIndex != nil || rightPageIndex != nil else { return nil }
        guard width > 0 else { return leftPageIndex ?? rightPageIndex }
        if let leftPageIndex, let rightPageIndex {
            return x < width / 2 ? leftPageIndex : rightPageIndex
        }
        if let leftPageIndex {
            return x < width / 2 ? leftPageIndex : nil
        }
        if let rightPageIndex {
            return x >= width / 2 ? rightPageIndex : nil
        }
        return nil
    }
}

struct MangaPagedReadingPlan: Hashable, Sendable {
    let pages: [MangaReaderPageProjection]
    let currentPageIndex: Int?
    let pageTurnDirection: MangaPageTurnDirection
    let usesTwoPageSpread: Bool
    let spreads: [MangaPageSpread]
    let currentSpreadIndex: Int?

    init(
        pages: [MangaReaderPageProjection],
        currentPageIndex: Int?,
        pageTurnDirection: MangaPageTurnDirection = .rightToLeft,
        usesTwoPageSpread: Bool = false
    ) {
        self.pages = pages
        let clampedCurrentPageIndex = Self.clampedIndex(currentPageIndex, pageCount: pages.count)
        self.currentPageIndex = clampedCurrentPageIndex
        self.pageTurnDirection = pageTurnDirection
        self.usesTwoPageSpread = usesTwoPageSpread
        let spreads = Self.makeSpreads(
            pages: pages,
            currentPageIndex: clampedCurrentPageIndex,
            pageTurnDirection: pageTurnDirection,
            usesTwoPageSpread: usesTwoPageSpread
        )
        self.spreads = spreads
        self.currentSpreadIndex = clampedCurrentPageIndex.flatMap { pageIndex in
            spreads.first { $0.containsPage(at: pageIndex) }?.index
        } ?? Self.clampedIndex(nil, pageCount: spreads.count)
    }

    var currentPage: MangaReaderPageProjection? {
        page(at: currentPageIndex)
    }

    var currentSpread: MangaPageSpread? {
        spread(at: currentSpreadIndex)
    }

    func page(at index: Int?) -> MangaReaderPageProjection? {
        guard let index,
              pages.indices.contains(index) else {
            return nil
        }
        return pages[index]
    }

    func spread(at index: Int?) -> MangaPageSpread? {
        guard let index,
              spreads.indices.contains(index) else {
            return nil
        }
        return spreads[index]
    }

    func globalIndex(forPageAt index: Int) -> Int? {
        page(at: index)?.globalIndex
    }

    func pageIndex(forSpreadAt index: Int) -> Int? {
        spread(at: index)?.preferredPageIndex
    }

    func globalIndex(forSpreadAt index: Int) -> Int? {
        spread(at: index)?.preferredPage.globalIndex
    }

    func spreadIndex(forPageAt index: Int) -> Int? {
        guard pages.indices.contains(index) else { return nil }
        return spreads.first { $0.containsPage(at: index) }?.index
    }

    func clampedPageIndex(_ index: Int?) -> Int? {
        Self.clampedIndex(index, pageCount: pages.count)
    }

    func clampedSpreadIndex(_ index: Int?) -> Int? {
        Self.clampedIndex(index, pageCount: spreads.count)
    }

    private static func clampedIndex(_ index: Int?, pageCount: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        return min(max(index ?? 0, 0), pageCount - 1)
    }

    private static func makeSpreads(
        pages: [MangaReaderPageProjection],
        currentPageIndex: Int?,
        pageTurnDirection: MangaPageTurnDirection,
        usesTwoPageSpread: Bool
    ) -> [MangaPageSpread] {
        guard usesTwoPageSpread else {
            return pages.indices.map { pageIndex in
                let page = pages[pageIndex]
                return MangaPageSpread(
                    index: pageIndex,
                    pageIndexes: [pageIndex],
                    leftPageIndex: pageIndex,
                    rightPageIndex: nil,
                    leftPage: page,
                    rightPage: nil,
                    preferredPageIndex: pageIndex,
                    preferredPage: page
                )
            }
        }

        var spreads: [MangaPageSpread] = []
        var pageIndex = pages.startIndex
        while pageIndex < pages.endIndex {
            let firstPageIndex = pageIndex
            let firstPage = pages[firstPageIndex]
            let secondPageIndex = pages.index(after: firstPageIndex)
            let pairsWithSecondPage = secondPageIndex < pages.endIndex &&
                pages[secondPageIndex].tid == firstPage.tid
            let pageIndexes = pairsWithSecondPage
                ? [firstPageIndex, secondPageIndex]
                : [firstPageIndex]
            let preferredPageIndex = currentPageIndex.flatMap { currentPageIndex in
                pageIndexes.contains(currentPageIndex) ? currentPageIndex : nil
            } ?? firstPageIndex
            let preferredPage = pages[preferredPageIndex]
            let leftPageIndex: Int?
            let rightPageIndex: Int?

            if let secondPageIndex = pageIndexes.dropFirst().first {
                switch pageTurnDirection {
                case .leftToRight:
                    leftPageIndex = firstPageIndex
                    rightPageIndex = secondPageIndex
                case .rightToLeft:
                    leftPageIndex = secondPageIndex
                    rightPageIndex = firstPageIndex
                }
            } else {
                switch pageTurnDirection {
                case .leftToRight:
                    leftPageIndex = firstPageIndex
                    rightPageIndex = nil
                case .rightToLeft:
                    leftPageIndex = nil
                    rightPageIndex = firstPageIndex
                }
            }

            spreads.append(
                MangaPageSpread(
                    index: spreads.count,
                    pageIndexes: pageIndexes,
                    leftPageIndex: leftPageIndex,
                    rightPageIndex: rightPageIndex,
                    leftPage: leftPageIndex.map { pages[$0] },
                    rightPage: rightPageIndex.map { pages[$0] },
                    preferredPageIndex: preferredPageIndex,
                    preferredPage: preferredPage
                )
            )
            pageIndex = pageIndexes.last.map { pages.index(after: $0) } ?? pages.index(after: firstPageIndex)
        }
        return spreads
    }
}
