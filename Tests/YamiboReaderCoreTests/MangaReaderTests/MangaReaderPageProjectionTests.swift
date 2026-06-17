import Foundation
import Testing
@testable import YamiboReaderCore

@Suite("MangaReaderTests: Page Projection")
struct MangaReaderTestsPageProjection {
    @Test func pageProjectionExpandsDocumentsWithStableIndexesAndReferers() throws {
        let first = try makeProjectionDocument(tid: "700", pageCount: 2)
        let second = try makeProjectionDocument(tid: "701", pageCount: 1)
        let window = try #require(MangaChapterWindow(documents: [first, second]))

        let pages = MangaReaderPageProjection.projections(from: window)

        #expect(pages.map(\.id) == ["700#0", "700#1", "701#0"])
        #expect(pages.map(\.globalIndex) == [0, 1, 2])
        #expect(pages.map(\.localIndex) == [0, 1, 0])
        #expect(pages.map(\.chapterPageCount) == [2, 2, 1])
        #expect(pages[0].refererURL == first.chapterURL)
        #expect(pages[2].refererURL == second.chapterURL)
        #expect(pages[0].ownerPostID == "post-700")
    }

    @Test func pageProjectionResolvesPageIndexFromReadingPosition() throws {
        let document = try makeProjectionDocument(tid: "700", pageCount: 3)
        let window = MangaChapterWindow(
            initialDocument: document,
            position: MangaReadingPosition(tid: "700", localIndex: 2)
        )
        let pages = MangaReaderPageProjection.projections(from: window)

        #expect(
            MangaReaderPageProjection.resolvedPageIndex(
                for: window.resolvedPosition,
                in: pages
            ) == 2
        )
    }
}

private func makeProjectionDocument(tid: String, pageCount: Int) throws -> MangaChapterDocument {
    let chapterURL = try #require(URL(string: "https://bbs.yamibo.com/thread-\(tid)-1-1.html"))
    let imageURLs = try (0..<pageCount).map { index in
        try #require(URL(string: "https://img.example.com/\(tid)-\(index).jpg"))
    }
    return MangaChapterDocument(
        tid: tid,
        ownerPostID: "post-\(tid)",
        chapterTitle: "第\(tid)话",
        chapterURL: chapterURL,
        imageURLs: imageURLs
    )
}
