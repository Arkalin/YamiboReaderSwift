import Foundation
import YamiboReaderCore

struct MangaPagedReadingPlan: Hashable, Sendable {
    let pages: [MangaReaderPageProjection]
    let currentPageIndex: Int?

    init(pages: [MangaReaderPageProjection], currentPageIndex: Int?) {
        self.pages = pages
        self.currentPageIndex = Self.clampedIndex(currentPageIndex, pageCount: pages.count)
    }

    var currentPage: MangaReaderPageProjection? {
        page(at: currentPageIndex)
    }

    func page(at index: Int?) -> MangaReaderPageProjection? {
        guard let index,
              pages.indices.contains(index) else {
            return nil
        }
        return pages[index]
    }

    func globalIndex(forPageAt index: Int) -> Int? {
        page(at: index)?.globalIndex
    }

    func clampedPageIndex(_ index: Int?) -> Int? {
        Self.clampedIndex(index, pageCount: pages.count)
    }

    private static func clampedIndex(_ index: Int?, pageCount: Int) -> Int? {
        guard pageCount > 0 else { return nil }
        return min(max(index ?? 0, 0), pageCount - 1)
    }
}
